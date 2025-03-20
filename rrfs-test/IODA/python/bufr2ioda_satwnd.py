#!/usr/bin/env python3
# (C) Copyright 2025 NOAA/NWS/NCEP/EMC
#     This software is licensed under the terms of the Apache Licence 
#     Version 2.0 which can be obtained at 
#     http://www.apache.org/licenses/LICENSE-2.0.
#
# --------------------------------------------------------
# This converts satwnd bufr data to JEDI/IODA input file.
# --------------------------------------------------------

import sys
import argparse
import numpy as np
import numpy.ma as ma
import calendar
import json
import time
import copy
import math
import datetime
import os
from datetime import datetime
from pyioda import ioda_obs_space as ioda_ospace
from wxflow import Logger
from pyiodaconv import bufr
from collections import namedtuple
import warnings
# suppress warnings
warnings.filterwarnings('ignore')

# =============================================
def bufr_to_ioda(config, logger):

#   Read bufr (not prepbufr) files
    bufrfile = "./satwndbufr"

#   Get GOES AMVs 
    subsets = [ "NC005030", "NC005031", "NC005034" ]
    cycle = config["cycle_datetime"]
# ---------------------------------------------
    logger.info(f"cycle= {cycle} ")

    # Global attributes
    data_description= "GOES Satellite Winds"
    data_product= "RAP hourly satwnd bufr data"

    # Get derived parameters
    yyyymmdd = cycle[0:8]
    hh = cycle[8:10]
    reference_time = datetime.strptime(cycle, "%Y%m%d%H")
    reference_time = reference_time.strftime("%Y-%m-%dT%H:%M:%SZ")
    logger.info(f"reference_time = {reference_time}")

    # ========================
    q = bufr.QuerySet(subsets)

    # MetaData
    q.add('year', '*/YEAR')
    q.add('month', '*/MNTH')
    q.add('day', '*/DAYS')
    q.add('hour', '*/HOUR')
    q.add('minute', '*/MINU')

    q.add('latitude', '*/CLATH')
    q.add('longitude', '*/CLONH')

    q.add('satelliteId', '*/SAID')
    q.add('satelliteZenithAngle', '*/SAZA')

    q.add('windCalculationMethod', '*/SWCM')

    q.add('frequency', '*/SCCF')
    q.add('processingCenter', '*/OGCE[1]')
    q.add('pressure', '*/PRLC[1]')
    q.add('correlation', '*/AMVIVR{1}/TCOV')

    q.add('variation', '*/AMVIVR{1}/CVWD')
#   q.add('surface', '*/AMVIVR{1}/LSQL')

    # ObsValue
    q.add('uwnd', '*/AMVIVR{1}/UWND')
    q.add('vwnd', '*/AMVIVR{1}/VWND')
    q.add('wdir', '*/WDIR')
    q.add('wspd', '*/WSPD')

    # ObsError estimation
    q.add('qifn', '*/AMVQIC{2}/PCCF')
    q.add('ee', '*/AMVQIC{4}/PCCF')

    # ================================================
    logger.info('Executing QuerySet to get ResultSet')

    with bufr.File(bufrfile) as f:
        try:
            r = f.execute(q)
        except Exception as err:
            logger.info(f'Return with {err}')
            return

    # MetaData
    lat = r.get('latitude')
    lon = r.get('longitude')
    lon[lon < 0] += 360      # Convert to [0,360]

    said = r.get('satelliteId')
    zen  = r.get('satelliteZenithAngle', type='float')
    fre  = r.get('frequency', type='float')
    cen  = r.get('processingCenter', type='float')
    meth = r.get('windCalculationMethod', type='float')

    pob = r.get('pressure', type='float')
    cor = r.get('correlation', type='float')
    vari= r.get('variation', type='float')
#   surf= r.get('surface', type='float')

    # Observation Time
    year = r.get('year')
    month = r.get('month')
    day = r.get('day')
    hour = r.get('hour')
    minute = r.get('minute')

    # DateTime: seconds since Epoch time
    # IODA has no support for numpy datetime arrays dtype=datetime64[s]

    timestamp = r.get_datetime('year', 'month', 'day', 'hour', 'minute').astype(np.int64)
    int64_fill_value = np.int64(0)
    timestamp = ma.array(timestamp)
    timestamp = ma.masked_values(timestamp, int64_fill_value)

    # ObsValue
    uwnd = r.get('uwnd', type='float')
    vwnd = r.get('vwnd', type='float')
    wdir = r.get('wdir', type='float')
    wspd = r.get('wspd', type='float')

    # ObsError
    qifn = r.get('qifn', type='float')  # percent Confidence
    ee   = r.get('ee', type='float')    # initial wind error (%)
    oer = 0.01 * ee * wspd              # initial wind error (meter)

    # Define Prepbufr Report Type
    otypvalue = 0     # initialize
    otypsize  = said.shape
    otyp = np.full(otypsize, otypvalue)
    otyp = ma.masked_values(otyp, said.fill_value)

    for i in range(len(otyp)):
        if meth[i] == 1.0:      # IR
            otyp[i] = 245
        if meth[i] == 2.0:      # Visible
            otyp[i] = 251
        if meth[i] == 3.0:      # WV Cloud TOP
            otyp[i] = 246
        if meth[i] == 5.0:      # WV Deep Layer
            otyp[i] = 247

    # QualityMark
    qmsize  = said.shape
    qmvalue = 2         # initial QM
    qm = np.full(qmsize, qmvalue)
    qm = ma.masked_values(qm, said.fill_value)

