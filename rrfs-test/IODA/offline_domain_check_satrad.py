#!/usr/bin/env python
import netCDF4 as nc
import numpy as np
from matplotlib.path import Path
from scipy.spatial import ConvexHull, Delaunay
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
from operator import itemgetter
import shapely.speedups
from collections import defaultdict

shapely.speedups.enable()

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

def normalize_lon(lon):
    lon = np.asarray(lon)
    return np.where(lon < 0.0, lon + 360.0, lon)

def bbox_filter(coords, ring):
    mins = ring.min(axis=0)
    maxs = ring.max(axis=0)
    return (
        (coords[:,0] >= mins[0]) & (coords[:,0] <= maxs[0]) &
        (coords[:,1] >= mins[1]) & (coords[:,1] <= maxs[1])
    )

def to_plain_array(a):
    # netCDF masked arrays to plain ndarray
    return np.array(a.filled(np.nan)) if np.ma.isMaskedArray(a) else np.array(a)

def polygon_from_structured_edges(grid_ds):
    """
    Build a domain boundary ring from a structured FV3-style grid using only
    the outer perimeter (no triangulation). Works for variables named either
    (grid_lat, grid_lon) or (grid_latt, grid_lont).
    """
    vars_ = grid_ds.variables
    # Accept common FV3 names
    if 'grid_lat' in vars_ and 'grid_lon' in vars_:
        glat = np.array(vars_['grid_lat'][:])
        glon = np.array(vars_['grid_lon'][:])
    elif 'grid_latt' in vars_ and 'grid_lont' in vars_:
        glat = np.array(vars_['grid_latt'][:])
        glon = np.array(vars_['grid_lont'][:])
    else:
        raise RuntimeError(
            "Structured grid expected but did not find grid_lat/grid_lon or grid_latt/grid_lont."
        )

    if glat.ndim != 2 or glon.ndim != 2 or glat.shape != glon.shape:
        raise RuntimeError("grid_lat/grid_lon must be 2-D arrays of the same shape.")

    # Normalize longitudes to [0,360)
    glon = normalize_lon(glon)

    # Extract perimeter in CCW order: top > right > bottom > left
    top    = np.c_[glon[0, :],          glat[0, :]]
    right  = np.c_[glon[1:, -1],        glat[1:, -1]]
    bottom = np.c_[glon[-1, -2::-1],    glat[-1, -2::-1]]     # exclude last to avoid dup
    left   = np.c_[glon[-2:0:-1, 0],    glat[-2:0:-1, 0]]     # exclude corners already used

    ring = np.vstack([top, right, bottom, left])
    return ring

