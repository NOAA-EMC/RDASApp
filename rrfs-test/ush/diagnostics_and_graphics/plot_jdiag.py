#!/usr/bin/env python
import os
import sys
import cartopy.crs as ccrs
from cartopy.mpl.ticker import (LongitudeFormatter, LatitudeFormatter,
                                LatitudeLocator, LongitudeLocator)
from collections.abc import Iterable
import numpy as np
import matplotlib
matplotlib.use('AGG')
import matplotlib.pyplot as plt
from mpl_toolkits.axes_grid1 import make_axes_locatable
import matplotlib.axes as maxes
from netCDF4 import Dataset

file = './jdiag_t133.nc4'
VARIABLE='airTemperature'
print('read file=', file)
ncDB = Dataset(file,'r')
obs = np.array(ncDB.groups['ObsValue'].variables[VARIABLE][:]) 
omb = np.array(ncDB.groups['ombg'].variables[VARIABLE][:]) 
oma = np.array(ncDB.groups['oman'].variables[VARIABLE][:]) 
qc = np.array(ncDB.groups['EffectiveQC2'].variables[VARIABLE][:]) 
hgt = np.array(ncDB.groups['MetaData'].variables['height'][:]) 
lat = np.array(ncDB.groups['MetaData'].variables['latitude'][:]) 
lon = np.array(ncDB.groups['MetaData'].variables['longitude'][:]) 

omb[qc[:] !=0] = np.NaN
oma[qc[:] !=0] = np.NaN

oma = np.ma.array(oma, mask=np.isnan(oma)) # Use a mask to mark the NaNs
omb = np.ma.array(omb, mask=np.isnan(omb)) # Use a mask to mark the NaNs

oma_bias=np.nanmean(oma)
omb_bias=np.nanmean(omb)

oma_rms = np.sqrt(np.nanmean(oma ** 2))
omb_rms = np.sqrt(np.nanmean(omb ** 2))

print('oma bias:',oma_bias)
print('omb bias:',omb_bias)
print('oma rms:',oma_rms)
print('omb rms:',omb_rms)

ratio=(omb_rms - oma_rms) / omb_rms
print('Fitting Ratio (rms):',ratio)

f = open('omaomb_stat.txt','w',newline='')
fstring={'layer','omb_bias','oma_bias','omb_rms','oma_rms','fitting_ratio'}
f.write('{0:14}  {1:>14}  {2:>14} {3:>14} {4:>14} {5:>14} \n'.format('layer','omb_bias','oma_bias','omb_rms','oma_rms','fitting_ratio'))
f.write('{0:14}  {1:14.3f}  {2:14.3f} {3:14.3f} {4:14.3f} {5:14.3f} \n'.format('whole',omb_bias, oma_bias, omb_rms, oma_rms, ratio))

#hgt_list=range(hmin,hmax,hstep)
hmin = 0
hmax = 13000
hstep = 1000

def plot(lat,lon,data, title):
    fig = plt.figure(figsize=(8,8))
    ax = fig.add_subplot(projection=ccrs.PlateCarree())
    central_lat = 37.5
    central_lon = -96
    extent = [-130, -65, 15, 50]
    ax.coastlines()
    ax.set_extent(extent)
    cm = plt.cm.get_cmap('rainbow')
    dotsize = 2
    cont = ax.scatter(lon, lat, c = data,
                    transform = ccrs.PlateCarree(),
                    cmap=cm, s = dotsize )
    ax.gridlines(draw_labels=True, xlocs=np.arange(-180,180,10),linestyle='--')
    divider = make_axes_locatable(ax)
    cax = divider.append_axes("bottom",size="5%", pad=0.5,axes_class=plt.Axes)
    plt.colorbar(cont,cax=cax,orientation='horizontal')
    plt.title(title, fontsize = 12)
    plt.savefig('jdiag_oma_omb.png',dpi=200,bbox_inches='tight')
    plt.close()

