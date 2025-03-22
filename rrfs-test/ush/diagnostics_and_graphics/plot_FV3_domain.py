#!/usr/bin/env python
import os
import matplotlib.pyplot as plt
from mpl_toolkits.basemap import Basemap
from mpl_toolkits.basemap import shiftgrid
import numpy as np
import pygrib
from netCDF4 import Dataset

data_loc = '/lfs5/BMC/wrfruc/Chunhua.Zhou/FV3/'
#title='RRFS_CONUS_13km'
title='RRFS_CONUS_3km'
bkg_map = Dataset(f'{data_loc}/{title}.grid_spec.nc','r')
bkg_data = Dataset(f'{data_loc}/{title}.sfc_data.nc','r')

# Load latitude/longitude from background grid spec file
grid_lon = bkg_map['grid_lon'][::]
grid_lat = bkg_map['grid_lat'][::]
print(np.shape(grid_lon))
data = bkg_data['shdmax'][0][::]
print(np.shape(data))

def plot_data(data, lat, lon, title):
    
    '''
    Input parameters:
    
        data: 2D Numpy array to be plotted
        lat: 2D Numpy array of latitude
        lon: 2D Numpy array of longitude
        title: Title string
        
    Draws a Basemap representation with the contoured data overlayed, with a colorbar.
        
    '''
    
    def trim_grid():
        '''
        The u, v, and H data are all on grids either one column, or one row smaller than lat/lon. 
        Return the smaller lat, lon grids, given the shape of the data to be plotted.
        '''
        y, x = np.shape(data)
        return lat[:y, :x], lon[:y, :x]
    
    def eq_contours():
        minval = np.amin(data)
        maxval = np.amax(data)
        if np.amin(data) < 0:
            # Set balanced contours. Choose an odd number in linspace below
            maxval = max(abs(minval), abs(maxval))
            return np.linspace(-maxval, maxval, 21)
        else:
            return np.linspace(minval, maxval, 21)
                              
    
    m = Basemap(projection='mill', 
                llcrnrlon=lon.min()-1,
                urcrnrlon=lon.max()+1,
                llcrnrlat=lat.min()-1,
                urcrnrlat=lat.max()+1,
                resolution='c',
               )

    lat_trim, lon_trim = trim_grid()
    plt.figure(figsize=(12,12))
    x, y = m(lon_trim, lat_trim)
    
    # Check out this link for all cmap options: https://matplotlib.org/3.1.0/tutorials/colors/colormaps.html
    # A good redwhiteblue cmap for increments is seismic, and for full fields with rainbow, change to hsv
    cs = m.contourf(x, y, data, eq_contours(), cmap='seismic')
    m.drawcoastlines();
    m.drawmapboundary();
    m.drawparallels(np.arange(-90.,120.,2),labels=[1,0,0,0]);
    m.drawmeridians(np.arange(-180.,180.,5),labels=[0,0,0,1]);
    plt.colorbar(cs,orientation='horizontal', fraction=0.046, pad=0.07);
    plt.title(f"{title}")
    plt.savefig(f'{title}.png',dpi=200,bbox_inches='tight')
    plt.close()

def main():
    plot_data(data, grid_lat,grid_lon, title)

if __name__ == '__main__': main()



