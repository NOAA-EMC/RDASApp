#!/usr/bin/env python
import netCDF4 as nc
import numpy as np
import matplotlib
import os
import cartopy
import cartopy.crs as ccrs
import cartopy.feature as cfeature
import matplotlib.ticker as mticker
from cartopy.mpl.gridliner import LONGITUDE_FORMATTER, LATITUDE_FORMATTER
import argparse
import warnings
import matplotlib.pyplot as plt

# Disable warnings for cleaner output
warnings.filterwarnings('ignore')

# Set matplotlib backend to 'agg' for non-interactive environments
matplotlib.use('agg')

# Parse command-line arguments
parser = argparse.ArgumentParser(description='Overlay MPAS and FV3 domains using scatter plots.')
parser.add_argument('mpas_filename', type=str, help='Path to MPAS invariant.nc file')
parser.add_argument('fv3_filename', type=str, help='Path to FV3 grid_spec.nc file')
parser.add_argument('--cen_lat', type=float, default=40.0, help='Central latitude for plot (degrees)')
parser.add_argument('--cen_lon', type=float, default=-97.5, help='Central longitude for plot (degrees)')
parser.add_argument('--plot_box_width', type=float, default=100.0, help='Width of plot box (degrees)')
parser.add_argument('--plot_box_height', type=float, default=50.0, help='Height of plot box (degrees)')
parser.add_argument('--output', type=str, default='map_domain_comparison.png', help='Output filename for the plot')
args = parser.parse_args()

# Assign arguments to variables
mpas_filename = args.mpas_filename
fv3_filename = args.fv3_filename
cen_lat = args.cen_lat
cen_lon = args.cen_lon
plot_box_width = args.plot_box_width
plot_box_height = args.plot_box_height
output_filename = args.output

# Read the datasets
grid_ds = nc.Dataset(mpas_filename, 'r')
grid2_ds = nc.Dataset(fv3_filename, 'r')

# Extract latitude and longitude for MPAS dataset
if 'grid_lat' in grid_ds.variables and 'grid_lon' in grid_ds.variables:  # FV3-style grid
    grid_lat = grid_ds.variables['grid_lat'][:, :].flatten()
    grid_lon = grid_ds.variables['grid_lon'][:, :].flatten()
elif 'latCell' in grid_ds.variables and 'lonCell' in grid_ds.variables:  # MPAS grid
    grid_lat = np.degrees(grid_ds.variables['latCell'][:])  # Convert radians to degrees
    grid_lon = np.degrees(grid_ds.variables['lonCell'][:])  # Convert radians to degrees
else:
    raise ValueError("Unrecognized grid format: 'grid_lat'/'grid_lon' or 'latCell'/'lonCell' not found.")

# Extract latitude and longitude for FV3 dataset
grid_lat2 = grid2_ds.variables['grid_lat'][:, :].flatten()
grid_lon2 = grid2_ds.variables['grid_lon'][:, :].flatten()

# Adjust longitudes from [0, 360] to [-180, 180] for plotting
adjusted_lon = np.where(grid_lon > 180, grid_lon - 360, grid_lon)
adjusted_lon2 = np.where(grid_lon2 > 180, grid_lon2 - 360, grid_lon2)

# Calculate plot extent
half_width = plot_box_width / 2.0
left = cen_lon - half_width
right = cen_lon + half_width
half_height = plot_box_height / 2.0
bot = cen_lat - half_height
top = cen_lat + half_height

# Create the figure
fig = plt.figure(figsize=(7, 4))
m1 = fig.add_subplot(1, 1, 1, projection=ccrs.PlateCarree(central_longitude=0))

# Set the correct extent: [lon_min, lon_max, lat_min, lat_max]
m1.set_extent([left, right, bot, top], crs=ccrs.PlateCarree())

# Add geographical features
m1.add_feature(cfeature.COASTLINE, zorder=10)
m1.add_feature(cfeature.BORDERS, zorder=10)
m1.add_feature(cfeature.STATES, zorder=10)

# Add gridlines
gl1 = m1.gridlines(crs=ccrs.PlateCarree(), draw_labels=True, linewidth=0.5, color='k', alpha=0.25, linestyle='-')
gl1.xlocator = mticker.FixedLocator(np.arange(-180.0, 181.0, 10.0))
gl1.ylocator = mticker.FixedLocator(np.arange(-80.0, 91.0, 10.0))
gl1.xformatter = LONGITUDE_FORMATTER
gl1.yformatter = LATITUDE_FORMATTER
gl1.xlabel_style = {'size': 5, 'color': 'gray'}
gl1.ylabel_style = {'size': 5, 'color': 'gray'}

# Scatter plot the domains
m1.scatter(adjusted_lon, grid_lat, c='b', s=1, label='MPAS Domain', zorder=2)
m1.scatter(adjusted_lon2, grid_lat2, c='y', s=1, label='FV3 Domain', zorder=3)

# Add legend and title
leg = plt.legend(loc='upper right', framealpha=0.9)
leg.set_zorder(100)
plt.title('MPAS and FV3 Domain Comparison')

# Finalize and save the plot
plt.tight_layout()
plt.savefig(output_filename, dpi=350)

# Close the datasets
grid_ds.close()
grid2_ds.close()
plt.close(fig)
