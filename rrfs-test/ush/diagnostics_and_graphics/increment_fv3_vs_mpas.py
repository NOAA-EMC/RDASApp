from netCDF4 import Dataset
import matplotlib
matplotlib.use('agg')
import matplotlib.pyplot as plt
import cartopy.crs as ccrs
import cartopy.feature as cfeature
from cartopy.mpl.gridliner import LONGITUDE_FORMATTER, LATITUDE_FORMATTER
import matplotlib.ticker as mticker
import numpy as np
import colormap
import argparse
import warnings
from matplotlib.tri import Triangulation, TriAnalyzer

warnings.filterwarnings('ignore')

# Unit conversions and labels
UNIT_CONVERSIONS = {
    "specificHumidity": 1000.0,  # Convert kg/kg to g/kg
}

UNITS = {
    "airTemperature": "K",
    "specificHumidity": "g/kg",
    "windEastward": "m/s",
    "windNorthward": "m/s",
    "stationPressure": "Pa"
}

# Variable name mappings for GSI files
GSI_VAR_MAP = {
    "airTemperature": "T",
    "specificHumidity": "q",
    "windEastward": "u",
    "windNorthward": "v",
    "stationPressure": "ps"
}

# Variable name mappings for MPAS files
MPAS_VAR_MAP = {
    "airTemperature": "theta",  # Requires special conversion
    "specificHumidity": "qv",
    "windEastward": "uReconstructZonal",
    "windNorthward": "uReconstructMeridional",
    "stationPressure": "pressure"
}

def plot_increment(gsi_inc, mpas_inc, lons, lats, mlons, mlats, variable, figname, clevmax):
    """
    Plot GSI and MPAS-JEDI increments side by side.

    Args:
        gsi_inc (ndarray): GSI increment data.
        mpas_inc (ndarray): MPAS-JEDI increment data.
        lons (ndarray): Longitude grid for GSI.
        lats (ndarray): Latitude grid for GSI.
        mlons (ndarray): Longitude grid for MPAS-JEDI.
        mlats (ndarray): Latitude grid for MPAS-JEDI.
        variable (str): Variable name.
        figname (str): Figure identifier.
        clevmax (float): Maximum contour level.
    """
    fig = plt.figure(figsize=(14, 3))
    m1 = fig.add_subplot(1, 2, 1, projection=ccrs.PlateCarree(central_longitude=0))
    m2 = fig.add_subplot(1, 2, 2, projection=ccrs.PlateCarree(central_longitude=0))

    # Set plot extent
    half_width, half_height = 35.0, 12.5
    cen_lat, cen_lon = 34.5, -97.5
    left, right = cen_lon - half_width, cen_lon + half_width
    bot, top = cen_lat - half_height, cen_lat + half_height
    m1.set_extent([left, right, bot, top])
    m2.set_extent([left, right, bot, top])

    # Add map features
    for m in [m1, m2]:
        m.add_feature(cfeature.COASTLINE)
        m.add_feature(cfeature.BORDERS)
        m.add_feature(cfeature.STATES)
        gl = m.gridlines(crs=ccrs.PlateCarree(), draw_labels=True, linewidth=0.5, 
                         color='k', alpha=0.25, linestyle='-')
        gl.xlocator = mticker.FixedLocator(np.arange(-180., 181., 5.))
        gl.ylocator = mticker.FixedLocator(np.arange(-80., 91., 5.))
        gl.xformatter = LONGITUDE_FORMATTER
        gl.yformatter = LATITUDE_FORMATTER
        gl.xlabel_style = {'size': 5, 'color': 'gray'}
        gl.ylabel_style = {'size': 5, 'color': 'gray'}

    # Define contour levels and colormap based on variable
    if variable == "airTemperature":
        clevs, cm, units, longname = plot_T_inc(gsi_inc, clevmax)
    elif variable == "specificHumidity":
        clevs, cm, units, longname = plot_q_inc(gsi_inc, clevmax)
    elif variable == "windEastward":
        clevs, cm, units, longname = plot_u_inc(gsi_inc, clevmax)
    elif variable == "windNorthward":
        clevs, cm, units, longname = plot_v_inc(gsi_inc, clevmax)
    elif variable == "stationPressure":
        clevs, cm, units, longname = plot_p_inc(gsi_inc, clevmax)
    else:
        raise ValueError(f"Unsupported variable: {variable}")

    # Plot GSI increment
    c1 = m1.contourf(lons, lats, gsi_inc, clevs, cmap=cm, extend='both')
    m1.set_title(f"{ctl_name} (FV3-GSI)", fontsize=9)

    # Plot MPAS-JEDI increment with triangulation
    triang = Triangulation(mlons, mlats)
    mask = TriAnalyzer(triang).get_flat_tri_mask(min_circle_ratio=0.1)
    triang.set_mask(mask)
    c2 = m2.tricontourf(triang, mpas_inc, clevs, cmap=cm, extend='both')
    m2.set_title(f"{exp_name} (MPAS-JEDI)", fontsize=9)

    # Add shared colorbar
    cax = fig.add_axes([0.125, 0.05, 0.775, 0.035])
    cbar = fig.colorbar(c1, cax=cax, orientation="horizontal", fraction=0.046, pad=0.07)
    cbar.set_label(units, size=8)
    cbar.ax.tick_params(labelsize=5, rotation=30)

    # Add titles and stats (max/min only)
    plt.suptitle(f"{longname} Increment at Level: lowest\n{figname}", fontsize=9, y=1.05)
    subtitle1 = f"max: {np.around(np.max(gsi_inc), 4)}\nmin: {np.around(np.min(gsi_inc), 4)}"
    subtitle2 = f"max: {np.around(np.max(mpas_inc), 4)}\nmin: {np.around(np.min(mpas_inc), 4)}"
    m1.text(left * 0.99, bot * 1.01, subtitle1, fontsize=6, ha='left', va='bottom')
    m2.text(left * 0.99, bot * 1.01, subtitle2, fontsize=6, ha='left', va='bottom')

    # Save the figure
    plt.savefig(f"./increment_{exp_name}_vs_{ctl_name}_{variable}_{figname}_levellowest.png", dpi=250, bbox_inches='tight')
    plt.close()

