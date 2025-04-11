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

# Variable name mappings for MPAS files
MPAS_VAR_MAP = {
    "airTemperature": "theta",  # Requires special conversion
    "specificHumidity": "qv",
    "windEastward": "uReconstructZonal",
    "windNorthward": "uReconstructMeridional",
    "stationPressure": "pressure"
}

def compute_mpas_increment(mpas_bkg, mpas_ana, variable, level):
    """
    Compute the analysis increment for an MPAS experiment at a specified level.

    Args:
        mpas_bkg (str): Path to MPAS background file.
        mpas_ana (str): Path to MPAS analysis file.
        variable (str): Variable name.
        level (int): Vertical level index (0-based).

    Returns:
        ndarray: Increment (analysis - background).
    """
    nc_a = Dataset(mpas_ana, mode='r')
    nc_b = Dataset(mpas_bkg, mode='r')
    if variable == "airTemperature":
        # Special handling: convert theta to temperature
        theta_a = nc_a.variables["theta"][0, :, level].astype(np.float64)
        theta_b = nc_b.variables["theta"][0, :, level].astype(np.float64)
        pres_a = (nc_a.variables['pressure_p'][0, :, level] + nc_a.variables['pressure_base'][0, :, level]) / 100.0  # hPa
        pres_b = (nc_b.variables['pressure_p'][0, :, level] + nc_b.variables['pressure_base'][0, :, level]) / 100.0
        mpas_a = theta_a / (1000.0 / pres_a) ** 0.286  # Convert to temperature (K)
        mpas_b = theta_b / (1000.0 / pres_b) ** 0.286
    else:
        mpas_var = MPAS_VAR_MAP.get(variable, variable)
        mpas_a = nc_a.variables[mpas_var][0, :, level].astype(np.float64)
        mpas_b = nc_b.variables[mpas_var][0, :, level].astype(np.float64)
    if variable in UNIT_CONVERSIONS:
        mpas_a *= UNIT_CONVERSIONS[variable]
        mpas_b *= UNIT_CONVERSIONS[variable]
    mpas_inc = mpas_a - mpas_b
    return mpas_inc

def plot_mpas_increments(mpas_inc1, mlons, mlats, variable, figname, level, clevmax, exp_name):
    """
    Plot MPAS increments from two experiments side by side at a specified level.

    Args:
        mpas_inc1 (ndarray): Increment data for experiment 1.
        mlons (ndarray): Longitude grid for MPAS.
        mlats (ndarray): Latitude grid for MPAS.
        variable (str): Variable name.
        figname (str): Figure identifier.
        level (int): Vertical level index (0-based).
        clevmax (float): Maximum contour level.
        exp_name (str): Name of the new experiment.
    """
    fig = plt.figure(figsize=(7, 3))
    m1 = fig.add_subplot(1, 1, 1, projection=ccrs.PlateCarree(central_longitude=0))

    # Set plot extent
    half_width, half_height = 35.0, 12.5
    cen_lat, cen_lon = 34.5, -97.5
    left, right = cen_lon - half_width, cen_lon + half_width
    bot, top = cen_lat - half_height, cen_lat + half_height
    m1.set_extent([left, right, bot, top])

    # Add map features
    for m in [m1]:
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

    # Define contour levels and colormap
    if variable == "airTemperature":
        clevs, cm, units, longname = plot_T_inc(mpas_inc1, clevmax)
    elif variable == "specificHumidity":
        clevs, cm, units, longname = plot_q_inc(mpas_inc1, clevmax)
    elif variable == "windEastward":
        clevs, cm, units, longname = plot_u_inc(mpas_inc1, clevmax)
    elif variable == "windNorthward":
        clevs, cm, units, longname = plot_v_inc(mpas_inc1, clevmax)
    elif variable == "stationPressure":
        clevs, cm, units, longname = plot_p_inc(mpas_inc1, clevmax)
    else:
        raise ValueError(f"Unsupported variable: {variable}")

    # Triangulation for MPAS grid (shared for both plots)
    triang = Triangulation(mlons, mlats)
    mask = TriAnalyzer(triang).get_flat_tri_mask(min_circle_ratio=0.1)
    triang.set_mask(mask)

    # Plot increment for experiment 1
    c1 = m1.tricontourf(triang, mpas_inc1, clevs, cmap=cm, extend='both')
    m1.set_title(f"{exp_name}", fontsize=9)

    # Add shared colorbar
    cax = fig.add_axes([0.125, 0.05, 0.775, 0.035])
    cbar = fig.colorbar(c1, cax=cax, orientation="horizontal", fraction=0.046, pad=0.07)
    cbar.set_label(units, size=8)
    cbar.ax.tick_params(labelsize=5, rotation=30)

    # Add titles and stats
    plt.suptitle(f"{longname} Increment at Level: {level+1}\n{figname}", fontsize=9, y=1.10)
    subtitle1 = f"max: {np.around(np.max(mpas_inc1), 4)}\nmin: {np.around(np.min(mpas_inc1), 4)}"
    m1.text(left * 0.99, bot * 1.01, subtitle1, fontsize=6, ha='left', va='bottom')

    # Save figure with experiment names and level+1 in filename
    plt.savefig(f"./increment_{exp_name}_{variable}_{figname}_level{level+1}.png", dpi=250, bbox_inches='tight')
    plt.close()

# Colormap and unit functions (unchanged)
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
    parser = argparse.ArgumentParser(description="Plot MPAS vs MPAS increments from two experiments.")
    parser.add_argument('-v', '--variable', type=str, required=True, help='Variable name (e.g., airTemperature)')
    parser.add_argument('-f', '--figname', type=str, required=True, help='Figure identifier')
    parser.add_argument('-m1b', '--mpas1_bkg', type=str, required=True, help='MPAS background file for experiment 1 (control)')
    parser.add_argument('-m1a', '--mpas1_ana', type=str, required=True, help='MPAS analysis file for experiment 1 (control)')
    parser.add_argument('-mg', '--mpas_grid', type=str, required=True, help='MPAS grid file')
    parser.add_argument('-e', '--exp_name', type=str, required=True, help='Name of the new experiment (${EXP_NAME})')
    parser.add_argument('-l', '--level', type=int, required=True, help='Model level (not python index)')
    args = parser.parse_args()

    # Assign arguments
    variable = args.variable
    figname = args.figname
    mpas1_bkg = args.mpas1_bkg
    mpas1_ana = args.mpas1_ana
    mpas_grid = args.mpas_grid
    exp_name = args.exp_name
    level = args.level - 1 # User should provide actual model level. Python indexing starts at 0.

    # Load MPAS grid
    f_latlon = Dataset(mpas_grid, "r")
    mlats = np.array(f_latlon.variables['latCell'][:]) * 180.0 / np.pi
    mlons0 = np.array(f_latlon.variables['lonCell'][:]) * 180.0 / np.pi
    mlons = np.where(mlons0 > 180.0, mlons0 - 360.0, mlons0)

    # Compute increments at specified level
    mpas_inc1 = compute_mpas_increment(mpas1_bkg, mpas1_ana, variable, level)

    # Plot with experiment names and specified level
    plot_mpas_increments(mpas_inc1, mlons, mlats, variable, figname, level, clevmax=5.0, exp_name=exp_name)
