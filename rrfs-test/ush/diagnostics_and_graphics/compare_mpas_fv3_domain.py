#!/usr/bin/env python
import netCDF4 as nc
import numpy as np
from matplotlib.path import Path
from scipy.spatial import ConvexHull, Delaunay
from timeit import default_timer as timer
import argparse
import warnings
import matplotlib
import os
import cartopy
import cartopy.crs as ccrs
import cartopy.feature as cfeature
import matplotlib.ticker as mticker
from cartopy.mpl.gridliner import LONGITUDE_FORMATTER, LATITUDE_FORMATTER
from operator import itemgetter
import shapely.speedups
shapely.speedups.enable()

################
### Settings ###
################

mpas_filename = '/scratch1/BMC/zrtrr/Samuel.Degelia/RDASApp_atms_fv3case/RDASApp/expr/mpas_2024052700/data/invariant.nc'
fv3_filename = '/scratch1/BMC/zrtrr/Samuel.Degelia/RDASApp_atms_fv3case/RDASApp/expr/fv3_2024052700/Data/bkg/grid_spec.nc'

#############################
### Begin executable code ###
#############################

# Disable warnings
warnings.filterwarnings('ignore')

# Set matplotlib backend
matplotlib.use('agg')
import matplotlib.pyplot as plt

# Plotting options
plot_box_width = 100. # define size of plot domain (units: lat/lon degrees)
plot_box_height = 50
cen_lat = 34.5
cen_lon = -97.5

grid_ds = nc.Dataset(mpas_filename, 'r')
grid2_ds = nc.Dataset(fv3_filename, 'r')
grid_lat2 = grid2_ds.variables['grid_lat'][:, :]
grid_lon2 = grid2_ds.variables['grid_lon'][:, :]

# Extract the grid latitude and longitude
if 'grid_lat' in grid_ds.variables and 'grid_lon' in grid_ds.variables:  # FV3 grid
    grid_lat = grid_ds.variables['grid_lat'][:, :]
    grid_lon = grid_ds.variables['grid_lon'][:, :]
    grid_lat = grid_lat.flatten()
    grid_lon = grid_lon.flatten()
elif 'latCell' in grid_ds.variables and 'lonCell' in grid_ds.variables:  # MPAS grid
    grid_lat = np.degrees(grid_ds.variables['latCell'][:])  # Convert radians to degrees
    grid_lon = np.degrees(grid_ds.variables['lonCell'][:])  # Convert radians to degrees
else:
    raise ValueError("Unrecognized grid format: 'grid_lat'/'grid_lon' or 'latCell'/'lonCell' not found.")

print("Generating figure...")

# Now create plot
# Set cartopy shapefile path
platform = os.getenv('HOSTNAME').upper()
if 'ORION' in platform:
        cartopy.config['data_dir']='/work/noaa/fv3-cam/sdegelia/cartopy'
elif 'H' in platform: # Will need to improve this once Hercules is supported
        cartopy.config['data_dir']='/home/Donald.E.Lippi/cartopy'

fig = plt.figure(figsize=(7,4))
m1 = fig.add_subplot(1, 1, 1, projection=ccrs.PlateCarree(central_longitude=0))
#m1 = fig.add_subplot(1, 1, 1, projection=ccrs.LambertConformal())
adjusted_lon = np.where(grid_lon > 180, grid_lon - 360, grid_lon)
adjusted_lon2 = np.where(grid_lon2 > 180, grid_lon2 - 360, grid_lon2)

# Determine extent for plot domain
half = plot_box_width / 2.
left = cen_lon - half
right = cen_lon + half
half = plot_box_height / 2.
bot = cen_lat - half
top = cen_lat + half

# Set extent for both plots
m1.set_extent([left, right, top, bot])

# Add features to the subplots
m1.add_feature(cfeature.COASTLINE, zorder=10)
m1.add_feature(cfeature.BORDERS, zorder=10)
m1.add_feature(cfeature.STATES, zorder=10)

# Gridlines for the subplots
gl1 = m1.gridlines(crs = ccrs.PlateCarree(), draw_labels = True, linewidth = 0.5, color = 'k', alpha = 0.25, linestyle = '-')
gl1.xlocator = mticker.FixedLocator([])
gl1.xlocator = mticker.FixedLocator(np.arange(-180., 181., 10.))
gl1.ylocator = mticker.FixedLocator(np.arange(-80., 91., 10.))
gl1.xformatter = LONGITUDE_FORMATTER
gl1.yformatter = LATITUDE_FORMATTER
gl1.xlabel_style = {'size': 5, 'color': 'gray'}
gl1.ylabel_style = {'size': 5, 'color': 'gray'}

# Plot the domain and the observations
m1.scatter(adjusted_lon.flatten(), grid_lat.flatten(), c='b', s=1, label='MPAS Domain', zorder=2)
m1.scatter(adjusted_lon2.flatten(), grid_lat2.flatten(), c='y', s=1, label='FV3 Domain', zorder=3)

plt.xlabel('Longitude')
plt.ylabel('Latitude')
leg = plt.legend(loc='upper right')
leg.set_zorder(15)
plt.tight_layout()
plt.savefig(f'./domain_comparison.png', dpi=350)

