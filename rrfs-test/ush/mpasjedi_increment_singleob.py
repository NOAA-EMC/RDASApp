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

warnings.filterwarnings('ignore')

############ USER INPUT ##########################################################
plot_var = "Increment"

lev = 23             # 1=sfc, 55=toa
clevmax_incr = 2.0     # max contour level for colorbar increment plots
decimals = 2            # number of decimals to round for text boxes

plot_box_width = 8.     # define size of plot domain (units: lat/lon degrees)

singleob_type = "adpupa"

variable = "airTemperature"

if variable == "airTemperature":
    obtype = 't'
    offset = -273.15

# JEDI data
datapath = "./"
janalysis   = "./ana.2024-05-27_00.00.00.nc"            # analysis file
jbackgrnd   = "./data/restart.2024-05-27_00.00.00.nc"
jstatic      = "./data/restart.2024-05-27_00.00.00.nc"
#jgrid = f"{datapath}/Data/bkg/fv3_grid_spec.nc"
#jdiag = f"{datapath}/{singleob_type}_hofxs_2022052619.nc4"
jdiag = "adpupa_hofx.nc4"


###################################################################################
# Set cartopy shapefile path
platform = os.getenv('HOSTNAME').upper()
if 'ORION' in platform:
        cartopy.config['data_dir']='/work/noaa/fv3-cam/sdegelia/cartopy'
elif 'H' in platform: # Will need to improve this once Hercules is supported
        cartopy.config['data_dir']='/home/Donald.E.Lippi/cartopy'
print(f"{jdiag}")
# Do a quick omf and hofx value check from GSI diag file

# FROM JEDI diag
jncdiag = Dataset(jdiag, mode='r')
oberr_input = jncdiag.groups["EffectiveError0"].variables[f"{variable}"][:][0]
oberr_final = jncdiag.groups["EffectiveError2"].variables[f"{variable}"][:][0]
ob = jncdiag.groups["ObsValue"].variables[f"{variable}"][:][0] + offset
omf= jncdiag.groups["ombg"].variables[f"{variable}"][:][0]
fmo= -1*omf
hofx= fmo+ob

oberr_input = np.around(oberr_input.astype(np.float64), decimals)
oberr_final = np.around(oberr_final.astype(np.float64), decimals)
job = np.around(ob.astype(np.float64), decimals)
jomf = np.around(omf.astype(np.float64), decimals)
jhofx = np.around(hofx.astype(np.float64), decimals)
print(f"JEDI:")
print(f"  oberr_input: {oberr_input}")
print(f"  oberr_final: {oberr_final}")
subtitle1_hofx = f"  ob:   {job}\n  omf:  {jomf}\n  hofx: {jhofx}\n  oberr_final: {oberr_final}\n"
print(subtitle1_hofx)

# Grab single ob lat/lon and double check they're the same.
joblat = jncdiag.groups["MetaData"].variables["latitude"][:][0]
joblon = jncdiag.groups["MetaData"].variables["longitude"][:][0]

joblat = np.around(joblat.astype(np.float64), decimals)
joblon = np.around(joblon.astype(np.float64), decimals)

singleob_lat = joblat
singleob_lon = np.around(joblon - 360., decimals)  # convert to E-W

print(f"Using:")
print(f"  singleob_lat: {singleob_lat}")
print(f"  singleob_lon: {singleob_lon}\n")

print(f"Creating {plot_var} Plot...\n")
lev = lev - 1

# JEDI ####################################
f_latlon = Dataset(jstatic, "r")
lats = np.array( f_latlon.variables['latCell'][:] ) * 180.0 / np.pi
lons0 = np.array( f_latlon.variables['lonCell'][:] ) * 180.0 / np.pi
lons = np.where(lons0>180.0,lons0-360.0,lons0)

# Open NETCDF4 dataset for reading
nc_a = Dataset(janalysis, mode='r')
nc_b = Dataset(jbackgrnd, mode='r')

# Read data and get dimensions
jedi_a = nc_a.variables["theta"][0,:,lev].astype(np.float64)
jedi_b = nc_b.variables["theta"][0,:,lev].astype(np.float64)

# Convert to temperature
if variable == "airTemperature":
	pres_a = (nc_a.variables['pressure_p'][0,:,lev] + nc_b['pressure_base'][0,:,lev])/100.0
	pres_b = (nc_b.variables['pressure_p'][0,:,lev] + nc_b['pressure_base'][0,:,lev])/100.0
	dividend_a = (1000.0/pres_a)**(0.286)
	dividend_b = (1000.0/pres_b)**(0.286)
	jedi_a = jedi_a / dividend_a
	jedi_b = jedi_b / dividend_b

# compute increment
jedi_inc = jedi_a - jedi_b

if plot_var == "Increment":
    title1 = "JEDI"
    jedi = jedi_inc
    clevmax = clevmax_incr

# CREATE PLOT ##############################
fig = plt.figure(figsize=(3,3))
m1 = fig.add_subplot(1, 1, 1, projection=ccrs.PlateCarree(central_longitude=0))

# Determine extent for plot domain
half = plot_box_width / 2.
left = singleob_lon - half
right = singleob_lon + half
bot = singleob_lat - half
top = singleob_lat + half

# Set extent for both plots
domain="single_ob"
m1.set_extent([left, right, top, bot])

# Add features to the subplots
m1.add_feature(cfeature.GSHHSFeature(scale='low'))

m1.add_feature(cfeature.COASTLINE)

m1.add_feature(cfeature.BORDERS)

m1.add_feature(cfeature.STATES)

#m.add_feature(cfeature.OCEAN)
#m.add_feature(cfeature.LAND)
#m.add_feature(cfeature.LAKES)

# Gridlines for the subplots
gl1 = m1.gridlines(crs = ccrs.PlateCarree(), draw_labels = True, linewidth = 0.5, color = 'k', alpha = 0.25, linestyle = '-')

gl1.xlocator = mticker.FixedLocator([])

gl1.xlocator = mticker.FixedLocator(np.arange(-180., 181., 5.))

gl1.ylocator = mticker.FixedLocator(np.arange(-80., 91., 5.))

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
#c1 = m1.contourf(lons, lats, jedi, clevs, cmap = cm)
c1 = plt.tricontourf(lons, lats, jedi, clevs, cmap = cm)

# Scatter the single ob location
m1.scatter(singleob_lon, singleob_lat, color='g', marker='o', s=2)

# Add colorbar
cbar1 = fig.colorbar(c1, orientation="horizontal", fraction=0.046, pad=0.07)

cbar1.set_label(units, size=8)

cbar1.ax.tick_params(labelsize=5, rotation=30)

# Add titles, text, and save the figure
plt.suptitle(f"Temperature {plot_var} at Level: {lev+1}\nobtype: {longname}", fontsize = 9, y = 1.05)

m1.set_title(f"{title1}", fontsize = 9, y = 0.98)

subtitle1_minmax = f"min: {np.around(np.min(jedi), decimals)}\nmax: {np.around(np.max(jedi), decimals)}"
m1.text(left, top, f"{subtitle1_minmax}", fontsize = 6, ha='left', va='bottom')

m1.text(left, bot, f"{subtitle1_hofx}", fontsize = 6, ha='left', va='bottom')

if plot_var == "Increment":
    plt.savefig(f"./increment_{variable}.png", dpi=250, bbox_inches='tight')

# Print some final stats
print(f"Stats:")
print(f" {title1} max: {np.around(np.max(jedi), decimals)}")
print(f" {title1} min: {np.around(np.min(jedi), decimals)}")