# Colormap and unit functions
def plot_T_inc(var_n, clevmax):
    longname = "airTemperature"
    units = "K"
    inc = 0.05 * clevmax
    clevs = np.arange(-clevmax, clevmax + inc, inc)
    cm = colormap.diff_colormap(clevs)
    return clevs, cm, units, longname

def plot_q_inc(var_n, clevmax):
    longname = "specificHumidity"
    units = "g/kg"
    inc = 0.05 * clevmax
    clevs = np.arange(-clevmax, clevmax + inc, inc)
    cm = colormap.diff_colormap(clevs)
    return clevs, cm, units, longname

def plot_u_inc(var_n, clevmax):
    longname = "windEastward"
    units = "m/s"
    inc = 0.05 * clevmax
    clevs = np.arange(-clevmax, clevmax + inc, inc)
    cm = colormap.diff_colormap(clevs)
    return clevs, cm, units, longname

def plot_v_inc(var_n, clevmax):
    longname = "windNorthward"
    units = "m/s"
    inc = 0.05 * clevmax
    clevs = np.arange(-clevmax, clevmax + inc, inc)
    cm = colormap.diff_colormap(clevs)
    return clevs, cm, units, longname

def plot_p_inc(var_n, clevmax):
    longname = "stationPressure"
    units = "Pa"
    inc = 0.05 * clevmax
    clevs = np.arange(-clevmax, clevmax + inc, inc)
    cm = colormap.diff_colormap(clevs)
    return clevs, cm, units, longname