# ---------------------------------------------------
    logger.info(' Check variable dimension and type')
    logger.info(f' lat  shape = {lat.shape}')
    logger.info(f' lon  shape = {lon.shape}')
    logger.info(f' said shape = {said.shape}')
    logger.info(f' zen  shape= {zen.shape}')
    logger.info(f' fre  shape= {fre.shape}')
    logger.info(f' cen  shape= {cen.shape}')
    logger.info(f' meth  shape= {meth.shape}')
    logger.info(f' pob  shape= {pob.shape}')
    logger.info(f' cor  shape= {cor.shape}')
    logger.info(f' vari  shape= {vari.shape}')
    logger.info(f' uwnd shape= {uwnd.shape}')
    logger.info(f' vwnd shape= {vwnd.shape}')
    logger.info(f' wdir shape= {wdir.shape}')
    logger.info(f' wspd shape= {wspd.shape}')
    logger.info(f' qm   shape= {qm.shape}')
    logger.info(f' otyp shape= {otyp.shape}')
    logger.info(f' qifn shape= {qifn.shape}')
    logger.info(f' ee   shape= {ee.shape}')
    logger.info(f' oer  shape= {oer.shape}')

    logger.info(f' lat  type= {lat.dtype}')
    logger.info(f' lon  type= {lon.dtype}')
    logger.info(f' said type= {said.dtype}')
    logger.info(f' zen  type= {zen.dtype}')
    logger.info(f' fre  type= {fre.dtype}')
    logger.info(f' cen  type= {cen.dtype}')
    logger.info(f' meth  type= {meth.dtype}')
    logger.info(f' pob  type= {pob.dtype}')
    logger.info(f' cor  type= {cor.dtype}')
    logger.info(f' vari  type= {vari.dtype}')
    logger.info(f' uwnd type= {uwnd.dtype}')
    logger.info(f' vwnd type= {vwnd.dtype}')
    logger.info(f' wdir type= {wdir.dtype}')
    logger.info(f' wspd type= {wspd.dtype}')
    logger.info(f' qm   type= {qm.dtype}')
    logger.info(f' otyp type= {otyp.dtype}')
    logger.info(f' qifn type= {qifn.dtype}')
    logger.info(f' ee   type= {ee.dtype}')
    logger.info(f' oer  type= {oer.dtype}')

    # -----------
    # output file
    # -----------
    dims = {'Location': np.arange(0, lat.shape[0])}
    iodafile = "./ioda_satwnd.nc"
    obsspace = ioda_ospace.ObsSpace(iodafile, mode='w', dim_dict=dims)

    # Global attributes
    obsspace.write_attr('sourceFiles', "rap.t??z.satwnd.tm00.bufr_d")
    obsspace.write_attr('description', data_description)
    obsspace.write_attr('product', data_product)
    obsspace.write_attr('subsets', subsets)

    # MetaData
    obsspace.create_var('MetaData/dateTime', dtype=timestamp.dtype, fillval=timestamp.fill_value) \
        .write_attr('units', 'seconds since 1970-01-01T00:00:00Z') \
        .write_attr('long_name', 'Datetime') \
        .write_data(timestamp)

    obsspace.create_var('MetaData/latitude', dtype=lat.dtype, fillval=lat.fill_value) \
        .write_attr('units', 'degrees_north') \
        .write_attr('valid_range', np.array([-90, 90], dtype=np.float32)) \
        .write_attr('long_name', 'Latitude') \
        .write_data(lat)

    obsspace.create_var('MetaData/longitude', dtype=lon.dtype, fillval=lon.fill_value) \
        .write_attr('units', 'degrees_east') \
        .write_attr('valid_range', np.array([-180, 180], dtype=np.float32)) \
        .write_attr('long_name', 'Longitude') \
        .write_data(lon)

    obsspace.create_var('MetaData/satelliteIdentifier', dtype=said.dtype, fillval=said.fill_value) \
        .write_attr('long_name', 'Satellite ID / prepbufr subtype') \
        .write_data(said)

    obsspace.create_var('MetaData/satelliteZenithAngle', dtype=zen.dtype, fillval=zen.fill_value) \
        .write_attr('units', 'degree') \
        .write_attr('long_name', 'Satellite Zenith Angle') \
        .write_data(zen)

    obsspace.create_var('MetaData/channelCentralFrequency', dtype=fre.dtype, fillval=fre.fill_value) \
        .write_attr('units', 'Hz') \
        .write_attr('long_name', 'Channel Center Frequency') \
        .write_data(fre)

    obsspace.create_var('MetaData/dataProvider', dtype=cen.dtype, fillval=cen.fill_value) \
        .write_attr('long_name', 'Processing Center') \
        .write_data(cen)

    obsspace.create_var('MetaData/windCalculationMethod', dtype=meth.dtype, fillval=meth.fill_value) \
        .write_attr('long_name', 'Wind Calculation Method') \
        .write_data(meth)

    obsspace.create_var('MetaData/pressure', dtype=pob.dtype, fillval=pob.fill_value) \
        .write_attr('units', 'Pa') \
        .write_attr('long_name', 'Pressure of Observation') \
        .write_data(pob)

    obsspace.create_var('MetaData/trackingCorrelation', dtype=cor.dtype, fillval=cor.fill_value) \
        .write_attr('units', '') \
        .write_attr('long_name', 'Tracking Correlation of Vector') \
        .write_data(cor)

    obsspace.create_var('MetaData/coefficientOfVariation', dtype=vari.dtype, fillval=vari.fill_value) \
        .write_attr('units', '') \
        .write_attr('long_name', 'coefficient Of Variation') \
        .write_data(vari)

