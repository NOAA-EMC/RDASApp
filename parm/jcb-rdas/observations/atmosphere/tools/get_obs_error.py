#!/usr/bin/env python3
import sys

def parse_file(file_path, obtype, error_col_index):
    with open(file_path, 'r') as file:
        lines = file.readlines()

    xvals = []
    errors = []
    obtype_section = False

    for line in lines:
        line = line.strip()

        # Check for the obtype identifier
        if line.startswith(str(obtype)):
            obtype_section = True
            continue
        elif line.startswith("c") or not line or line.startswith(tuple(map(str, range(obtype + 1, obtype + 2)))):
            obtype_section = False

        # If we're in the specified obtype section, parse the lines
        if obtype_section:
            columns = line.split()
            if len(columns) >= max(2, error_col_index + 1):
                try:
                    xval = int(float(columns[0])*100)
                    if(error_col_index == 2): #RH
                      error = round(float(columns[error_col_index])/10.,13)
                    elif(error_col_index == 4): #sfcp
                      error = round(float(columns[error_col_index])*100.,6)
                    else:
                      error = float(columns[error_col_index])
                    xvals.append(xval)
                    errors.append(error)
                except ValueError:
                    continue

    return xvals, errors

def main():
    if len(sys.argv) != 4:
        print("Usage: python get_obs_error.py <file_path> <obtype> <error_col_index>")
        sys.exit(1)

    file_path = sys.argv[1]
    obtype = int(sys.argv[2])
    error_col_index = int(sys.argv[3])
    if error_col_index == 1:
        print(f"error_col_index={error_col_index} (T)")
    if error_col_index == 2:
        print(f"error_col_index={error_col_index} (RH)")
    if error_col_index == 3:
        print(f"error_col_index={error_col_index} (UV)")
    if error_col_index == 4:
        print(f"error_col_index={error_col_index} (Ps)")

    xvals, errors = parse_file(file_path, obtype, error_col_index)

    print(f'xvals: {xvals}')
    print(f'errors: {errors}')

if __name__ == '__main__':
    main()
