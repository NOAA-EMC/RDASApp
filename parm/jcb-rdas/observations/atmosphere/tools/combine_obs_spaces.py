#!/usr/bin/env python3
"""
Combine multiple JEDI obs-space YAML templates (e.g., adpsfc_airTemperature_181.yaml.j2)
into a single combined YAML.j2 file (e.g., adpsfc.yaml.j2).

This version:
  - Builds safe, union-based ObsValue and ObsType location reductions.
  - Runs all independent iuse filters before the remaining combined QC.
  - Merges compatible pointwise filters by unioning their ObsType selectors.
  - Retains "reduce obs space" only when removing the full location is safe.
  - Prepends a universal "reject all" filter after location reduction.
  - Reads observed variables from each template instead of inferring them from filenames.
  - Preserves each template's nonlinear and linear observation-operator settings.
  - Uses Composite operators when the inputs require different operator configurations.
  - Splits incompatible same-variable operator settings into separate ObsSpaces by default.
  - Can keep the first same-variable operator setting when one ObsSpace is required.
  - Produces indentation and layout consistent with standard JEDI YAMLs.
"""

import argparse
from collections import OrderedDict
from dataclasses import dataclass, field
from pathlib import Path
import re
import sys
from typing import Dict, List, Optional, Tuple


# ------------------------
# Constants
# ------------------------
SELECTION_UDESCRIPTORS = (
    "obs_type_check",
    "obs_kx_check",
)

POINTWISE_MERGEABLE_FILTERS = (
    "AcceptList",
    "Background Check",
    "Bounds Check",
    "Domain Check",
    "Perform Action",
    "PreQC",
    "RejectList",
    "Variable Assignment",
)

# These filters occur before stream-specific error assignments and thinning in
# the conventional templates. Merging later filters would require a dependency
# scheduler to ensure that every source stream has completed its prerequisites.
ORDER_INDEPENDENT_MERGE_UDESCRIPTORS = (
    "quality_marker_check",
    "time_window_check",
)

OPERATOR_CONFLICT_POLICIES = (
    "split",
    "use-first",
    "error",
)


# ------------------------
# Parsed operator containers
# ------------------------
@dataclass(frozen=True)
class OperatorSpec:
    """An operator name and its non-variable YAML options."""

    name: str
    option_lines: Tuple[str, ...]
    had_variables: bool


@dataclass
class OperatorGroup:
    """Variables that share the same nonlinear and linear operators."""

    obs_operator: OperatorSpec
    linear_obs_operator: Optional[OperatorSpec]
    variables: List[str] = field(default_factory=list)
    source_files: List[Path] = field(default_factory=list)


@dataclass(frozen=True)
class KxSelector:
    """One ObsType whitelist or blacklist in a filter where statement."""

    variable: str
    operator: str
    values: Tuple[str, ...]
    value_line_index: int


@dataclass(frozen=True)
class FilterBlock:
    """One filter and the text that immediately precedes it."""

    leading_lines: Tuple[str, ...]
    lines: Tuple[str, ...]
    jinja_depth: int


@dataclass(frozen=True)
class FilterSection:
    """Parsed filters plus text following the final filter."""

    blocks: Tuple[FilterBlock, ...]
    trailing_lines: Tuple[str, ...]


@dataclass(frozen=True)
class SelectionSpec:
    """Source-derived variable validity and KX selection for one template."""

    value_variable: str
    kx_variable: str
    kx_values: Tuple[str, ...]


@dataclass(frozen=True)
class InputTemplate:
    """Parsed content needed from one input obs-space template."""

    path: Path
    variables: Tuple[str, ...]
    obs_operator: OperatorSpec
    linear_obs_operator: Optional[OperatorSpec]
    filter_section: FilterSection
    selection: SelectionSpec


@dataclass
class FilterOccurrence:
    """A filter block while it is being transformed for combined output."""

    template: InputTemplate
    block: FilterBlock
    lines: List[str]
    skip: bool = False
    notes: List[str] = field(default_factory=list)


@dataclass
class FilterMergeStats:
    """Counts describing filter transformations in one output ObsSpace."""

    merged_groups: int = 0
    merged_blocks: int = 0
    deduplicated_blocks: int = 0
    converted_reductions: int = 0
    retained_reductions: int = 0
    generated_time_reducer: bool = False


@dataclass
class ObsSpacePartition:
    """A set of templates with compatible operators for every variable."""

    templates: List[InputTemplate] = field(default_factory=list)
    variable_owners: dict = field(default_factory=dict)


class CombineError(ValueError):
    """Raised when input templates cannot be combined safely."""


# ------------------------
# Parse arguments
# ------------------------
def parse_args():
    parser = argparse.ArgumentParser(
        description=(
            "Combine JEDI obs-space YAMLs while preserving operators, merging "
            "compatible filters, and safely reducing unused locations"
        )
    )
    parser.add_argument("inputs", nargs="+", help="Input YAML files to combine")
    parser.add_argument("-o", "--output", required=True, help="Output YAML file name")
    parser.add_argument(
        "--operator-conflict",
        choices=OPERATOR_CONFLICT_POLICIES,
        default="split",
        help=(
            "How to handle one variable using incompatible operator settings: "
            "split into separate ObsSpaces (default), keep the first setting, "
            "or stop with an error"
        ),
    )
    return parser.parse_args()


# ------------------------
# Helper: basic YAML text parsing
# ------------------------
def leading_spaces(line):
    """Return the number of leading spaces and reject tab-indented YAML."""

    leading_whitespace = line[:len(line) - len(line.lstrip())]
    if "\t" in leading_whitespace:
        raise CombineError("Tab indentation is not supported")
    return len(line) - len(line.lstrip(" "))