#   obsspace.create_var('MetaData/surfaceQualifier', dtype=surf.dtype, fillval=surf.fill_value) \
#       .write_attr('units', '') \
#       .write_attr('long_name', 'Land/Sea Qualifier') \
#       .write_data(surf)

    obsspace.create_var('MetaData/qiWithoutForecast', dtype=qifn.dtype, fillval=qifn.fill_value) \
        .write_attr('units', 'percent') \
        .write_attr('long_name', 'Percent Confidence qifn') \
        .write_data(qifn)

    obsspace.create_var('MetaData/percentErrorEE', dtype=ee.dtype, fillval=ee.fill_value) \
        .write_attr('units', 'percent') \
        .write_attr('long_name', 'Estimated Error in percent ee') \
        .write_data(ee)

    obsspace.create_var('MetaData/prepbufrReportType', dtype=otyp.dtype, fillval=otyp.fill_value) \
        .write_attr('long_name', 'prepbufr Report Type') \
        .write_data(otyp)

    # QualityMarker
    obsspace.create_var('MetaData/windQualityMarker', dtype=qm.dtype, fillval=qm.fill_value) \
        .write_attr('long_name', 'Wind Quality Marker') \
        .write_data(qm)

    # ObsValue
    obsspace.create_var('ObsValue/windEastward', dtype=uwnd.dtype, fillval=uwnd.fill_value) \
        .write_attr('units', 'm s-1') \
        .write_attr('long_name', 'Eastward Wind') \
        .write_data(uwnd)

    obsspace.create_var('ObsValue/windNorthward', dtype=vwnd.dtype, fillval=vwnd.fill_value) \
        .write_attr('units', 'm s-1') \
        .write_attr('long_name', 'Northward Wind') \
        .write_data(vwnd)

    obsspace.create_var('ObsValue/windDirection', dtype=wdir.dtype, fillval=wdir.fill_value) \
        .write_attr('units', 'degree') \
        .write_attr('long_name', 'Wind Direction') \
        .write_data(wdir)

    obsspace.create_var('ObsValue/windSpeed', dtype=wspd.dtype, fillval=wspd.fill_value) \
        .write_attr('units', 'm s-1') \
        .write_attr('long_name', 'Wind Speed') \
        .write_data(wspd)


    # ObsError
    obsspace.create_var('ObsError/windEastward', dtype=oer.dtype, fillval=oer.fill_value) \
        .write_attr('units', 'm s-1') \
        .write_attr('long_name', 'Estimated wind error') \
        .write_data(oer)

    obsspace.create_var('ObsError/windNorthward', dtype=oer.dtype, fillval=oer.fill_value) \
        .write_attr('units', 'm s-1') \
        .write_attr('long_name', 'Estimated wind error') \
        .write_data(oer)

    logger.info("Done!")

#================================================================
if __name__ == '__main__':

    parser = argparse.ArgumentParser()
    parser.add_argument('-c', '--config', type=str, help='Input JSON configuration', required=True)
    parser.add_argument('-v', '--verbose', help='print debug logging information',
                        action='store_true')
    args = parser.parse_args()

#--------- LOG info format ------------------------
    log_level = 'DEBUG' if args.verbose else 'INFO'
    logger = Logger('', level=log_level, colored_log=True)

    with open(args.config, "r") as json_file:
        config = json.load(json_file)

    bufr_to_ioda(config, logger)
