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
import argparse

warnings.filterwarnings('ignore')

############ USER INPUT ##########################################################
plot_var = "Increment"  # Creates 2 plots: JEDI & GSI increment plots
#plot_var = "Diff"       # Creates 2 plots: JEDI-GSI Analysis and Background plots

lev = 60                # 60=sfc; 1=toa
clevmax_diff = 0.1     # max contour level for colorbar diff plots
clevmax_incr = 0.1     # max contour level for colorbar increment plots
decimals = 4            # number of decimals to round for text boxes

plot_box_width = 5.     # define size of plot domain (units: lat/lon degrees)

parser = argparse.ArgumentParser()
parser.add_argument('-j', '--jedidiag', type=str, help='jedi diagnostic file', required=True)
parser.add_argument('-g', '--gsidiag', type=str, help='gsi diagnostic file', required=True)
parser.add_argument('-v', '--variable', type=str, help='variable name', required=True)
parser.add_argument('-o', '--obtype', type=int, help='bufr observation type', required=True)
args = parser.parse_args()

jdiag = args.jedidiag
gdiag = args.gsidiag
variable = args.variable
obtype = args.obtype

#jdiag = str(sys.argv[1])
#gdiag = str(sys.argv[2])
#variable = str(sys.argv[3])
#obtype = int(sys.argv[4]) # bufr type (e.g., 88 is mesonet)

# JEDI data
datapath = "./"
janalysis = f"{datapath}/hybens3dvar-fv3_lam-C775.fv_core.res.nc"
jbackgrnd = f"{datapath}/data/bkg/fv3_dynvars.nc"
jgrid = f"{datapath}/data/bkg/fv3_grid_spec.nc"
#jdiag = f"{datapath}/jdiag_{singleob_type}_{variable}_2022052619.nc4"
jdiag = f"{datapath}/{jdiag}"

#GSI data
datapath = "../gsi_2022052619/"
ganalysis = f"{datapath}/fv3_dynvars"
gbackgrnd = f"{datapath}/data/bkg/fv3_dynvars"
ggrid = f"{datapath}/data/bkg/fv3_grid_spec"
#gdiag = f"{datapath}/{singleob_type}.conv_{obtype}_01.nc4"
#gdiag = f"{datapath}/diags-single/diag_conv_t_ges.2022052619"
#gdiag = f"{datapath}/diags-full/diag_conv_t_ges.2022052619"
gdiag = f"{datapath}/{gdiag}"

###################################################################################
# Set cartopy shapefile path
platform = os.getenv('HOSTNAME').upper()
if 'ORION' in platform:
        cartopy.config['data_dir']='/work/noaa/fv3-cam/sdegelia/cartopy'
elif 'H' in platform: # Will need to improve this once Hercules is supported
        cartopy.config['data_dir']='/home/Donald.E.Lippi/cartopy'

print(f"{jdiag}")

if obtype < 100:
    if variable[:4] == "wind":
        obtype = obtype + 200
    else:
        obtype = obtype + 100

# Do a quick omf and hofx value check from GSI diag file

# FROM JEDI diag
jncdiag = Dataset(jdiag, mode='r')
oberr_input = jncdiag.groups["EffectiveError0"].variables[f"{variable}"][:][0]
oberr_final = jncdiag.groups["EffectiveError2"].variables[f"{variable}"][:][0]
ob = jncdiag.groups["ObsValue"].variables[f"{variable}"][:][0]
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

# FROM GSI diag
#prefix = ""
#if variable == "windEastward":
#    prefix = "u_"
#if variable == "windNorthward":
#    prefix = "v_"

gncdiag = Dataset(gdiag, mode='r')
oberr_input = jncdiag.groups["GsiInputObsError"].variables[f"{variable}"][:][0]
oberr_final = jncdiag.groups["GsiFinalObsError"].variables[f"{variable}"][:][0]
ob = jncdiag.groups["ObsValue"].variables[f"{variable}"][:][0]
hofx = jncdiag.groups["GsiHofXBc"].variables[f"{variable}"][:][0]
#hofx = jncdiag.groups["GsiHofX"].variables[f"{variable}"][:][0]
omf = ob - hofx

