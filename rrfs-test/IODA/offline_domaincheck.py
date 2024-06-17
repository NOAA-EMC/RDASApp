import numpy as np 
from netCDF4 import Dataset
import os 

###########################################################
# This code performs a very simple domain check for IODA 
# observations output from bufr2ioda.x based on a range 
# of latitude and longitudes. Currently, the online domain
# check in JEDI/UFO keeps obs. in memory which causes various
# issues including when using halo obs. distribution for 
# a regional LETKF. 
# 
# Note: the output file from this code will be appended with
# the "_dc" filter standing for "domain-check". 
###########################################################

### Settings ###
filelist = ['rap.t19z.prepbufr.MSONET.tm00.nc']
lat_range = [21.0, 53.0]
lon_range = [-133.0, -60.0]

### Begin code ###
for infile in filelist: 

    print('Working on %s' % infile)
    nc = Dataset(infile, 'r')

    # Determine which obs to keep based on lat/long 
    keep = np.zeros_like(nc.variables['Location'][:])
    lats = nc.groups['MetaData'].variables['latitude'][:]
    lons = nc.groups['MetaData'].variables['longitude'][:]
    lon_range = np.asarray(lon_range) + 360.0
    for iob in range(0,len(keep)):
        if (lats[iob] < lat_range[1] and lats[iob] > lat_range[0] and
            lons[iob] < lon_range[1] and lons[iob] > lon_range[0]):
            keep[iob] = 1
    if sum(keep) == 0: 
        print('   Skipping... no obs in the given lat/lon range')
        continue
    keep = keep.astype(bool)
    un, counts = np.unique(keep, return_counts=True)

    # Create new file and dimensions
    outfile = infile.replace('.nc', '_dc.nc')
    if os.path.isfile(outfile):
        os.remove(outfile)
    fout = Dataset(outfile, 'w')
    fout.createDimension('Location', counts[1])
    fout.createVariable('Location', 'int64', 'Location')
    fout.variables['Location'][:] = 0
    for attr in nc.variables['Location'].ncattrs(): # Attributes for Location variable
        fout.variables['Location'].setncattr(attr, nc.variables['Location'].getncattr(attr))
    # Copy all non-grouped attributes into new file 
    for attr in nc.ncattrs(): # Attributes for main file
        fout.setncattr(attr, nc.getncattr(attr))

    # Copy all groups and variables into new file, but only keeping the vars in range
    groups = nc.groups
    for group in groups:
        g = fout.createGroup(group)
        for var in nc.groups[group].variables:
            invar = nc.groups[group].variables[var]
            try:  # Non-string variables
                vartype = invar.dtype
                fill = invar.getncattr('_FillValue')
                g.createVariable(var, vartype, 'Location', fill_value=fill)
            except: # String variables
                g.createVariable(var, 'str', 'Location')
            g.variables[var][:] = invar[:][keep]
            # Copy attributes for this variable
            for attr in invar.ncattrs():
                if '_FillValue' in attr: continue
                g.variables[var].setncattr(attr, invar.getncattr(attr))
    fout.close()