def find_section(lines, section, start=0):
    """Find an exact YAML section header after start."""

    target = f"{section}:"
    for index in range(start, len(lines)):
        if lines[index].strip() == target:
            return index
    return None


def extract_section(lines, start_section, end_sections, path, required=True):
    """Extract lines between top-level obs-space sections."""

    start = find_section(lines, start_section)
    if start is None:
        if required:
            raise CombineError(f"{path}: missing '{start_section}:' section")
        return None

    ends = []
    for section in end_sections:
        index = find_section(lines, section, start + 1)
        if index is not None:
            ends.append(index)

    if not ends:
        raise CombineError(
            f"{path}: could not find the end of the '{start_section}:' section"
        )

    return lines[start + 1:min(ends)]


def trim_blank_lines(lines):
    """Remove blank lines from the beginning and end of a block."""

    trimmed = list(lines)
    while trimmed and not trimmed[0].strip():
        trimmed.pop(0)
    while trimmed and not trimmed[-1].strip():
        trimmed.pop()
    return trimmed


def parse_inline_list(value, path, field_name):
    """Parse the simple inline lists used for observed variables."""

    if not (value.startswith("[") and value.endswith("]")):
        raise CombineError(
            f"{path}: '{field_name}' must use an inline list, such as "
            "[airTemperature, specificHumidity]"
        )

    contents = value[1:-1].strip()
    if not contents:
        return []

    values = []
    for item in contents.split(","):
        item = item.strip().strip("\"'")
        if not item:
            raise CombineError(f"{path}: empty item in '{field_name}'")
        values.append(item)
    return values


# ------------------------
# Helper: extract observed variables from YAML
# ------------------------
def extract_observed_variables(lines, path):
    """Read the observed variable list from an input template."""

    matches = []
    for line in lines:
        stripped = line.strip()
        if stripped.startswith("observed variables:"):
            matches.append(stripped.split(":", 1)[1].strip())

    if len(matches) != 1:
        raise CombineError(
            f"{path}: expected exactly one 'observed variables:' field, "
            f"found {len(matches)}"
        )

    variables = parse_inline_list(matches[0], path, "observed variables")
    if not variables:
        raise CombineError(f"{path}: observed variable list is empty")
    return variables


# ------------------------
# Helper: extract observation operators
# ------------------------
def normalize_operator_block(block, path, section_name):
    """Dedent an operator block and separate its variable list from its options."""

    block = trim_blank_lines(block)
    if not block:
        raise CombineError(f"{path}: '{section_name}:' section is empty")

    name_candidates = [
        (index, line)
        for index, line in enumerate(block)
        if line.strip().startswith("name:")
    ]
    if not name_candidates:
        raise CombineError(f"{path}: '{section_name}:' has no operator name")

    _, name_line = name_candidates[0]
    base_indent = leading_spaces(name_line)
    normalized = []
    for line in block:
        if not line.strip():
            normalized.append("")
            continue
        if leading_spaces(line) < base_indent:
            raise CombineError(
                f"{path}: unsupported indentation in '{section_name}:' section"
            )
        normalized.append(line[base_indent:])

    name = None
    had_variables = False
    option_lines = []
    index = 0

    while index < len(normalized):
        line = normalized[index]
        stripped = line.strip()
        indent = leading_spaces(line) if stripped else 0

        if indent == 0 and stripped.startswith("name:"):
            if name is not None:
                raise CombineError(
                    f"{path}: multiple top-level names in '{section_name}:' section"
                )
            name = stripped.split(":", 1)[1].strip()
            index += 1
            continue

        if indent == 0 and stripped.startswith("variables:"):
            had_variables = True
            inline_value = stripped.split(":", 1)[1].strip()
            index += 1

            if inline_value:
                continue

            # Remove the indentless YAML sequence belonging to variables.
            while index < len(normalized):
                candidate = normalized[index]
                candidate_stripped = candidate.strip()
                if not candidate_stripped:
                    index += 1
                    continue

                candidate_indent = leading_spaces(candidate)
                if candidate_indent == 0 and not candidate_stripped.startswith("-"):
                    break
                index += 1
            continue

        option_lines.append(line)
        index += 1

    if name is None or not name:
        raise CombineError(f"{path}: '{section_name}:' has an empty operator name")

    option_lines = trim_blank_lines(option_lines)
    return OperatorSpec(name, tuple(option_lines), had_variables)


def extract_operator(lines, path, linear=False):
    """Extract one nonlinear or linear observation operator from a template."""

    if linear:
        section_name = "linear obs operator"
        block = extract_section(
            lines,
            section_name,
            ("obs error", "obs localizations", "obs filters"),
            path,
            required=False,
        )
        if block is None:
            return None
    else:
        section_name = "obs operator"
        block = extract_section(
            lines,
            section_name,
            ("linear obs operator", "obs error", "obs localizations", "obs filters"),
            path,
        )

    return normalize_operator_block(block, path, section_name)


# ------------------------
# Helper: parse observation filters without rendering Jinja
# ------------------------
def is_active_jinja_control(line):
    """Return true for a line containing a Jinja control delimiter."""

    # Jinja recognizes its delimiters even when YAML sees a leading '#'.
    return "{%" in line or "{#" in line


def calculate_jinja_depths(lines):
    """Return the active Jinja block depth immediately before each line."""

    open_tags = {"block", "call", "filter", "for", "if", "macro", "with"}
    depth = 0
    depths = []

    for line in lines:
        depths.append(depth)
        if "{%" not in line:
            continue

        match = re.search(r"\{%\s*([A-Za-z_]+)", line)
        if match is None:
            continue

        tag = match.group(1)
        if tag.startswith("end"):
            depth = max(0, depth - 1)
        elif tag in open_tags:
            depth += 1

    return depths