def plot_hist(a,b,title):
    n_bins = 20
    a_bias = np.nanmean(a)
    b_bias = np.nanmean(b)
    a_rms = np.sqrt(np.nanmean(a ** 2))
    b_rms = np.sqrt(np.nanmean(b ** 2))
    abratio = (b_rms - a_rms) / b_rms
    f, ax = plt.subplots()
    colors = ['orange', 'green']
    labels = ['OMB', 'OMA']
    # plt.hist((b,a), bins=n_bins,density=True, histtype='bar', color=colors, label=labels)
    plt.hist((b,a), bins=n_bins, histtype='bar', color=colors, label=labels)
    plt.legend(prop={'size': 10})
    plt.title(title)
    subtitle = f" OMB bias: {np.around((b_bias), 3)}\n OMB rms: {np.around((b_rms), 3)}\n"
    subtitle = subtitle + f"\n OMA bias: {np.around((a_bias), 3)}\n OMA rms: {np.around((a_rms), 3)}\n"
    subtitle = subtitle + f"\n Fitting Ratio: {np.around((abratio), 3)}\n "
    plt.text(0.01, 0.95,f"{subtitle}",  transform=ax.transAxes, ha='left', va='top', fontsize=12)
    plt.savefig('jdiag_hist.png',dpi=200,bbox_inches='tight')
    plt.close()

def main():
    print('plotting OMB and OMA')
    title = f'OMB - {VARIABLE}'
    plot(lat, lon, omb, title)
    os.rename('./jdiag_oma_omb.png',f'./jdiag_omb.png')
    title = f'OMA - {VARIABLE}'
    plot(lat, lon, oma, title)
    os.rename('./jdiag_oma_omb.png',f'./jdiag_oma.png')
    title = f'{VARIABLE}'
    plot_hist(oma,omb,title)
    os.rename('./jdiag_hist.png',f'./jdiag_hist.all.png')

    hgt_list = range(hmin,hmax,hstep)
    nlayer = len(hgt_list)
    biasa = np.empty(nlayer)
    biasb = np.empty(nlayer)
    rmsa = np.empty(nlayer)
    rmsb = np.empty(nlayer)
    ratio = np.empty(nlayer)
    layer = [''] * nlayer

    for i,hgts in enumerate(hgt_list):
        tmpa = np.empty(len(oma))
        tmpb = np.empty(len(oma))
        h1 = hgts
        h2 = h1 + hstep
        layer[i] = f'{h1}-{h2}m'
        print(h1,'-',h2)
        tmpa = oma[(hgt[:]>=h1) & (hgt[:]<h2)]
        biasa[i] = np.nanmean(tmpa)
        rmsa[i] = np.sqrt(np.nanmean(tmpa ** 2))
        tmpb = omb[(hgt[:]>=h1) & (hgt[:]<h2)]
        biasb[i] = np.nanmean(tmpb)
        rmsb[i] = np.sqrt(np.nanmean(tmpb ** 2))
        ratio[i] = ( rmsb[i] - rmsa[i] ) / rmsb[i]

        f.write('{0:14}  {1:14.3f}  {2:14.3f} {3:14.3f} {4:14.3f} {5:14.3f} \n'.format(f'{h1}-{h2}m',biasb[i],biasa[i],rmsb[i],rmsa[i],ratio[i]))

        title = f'{VARIABLE}: {h1}m-{h2}m'
        plot_hist(tmpa,tmpb,title)
        os.rename('./jdiag_hist.png',f'./jdiag_hist.{h1}-{h2}.png')

    print('oma_bias=',biasa)
    print('omb_bias=',biasb)
    print('oma_rms=',rmsa)
    print('omb_rms=',rmsb)
    print('fit ratio=',ratio)
    f.close()

    plt.plot(ratio,layer)
    plt.grid(linestyle = ':')
    plt.title(f'Fitting Ratio: {VARIABLE}')
    plt.savefig('jdiag_ratio.png',dpi=200,bbox_inches='tight')
    plt.close()

if __name__ == '__main__': main()


