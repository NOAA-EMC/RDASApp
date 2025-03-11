import yaml

yaml_file = "./jedi.yaml"

# Load the YAML
with open(yaml_file, "r") as file:
    yaml_data = file.readlines()

# Dynamically comment out the block
start_commenting = False
for i, line in enumerate(yaml_data):
    if "# Error inflation based on pressure check (setupq.f90)" in line:
        start_commenting = True
    if start_commenting:
        if line.strip():  # Avoid empty lines
            yaml_data[i] = "# " + line
        if line.strip() == "request_saturation_specific_humidity_geovals: true":  
            start_commenting = False

# Save the updated file
with open(f"{yaml_file}", "w") as file:
    file.writelines(yaml_data)