def split_structural_prefix(lines):
    """Separate required Jinja controls from decorative filter comments."""

    last_control = None
    for index, line in enumerate(lines):
        if is_active_jinja_control(line):
            last_control = index

    if last_control is None:
        return [], list(lines)
    return list(lines[:last_control + 1]), list(lines[last_control + 1:])


def extract_filters_section(lines, path):
    """Split an obs-filter section into individual filter blocks."""

    start = find_section(lines, "obs filters")
    if start is None:
        raise CombineError(f"{path}: missing 'obs filters:' section")

    filter_lines = lines[start + 1:]
    filter_starts = [
        index
        for index, line in enumerate(filter_lines)
        if line.strip().startswith("- filter:")
    ]
    if not filter_starts:
        return FilterSection((), tuple(filter_lines))

    jinja_depths = calculate_jinja_depths(filter_lines)
    pending_prefix = list(filter_lines[:filter_starts[0]])
    blocks = []

    for position, block_start in enumerate(filter_starts):
        if position + 1 < len(filter_starts):
            block_end = filter_starts[position + 1]
        else:
            block_end = len(filter_lines)

        block_lines = list(filter_lines[block_start:block_end])
        suffix = []

        # Move comments, blank lines, and outer Jinja controls to the prefix of
        # the next filter. Embedded Jinja controls remain when followed by YAML.
        while len(block_lines) > 1:
            stripped = block_lines[-1].strip()
            if (
                stripped
                and not stripped.startswith("#")
                and not is_active_jinja_control(block_lines[-1])
            ):
                break
            suffix.insert(0, block_lines.pop())

        blocks.append(
            FilterBlock(
                leading_lines=tuple(pending_prefix),
                lines=tuple(block_lines),
                jinja_depth=jinja_depths[block_start],
            )
        )
        pending_prefix = suffix

    return FilterSection(tuple(blocks), tuple(pending_prefix))


def filter_name(block):
    """Return the UFO filter name from a parsed filter block."""

    return yaml_scalar(block.lines[0].strip().split(":", 1)[1])


def yaml_scalar(value):
    """Remove simple YAML quotes and trailing comments from a scalar."""

    return value.split("#", 1)[0].strip().strip("\"'")


def filter_udescriptor(block):
    """Return a filter udescriptor, or None when it is absent."""

    for line in block.lines:
        stripped = line.strip()
        if stripped.startswith("udescriptor:"):
            return yaml_scalar(stripped.split(":", 1)[1])
    return None


def filter_action(block):
    """Return the configured action name, or None when it is absent."""

    for index, line in enumerate(block.lines[:-1]):
        if line.strip() != "action:":
            continue
        for candidate in block.lines[index + 1:]:
            stripped = candidate.strip()
            if not stripped:
                continue
            if stripped.startswith("name:"):
                return yaml_scalar(stripped.split(":", 1)[1])
            break
    return None


def named_list(block, field_name):
    """Extract names from one inline or indentless YAML variable list."""

    base_indent = leading_spaces(block.lines[0])
    field_indent = base_indent + 2

    for index, line in enumerate(block.lines):
        stripped = line.strip()
        if leading_spaces(line) != field_indent:
            continue
        if not stripped.startswith(f"{field_name}:"):
            continue

        inline_value = stripped.split(":", 1)[1].strip()
        if inline_value:
            return tuple(parse_inline_list(inline_value, "filter", field_name))

        names = []
        for candidate in block.lines[index + 1:]:
            candidate_stripped = candidate.strip()
            if not candidate_stripped or candidate_stripped.startswith("#"):
                continue
            candidate_indent = leading_spaces(candidate)
            if candidate_indent == field_indent and not candidate_stripped.startswith("-"):
                break
            if candidate_indent == field_indent and candidate_stripped.startswith("- name:"):
                names.append(yaml_scalar(candidate_stripped.split(":", 1)[1]))
        return tuple(names)

    return ()


def top_level_filter_value(block, field_name):
    """Return a scalar top-level filter field, or None when absent."""

    field_indent = leading_spaces(block.lines[0]) + 2
    for line in block.lines:
        stripped = line.strip()
        if (
            leading_spaces(line) == field_indent
            and stripped.startswith(f"{field_name}:")
        ):
            return yaml_scalar(stripped.split(":", 1)[1])
    return None


def parse_kx_values(value, path):
    """Parse the integer ObsType lists used by the conventional templates."""

    contents = value.strip()
    if contents.startswith("[") and contents.endswith("]"):
        contents = contents[1:-1].strip()

    values = []
    for item in contents.split(","):
        item = item.strip()
        if not item:
            continue
        if not re.fullmatch(r"[0-9]+(?:-[0-9]+)?", item):
            raise CombineError(
                f"{path}: unsupported ObsType list item '{item}' in '{value}'"
            )
        if item not in values:
            values.append(item)

    if not values:
        raise CombineError(f"{path}: empty ObsType selector '{value}'")
    return tuple(values)