def polygon_from_mpas_boundary(grid_ds, simplify_target=20000):
    """
    Build the exact MPAS outer boundary by walking boundary edges.
    Returns ring as (N,2) [lon_deg, lat_deg] in [0,360) lon (no seam shift yet).
    simplify_target: if the ring has more vertices than this, stride-subsample it.
    """
    # Required topology
    for v in ("cellsOnEdge", "verticesOnEdge", "lonVertex", "latVertex"):
        if v not in grid_ds.variables:
            raise RuntimeError("MPAS boundary requires cellsOnEdge, verticesOnEdge, lonVertex, latVertex.")

    cellsOnEdge    = to_plain_array(grid_ds.variables["cellsOnEdge"][:])   # (nEdges, 2), int
    verticesOnEdge = to_plain_array(grid_ds.variables["verticesOnEdge"][:])# (nEdges, 2), int
    lonVertex      = to_plain_array(grid_ds.variables["lonVertex"][:])     # (nVertices,)
    latVertex      = to_plain_array(grid_ds.variables["latVertex"][:])

    # Convert to degrees; clean invalids
    lonv = np.degrees(lonVertex)
    latv = np.degrees(latVertex)
    goodv = np.isfinite(lonv) & np.isfinite(latv)
    if not goodv.all():
        # If any bad vertices exist, just ignore edges touching them
        pass

    # Boundary edges have a missing neighbor (cell id == 0)
    ce = cellsOnEdge.astype(np.int64)
    boundary_mask = (ce[:, 0] == 0) | (ce[:, 1] == 0)
    if not np.any(boundary_mask):
        raise RuntimeError("No boundary edges found (is this a global mesh?).")

    bedges = verticesOnEdge[boundary_mask].astype(np.int64)  # 1-based indices
    # Convert to 0-based; drop invalids (<=0) and edges that touch bad vertices
    v1 = bedges[:, 0] - 1
    v2 = bedges[:, 1] - 1
    ok = (v1 >= 0) & (v2 >= 0)
    if not goodv.all():
        ok &= goodv[v1] & goodv[v2]
    v1, v2 = v1[ok], v2[ok]

    # Build adjacency along boundary
    adj = defaultdict(list)
    for a, b in zip(v1, v2):
        adj[a].append(b)
        adj[b].append(a)

    # Each boundary vertex should have degree 2 (closed polygon).
    # If not, we still try to walk and skip dead-ends.
    visited_e = set()
    loops = []
    for s in list(adj.keys()):
        for nb in adj[s]:
            e = (min(s, nb), max(s, nb))
            if e in visited_e:
                continue
            # Trace a loop starting with edge
            ring_idx = [s, nb]
            visited_e.add(e)
            prev, cur = s, nb
            while True:
                nbs = adj[cur]
                # Pick the neighbor that isn't the one we came from
                nxt = nbs[0] if nbs[0] != prev else (nbs[1] if len(nbs) > 1 else None)
                if nxt is None:
                    break
                e2 = (min(cur, nxt), max(cur, nxt))
                if e2 in visited_e:
                    # closed?
                    if nxt == ring_idx[0]:
                        loops.append(ring_idx)
                    break
                visited_e.add(e2)
                ring_idx.append(nxt)
                prev, cur = cur, nxt
                if cur == ring_idx[0]:
                    loops.append(ring_idx)
                    break

    if not loops:
        raise RuntimeError("Could not assemble a boundary loop from MPAS edges.")

    # Choose the largest loop (by vertex count)
    ring_ids = max(loops, key=len)

    # Compose lon/lat; normalize lon to [0,360)
    lon = lonv[ring_ids]
    lat = latv[ring_ids]
    lon = np.where(lon < 0.0, lon + 360.0, lon)
    ring = np.c_[lon, lat]

    # Optional lightweight simplification by uniform stride
    if simplify_target and ring.shape[0] > simplify_target:
        stride = max(1, ring.shape[0] // simplify_target)
        ring = ring[::stride]

    return ring

def build_domain_ring(grid_ds):
    varsin = grid_ds.variables.keys()
    if (('grid_lat' in varsin and 'grid_lon' in varsin) or
        ('grid_latt' in varsin and 'grid_lont' in varsin)):
        ring = polygon_from_structured_edges(grid_ds)
    elif {'cellsOnEdge','verticesOnEdge','lonVertex','latVertex'}.issubset(varsin):
        ring = polygon_from_mpas_boundary(grid_ds, simplify_target=20000)
    else:
        raise RuntimeError("Unsupported grid file: need grid_lat/grid_lon (or grid_latt/grid_lont) or cells/verticesOnEdge")

    # Normalize and optionally fix the dateline seam
    ring[:,0] = normalize_lon(ring[:,0])
    L = ring[:,0]
    span_direct = L.max() - L.min()
    L_shift = np.where(L > 180.0, L - 360.0, L)
    span_shift = L_shift.max() - L_shift.min()
    lon_offset = -360 if span_shift < span_direct else 0
    if lon_offset == -360:
        ring[:, 0] = L_shift
    return ring

def shrink_boundary(points, factor=0.01):
    centroid = np.nanmean(points, axis=0)
    v = points - centroid
    return centroid + (1.0 - factor) * v

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
parser.add_argument('-s', '--shrink', type=float, help='hull shrink factor', required=True)
args = parser.parse_args()

# Assign filenames
obs_filename = args.obs
grid_filename = args.grid  # see note above.
make_fig = args.fig
hull_shrink_factor = args.shrink

print(f"Obs file: {obs_filename}")
print(f"Grid file: {grid_filename}")
print(f"Figure flag: {args.fig}")
print(f"Hull shrink factor: {hull_shrink_factor}")

# Plotting options
plot_box_width = 100. # define size of plot domain (units: lat/lon degrees)
plot_box_height = 50
cen_lat = 34.5
cen_lon = -97.5
#hull_shrink_factor = 0.10  #10% was found to work fairly well.

grid_ds = nc.Dataset(grid_filename, 'r')
obs_ds = nc.Dataset(obs_filename, 'r')

# Build ring
ring = build_domain_ring(grid_ds)

# Optional slight shrink to avoid grazing the exact boundary
ring = shrink_boundary(ring, factor=hull_shrink_factor)

# Build polygon
domain_path = Path(ring)

# Observation coords (normalize lon)
obs_lat = obs_ds.groups['MetaData'].variables['latitude'][:]
obs_lon = obs_ds.groups['MetaData'].variables['longitude'][:]
obs_lon = normalize_lon(obs_lon)
obs_coords = np.c_[obs_lon, obs_lat]

# Fast prefilter with bbox
prefilter_mask = bbox_filter(obs_coords, ring)
candidates = np.where(prefilter_mask)[0]

inside_small = domain_path.contains_points(obs_coords[candidates])
inside_indices = candidates[inside_small]
toc(tic1,label="Time to find obs within domain: ")

tic2 = tic()
# Create a new NetCDF file to store the selected data using the more efficient method
try:
    outfile = obs_filename.replace('.nc', '_dc.nc')
except:
    outfile = obs_filename.replace('.nc4', '_dc.nc4')
fout = nc.Dataset(outfile, 'w')

# Create dimensions and variables in the new file
location_size = len(inside_indices)
channel_size = obs_ds.dimensions['Channel'].size if 'Channel' in obs_ds.dimensions else 0  # Use the second dimension's size if exists

# Channel variable
if '_FillValue' in obs_ds.variables['Channel'].ncattrs():
    fill_value = obs_ds.variables['Channel'].getncattr('_FillValue')
else:
    fill_value = 2147483647
if 'Channel' not in fout.dimensions and channel_size > 0:
    fout.createDimension('Channel', channel_size)
    fout.createVariable('Channel', 'int32', 'Channel', fill_value=fill_value)
    fout.variables['Channel'][:] = obs_ds.variables['Channel'][:]
    for attr in obs_ds.variables['Channel'].ncattrs():  # Attributes for Location variable
        if attr != '_FillValue':
           fout.variables['Channel'].setncattr(attr, obs_ds.variables['Channel'].getncattr(attr))

# Location variable
if '_FillValue' in obs_ds.variables['Channel'].ncattrs():
    fill_value = obs_ds.variables['Channel'].getncattr('_FillValue')
else:
    fill_value = 2147483647
if 'Location' not in fout.dimensions:
    fout.createDimension('Location', location_size)
    fout.createVariable('Location', 'int32', 'Location', fill_value=fill_value)
    fout.variables['Location'][:] = 0
    for attr in obs_ds.variables['Location'].ncattrs():  # Attributes for Location variable
        if attr != '_FillValue':
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
        vartype = invar.dtype
        fill = invar.getncattr('_FillValue')
        dimensions = invar.dimensions

        # Create a new variable with the correct dimensions
        if len(dimensions) == 1:  # One-dimensional variable
            try:
                g.createVariable(var, vartype, dimensions, fill_value=fill)
            except:
                g.createVariable(var, 'str', dimensions, fill_value=fill)
            # If variable has only dimensions of channel then we do not need to process it 
            if g.variables[var].dimensions[0] == 'Channel': 
                g.variables[var][:] = invar[:][:]
            else: 
                g.variables[var][:] = invar[:][inside_indices]
            # Copy attributes for this variable
            for attr in invar.ncattrs():
                if '_FillValue' in attr: continue
                g.variables[var].setncattr(attr, invar.getncattr(attr))

        elif len(dimensions) == 2:  # Two-dimensional variable
            try:
                g.createVariable(var, vartype, dimensions, fill_value=fill)
            except:
                g.createVariable(var, 'str', dimensions, fill_value=fill)
            for idy in range(0, len(invar[0,:])): # new method for slicing very large 2d arrays
                g.variables[var][:,idy] = itemgetter(*inside_indices)(invar[:,idy])

            # Copy attributes for this variable
            for attr in invar.ncattrs():
                if '_FillValue' in attr: continue
                g.variables[var].setncattr(attr, invar.getncattr(attr))

        else:
            raise NotImplementedError("Handling for more than two dimensions not implemented.")

# Add ObsError and fill with anything (prevents zero increments in LETKF)
obsval = obs_ds.groups['ObsValue'].variables['brightnessTemperature']
vartype = obsval.dtype
dimensions = obsval.dimensions
fill = obsval.getncattr('_FillValue')
g = fout.createGroup('ObsError')
g.createVariable('brightnessTemperature', vartype, dimensions, fill_value=fill)
g.variables['brightnessTemperature'][:,:] = 999

# Finally add global attribute with the settings used to run this domain check
fout.setncattr('Orig_obs_file', obs_filename)
fout.setncattr('Grid_file', grid_filename)
fout.setncattr('Shrink_factor',hull_shrink_factor)

# Extract the grid latitude and longitude
if 'grid_lat' in grid_ds.variables and 'grid_lon' in grid_ds.variables:  # FV3 grid
    grid_lat = grid_ds.variables['grid_lat'][:, :]
    grid_lon = grid_ds.variables['grid_lon'][:, :]
    grid_lat = grid_lat.flatten()
    grid_lon = grid_lon.flatten()
    dycore = "FV3"
elif 'latCell' in grid_ds.variables and 'lonCell' in grid_ds.variables:  # MPAS grid
    grid_lat = np.degrees(grid_ds.variables['latCell'][:])  # Convert radians to degrees
    grid_lon = np.degrees(grid_ds.variables['lonCell'][:])  # Convert radians to degrees
    dycore = "MPAS"
else:
    raise ValueError("Unrecognized grid format: 'grid_lat'/'grid_lon' or 'latCell'/'lonCell' not found.")

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
#m1.fill(adjusted_lon.flatten(), grid_lat.flatten(), color='b', label='Domain Boundary', zorder=1, transform=ccrs.PlateCarree())
m1.scatter(adjusted_lon.flatten(), grid_lat.flatten(), c='b', s=1, label='Domain Boundary', zorder=2)

# Plot included observations
included_lat = obs_lat[inside_indices]
included_lon = obs_lon[inside_indices]
included_count = len(included_lat)
plt.scatter(included_lon, included_lat, c='g', s=2, label=f'Included Observations ({included_count})', zorder=3, transform=ccrs.PlateCarree())

# Plot excluded observations
excluded_indices = np.setdiff1d(np.arange(len(obs_lat)), inside_indices)
excluded_lat = obs_lat[excluded_indices]
excluded_lon = obs_lon[excluded_indices]

excluded_count = len(excluded_lat)
total_count = len(obs_lat)

print(f"Ob counts:")
print(f"  Excluded: {excluded_count}")
print(f"  Included: {included_count}")
print(f"  Total:    {total_count}")
plt.scatter(excluded_lon, excluded_lat, c='r', s=2, label=f'Excluded Observations ({excluded_count})', zorder=4, transform=ccrs.PlateCarree())

plt.xlabel('Longitude')
plt.ylabel('Latitude')
plt.legend(loc='upper right')
plt.title(f'{dycore} Domain and Observations ({hull_shrink_factor*100}%)')
plt.tight_layout()
plt.savefig(f'./domain_check_{dycore}.png')

toc(tic3,label="Time to create figure: ")
toc(tic1,label="Total elapsed time: ")
