import yaml, sys

ctest = sys.argv[1]
yaml_file = "./jedi.yaml"

def comment_block(yaml_in, start_line, end_line):

    # Load the YAML
    with open(yaml_in, "r") as file:
        yaml_data = file.readlines()

    # Dynamically comment out the block
    start_commenting = False
    for i, line in enumerate(yaml_data):
        if start_line in line:
            start_commenting = True
        if start_commenting:
            if line.strip():  # Avoid empty lines
                yaml_data[i] = "# " + line
            if line.strip() == end_line:
                start_commenting = False

    with open(f"{yaml_file}", "w") as file:
        file.writelines(yaml_data)

    return

def comment_line(yaml_in, cline):

    # Load the YAML
    with open(yaml_in, "r") as file:
        yaml_data = file.readlines()

    # Dynamically comment out the line
    for i, line in enumerate(yaml_data):
        if cline in line:
            yaml_data[i] = "#" + line

    with open(f"{yaml_file}", "w") as file:
        file.writelines(yaml_data)

    return

if 'mpas' in ctest:
    start = "# Error inflation based on pressure check (setupq.f90)"
    end = "request_saturation_specific_humidity_geovals: true"
    comment_block(yaml_file, start, end)
if 'fv3' in ctest:
    comment_line(yaml_file, "SurfaceWindGeoVars: uv")
    comment_line(yaml_file, "IRVISlandCoeff: IGBP")