#oberr_input = 1.0/(gncdiag.variables["Errinv_Input"][:][0])
#oberr_final = 1.0/(gncdiag.variables["Errinv_Final"][:][0])
#ob = gncdiag.variables[f"{prefix}Observation"][:][0]
#omf= gncdiag.variables[f"{prefix}Obs_Minus_Forecast_unadjusted"][:][0]
#omf= gncdiag.variables["Obs_Minus_Forecast_adjusted"][:][0]
#fmo= -1*omf
#hofx= fmo+ob
oberr_input = np.around(oberr_input.astype(np.float64), decimals)
oberr_final = np.around(oberr_final.astype(np.float64), decimals)
gob = np.around(ob.astype(np.float64), decimals)
gomf = np.around(omf.astype(np.float64), decimals)
ghofx = np.around(hofx.astype(np.float64), decimals)
print(f"GSI:")
print(f"  oberr_input: {oberr_input}")
print(f"  oberr_final: {oberr_final}")
#subtitle2_hofx = f"  ob:   {gob}\n  omf:  {gomf}\n  hofx: {ghofx}\n  oberr_in: {oberr_input}\n  oberr_out: {oberr_final}\n"
subtitle2_hofx = f"  ob:   {gob}\n  omf:  {gomf}\n  hofx: {ghofx}\n  oberr_final: {oberr_final}\n"
print(subtitle2_hofx)

dhofx = jhofx - ghofx
percd_hofx = 100 * dhofx / ghofx
subtitle1_percd = f"  hofx (diff):   {np.around(dhofx, decimals)}\n"
subtitle1_percd = f"{subtitle1_percd}  hofx (% diff): {np.around(percd_hofx, 2)}%"

# Grab single ob lat/lon and double check they're the same.
joblat = jncdiag.groups["MetaData"].variables["latitude"][:][0]
joblon = jncdiag.groups["MetaData"].variables["longitude"][:][0]

goblat = gncdiag.variables["Latitude"][:][0]
goblon = gncdiag.variables["Longitude"][:][0]

joblat = np.around(joblat.astype(np.float64), decimals)
joblon = np.around(joblon.astype(np.float64), decimals)
goblat = np.around(goblat.astype(np.float64), decimals)
goblon = np.around(goblon.astype(np.float64), decimals)

if np.abs(joblat - goblat) > 0:
   print(f"joblat - goblat > 0")
   #exit()
if np.abs(joblon - goblon) > 0:
   print(f"joblon - goblon > 0")
   #exit()

singleob_lat = joblat
singleob_lon = np.around(joblon - 360., decimals)  # convert to E-W

print(f"Using:")
print(f"  singleob_lat: {singleob_lat}")
print(f"  singleob_lon: {singleob_lon}\n")

print(f"Creating {plot_var} Plot...\n")
lev = lev - 1

# JEDI ####################################
nc_g = Dataset(jgrid, mode='r')
lats = nc_g.variables["grid_latt"][:,:]
lons = nc_g.variables["grid_lont"][:,:]
#lons = lons[:,:] - 180

# Open NETCDF4 dataset for reading
nc_a = Dataset(janalysis, mode='r')
nc_b = Dataset(jbackgrnd, mode='r')

# Read data and get dimensions
jedi_a = nc_a.variables["T"][0,lev,:,:].astype(np.float64)
jedi_b = nc_b.variables["T"][0,lev,:,:].astype(np.float64)

# compute increment
jedi_inc = jedi_a - jedi_b

# GSI ######################################
nc_g = Dataset(ggrid, mode='r')
#lats = nc_g.variables["grid_latt"][:,:]  # should be the same
#lons = nc_g.variables["grid_lont"][:,:]
#lons = lons[:,:] - 180

# Open NETCDF4 dataset for reading
nc_a = Dataset(ganalysis, mode='r')
nc_b = Dataset(gbackgrnd, mode='r')

# Read data and get dimensions
gsi_a = nc_a.variables["T"][0,lev,:,:].astype(np.float64)
gsi_b = nc_b.variables["T"][0,lev,:,:].astype(np.float64)

# compute increment
gsi_inc = gsi_a - gsi_b

if plot_var == "Increment":
    title1 = "JEDI"
    title2 = "GSI"
    jedi = jedi_inc
    gsi = gsi_inc
    clevmax = clevmax_incr

