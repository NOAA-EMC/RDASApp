from netCDF4 import Dataset
import pdb
import matplotlib
matplotlib.use('agg')
import matplotlib.pyplot as plt
import matplotlib.colors as mcolors
import cartopy.geodesic
import cartopy
import cartopy.crs as ccrs
import cartopy.feature as cfeature
from cartopy.mpl.gridliner import LONGITUDE_FORMATTER, LATITUDE_FORMATTER
import matplotlib.ticker as mticker
import numpy as np
import time
import sys, os
import shapely.geometry
import warnings
from scipy.spatial.distance import cdist

"""
Compute rotated lon/lat parameters for GSIbec grids.
This tool expects a FV3 grid file (fv3_grid_spec) in the current directory.

Example
-------
python rotated_lonlat_parameters.py

Expected output includes:
nx : 3950, ny : 2700, grid_ratio_fv3_regional : 2.0
nxa : 1976, nya : 1351
north_pole_lat : 34.9999966097°, north_pole_lon : 67.4999923706°
lat_start : -36.4147012390921°, lat_end : 36.4147012390921°
lon_start : -59.7587096910596°, lon_end : 59.7587096910596°
"""

############ USER INPUT ###################
jgrid = f"./fv3_grid_spec"
grid_ratio_fv3_regional = 2.0
do_plot = False
###########################################

############ Constants ####################
deg2rad = np.pi / 180.0
rad2deg = 180.0 / np.pi
quarter = 0.25
one = 1.0
###########################################

# Read lon/lat from fv3_grid_spec
nc_g = Dataset(jgrid, mode='r')
nx = nc_g.dimensions["grid_xt"].size
ny = nc_g.dimensions["grid_yt"].size
grid_latt = nc_g.variables["grid_latt"][:,:].astype(np.float64)
grid_lont = nc_g.variables["grid_lont"][:,:].astype(np.float64)

print(f"nx : {nx}, ny : {ny}, grid_ratio_fv3_regional : {grid_ratio_fv3_regional}")

# Numbers of analysis grids
nxa = 1 + int(np.floor((nx - one) /grid_ratio_fv3_regional + 0.5))
nya = 1 + int(np.floor((ny - one) /grid_ratio_fv3_regional + 0.5))

print(f"nxa : {nxa}, nya : {nya}")

# create xc, yc, zc for the cell centers.
xc = np.zeros((ny, nx))
yc = np.zeros((ny, nx))
zc = np.zeros((ny, nx))
gclat = np.zeros((ny, nx))
gclon = np.zeros((ny, nx))
gcrlat = np.zeros((ny, nx))
gcrlon = np.zeros((ny, nx))

lat_rad = grid_latt * deg2rad
lon_rad = grid_lont * deg2rad

xc = np.cos(lat_rad) * np.cos(lon_rad)
yc = np.cos(lat_rad) * np.sin(lon_rad)
zc = np.sin(lat_rad)


#  compute center as average x,y,z coordinates of corners of domain --
i0, i1 = 0, nx - 1
j0, j1 = 0, ny - 1

xcent = quarter * (xc[j0, i0] + xc[j1, i0] + xc[j0, i1] + xc[j1, i1])
ycent = quarter * (yc[j0, i0] + yc[j1, i0] + yc[j0, i1] + yc[j1, i1])
zcent = quarter * (zc[j0, i0] + zc[j1, i0] + zc[j0, i1] + zc[j1, i1])

rnorm = one / np.sqrt(xcent**2 + ycent**2 + zcent**2)
xcent *= rnorm
ycent *= rnorm
zcent *= rnorm

centlat = np.arcsin(zcent) * rad2deg
centlon = np.arctan2(ycent, xcent) * rad2deg

north_pole_lat = 90.0 - centlat
north_pole_lon = centlon + 180.0 

print(f"north_pole_lat : {north_pole_lat:.10f}°, north_pole_lon : {north_pole_lon:.10f}°")

# compute new lats, lons in the rotated lon-lat
rlon0 = centlon
rlat0 = centlat

lat_rad = grid_latt * deg2rad
lon_rad = grid_lont * deg2rad

x = np.cos(lat_rad) * np.cos(lon_rad)
y = np.cos(lat_rad) * np.sin(lon_rad)
z = np.sin(lat_rad)

rlon0_rad = rlon0 * deg2rad
xt =  x * np.cos(rlon0_rad) + y * np.sin(rlon0_rad)
yt = -x * np.sin(rlon0_rad) + y * np.cos(rlon0_rad)
zt =  z