def kx_selectors(block, path):
    """Find ObsType is_in/is_not_in conditions in a filter block."""

    selectors = []
    lines = block.lines

    for index, line in enumerate(lines):
        stripped = line.strip()
        variable = None

        match = re.fullmatch(r"- variable:\s*ObsType/([^\s#]+)", stripped)
        if match is not None:
            variable = match.group(1)
        elif stripped == "- variable:":
            for candidate in lines[index + 1:index + 4]:
                candidate_stripped = candidate.strip()
                match = re.fullmatch(r"name:\s*ObsType/([^\s#]+)", candidate_stripped)
                if match is not None:
                    variable = match.group(1)
                    break

        if variable is None:
            continue

        condition_indent = leading_spaces(line)
        for value_index in range(index + 1, len(lines)):
            candidate = lines[value_index]
            candidate_stripped = candidate.strip()
            if (
                value_index > index + 1
                and leading_spaces(candidate) <= condition_indent
                and candidate_stripped.startswith("- variable:")
            ):
                break
            for operator in ("is_in", "is_not_in"):
                if candidate_stripped.startswith(f"{operator}:"):
                    raw_values = yaml_scalar(candidate_stripped.split(":", 1)[1])
                    selectors.append(
                        KxSelector(
                            variable=variable,
                            operator=operator,
                            values=parse_kx_values(raw_values, path),
                            value_line_index=value_index,
                        )
                    )
                    break
            else:
                continue
            break

    return tuple(selectors)


def condition_variable(block, group_name, condition_name, condition_value, path):
    """Find one where variable having the requested condition."""

    lines = block.lines
    matches = []
    variable_pattern = re.compile(
        rf"- variable:\s*{re.escape(group_name)}/([^\s#]+)"
    )
    nested_pattern = re.compile(
        rf"name:\s*{re.escape(group_name)}/([^\s#]+)"
    )

    for index, line in enumerate(lines):
        stripped = line.strip()
        variable_match = variable_pattern.fullmatch(stripped)
        variable = variable_match.group(1) if variable_match is not None else None

        if variable is None and stripped == "- variable:":
            for candidate in lines[index + 1:index + 4]:
                nested_match = nested_pattern.fullmatch(candidate.strip())
                if nested_match is not None:
                    variable = nested_match.group(1)
                    break

        if variable is None:
            continue

        condition_indent = leading_spaces(line)
        for candidate in lines[index + 1:]:
            candidate_stripped = candidate.strip()
            if (
                leading_spaces(candidate) <= condition_indent
                and candidate_stripped.startswith("- variable:")
            ):
                break
            if candidate_stripped.startswith(f"{condition_name}:"):
                value = yaml_scalar(candidate_stripped.split(":", 1)[1])
                if value == condition_value:
                    matches.append(variable)
                break

    if len(matches) != 1:
        raise CombineError(
            f"{path}: expected one {group_name} condition with "
            f"'{condition_name}: {condition_value}', found {len(matches)}"
        )
    return matches[0]


def parse_selection_spec(filter_section, path):
    """Extract the source template's missing-value and KX reduction rules."""

    by_udescriptor = {}
    for block in filter_section.blocks:
        udescriptor = filter_udescriptor(block)
        if udescriptor in SELECTION_UDESCRIPTORS:
            by_udescriptor.setdefault(udescriptor, []).append(block)

    for udescriptor in SELECTION_UDESCRIPTORS:
        count = len(by_udescriptor.get(udescriptor, []))
        if count != 1:
            raise CombineError(
                f"{path}: expected exactly one '{udescriptor}' filter, found {count}"
            )

    type_block = by_udescriptor["obs_type_check"][0]
    kx_block = by_udescriptor["obs_kx_check"][0]
    if filter_action(type_block) != "reduce obs space":
        raise CombineError(
            f"{path}: 'obs_type_check' must use 'reduce obs space'"
        )
    if filter_action(kx_block) != "reduce obs space":
        raise CombineError(
            f"{path}: 'obs_kx_check' must use 'reduce obs space'"
        )

    value_variable = condition_variable(
        type_block,
        "ObsValue",
        "value",
        "is_not_valid",
        path,
    )
    selectors = kx_selectors(kx_block, path)
    if len(selectors) != 1 or selectors[0].operator != "is_not_in":
        raise CombineError(
            f"{path}: 'obs_kx_check' must contain one ObsType is_not_in condition"
        )

    return SelectionSpec(
        value_variable=value_variable,
        kx_variable=selectors[0].variable,
        kx_values=selectors[0].values,
    )


# ------------------------
# Collect variables, operators, and filters
# ------------------------
def operator_key(template):
    """Return the nonlinear and linear operator signature for a template."""

    return template.obs_operator, template.linear_obs_operator


def parse_input_templates(input_names):
    """Read and parse every input template once."""

    templates = []
    for input_name in input_names:
        path = Path(input_name)
        try:
            lines = path.read_text(encoding="utf-8").splitlines()
        except OSError as error:
            raise CombineError(f"Could not read {path}: {error}") from error

        filter_section = extract_filters_section(lines, path)

        templates.append(
            InputTemplate(
                path=path,
                variables=tuple(extract_observed_variables(lines, path)),
                obs_operator=extract_operator(lines, path),
                linear_obs_operator=extract_operator(lines, path, linear=True),
                filter_section=filter_section,
                selection=parse_selection_spec(filter_section, path),
            )
        )
    return templates


def partition_inputs(templates):
    """Greedily place each template into the first compatible ObsSpace."""

    partitions = []
    for template in templates:
        template_key = operator_key(template)

        for partition in partitions:
            compatible = all(
                variable not in partition.variable_owners
                or partition.variable_owners[variable] == template_key
                for variable in template.variables
            )
            if not compatible:
                continue

            partition.templates.append(template)
            for variable in template.variables:
                partition.variable_owners[variable] = template_key
            break
        else:
            partitions.append(
                ObsSpacePartition(
                    templates=[template],
                    variable_owners={
                        variable: template_key
                        for variable in template.variables
                    },
                )
            )

    return partitions


def describe_sources(group):
    """Return a compact source-file list for diagnostics."""

    return ", ".join(source.name for source in group.source_files)


