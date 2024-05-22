from netCDF4 import Dataset
import pdb
import matplotlib
matplotlib.use('agg')
import matplotlib.pyplot as plt
import matplotlib.colors as mcolors
import numpy as np
import time
import sys, os
import warnings
import argparse

warnings.filterwarnings('ignore')

############ USER INPUT ##########################################################
parser = argparse.ArgumentParser()
parser.add_argument('-d', '--diag', type=str, help='diagnostic file', required=True)
parser.add_argument('-v', '--variable', type=str, help='variable name', required=True)
parser.add_argument('-o', '--obtype', type=int, help='bufr observation type', required=True)
args = parser.parse_args()

diag = args.diag
variable = args.variable
obtype = args.obtype
###################################################################################
if obtype < 100:
    if variable[:4] == "wind":
        obtype = obtype + 200
    else:
        obtype = obtype + 100

print(f"{diag}")
ncdiag = Dataset(diag, mode='r')

# FROM JEDI diag
jhofx = ncdiag.groups["hofx0"].variables[f"{variable}"][:]
jerrf = ncdiag.groups["EffectiveError0"].variables[f"{variable}"][:]
jerrf = np.ma.masked_greater(jerrf, 999) # mask large values

# FROM GSI diag
#ghofx = ncdiag.groups["GsiHofX"].variables[f"{variable}"][:]
ghofx = ncdiag.groups["GsiHofXBc"].variables[f"{variable}"][:] # correct one to use.
gerrf = ncdiag.groups["GsiFinalObsError"].variables[f"{variable}"][:]
gerrf = np.ma.masked_greater(gerrf, 999) # mask large values

print(f"min/max of jedi errf: {np.min(jerrf)} {np.max(jerrf)}")
print(f"min/max of gsi errf: {np.min(gerrf)} {np.max(gerrf)}")

xmin = np.min(jerrf)
xmax = np.max(jerrf)
# Round to nearest 10 that contains all errf values.
errf_xmin = np.floor(xmin/10)*10
errf_xmax = np.ceil(xmax/10)*10

xmin = np.min(jhofx)
xmax = np.max(jhofx)
# Round to nearest 10 that contains all hofx values.
hofx_xmin = np.floor(xmin/10)*10
hofx_xmax = np.ceil(xmax/10)*10

# CREATE PLOT ##############################
fig = plt.figure(figsize = (6, 3))
plt1 = fig.add_subplot(1, 2, 1)
plt2 = fig.add_subplot(1, 2, 2)

# plot hofx values
plt1.scatter(jhofx, ghofx, c = 'gray', s = 0.5) #, label="Hofx Validation Jedi vs GSI")
plt2.scatter(jerrf, gerrf, c = 'gray', s = 0.5) #, label="Hofx Validation Jedi vs GSI")

# plot line of slope=1
x = np.linspace(hofx_xmin, hofx_xmax, 10)
plt1.plot(x, x, color = 'k', linewidth = 0.5, linestyle = '--') #, label="Expectation")
x = np.linspace(errf_xmin, errf_xmax, 10)
plt2.plot(x, x, color = 'k', linewidth = 0.5, linestyle = '--') #, label="Expectation")

# custom options for axes
plt1.set_xlabel('JEDI hofx', fontsize = 5)
plt1.set_ylabel('GSI hofx', fontsize = 5)
plt1.tick_params(axis='both', labelsize = 5)
plt2.set_xlabel('JEDI errf', fontsize = 5)
plt2.set_ylabel('GSI errf', fontsize = 5)
plt2.tick_params(axis='both', labelsize = 5)

# Add titles, text, and save the figure
plt.suptitle(f"{variable} validation GSI vs JEDI", fontsize = 9, y = 1.00)
plt1.set_title(f"hofx", fontsize = 9)
plt2.set_title(f"final ob error", fontsize = 9)
plt.savefig(f"./fv3jedi_vs_gsi_validation_{obtype}_{variable}.png", dpi = 250, bbox_inches = 'tight')
