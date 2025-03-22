#!/usr/bin/env python
from netCDF4 import Dataset
import matplotlib
matplotlib.use('agg')
import matplotlib.pyplot as plt
import cartopy
import cartopy.crs as ccrs
import cartopy.feature as cfeature
import numpy as np
import sys, os
import warnings
from matplotlib.tri import Triangulation, TriAnalyzer

warnings.filterwarnings('ignore')

############ USER INPUT ##########################################################

# MPAS info
jstatic = "data/invariant.nc"  # to load the MPAS lat/lon
ens_file = "mpasout.2024-05-27_00.00.00.nc"
nmems = 30

# Plotting options
variable = "airTemperature"  # currently only working for [airTemperature]
lev = 23                # 1=sfc, 55=toa
plot_box_width = 100.     # define size of plot domain (units: lat/lon degrees)
plot_box_height = 50.
cen_lat = 34.5
cen_lon = -97.5

###################################################################################

# Set cartopy shapefile path
platform = os.getenv('HOSTNAME').upper()
if 'ORION' in platform:
    cartopy.config['data_dir']='/work/noaa/fv3-cam/sdegelia/cartopy'
elif 'H' in platform:  # Will need to improve this once Hercules is supported
    cartopy.config['data_dir']='/home/Donald.E.Lippi/cartopy'

# Get domain info
f_latlon = Dataset(jstatic, "r")
lats = np.array(f_latlon.variables['latCell'][:]) * 180.0 / np.pi
lons0 = np.array(f_latlon.variables['lonCell'][:]) * 180.0 / np.pi
lons = np.where(lons0 > 180.0, lons0 - 360.0, lons0)

# Now read the var you want
bg_all = []
for imem in range(1, nmems + 1):
    try:
        infile = 'data/ens/mem%s/%s' % (str(imem).zfill(3), ens_file)
        nc = Dataset(infile, 'r')
    except FileNotFoundError:
        infile = 'data/ens/mem%s/%s' % (str(imem).zfill(2), ens_file)
        nc = Dataset(infile, 'r')
    if variable == 'airTemperature':
        bg = nc.variables['theta'][0, :, lev].astype(np.float64)
        pres = (nc.variables['pressure_p'][0, :, lev] + nc.variables['pressure_base'][0, :, lev]) / 100.0
        dividend = (1000.0 / pres) ** (0.286)
        bg = bg / dividend
    else:
        sys.exit("Error: requested variable not yet implemented.")
    bg_all.append(bg)

# Compute variance
bg_all = np.asarray(bg_all)
var = np.nanvar(bg_all, axis=0)

# Define plot domain bounds
half = plot_box_width / 2.
left = cen_lon - half
right = cen_lon + half
half = plot_box_height / 2.
bot = cen_lat - half
top = cen_lat + half

# Create plot ##############################
fig = plt.figure(figsize=(7, 4))
m1 = fig.add_subplot(1, 1, 1, projection=ccrs.PlateCarree(central_longitude=0))

m1.set_extent([left, right, bot, top])

m1.add_feature(cfeature.COASTLINE)
m1.add_feature(cfeature.BORDERS)
m1.add_feature(cfeature.STATES)

# Define colormap
units = r"$K^2$"
cmap = plt.get_cmap('viridis')
cmap.set_under('gray')

# Plot using Delaunay triangulation
triang = Triangulation(lons, lats)
mask = TriAnalyzer(triang).get_flat_tri_mask(min_circle_ratio=0.1)
triang.set_mask(mask)

# Plot the variance data on the triangulation
c1 = m1.tricontourf(triang, var, cmap=cmap, levels=100, transform=ccrs.PlateCarree())

# Add colorbar
cbar1 = fig.colorbar(c1, orientation="horizontal", fraction=0.046, pad=0.07)
cbar1.set_label(units, size=8)
cbar1.ax.tick_params(labelsize=5, rotation=30)

plt.tight_layout()
plt.savefig(f"./spread_{variable}.png", dpi=250, bbox_inches='tight')
plt.close()

