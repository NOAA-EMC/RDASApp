import yaml
import glob

# This script modifies some of the super yamls for FV3-JEDI
# It comments out the ObsErrorFactorPressureCheck for adpupa_winds
# It also uncomments the ObsErrorFactorPressureCheck for moisture yamls

yaml_file = "./jedi.yaml"

# Load the YAML
with open(yaml_file, "r") as file:
    yaml_data = file.readlines()

# Remove ObsErrorFactorPressureCheck for adpupa_winds
start_commenting = False
found_obspace = False
check_lines = ["# Error inflation (windEastward) based on pressure check (setupw.f90)", \
               "# Error inflation (windNorthward) based on pressure check (setupw.f90)"]
for i, line in enumerate(yaml_data):
    if "name: adpupa_winds_220" in line:
        found_obspace = True
    if found_obspace:
        if any(x in line for x in check_lines):
            start_commenting = True
        if start_commenting:
            if line.strip():  # Avoid empty lines
                yaml_data[i] = '# ' + line
            if "inflation factor: 4.0" in line:
                start_commenting = False
        if "- obs space:" in line:
            found_obspace = False

# Uncomment ObsErrorFactorPressureCheck for moisture yamls
start_uncommenting = False
for i, line in enumerate(yaml_data):
    if "# Error inflation based on pressure check (setupq.f90)" in line:
        start_uncommenting = True
    if start_uncommenting:
        if line.strip() and line[0] == '#':  # Avoid empty lines
            yaml_data[i] = line[2:]
        if "request_saturation_specific_humidity_geovals: true" in line:
            start_uncommenting = False

# Save the updated file
with open(f"{yaml_file}", "w") as file:
    file.writelines(yaml_data)