if plot_var == "Diff":
    title1 = "JEDI - GSI Analysis"
    title2 = "JEDI - GSI Background"
    jedi = jedi_a - gsi_a
    gsi  = jedi_b - gsi_b
    clevmax = clevmax_diff

# CREATE PLOT ##############################
fig = plt.figure(figsize=(6,3))
m1 = fig.add_subplot(1, 2, 1, projection=ccrs.PlateCarree(central_longitude=0))
m2 = fig.add_subplot(1, 2, 2, projection=ccrs.PlateCarree(central_longitude=0))

# Convert from degrees E to E-W where W is negative and E is positive.
#singleob_lon = -360. + singleob_lon

# Determine extent for plot domain
half = plot_box_width / 2.
left = singleob_lon - half
right = singleob_lon + half
bot = singleob_lat - half
top = singleob_lat + half

# Set extent for both plots
domain="single_ob"
m1.set_extent([left, right, top, bot])
m2.set_extent([left, right, top, bot])

# Add features to the subplots
m1.add_feature(cfeature.GSHHSFeature(scale='low'))
m2.add_feature(cfeature.GSHHSFeature(scale='low'))

m1.add_feature(cfeature.COASTLINE)
m2.add_feature(cfeature.COASTLINE)

m1.add_feature(cfeature.BORDERS)
m2.add_feature(cfeature.BORDERS)

m1.add_feature(cfeature.STATES)
m2.add_feature(cfeature.STATES)

#m.add_feature(cfeature.OCEAN)
#m.add_feature(cfeature.LAND)
#m.add_feature(cfeature.LAKES)

# Gridlines for the subplots
gl1 = m1.gridlines(crs = ccrs.PlateCarree(), draw_labels = True, linewidth = 0.5, color = 'k', alpha = 0.25, linestyle = '-')
gl2 = m2.gridlines(crs = ccrs.PlateCarree(), draw_labels = True, linewidth = 0.5, color = 'k', alpha = 0.25, linestyle = '-')

gl1.xlocator = mticker.FixedLocator([])
gl2.xlocator = mticker.FixedLocator([])

gl1.xlocator = mticker.FixedLocator(np.arange(-180., 181., 5.))
gl2.xlocator = mticker.FixedLocator(np.arange(-180., 181., 5.))

gl1.ylocator = mticker.FixedLocator(np.arange(-80., 91., 5.))
gl2.ylocator = mticker.FixedLocator(np.arange(-80., 91., 5.))

gl1.xformatter = LONGITUDE_FORMATTER
gl2.xformatter = LONGITUDE_FORMATTER

gl1.yformatter = LATITUDE_FORMATTER
gl2.yformatter = LATITUDE_FORMATTER

gl1.xlabel_style = {'size': 5, 'color': 'gray'}
gl2.xlabel_style = {'size': 5, 'color': 'gray'}

gl1.ylabel_style = {'size': 5, 'color': 'gray'}
gl2.ylabel_style = {'size': 5, 'color': 'gray'}

def plot_T_inc(var_n, clevmax):
    """Temperature increment/diff [K]"""
    longname = "airTemperature"
    units="K"
    inc = 0.05*clevmax
    clevs = np.arange(-1.0*clevmax, 1.0*clevmax+inc, inc)
    cm = colormap.diff_colormap(clevs)
    return(clevs, cm, units, longname)

def plot_q_inc(var_n, clevmax):
    """specific Humidity increment/diff [K]"""
    longname = "specificHumidity"
    units="g/kg"
    inc = 0.05*clevmax
    clevs = np.arange(-1.0*clevmax, 1.0*clevmax+inc, inc)
    cm = colormap.diff_colormap(clevs)
    return(clevs, cm, units, longname)

def plot_u_inc(var_n, clevmax):
    """zonal wind increment/diff [K]"""
    longname = "windEastward"
    units="m/s"
    inc = 0.05*clevmax
    clevs = np.arange(-1.0*clevmax, 1.0*clevmax+inc, inc)
    cm = colormap.diff_colormap(clevs)
    return(clevs, cm, units, longname)

