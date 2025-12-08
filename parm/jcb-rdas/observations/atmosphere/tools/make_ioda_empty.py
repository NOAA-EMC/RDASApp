#!/usr/bin/env python3
import sys
import numpy as np
from netCDF4 import Dataset, stringtochar, VLType

def is_string_type(var):
    """
    Return True if var is any known form of netCDF string:
    - netCDF4 datatype == str
    - netCDF4 variable-length string (VLType)
    - numpy byte string (kind='S')
    - numpy unicode (kind='U')
    """
    dt = var.datatype

    # netCDF4 classic variable-length string
    if dt == str:
        return True

    # netCDF4 VLType string
    if isinstance(dt, VLType):
        return True

    # numpy dtype cases
    try:
        if hasattr(var.dtype, "kind"):
            if var.dtype.kind in ("S", "U"):
                return True
    except Exception:
        pass

    return False

def copy_non_fill_attributes(src, dst):
    for aname in src.ncattrs():
        if aname == "_FillValue":
            continue
        dst.setncattr(aname, src.getncattr(aname))

def create_empty_variable(ncout, gname, vname, var):
    # Fill value before creation
    fill_value = var._FillValue if "_FillValue" in var.ncattrs() else None

    # Dimensions: Location -> 1
    dims = []
    for d in var.dimensions:
        if d == "Location":
            dims.append("Location")
        else:
            dims.append(d)

    # Create variable with fill_value at creation time
    vout = ncout.groups[gname].createVariable(
        vname,
        var.dtype,
        dims,
        fill_value=fill_value
    )

    # Copy all NON-fill-value attributes
    copy_non_fill_attributes(var, vout)

    # Build shape
    shape = []
    for d in dims:
        if d == "Location":
            shape.append(1)
        else:
            shape.append(ncout.dimensions[d].size)

    # Construct empty data
    if is_string_type(var):
        arr = np.empty(shape, dtype=object)
        fv = fill_value if fill_value not in (None, "") else ""
        for idx in np.ndindex(*shape):
            arr[idx] = fv

        # Convert to char array if needed
        try:
            if vout.dtype.kind == "S":
                arr = stringtochar(arr)
        except Exception:
            pass

    else:
        fv = fill_value if fill_value is not None else 0
        arr = np.full(shape, fv, dtype=var.dtype)

    vout[:] = arr

def create_empty_ioda(input_file, output_file):
    fin = Dataset(input_file, "r")
    fout = Dataset(output_file, "w", format="NETCDF4")

    # Global attributes
    for a in fin.ncattrs():
        fout.setncattr(a, fin.getncattr(a))

    # Dimensions
    for dname, dim in fin.dimensions.items():
        if dname == "Location":
            fout.createDimension("Location", 1)
        else:
            fout.createDimension(dname, len(dim))

    # Groups
    for gname in fin.groups:
        fout.createGroup(gname)

    # Variables
    for gname, grp in fin.groups.items():
        for vname, var in grp.variables.items():
            create_empty_variable(fout, gname, vname, var)

    fin.close()
    fout.close()
    print(f"Created empty/masked IODA file: {output_file}")

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: make_ioda_empty.py input.nc output.nc")
        sys.exit(1)
    create_empty_ioda(sys.argv[1], sys.argv[2])

