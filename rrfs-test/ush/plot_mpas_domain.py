import os
import sys
import numpy as np
from netCDF4 import Dataset
import matplotlib
import matplotlib.pyplot as plt
import matplotlib.colors as mcolors
import matplotlib.ticker as mticker
from matplotlib.tri import Triangulation, TriAnalyzer
import cartopy.crs as ccrs
from cartopy.mpl.gridliner import LONGITUDE_FORMATTER, LATITUDE_FORMATTER
import cartopy.feature as cfeature

STATIC    = "conus12km.static.nc"                         # to load the MPAS lat/lon 
title = "MPAS_CONUS12km"
#STATIC    = "conus3km.static.nc"                         # to load the MPAS lat/lon 
#title = "MPAS_CONUS3km"
VARIABLE  = "shdmax"                       # variable to plot
f_latlon = Dataset(STATIC, "r")

lats = np.array( f_latlon.variables['latCell'][:] ) * 180.0 / np.pi
lons0 = np.array( f_latlon.variables['lonCell'][:] ) * 180.0 / np.pi
lons = np.where(lons0>180.0,lons0-360.0,lons0)

data = np.array( f_latlon.variables[VARIABLE][:] )

print(lats)
print(min(lons),max(lons))
print(data)
print(min(data),max(data))

fig = plt.figure(figsize=(12,12))
m1 = fig.add_subplot(1, 1, 1, projection=ccrs.PlateCarree(central_longitude=0))

central_lat = 34.5
central_lon = -97.5
extent = [-136, -58, 18, 50]  
m1.set_extent(extent)

# Add features to the subplots
m1.add_feature(cfeature.COASTLINE)
m1.add_feature(cfeature.BORDERS)
m1.add_feature(cfeature.STATES)

# Gridlines for the subplots
gl1 = m1.gridlines(crs=ccrs.PlateCarree(), draw_labels=True, linewidth=0.5, color='k', alpha=0.25, linestyle='-')
gl1.xlocator = mticker.FixedLocator(np.arange(-180., 181., 5.))
gl1.ylocator = mticker.FixedLocator(np.arange(-80., 91., 2.))
gl1.xformatter = LONGITUDE_FORMATTER
gl1.yformatter = LATITUDE_FORMATTER
gl1.xlabel_style = {'size': 5, 'color': 'gray'}
gl1.ylabel_style = {'size': 5, 'color': 'gray'}

# Create triangulation and mask
triang = Triangulation(lons, lats)
mask = TriAnalyzer(triang).get_flat_tri_mask(min_circle_ratio=0.1)
triang.set_mask(mask)

# Plot the data using triangulation
c1 = m1.tricontourf(triang, data, cmap='seismic', transform=ccrs.PlateCarree())

# Add colorbar
cbar1 = fig.colorbar(c1, orientation="horizontal", fraction=0.046, pad=0.07)
cbar1.ax.tick_params(labelsize=5, rotation=30)

# Add titles, text, and save the figure
plt.title(title)
plt.tight_layout()
plt.savefig(f"./{title}.png", dpi=250, bbox_inches='tight')
plt.close()