def collect_partition(templates, conflict_policy):
    """Collect one output ObsSpace and resolve conflicts using the selected policy."""

    obs_vars = []
    warnings = []
    groups = OrderedDict()
    variable_owners = {}

    for template in templates:
        group_key = operator_key(template)
        if group_key not in groups:
            groups[group_key] = OperatorGroup(
                template.obs_operator,
                template.linear_obs_operator,
            )
        group = groups[group_key]
        group.source_files.append(template.path)

        for variable in template.variables:
            previous_key = variable_owners.get(variable)
            if previous_key is not None and previous_key != group_key:
                previous_group = groups[previous_key]
                message = (
                    f"Variable '{variable}' uses incompatible operator settings in "
                    f"{describe_sources(previous_group)} and {template.path.name}"
                )
                if conflict_policy == "error":
                    raise CombineError(message)
                if conflict_policy != "use-first":
                    raise CombineError(
                        f"Internal error: unresolved operator conflict: {message}"
                    )

                warning = f"{message}; keeping the first setting"
                if warning not in warnings:
                    warnings.append(warning)
                continue

            variable_owners[variable] = group_key
            if variable not in obs_vars:
                obs_vars.append(variable)
            if variable not in group.variables:
                group.variables.append(variable)

    nonempty_groups = [group for group in groups.values() if group.variables]
    if not nonempty_groups:
        raise CombineError("No operator variables remained after conflict handling")

    return obs_vars, nonempty_groups, warnings


# ------------------------
# Combine filters while preserving location-level safety
# ------------------------
def ordered_unique(values):
    """Return values once while preserving their first-seen order."""

    result = []
    for value in values:
        if value not in result:
            result.append(value)
    return result


def block_with_lines(occurrence):
    """Create a temporary parsed block using an occurrence's current lines."""

    return FilterBlock(
        leading_lines=(),
        lines=tuple(occurrence.lines),
        jinja_depth=occurrence.block.jinja_depth,
    )


def replace_action_name(lines, old_name, new_name):
    """Replace one configured filter action without touching nested names."""

    result = list(lines)
    for index, line in enumerate(result[:-1]):
        if line.strip() != "action:":
            continue
        for name_index in range(index + 1, len(result)):
            stripped = result[name_index].strip()
            if not stripped:
                continue
            if stripped.startswith("name:"):
                current_name = yaml_scalar(stripped.split(":", 1)[1])
                if current_name == old_name:
                    indent = result[name_index][:
                        len(result[name_index]) - len(result[name_index].lstrip())
                    ]
                    result[name_index] = f"{indent}name: {new_name}"
                return result
            break
    return result


def reduction_is_location_safe(block, obs_vars):
    """Return true when a source filter covers every output variable."""

    variables = named_list(block, "filter variables")
    return bool(variables) and set(variables) == set(obs_vars)


def canonical_filter_lines(lines):
    """Normalize filter indentation and trailing whitespace for comparison."""

    base_indent = leading_spaces(lines[0])
    return tuple(
        line[base_indent:].rstrip() if line.strip() else ""
        for line in lines
    )


def filter_contains_jinja_control(block):
    """Return true when a filter contains conditional Jinja structure."""

    return any(is_active_jinja_control(line) for line in block.lines)


def simple_iuse_filter(block):
    """Return true when an iuse filter can be moved ahead of combined QC."""

    return (
        filter_udescriptor(block) == "iuse_check"
        and block.jinja_depth == 0
        and not filter_contains_jinja_control(block)
    )


def early_merge_position_is_safe(occurrence):
    """Verify that a merge candidate has no stream-specific prerequisite."""

    udescriptor = filter_udescriptor(occurrence.block)
    allowed_predecessors = {
        "at2m_temperature_alias",
        "iuse_check",
        "obs_kx_check",
        "obs_type_check",
    }
    if udescriptor == "time_window_check":
        allowed_predecessors.add("quality_marker_check")

    for block in occurrence.template.filter_section.blocks:
        if block is occurrence.block:
            return True
        predecessor = filter_udescriptor(block)
        if predecessor not in allowed_predecessors:
            return False
        if predecessor == "iuse_check" and not simple_iuse_filter(block):
            return False

    return False


def merge_signature(occurrence):
    """Build a key for pointwise filters differing only by an is_in KX list."""

    block = block_with_lines(occurrence)
    if block.jinja_depth != 0 or filter_contains_jinja_control(block):
        return None
    if filter_name(block) not in POINTWISE_MERGEABLE_FILTERS:
        return None
    if filter_udescriptor(block) not in ORDER_INDEPENDENT_MERGE_UDESCRIPTORS:
        return None
    if not early_merge_position_is_safe(occurrence):
        return None

    selectors = kx_selectors(block, occurrence.template.path)
    if len(selectors) != 1 or selectors[0].operator != "is_in":
        return None

    selector = selectors[0]
    canonical = list(canonical_filter_lines(occurrence.lines))
    selector_line = canonical[selector.value_line_index]
    key_name = selector_line.split(":", 1)[0]
    canonical[selector.value_line_index] = f"{key_name}: <OBS_TYPES>"
    return tuple(canonical)


def replace_selector_values(occurrence, selector, values):
    """Write a union ObsType list into one filter where condition."""

    line = occurrence.lines[selector.value_line_index]
    key = line.split(":", 1)[0]
    occurrence.lines[selector.value_line_index] = (
        f"{key}: {', '.join(values)}"
    )


