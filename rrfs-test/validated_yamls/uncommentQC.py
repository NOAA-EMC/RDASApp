import yaml
import glob

yaml_file = "./jedi.yaml"

# Load the YAML
with open(yaml_file, "r") as file:
    yaml_data = file.readlines()

# Dynamically uncomment out the block
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

