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
import colormap
import time
import sys, os
import shapely.geometry
import warnings
from scipy.spatial.distance import cdist
from scipy.interpolate import interp1d

warnings.filterwarnings('ignore')

############ USER INPUT ##########################################################
plot_var = "Increment"
pres_lev = 500         # choose a specific pressure level in hPa
clevmax_incr = 5     # max contour level for colorbar increment plots
decimals = 2            # number of decimals to round for text boxes
plot_box_width = 70.     # define size of plot domain (units: lat/lon degrees)
plot_box_height = 30

variable = "airTemperature"
if variable == "airTemperature":
    obtype = 't'
    offset = -273.15

# JEDI data
datapath = "./"
#jgrid = f"{datapath}/data/bkg/fv3_grid_spec.nc"
jgrid = f"{datapath}/data/bkg/grid_spec.nc"

# FOR LETKF 
#janalysis = f"{datapath}/letkf-meanposterior-fv3_lam-C775.fv_core.res.nc" # 
#jbackgrnd = f"{datapath}/letkf-meanprior-fv3_lam-C775.fv_core.res.nc"

# FOR HYBRID (or ENVAR)
janalysis = f"{datapath}/ens3dvar-fv3_lam-C775.fv_core.res.nc"
jbackgrnd = f"{datapath}/data/bkg/20240527.000000.fv_core.res.tile1.nc"
#added for pressure calculations
jbackgrnd2 = f"{datapath}/data/bkg/20240527.000000.fv_core.res.nc"

###################################################################################
# Set cartopy shapefile path
platform = os.getenv('HOSTNAME').upper()
if 'ORION' in platform:
        cartopy.config['data_dir']='/work/noaa/fv3-cam/sdegelia/cartopy'
elif 'H' in platform: # Will need to improve this once Hercules is supported
        cartopy.config['data_dir']='/home/Donald.E.Lippi/cartopy'

nc_g = Dataset(jgrid, mode='r')
lats = nc_g.variables["grid_latt"][:,:]
lons = nc_g.variables["grid_lont"][:,:]
#lons = lons[:,:] - 180

# Open NETCDF4 dataset for reading
nc_a = Dataset(janalysis, mode='r')
nc_b = Dataset(jbackgrnd, mode='r')
#added for pressure calculations
nc_b2 = Dataset(jbackgrnd2, mode='r')

# Read data and get dimensions
#lev = lev-1
#jedi_a = nc_a.variables["T"][0,lev,:,:].astype(np.float64)
#jedi_b = nc_b.variables["T"][0,lev,:,:].astype(np.float64)
jedi_a = nc_a.variables["T"][0,:,:,:].astype(np.float64)
jedi_b = nc_b.variables["T"][0,:,:,:].astype(np.float64)

#coefficients from slightly different background file that define the hybrid sigma-pressure coordinates of FV3
ak = nc_b2.variables['ak'][0]
ak = ak[::-1] * 0.01
nc_b2.close()

#read in air pressure thickness
pres_raw = nc_a.variables["DELP"][0,:,:,:].astype(np.float64)
print(f"Shape of pres: {pres_raw.shape}")

#read in air pressure thickness, and then calculate pressure
try: # sometimes the delp variable name is capitalized, sometimes it isnt
    delp = nc_b.variables['delp'][0]
except:
    delp = nc_b.variables['DELP'][0]
shape = np.shape(delp)
nz = shape[0]
ny = shape[1]
nx = shape[2]
pres = np.empty((len(ak)-1,ny,nx))
for k in range(0, nz):
    pres[k,:,:] = np.sum(delp[:k,:,:], axis=0) * 0.01

# compute increment
#jedi_inc = jedi_a - jedi_b
jedi_inc_all = jedi_a - jedi_b

# Interpolate using user input pressure level
#Initialize the array to store the interpolated values
jedi_inc = np.zeros(jedi_inc_all.shape[1:])
#loop over grid points
for i in range(jedi_inc.shape[0]):
    for j in range(jedi_inc.shape[1]):
        #extract pressure level for current grid point
        p_levels = pres[:, i, j] #column of p values at i,j grid point                         
        jedi_inc_val = jedi_inc_all[:, i, j] #corresponding increments
        #create interpolator
        interpolator = interp1d(p_levels, jedi_inc_val, kind='linear', bounds_error=False, fill_value="extrapolate")
        #interpolate to user input pressure level
        jedi_inc[i, j] = interpolator(pres_lev)

#reshape jedi_inc
jedi_inc = jedi_inc.squeeze()

if plot_var == "Increment":
    title1 = "JEDI"
    jedi = jedi_inc
    clevmax = clevmax_incr

# CREATE PLOT ##############################
fig = plt.figure(figsize=(7,4))
m1 = fig.add_subplot(1, 1, 1, projection=ccrs.PlateCarree(central_longitude=0))

# Determine extent for plot domain
cen_lat = 34.5
cen_lon = -97.5
half = plot_box_width / 2.
left = cen_lon - half
right = cen_lon + half
half = plot_box_height / 2.
bot = cen_lat - half
top = cen_lat + half

# Set extent for both plots
domain="single_ob"
m1.set_extent([left, right, top, bot])

# Add features to the subplots
#m1.add_feature(cfeature.GSHHSFeature(scale='low'))
m1.add_feature(cfeature.COASTLINE)
m1.add_feature(cfeature.BORDERS)
m1.add_feature(cfeature.STATES)
#m.add_feature(cfeature.OCEAN)
#m.add_feature(cfeature.LAND)
#m.add_feature(cfeature.LAKES)

# Gridlines for the subplots
gl1 = m1.gridlines(crs = ccrs.PlateCarree(), draw_labels = True, linewidth = 0.5, color = 'k', alpha = 0.25, linestyle = '-')
gl1.xlocator = mticker.FixedLocator([])
gl1.xlocator = mticker.FixedLocator(np.arange(-180., 181., 10.))
gl1.ylocator = mticker.FixedLocator(np.arange(-80., 91., 10.))
gl1.xformatter = LONGITUDE_FORMATTER
gl1.yformatter = LATITUDE_FORMATTER
gl1.xlabel_style = {'size': 5, 'color': 'gray'}
gl1.ylabel_style = {'size': 5, 'color': 'gray'}


def plot_T_inc(var_n, clevmax):
    """Temperature increment/diff [K]"""
    longname = "airTemperature"
    units="K"
    inc = 0.05*clevmax
    clevs = np.arange(-1.0*clevmax, 1.0*clevmax+inc, inc)
    cm = colormap.diff_colormap(clevs)
    return(clevs, cm, units, longname)

# Plot the data
if variable == "airTemperature":
    clevs, cm, units, longname = plot_T_inc(jedi_inc, clevmax)

units="K"
c1 = m1.contourf(lons, lats, jedi, clevs, cmap = cm, extend='both')

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
    plt.savefig(f"./increment_{variable}.png", dpi=350, bbox_inches='tight')

# Print some final stats
print(f"Stats:")
print(f" {title1} max: {np.around(np.max(jedi), decimals)}")
print(f" {title1} min: {np.around(np.min(jedi), decimals)}")
