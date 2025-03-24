#!/usr/bin/env python
from netCDF4 import Dataset
import matplotlib
matplotlib.use('agg')
import matplotlib.pyplot as plt
import matplotlib.colors as mcolors
import cartopy
import cartopy.crs as ccrs
import cartopy.feature as cfeature
from cartopy.mpl.gridliner import LONGITUDE_FORMATTER, LATITUDE_FORMATTER
import matplotlib.ticker as mticker
import numpy as np
import colormap
import os
import warnings
from matplotlib.tri import Triangulation, TriAnalyzer
from scipy.interpolate import interp1d

warnings.filterwarnings('ignore')

############ USER INPUT ##########################################################
plot_var = "Increment"
pres_lev = 500         # additionally, choose a specific pressure level in hPa
clevmax_incr = 2.0      # max contour level for colorbar increment plots
decimals = 2            # number of decimals to round for text boxes
plot_box_width = 100.   # define size of plot domain (units: lat/lon degrees)
plot_box_height = 50.
cen_lat = 34.5
cen_lon = -97.5

variable = "airTemperature"
if variable == "airTemperature":
    obtype = 't'
    offset = -273.15

# JEDI data
datapath = "./"
jstatic      = "./data/invariant.nc"                 # to load the MPAS lat/lon

janalysis   = "./ana.2024-05-27_00.00.00.nc"            # analysis file
jbackgrnd   = "./data/mpasout.2024-05-27_00.00.00.nc"            # background file

###################################################################################
# Set cartopy shapefile path
platform = os.getenv('HOSTNAME').upper()
if 'ORION' in platform:
    cartopy.config['data_dir']='/work/noaa/fv3-cam/sdegelia/cartopy'
elif 'H' in platform: # Will need to improve this once Hercules is supported
    cartopy.config['data_dir']='/home/Donald.E.Lippi/cartopy'

f_latlon = Dataset(jstatic, "r")
lats = np.array(f_latlon.variables['latCell'][:]) * 180.0 / np.pi
lons0 = np.array(f_latlon.variables['lonCell'][:]) * 180.0 / np.pi
lons = np.where(lons0 > 180.0, lons0 - 360.0, lons0)

# Open NETCDF4 dataset for reading
nc_a = Dataset(janalysis, mode='r')
nc_b = Dataset(jbackgrnd, mode='r')

# Read data and get dimensions
jedi_a = nc_a.variables["theta"][0, :, :].astype(np.float64)
jedi_b = nc_b.variables["theta"][0, :, :].astype(np.float64)

# Convert to temperature
if variable == "airTemperature":
	pres_a = (nc_a.variables['pressure_p'][0,:,:] + nc_b['pressure_base'][0,:,:])/100.0
	pres_b = (nc_b.variables['pressure_p'][0,:,:] + nc_b['pressure_base'][0,:,:])/100.0
	dividend_a = (1000.0/pres_a)**(0.286)
	dividend_b = (1000.0/pres_b)**(0.286)
	jedi_a = jedi_a / dividend_a
	jedi_b = jedi_b / dividend_b

# Compute increment
jedi_inc_all = jedi_a - jedi_b

# Interpolate using user input pressure level
# Initialize the array to store the interpolated values
jedi_inc = np.zeros((jedi_inc_all.shape[0], 1)) 
#loop over grid points
for i in range(jedi_inc_all.shape[0]):
    #extract pressure level for current grid point
    p_levels = pres_a[i, :] #p value at grid point
    jedi_inc_val = jedi_inc_all[i, :] #corresponding increment
    #create interpolator
    interpolator = interp1d(p_levels, jedi_inc_val, kind='linear', bounds_error=False, fill_value="extrapolate")     
    #interpolate to user input pressure level
    jedi_inc[i, 0] = interpolator(pres_lev)

#reshape jedi_inc
jedi_inc = jedi_inc.squeeze()

def plot_T_inc(var_n, clevmax):
    """Temperature increment/diff [K]"""
    longname = "airTemperature"
    units = "K"
    inc = 0.05 * clevmax
    clevs = np.arange(-1.0 * clevmax, 1.0 * clevmax + inc, inc)
    cm = colormap.diff_colormap(clevs)
    return clevs, cm, units, longname

# CREATE PLOT ##############################
fig = plt.figure(figsize=(7, 4))
m1 = fig.add_subplot(1, 1, 1, projection=ccrs.PlateCarree(central_longitude=0))

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
gl1 = m1.gridlines(crs=ccrs.PlateCarree(), draw_labels=True, linewidth=0.5, color='k', alpha=0.25, linestyle='-')
gl1.xlocator = mticker.FixedLocator(np.arange(-180., 181., 5.))
gl1.ylocator = mticker.FixedLocator(np.arange(-80., 91., 5.))
gl1.xformatter = LONGITUDE_FORMATTER
gl1.yformatter = LATITUDE_FORMATTER
gl1.xlabel_style = {'size': 5, 'color': 'gray'}
gl1.ylabel_style = {'size': 5, 'color': 'gray'}

# Create triangulation and mask
triang = Triangulation(lons, lats)
mask = TriAnalyzer(triang).get_flat_tri_mask(min_circle_ratio=0.1)
triang.set_mask(mask)

# Plot the data using triangulation
clevs, cm, units, longname = plot_T_inc(jedi_inc, clevmax_incr)
c1 = m1.tricontourf(triang, jedi_inc, clevs, cmap=cm, extend='both')

# Add colorbar
cbar1 = fig.colorbar(c1, orientation="horizontal", fraction=0.046, pad=0.07)
cbar1.set_label(units, size=8)
cbar1.ax.tick_params(labelsize=5, rotation=30)

# Add titles, text, and save the figure
plt.suptitle(f"Temperature {plot_var} at {pres_lev} hPa", fontsize=9, y=0.95)
 
subtitle1_minmax = f"min: {np.around(np.min(jedi_inc), decimals)}\nmax: {np.around(np.max(jedi_inc), decimals)}"
m1.text(left * 0.99, bot * 1.01, f"{subtitle1_minmax}", fontsize=6, ha='left', va='bottom')
if plot_var == "Increment":
    plt.tight_layout()
    plt.savefig(f"./increment_{variable}.png", dpi=250, bbox_inches='tight')

# Print some final stats
print(f"Stats:")
print(f" {longname} max: {np.around(np.max(jedi_inc), decimals)}")