rlat0_rad = rlat0 * deg2rad
xtt =  xt * np.cos(rlat0_rad) + zt * np.sin(rlat0_rad)
ytt =  yt
ztt = -xt * np.sin(rlat0_rad) + zt * np.cos(rlat0_rad)

gcrlat = np.arcsin(ztt) * rad2deg
gcrlon = np.arctan2(ytt, xtt) * rad2deg

#####################################################
## compute analysis A-grid  lats, lons
#####################################################

# obtain analysis grid spacing
dlat = (np.max(gcrlat) - np.min(gcrlat)) / (ny - 1)
dlon = (np.max(gcrlon) - np.min(gcrlon)) / (nx - 1)
adlat = dlat * grid_ratio_fv3_regional
adlon = dlon * grid_ratio_fv3_regional

# setup analysis A-grid; find center of the domain
nlonh = nxa // 2
nlath = nya // 2

if nxa % 2 == 0: 
    clon = adlon / 2.0
    cx = 0.5
else:            
    clon = adlon
    cx = 1.0

if nya % 2 == 0:
    clat = adlat / 2.0
    cy = 0.5
else:
    clat = adlat
    cy = 1.0

# setup analysis A-grid from center of the domain
j_idx = np.arange(1, nxa + 1)
i_idx = np.arange(1, nya + 1)

J, I = np.meshgrid(j_idx, i_idx)  

lon_rotated = (J - nlonh) * adlon - clon
lat_rotated = (I - nlath) * adlat - clat

print(f"lat_start : {np.min(lat_rotated):.13f}°, lat_end : {np.max(lat_rotated):.13f}°")
print(f"lon_start : {np.min(lon_rotated):.13f}°, lon_end : {np.max(lon_rotated):.13f}°")

if not do_plot: sys.exit()

# unroate
lat_rad = lat_rotated * deg2rad  # shape (nx, ny)
lon_rad = lon_rotated * deg2rad

xtt = np.cos(lat_rad) * np.cos(lon_rad)
ytt = np.cos(lat_rad) * np.sin(lon_rad)
ztt = np.sin(lat_rad)

rlat0_rad = rlat0 * deg2rad
xt = xtt * np.cos(rlat0_rad) - ztt * np.sin(rlat0_rad)
yt = ytt
zt = xtt * np.sin(rlat0_rad) + ztt * np.cos(rlat0_rad)

rlon0_rad = rlon0 * deg2rad
x = xt * np.cos(rlon0_rad) - yt * np.sin(rlon0_rad)
y = xt * np.sin(rlon0_rad) + yt * np.cos(rlon0_rad)
z = zt

rlat_in = np.arcsin(z) * rad2deg
rlon_in = np.arctan2(y, x) * rad2deg

# Draw map

fig = plt.figure(figsize=(3,3))
m1 = fig.add_subplot(1, 1, 1, projection=ccrs.PlateCarree(central_longitude=0))

# Determine extent for plot domain
plot_box_width = 100.     # define size of plot domain (units: lat/lon degrees)
plot_box_height = 50.

# Determine extent for plot domain
cen_lat = centlat
cen_lon = centlon
half = plot_box_width / 2.
left = cen_lon - half
right = cen_lon + half
half = plot_box_height / 2.
bot = cen_lat - half
top = cen_lat + half

# Set extent for both plots
#m1.set_extent([-179, 180, -90, 90])
m1.set_extent([left, right, top, bot])

# Add features to the subplots
m1.add_feature(cfeature.COASTLINE)
m1.add_feature(cfeature.BORDERS)

# Gridlines for the subplots
gl1 = m1.gridlines(crs = ccrs.PlateCarree(), draw_labels = True, linewidth = 0.5, color = 'k', alpha = 0.25, linestyle = '-')
gl1.xlocator = mticker.FixedLocator([])
gl1.xlocator = mticker.FixedLocator(np.arange(-180., 181., 20.))
gl1.ylocator = mticker.FixedLocator(np.arange(-80., 91., 20.))
gl1.xformatter = LONGITUDE_FORMATTER
gl1.yformatter = LATITUDE_FORMATTER
gl1.xlabel_style = {'size': 4, 'color': 'gray'}
gl1.ylabel_style = {'size': 4, 'color': 'gray'}

# Scatter the single ob location
m1.scatter(rlon_in, rlat_in, color='b', marker='o', s=0.01)
m1.scatter(grid_lont, grid_latt, color='g', marker='o', s=0.01)

plt.savefig(f"./test.png", dpi=400, bbox_inches='tight')
