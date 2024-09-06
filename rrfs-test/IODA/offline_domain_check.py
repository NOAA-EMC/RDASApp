#!/usr/bin/env python
import netCDF4 as nc
import numpy as np
from matplotlib.path import Path
from scipy.spatial import ConvexHull
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

"""
This program determines if observations are in/outside of a convex hull
computed via a lat/lon grid file (see note below about the grid file).
A convex hull is the smallest convex shape (or polygon) that can enclose a set
of points in a plane (or in higher dimensions). Imagine stretching a rubber band
around the outermost points in a set; the shape that the rubber band forms is
the convex hull. So, if there are any concave points between vertices,
then there would be whitespace between the red and blue box. I've shrunk the
convex hull such that there wouldn't be such whitespace which, of course,
in tern means that it is going to be not an exact match of the domain grid
(e.g., near corners). This can be tuned via the "hull_shrink_factor".
"""

# Disable warnings
warnings.filterwarnings('ignore')

# Set matplotlib backend
matplotlib.use('agg')
import matplotlib.pyplot as plt

# Functions for calculating run times.
def tic():
    return timer()

def toc(tic=tic, label=""):
    toc = timer()
    elapsed = toc-tic
    hrs = int(elapsed // 3600)
    mins = int((elapsed % 3600) // 60)
    secs = int(elapsed % 3600 % 60)
    print(f"{label}({elapsed:.2f}s), {hrs:02}:{mins:02}:{secs:02}")

tic1 = tic()

# Parse command-line arguments
# Note:
#    The grid file is what contains variables grid_lat/grid_lon
#    OR latCell/lonCell for FV3 and MPAS respectively.
#    Examples can be found in the following rrfs-test cases:
#      - rrfs-data_fv3jedi_2022052619/Data/bkg/fv3_grid_spec.nc
#      - mpas_2024052700/data/restart.2024-05-27_00.00.00.nc
parser = argparse.ArgumentParser()
parser.add_argument('-g', '--grid', type=str, help='grid file', required=True)
parser.add_argument('-o', '--obs', type=str, help='ioda observation file', required=True)
parser.add_argument('-f', '--fig', action='store_true', help='disable figure (default is False)', required=False)
args = parser.parse_args()

# Assign filenames
obs_filename = args.obs
grid_filename = args.grid  # see note above.
make_fig = args.fig

print(f"Obs file: {obs_filename}")
print(f"Grid file: {grid_filename}")
print(f"Figure flag: {args.fig}")

# Plotting options
plot_box_width = 100. # define size of plot domain (units: lat/lon degrees)
plot_box_height = 50
cen_lat = 34.5
cen_lon = -97.5
hull_shrink_factor = 0.04  #4% was found to work fairly well.

grid_ds = nc.Dataset(grid_filename, 'r')
obs_ds = nc.Dataset(obs_filename, 'r')

# Extract the grid latitude and longitude
if 'grid_lat' in grid_ds.variables and 'grid_lon' in grid_ds.variables:  # FV3 grid
    grid_lat = grid_ds.variables['grid_lat'][:, :]
    grid_lon = grid_ds.variables['grid_lon'][:, :]
    dycore = "FV3"
elif 'latCell' in grid_ds.variables and 'lonCell' in grid_ds.variables:  # MPAS grid
    grid_lat = np.degrees(grid_ds.variables['latCell'][:])  # Convert radians to degrees
    grid_lon = np.degrees(grid_ds.variables['lonCell'][:])  # Convert radians to degrees
    dycore = "MPAS"
else:
    raise ValueError("Unrecognized grid format: 'grid_lat'/'grid_lon' or 'latCell'/'lonCell' not found.")

print(f"Max/Min Lat: {np.max(grid_lat)}, {np.min(grid_lat)}")
print(f"Max/Min Lon: {np.max(grid_lon)-360}, {np.min(grid_lon)-360}\n")

# Flatten the grid lat/lon arrays and pair them as coordinates
grid_polygon = np.vstack((grid_lon.flatten(), grid_lat.flatten())).T
grid_polygon = np.ma.filled(grid_polygon, np.nan)
grid_polygon = grid_polygon[~np.isnan(grid_polygon).any(axis=1)]

# Create convex hull from grid points
hull = ConvexHull(grid_polygon)
hull_points = grid_polygon[hull.vertices]

# Compute the centroid of the convex hull
centroid = np.mean(hull_points, axis=0)

# Function to shrink the boundary points
def shrink_boundary(points, centroid, factor=0.04):
    new_points = []
    for point in points:
        direction = point - centroid
        distance_to_centroid = np.linalg.norm(direction)
        direction_normalized = direction / distance_to_centroid
        new_point = point - factor * direction_normalized * distance_to_centroid
        new_points.append(new_point)
    return np.array(new_points)

# Shrink the hull boundary
shrunken_points = shrink_boundary(hull_points, centroid, factor=hull_shrink_factor)

# Ensure the boundary is closed
if not np.array_equal(shrunken_points[0], shrunken_points[-1]):
    shrunken_points = np.vstack([shrunken_points, shrunken_points[0]])

# Create a Path object for the polygon domain
domain_path = Path(shrunken_points)

# Extract observation latitudes and longitudes
obs_lat = obs_ds.groups['MetaData'].variables['latitude'][:]
obs_lon = obs_ds.groups['MetaData'].variables['longitude'][:]

# Pair the observation lat/lon as coordinates
obs_coords = np.vstack((obs_lon, obs_lat)).T

# Check if each observation is within the domain
inside_domain = domain_path.contains_points(obs_coords)

# Get indices of observations within the domain
inside_indices = np.where(inside_domain)[0]
toc(tic1,label="Time to find obs within domain: ")

tic2 = tic()
# Create a new NetCDF file to store the selected data using the more efficient method
try:
    outfile = obs_filename.replace('.nc', '_dc.nc')
except:
    outfile = obs_filename.replace('.nc4', '_dc.nc4')
fout = nc.Dataset(outfile, 'w')

# Create dimensions and variables in the new file
fout.createDimension('Location', len(inside_indices))
fout.createVariable('Location', 'int64', 'Location')
fout.variables['Location'][:] = 0
for attr in obs_ds.variables['Location'].ncattrs():  # Attributes for Location variable
    fout.variables['Location'].setncattr(attr, obs_ds.variables['Location'].getncattr(attr))

# Copy all non-grouped attributes into the new file
for attr in obs_ds.ncattrs():  # Attributes for the main file
    fout.setncattr(attr, obs_ds.getncattr(attr))

# Copy all groups and variables into the new file, keeping only the variables in range
groups = obs_ds.groups
for group in groups:
    g = fout.createGroup(group)
    for var in obs_ds.groups[group].variables:
        invar = obs_ds.groups[group].variables[var]
        try:  # Non-string variables
            vartype = invar.dtype
            fill = invar.getncattr('_FillValue')
            g.createVariable(var, vartype, 'Location', fill_value=fill)
        except:  # String variables
            g.createVariable(var, 'str', 'Location')
        g.variables[var][:] = invar[:][inside_indices]
        # Copy attributes for this variable
        for attr in invar.ncattrs():
            if '_FillValue' in attr: continue
            g.variables[var].setncattr(attr, invar.getncattr(attr))

# Close the datasets
obs_ds.close()
fout.close()
grid_ds.close()
toc(tic2,label="Time to create new obs file: ")

tic3 = tic()

if not make_fig:
    exit()

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
adjusted_shrunken_points = np.copy(shrunken_points)
adjusted_shrunken_points[:, 0] = np.where(shrunken_points[:, 0] > 180, shrunken_points[:, 0] - 360, shrunken_points[:, 0])

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
m1.add_feature(cfeature.COASTLINE)
m1.add_feature(cfeature.BORDERS)
m1.add_feature(cfeature.STATES)

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
m1.fill(adjusted_lon.flatten(), grid_lat.flatten(), color='b', label='Domain Boundary', zorder=1, transform=ccrs.PlateCarree())
m1.plot(adjusted_shrunken_points[:, 0], shrunken_points[:, 1], 'r-', label='Convex Hull', zorder=10, transform=ccrs.PlateCarree())

# Plot included observations
included_lat = obs_lat[inside_indices]
included_lon = obs_lon[inside_indices]
plt.scatter(included_lon, included_lat, c='g', s=2, label='Included Observations', zorder=3, transform=ccrs.PlateCarree())

# Plot excluded observations
excluded_indices = np.setdiff1d(np.arange(len(obs_lat)), inside_indices)
excluded_lat = obs_lat[excluded_indices]
excluded_lon = obs_lon[excluded_indices]
plt.scatter(excluded_lon, excluded_lat, c='r', s=2, label='Excluded Observations', zorder=4, transform=ccrs.PlateCarree())

plt.xlabel('Longitude')
plt.ylabel('Latitude')
plt.legend(loc='upper right')
plt.title(f'{dycore} Domain and Observations')
plt.tight_layout()
plt.savefig(f'./domain_check_{dycore}.png')

toc(tic3,label="Time to create figure: ")
toc(tic1,label="Total elapsed time: ")