if __name__ == "__main__":
    # Parse command-line arguments
    parser = argparse.ArgumentParser(description="Plot GSI vs MPAS-JEDI increments.")
    parser.add_argument('-v', '--variable', type=str, required=True, help='Variable name (e.g., airTemperature)')
    parser.add_argument('-f', '--figname', type=str, required=True, help='Figure identifier')
    parser.add_argument('-gb', '--gsi_bkg', type=str, required=True, help='GSI background file path')
    parser.add_argument('-ga', '--gsi_ana', type=str, required=True, help='GSI analysis file path')
    parser.add_argument('-mb', '--mpas_bkg', type=str, required=True, help='MPAS background file path')
    parser.add_argument('-ma', '--mpas_ana', type=str, required=True, help='MPAS analysis file path')
    parser.add_argument('-gg', '--gsi_grid', type=str, required=True, help='GSI grid file path')
    parser.add_argument('-mg', '--mpas_grid', type=str, required=True, help='MPAS grid file path')
    parser.add_argument('-c', '--ctl_name', type=str, required=True, help='Name of the control experiment (${CTL_NAME})')
    parser.add_argument('-e', '--exp_name', type=str, required=True, help='Name of the new experiment (${EXP_NAME})')
    args = parser.parse_args()

    # Assign arguments
    variable = args.variable
    figname = args.figname
    gsi_bkg = args.gsi_bkg
    gsi_ana = args.gsi_ana
    mpas_bkg = args.mpas_bkg
    mpas_ana = args.mpas_ana
    gsi_grid = args.gsi_grid
    mpas_grid = args.mpas_grid
    ctl_name = args.ctl_name
    exp_name = args.exp_name

    # Load GSI grid
    nc_g = Dataset(gsi_grid, mode='r')
    lats = nc_g.variables["grid_latt"][:, :]
    lons = nc_g.variables["grid_lont"][:, :]

    # Load MPAS grid
    f_latlon = Dataset(mpas_grid, "r")
    mlats = np.array(f_latlon.variables['latCell'][:]) * 180.0 / np.pi
    mlons0 = np.array(f_latlon.variables['lonCell'][:]) * 180.0 / np.pi
    mlons = np.where(mlons0 > 180.0, mlons0 - 360.0, mlons0)

    # Load GSI data (surface level assumed at index 64)
    nc_a = Dataset(gsi_ana, mode='r')
    nc_b = Dataset(gsi_bkg, mode='r')
    gsi_var = GSI_VAR_MAP.get(variable, variable)
    gsi_a = nc_a.variables[gsi_var][0, 64, :, :].astype(np.float64)
    gsi_b = nc_b.variables[gsi_var][0, 64, :, :].astype(np.float64)
    if variable in UNIT_CONVERSIONS:
        gsi_a *= UNIT_CONVERSIONS[variable]
        gsi_b *= UNIT_CONVERSIONS[variable]
    gsi_inc = gsi_a - gsi_b

    # Load MPAS data (surface level assumed at index 0)
    nc_a = Dataset(mpas_ana, mode='r')
    nc_b = Dataset(mpas_bkg, mode='r')
    if variable == "airTemperature":
        # Special handling for airTemperature in MPAS: convert theta to temperature
        theta_a = nc_a.variables["theta"][0, :, 0].astype(np.float64)
        theta_b = nc_b.variables["theta"][0, :, 0].astype(np.float64)
        pres_a = (nc_a.variables['pressure_p'][0, :, 0] + nc_a.variables['pressure_base'][0, :, 0]) / 100.0  # Pressure in hPa
        pres_b = (nc_b.variables['pressure_p'][0, :, 0] + nc_b.variables['pressure_base'][0, :, 0]) / 100.0
        mpas_a = theta_a / (1000.0 / pres_a) ** 0.286  # Convert potential temperature to temperature (K)
        mpas_b = theta_b / (1000.0 / pres_b) ** 0.286
    else:
        mpas_var = MPAS_VAR_MAP.get(variable, variable)
        mpas_a = nc_a.variables[mpas_var][0, :, 0].astype(np.float64)
        mpas_b = nc_b.variables[mpas_var][0, :, 0].astype(np.float64)
    if variable in UNIT_CONVERSIONS:
        mpas_a *= UNIT_CONVERSIONS[variable]
        mpas_b *= UNIT_CONVERSIONS[variable]
    mpas_inc = mpas_a - mpas_b

    # Plot the increments
    plot_increment(gsi_inc, mpas_inc, lons, lats, mlons, mlats, variable, figname, clevmax=5.0)