def merge_compatible_filters(occurrences, stats):
    """Union pointwise KX filters and remove exact redundant filters."""

    groups: Dict[Tuple[str, ...], List[FilterOccurrence]] = OrderedDict()
    for occurrence in occurrences:
        if occurrence.skip:
            continue
        signature = merge_signature(occurrence)
        if signature is not None:
            groups.setdefault(signature, []).append(occurrence)

    for group in groups.values():
        if len(group) < 2:
            continue

        values = []
        for occurrence in group:
            selector = kx_selectors(
                block_with_lines(occurrence),
                occurrence.template.path,
            )[0]
            values.extend(selector.values)

        first = group[0]
        first_selector = kx_selectors(
            block_with_lines(first),
            first.template.path,
        )[0]
        union_values = ordered_unique(values)
        replace_selector_values(first, first_selector, union_values)
        first.notes.append(
            "Merged compatible ObsType selectors: " + ", ".join(union_values)
        )

        for occurrence in group[1:]:
            occurrence.skip = True

        stats.merged_groups += 1
        stats.merged_blocks += len(group) - 1

    exact_blocks: Dict[Tuple[str, ...], FilterOccurrence] = OrderedDict()
    for occurrence in occurrences:
        if occurrence.skip:
            continue

        block = block_with_lines(occurrence)
        if block.jinja_depth != 0 or filter_contains_jinja_control(block):
            continue
        if filter_name(block) not in POINTWISE_MERGEABLE_FILTERS:
            continue
        if filter_udescriptor(block) not in ORDER_INDEPENDENT_MERGE_UDESCRIPTORS:
            continue
        if not early_merge_position_is_safe(occurrence):
            continue

        key = canonical_filter_lines(occurrence.lines)
        if key in exact_blocks:
            occurrence.skip = True
            stats.deduplicated_blocks += 1
        else:
            exact_blocks[key] = occurrence


def time_window_details(block, path):
    """Return a simple numeric time-window definition, or None."""

    if filter_udescriptor(block) != "time_window_check":
        return None
    if filter_name(block) != "Bounds Check":
        return None
    if filter_action(block) != "reduce obs space":
        return None
    if top_level_filter_value(block, "defer to post") == "true":
        return None

    test_variables = named_list(block, "test variables")
    minimum = top_level_filter_value(block, "minvalue")
    maximum = top_level_filter_value(block, "maxvalue")
    selectors = kx_selectors(block, path)
    if (
        len(test_variables) != 1
        or minimum is None
        or maximum is None
        or len(selectors) != 1
        or selectors[0].operator != "is_in"
    ):
        return None

    try:
        minimum_number = float(minimum)
        maximum_number = float(maximum)
    except ValueError:
        return None

    return test_variables[0], minimum_number, maximum_number


def format_number(value):
    """Format an integer-valued float without a decimal suffix."""

    if value.is_integer():
        return str(int(value))
    return str(value)


def find_shared_time_reducer(templates, occurrences, obs_vars):
    """Find the widest safe time window shared by a mixed ObsSpace."""

    by_template: Dict[Path, List[FilterOccurrence]] = OrderedDict()
    for occurrence in occurrences:
        if filter_udescriptor(occurrence.block) == "time_window_check":
            by_template.setdefault(occurrence.template.path, []).append(occurrence)

    selected = []
    details = []
    for template in templates:
        candidates = by_template.get(template.path, [])
        if len(candidates) != 1:
            return None
        detail = time_window_details(candidates[0].block, template.path)
        if detail is None:
            return None
        selector = kx_selectors(candidates[0].block, template.path)[0]
        if (
            selector.variable != template.selection.kx_variable
            or set(selector.values) != set(template.selection.kx_values)
        ):
            return None
        selected.append(candidates[0])
        details.append(detail)

    if not selected:
        return None
    if all(reduction_is_location_safe(item.block, obs_vars) for item in selected):
        return None

    test_variables = {detail[0] for detail in details}
    if len(test_variables) != 1:
        return None

    minimum = min(detail[1] for detail in details)
    maximum = max(detail[2] for detail in details)
    redundant = {
        id(occurrence)
        for occurrence, detail in zip(selected, details)
        if detail[1] == minimum and detail[2] == maximum
    }
    return next(iter(test_variables)), minimum, maximum, redundant


def build_selection_reducers(templates, obs_vars):
    """Build union validity and KX filters that may safely remove locations."""

    value_variables = ordered_unique(
        template.selection.value_variable for template in templates
    )
    kx_by_variable: Dict[str, List[str]] = OrderedDict()
    for template in templates:
        values = kx_by_variable.setdefault(template.selection.kx_variable, [])
        for value in template.selection.kx_values:
            if value not in values:
                values.append(value)

    lines = [
        "         # ---- Safe combined location reduction ----",
        "         # Keep a location when at least one source ObsValue is valid.",
        "         - filter: Domain Check",
        '           udescriptor: "obs_type_check"',
        "           filter variables:",
    ]
    lines.extend(f"           - name: {variable}" for variable in obs_vars)
    lines.append("           where:")
    for variable in value_variables:
        lines.extend(
            [
                f"           - variable: ObsValue/{variable}",
                "             value: is_valid",
            ]
        )
    if len(value_variables) > 1:
        lines.append("           where operator: or")
    lines.extend(
        [
            "           action:",
            "             name: reduce obs space",
            "",
            "         # Keep a location when at least one variable has an allowed KX.",
            "         - filter: Domain Check",
            '           udescriptor: "obs_kx_check"',
            "           filter variables:",
        ]
    )
    lines.extend(f"           - name: {variable}" for variable in obs_vars)
    lines.append("           where:")
    for variable, values in kx_by_variable.items():
        lines.extend(
            [
                f"           - variable: ObsType/{variable}",
                f"             is_in: {', '.join(values)}",
            ]
        )
    if len(kx_by_variable) > 1:
        lines.append("           where operator: or")
    lines.extend(
        [
            "           action:",
            "             name: reduce obs space",
            "",
        ]
    )
    return lines


