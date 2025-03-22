import matplotlib.pyplot as plt
import matplotlib.colors as mcolors
import numpy as np


def diff_colormap(clevs):
    size = len(clevs)
    sizeby2 = int(size / 2)
    pd = 1. / sizeby2
    colors = [() for i in range(size)]
    incup = 0
    incdown = 1
    blue = (0,0,1)
    colors[0] = blue

    #for j in range(1, sizeby2 - 1):
    for j in range(1, sizeby2):
        incup = np.round(incup + pd, 4)
        colors[j] = (incup, incup, 1)

    white = (1., 1., 1.)
    colors[sizeby2 - 1] = white
    colors[sizeby2]     = white
    colors[sizeby2 + 1] = white

    red = (1, 0, 0)
    colors[-1] = red

    #for k in range(sizeby2 + 2, size):
    for k in range(sizeby2 + 1, size):
        incdown = np.round(incdown - pd, 4)
        colors[k] = (1, incdown, incdown)

    # Make values near zero gray instead of white
    gray = (0.75, 0.75, 0.75)
    colors[sizeby2 - 1] =  gray
    colors[sizeby2] = gray
    colors[sizeby2 + 1] = gray

    levs = 1
    cmap = mcolors.LinearSegmentedColormap.from_list(name='red_white_blue', colors = colors)
    return cmap

