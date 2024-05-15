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

warnings.filterwarnings('ignore')

############ USER INPUT ##########################################################
# JEDI data
variable = str(sys.argv[1])
obtype = int(sys.argv[2]) # bufr type (e.g., 88 is mesonet)
datapath = "./"
diag = f"{datapath}/MSONET_hofxs_{variable}_2022052619.nc4"

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

# FROM GSI diag
ghofx = ncdiag.groups["GsiHofX"].variables[f"{variable}"][:]

# Find the best range to plot
jmin = np.min(jhofx)
jmax = np.max(jhofx)
print(f"hofx range:  min={jmin}, max={jmax}")
# Round to nearest 10 that contains all hofx values.
jmin = np.floor(jmin/10)*10
jmax = np.ceil(jmax/10)*10
print(f"plot bounds: min={jmin}, max={jmax}")

# CREATE PLOT ##############################
fig = plt.figure(figsize = (3,3))

# plot hofx values
plt.scatter(jhofx, ghofx, c = 'gray', s = 0.5) #, label="Hofx Validation Jedi vs GSI")

# plot line of slope=1
x = np.linspace(jmin, jmax, 10)
plt.plot(x, x, color = 'k', linewidth = 0.5, linestyle = '--') #, label="Expectation")

# custom options for axes
plt.xlabel('JEDI hofx', fontsize = 5)
plt.ylabel('GSI hofx', fontsize = 5)
plt.xticks(fontsize = 5)
plt.yticks(fontsize = 5)

# Add titles, text, and save the figure
plt.suptitle(f"{variable} hofx validation GSI vs JEDI", fontsize = 9, y = 1.00)
plt.savefig(f"./hofx_validation_{obtype}_{variable}.png", dpi = 250, bbox_inches = 'tight')