def build_time_reducer(test_variable, minimum, maximum, obs_vars):
    """Build a broad time filter that is safe for every source stream."""

    lines = [
        "         # Remove only locations outside every source time window.",
        "         - filter: Bounds Check",
        '           udescriptor: "combined_time_window_check"',
        "           filter variables:",
    ]
    lines.extend(f"           - name: {variable}" for variable in obs_vars)
    lines.extend(
        [
            "           test variables:",
            f"           - name: {test_variable}",
            f"           minvalue: {format_number(minimum)}",
            f"           maxvalue: {format_number(maximum)}",
            "           action:",
            "             name: reduce obs space",
            "",
        ]
    )
    return lines


def build_combined_filters(templates, obs_vars):
    """Transform and render all filters for one combined ObsSpace."""

    stats = FilterMergeStats()
    occurrences = []
    occurrences_by_template: Dict[Path, List[FilterOccurrence]] = OrderedDict()

    for template in templates:
        template_occurrences = []
        for block in template.filter_section.blocks:
            occurrence = FilterOccurrence(
                template=template,
                block=block,
                lines=list(block.lines),
            )
            occurrences.append(occurrence)
            template_occurrences.append(occurrence)
        occurrences_by_template[template.path] = template_occurrences

    for occurrence in occurrences:
        if filter_udescriptor(occurrence.block) in SELECTION_UDESCRIPTORS:
            occurrence.skip = True

    time_reducer = find_shared_time_reducer(templates, occurrences, obs_vars)
    if time_reducer is not None:
        test_variable, minimum, maximum, redundant = time_reducer
        for occurrence in occurrences:
            if id(occurrence) in redundant:
                occurrence.skip = True
        stats.generated_time_reducer = True

    iuse_occurrences = []
    for occurrence in occurrences:
        if not occurrence.skip and simple_iuse_filter(occurrence.block):
            occurrence.skip = True
            iuse_occurrences.append(occurrence)

    for occurrence in occurrences:
        if occurrence.skip:
            continue
        current_block = block_with_lines(occurrence)
        if filter_action(current_block) != "reduce obs space":
            continue
        if reduction_is_location_safe(current_block, obs_vars):
            continue
        else:
            occurrence.lines = replace_action_name(
                occurrence.lines,
                "reduce obs space",
                "reject",
            )

    merge_compatible_filters(occurrences, stats)

    # Count only source filters that remain in the rendered output.
    for occurrence in occurrences:
        if occurrence.skip:
            continue
        if filter_action(occurrence.block) != "reduce obs space":
            continue
        if filter_action(block_with_lines(occurrence)) == "reduce obs space":
            stats.retained_reductions += 1
        else:
            stats.converted_reductions += 1

    output = build_selection_reducers(templates, obs_vars)
    if time_reducer is not None:
        output.extend(build_time_reducer(test_variable, minimum, maximum, obs_vars))

    output.extend(build_reject_filter(obs_vars).rstrip().splitlines())
    output.append("")

    if iuse_occurrences:
        output.append("         # ---- Accept, reject, or passivate configured streams ----")
        for occurrence in iuse_occurrences:
            output.append(f"         # From {occurrence.template.path.name}")
            output.extend(occurrence.lines)
            output.append("")

    for template in templates:
        output.append(f"# ---- Filters retained from {template.path.name} ----")
        for occurrence in occurrences_by_template[template.path]:
            structural, decorative = split_structural_prefix(
                occurrence.block.leading_lines
            )
            output.extend(structural)
            if occurrence.skip:
                continue
            output.extend(decorative)
            for note in occurrence.notes:
                output.append(f"         # {note}")
            output.extend(occurrence.lines)
        output.extend(template.filter_section.trailing_lines)
        output.append("")

    return "\n".join(output).rstrip() + "\n", stats


# ------------------------
# Build obs operator block
# ------------------------
def render_simple_operator(section_name, operator, variables):
    """Render a non-Composite operator using its original options."""

    lines = [f"       {section_name}:", f"         name: {operator.name}"]
    lines.extend(
        f"         {line}" if line else ""
        for line in operator.option_lines
    )

    if operator.had_variables:
        lines.append("         variables:")
        lines.extend(f"         - name: {variable}" for variable in variables)
    return lines


def render_operator_component(operator, variables):
    """Render one variable-routed component of a Composite operator."""

    lines = [f"         - name: {operator.name}"]
    lines.extend(
        f"           {line}" if line else ""
        for line in operator.option_lines
    )
    lines.append("           variables:")
    lines.extend(f"           - name: {variable}" for variable in variables)
    return lines


def render_composite_operator(section_name, operators_and_variables):
    """Render components when variables require different operator settings."""

    lines = [
        f"       {section_name}:",
        "         name: Composite",
        "         components:",
    ]
    for operator, variables in operators_and_variables:
        if operator.name == "Composite":
            raise CombineError(
                f"Cannot nest an existing Composite inside combined '{section_name}'"
            )
        lines.extend(render_operator_component(operator, variables))
    return lines