def plot_v_inc(var_n, clevmax):
    """meridional wind increment/diff [K]"""
    longname = "windNorthward"
    units="m/s"
    inc = 0.05*clevmax
    clevs = np.arange(-1.0*clevmax, 1.0*clevmax+inc, inc)
    cm = colormap.diff_colormap(clevs)
    return(clevs, cm, units, longname)

def plot_p_inc(var_n, clevmax):
    """station pressure increment/diff [K]"""
    longname = "stationPressure"
    units="Pa"
    inc = 0.05*clevmax
    clevs = np.arange(-1.0*clevmax, 1.0*clevmax+inc, inc)
    cm = colormap.diff_colormap(clevs)
    return(clevs, cm, units, longname)

# Plot the data
if variable == "airTemperature":
    clevs, cm, units, longname = plot_T_inc(jedi_inc, clevmax)
if variable == "specificHumidity":
    clevs, cm, units, longname = plot_q_inc(jedi_inc, clevmax)
if variable == "windEastward":
    clevs, cm, units, longname = plot_u_inc(jedi_inc, clevmax)
if variable == "windNorthward":
    clevs, cm, units, longname = plot_v_inc(jedi_inc, clevmax)
if variable == "stationPressure":
    clevs, cm, units, longname = plot_p_inc(jedi_inc, clevmax)

units="K" # for now, plotting temperature incs for all ob types assimilated.

c1 = m1.contourf(lons, lats, jedi, clevs, cmap = cm)
c2 = m2.contourf(lons, lats,  gsi, clevs, cmap = cm)

# Scatter the single ob location
m1.scatter(singleob_lon, singleob_lat, color='g', marker='o', s=2)
m2.scatter(singleob_lon, singleob_lat, color='g', marker='o', s=2)

# Add colorbar
cax1 = fig.add_axes([0.125000, 0.05, 0.352273, 0.03542]) #x, y, width, height
cax2 = fig.add_axes([0.547727, 0.05, 0.352273, 0.03542])

cbar1 = fig.colorbar(c1, cax=cax1, orientation="horizontal", fraction=0.046, pad=0.07)
cbar2 = fig.colorbar(c2, cax=cax2, orientation="horizontal", fraction=0.046, pad=0.07)

cbar1.set_label(units, size=8)
cbar2.set_label(units, size=8)

cbar1.ax.tick_params(labelsize=5, rotation=30)
cbar2.ax.tick_params(labelsize=5, rotation=30)

# Add titles, text, and save the figure
plt.suptitle(f"Temperature {plot_var} at Level: {lev+1}\nobtype: {longname}", fontsize = 9, y = 1.05)

m1.set_title(f"{title1}", fontsize = 9)
m2.set_title(f"{title2}", fontsize = 9)

subtitle1_minmax = f"min: {np.around(np.min(jedi), decimals)}\nmax: {np.around(np.max(jedi), decimals)}"
subtitle2_minmax = f"min: {np.around(np.min(gsi), decimals)}\nmax: {np.around(np.max(gsi), decimals)}"
m1.text(left, top, f"{subtitle1_minmax}", fontsize = 6, ha='left', va='bottom')
m2.text(left, top, f"{subtitle2_minmax}", fontsize = 6, ha='left', va='bottom')

m1.text(left, bot, f"{subtitle1_hofx}", fontsize = 6, ha='left', va='bottom')
m2.text(left, bot, f"{subtitle2_hofx}", fontsize = 6, ha='left', va='bottom')

m1.text(left*1.01, bot*.94, f"{subtitle1_percd}", fontsize = 6, ha='left', va='top')
#m2.text(left, bot, f"subtitle2_percd}", fontsize = 6, ha='left', va='top')

if plot_var == "Increment":
    plt.savefig(f"./fv3jedi_vs_gsi_increment_{obtype}_{variable}.png", dpi=250, bbox_inches='tight')
if plot_var == "Diff":
    plt.savefig(f"./fv3jedi_vs_gsi_difference_{obtype}_{variable}.png", dpi=250, bbox_inches='tight')

# Print some final stats
print(f"Stats:")
print(f" {title1} max: {np.around(np.max(jedi), decimals)}")
print(f" {title1} min: {np.around(np.min(jedi), decimals)}")
print(f" {title2} max: {np.around(np.max(gsi), decimals)}")
print(f" {title2} min: {np.around(np.min(gsi), decimals)}")