def build_obs_operator_block(groups):
    """Build nonlinear and linear operator sections from source-derived groups."""

    if len(groups) == 1:
        obs_lines = render_simple_operator(
            "obs operator", groups[0].obs_operator, groups[0].variables
        )
    else:
        obs_lines = render_composite_operator(
            "obs operator",
            [
                (group.obs_operator, group.variables)
                for group in groups
            ],
        )

    linear_operators = [group.linear_obs_operator for group in groups]
    if all(operator is None for operator in linear_operators):
        return "\n".join(obs_lines) + "\n"
    if any(operator is None for operator in linear_operators):
        missing_sources = ", ".join(
            source.name
            for group in groups
            if group.linear_obs_operator is None
            for source in group.source_files
        )
        raise CombineError(
            "Cannot build a Composite linear obs operator because these inputs "
            f"have no linear obs operator: {missing_sources}"
        )

    if len(groups) == 1:
        linear_lines = render_simple_operator(
            "linear obs operator",
            groups[0].linear_obs_operator,
            groups[0].variables,
        )
    else:
        linear_lines = render_composite_operator(
            "linear obs operator",
            [
                (group.linear_obs_operator, group.variables)
                for group in groups
            ],
        )

    return "\n".join(obs_lines + [""] + linear_lines) + "\n"


# ------------------------
# Build universal reject-all filter
# ------------------------
def build_reject_filter(obs_vars):
    return (
        "         # ---- Initial blanket rejection ----\n"
        "         - filter: Perform Action\n"
        "           udescriptor: \"obs_type_check_initial_reject\"\n"
        "           filter variables:\n"
        + "".join(f"           - name: {variable}\n" for variable in obs_vars)
        + "           action:\n"
          "             name: reject\n\n"
    )


# ------------------------
# Build YAML header
# ------------------------
def build_obs_space_yaml(templates, space_name, input_name, conflict_policy):
    """Build one ObsSpace entry from a compatible template partition."""

    obs_vars, operator_groups, warnings = collect_partition(
        templates,
        conflict_policy,
    )
    obs_operator_block = build_obs_operator_block(operator_groups)
    filters, filter_stats = build_combined_filters(templates, obs_vars)

    combined_from = ", ".join(template.path.name for template in templates)
    vars_csv = ", ".join(obs_vars)

    obs_space = f"""# ObsSpace {space_name} combined from: {combined_from}
     - obs space:
         name: {space_name}
         distribution:
           name: "{{{{distribution}}}}"
           halo size: 500e3
         obsdatain:
           engine:
             type: H5File
             obsfile: "data/obs/ioda_{input_name}.nc"
             missing file action: "warn"
           obsgrouping:
             group variables: ["stationIdentification"]
             sort variable: "pressure"
             sort order: "descending"
         obsdataout:
           empty obs space action: "{{{{empty_obs_space_action}}}}"
           engine:
             type: H5File
             obsfile: jdiag_{space_name}.nc
             allow overwrite: true
         io pool:
           max pool size: 1
         observed variables: [{vars_csv}]
         simulated variables: [{vars_csv}]

{obs_operator_block}       obs error:
         covariance model: diagonal

       obs localizations:
         - localization method: Horizontal Gaspari-Cohn
           lengthscale: 200e3

       obs filters:
{filters}
"""

    return obs_space, warnings, filter_stats


def build_combined_yaml(input_names, output_name, conflict_policy):
    """Build one or more combined ObsSpaces using the requested conflict policy."""

    templates = parse_input_templates(input_names)
    input_name = Path(Path(output_name).stem).stem

    if conflict_policy == "split":
        partitions = partition_inputs(templates)
    else:
        partitions = [ObsSpacePartition(templates=templates)]

    header_lines = [
        "# Auto-generated by combine_obs_spaces.py",
        f"# Operator conflict policy: {conflict_policy}",
    ]
    if len(partitions) > 1:
        header_lines.append(
            f"# Generated {len(partitions)} ObsSpaces to preserve incompatible "
            "same-variable operator settings"
        )

    obs_spaces = []
    space_names = []
    warnings = []
    filter_stats_by_space = []
    for index, partition in enumerate(partitions, start=1):
        space_name = input_name if index == 1 else f"{input_name}_{index}"
        space_names.append(space_name)
        partition_yaml, partition_warnings, filter_stats = build_obs_space_yaml(
            partition.templates,
            space_name,
            input_name,
            "error" if conflict_policy == "split" else conflict_policy,
        )
        obs_spaces.append(partition_yaml.rstrip())
        warnings.extend(partition_warnings)
        filter_stats_by_space.append((space_name, filter_stats))

    for warning in warnings:
        header_lines.append(f"# WARNING: {warning}")

    combined_yaml = "\n".join(header_lines) + "\n\n"
    combined_yaml += "\n\n".join(obs_spaces) + "\n"
    return combined_yaml, warnings, space_names, filter_stats_by_space


# ------------------------
# Write output
# ------------------------
def main():
    args = parse_args()
    try:
        combined_yaml, warnings, space_names, filter_stats_by_space = build_combined_yaml(
            args.inputs,
            args.output,
            args.operator_conflict,
        )
        Path(args.output).write_text(combined_yaml, encoding="utf-8")
    except CombineError as error:
        raise SystemExit(f"ERROR: {error}") from None
    except OSError as error:
        raise SystemExit(f"ERROR: Could not write {args.output}: {error}") from None

    for warning in warnings:
        print(f"WARNING: {warning}", file=sys.stderr)
    if len(space_names) > 1:
        print(
            f"Generated {len(space_names)} ObsSpaces in {args.output}: "
            + ", ".join(space_names)
        )
    for space_name, stats in filter_stats_by_space:
        time_reducer = "yes" if stats.generated_time_reducer else "no"
        print(
            f"Filter summary for {space_name}: "
            f"merged {stats.merged_blocks} blocks in {stats.merged_groups} groups; "
            f"removed {stats.deduplicated_blocks} exact duplicates; "
            f"retained {stats.retained_reductions} source reductions; "
            f"converted {stats.converted_reductions} unsafe reductions to reject; "
            f"shared time reducer: {time_reducer}"
        )
    print(f"Combined YAML written to: {args.output}")


if __name__ == "__main__":
    main()
