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

    subsets = config["subsets"]      # an array of subset
    logger.info(f"Checking subsets = {subsets}")

    # Get parameters from configuration input (command line/file)
    data_format = config["data_format"]
    data_type = config["data_type"]
    data_description = config["data_description"]
    data_product = config["data_product"]
    cycle_type = config["cycle_type"]
    dump_dir = config["dump_directory"]   
    ioda_dir = config["ioda_directory"]  
    cycle = config["cycle_datetime"]
# ---------------------------------------------
    logger.info(f"cycle= {cycle} ")
    logger.info(f"dump_directory= {dump_dir} ")
    logger.info(f"ioda_directory= {ioda_dir} ")

    # Get derived parameters
    yyyymmdd = cycle[0:8]
    hh = cycle[8:10]
    reference_time = datetime.strptime(cycle, "%Y%m%d%H")
    reference_time = reference_time.strftime("%Y-%m-%dT%H:%M:%SZ")
    logger.info(f"reference_time = {reference_time}")

#   Read bufr (not prepbufr) files
    bufrfile = f"{cycle_type}.t{hh}z.{data_format}.tm00.bufr_d"

    DATA_PATH = os.path.join(dump_dir, bufrfile)
    if not os.path.isfile(DATA_PATH):
        logger.info(f"DATA_PATH {DATA_PATH} does not exist")
        return
    logger.info(f"DATA_PATH is: {DATA_PATH}")

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
    q.add('surface', '*/AMVIVR{1}/LSQL')

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

    with bufr.File(DATA_PATH) as f:
        try:
            r = f.execute(q)
        except Exception as err:
            logger.info(f'Return with {err}')
            return

    # MetaData
    lat = r.get('latitude')
    lon = r.get('longitude')
    lon[lon > 180] -= 360      # Convert to [-180,180]

    said = r.get('satelliteId')
    zen  = r.get('satelliteZenithAngle', type='float')
    fre  = r.get('frequency', type='float')
    cen  = r.get('processingCenter', type='float')
    meth = r.get('windCalculationMethod', type='float')

    pob = r.get('pressure', type='float')
    cor = r.get('correlation', type='float')
    vari= r.get('variation', type='float')
    surf= r.get('surface', type='float')

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

    # Prepbufr Report Type
    otypvalue = 0         # initialize
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
    logger.debug(' Check variable dimension and type')
    logger.debug(f' lat  shape = {lat.shape}')
    logger.debug(f' lon  shape = {lon.shape}')
    logger.debug(f' said shape = {said.shape}')
    logger.debug(f' zen  shape= {zen.shape}')
    logger.debug(f' fre  shape= {fre.shape}')
    logger.debug(f' cen  shape= {cen.shape}')
    logger.debug(f' meth  shape= {meth.shape}')
    logger.debug(f' pob  shape= {pob.shape}')
    logger.debug(f' cor  shape= {cor.shape}')
    logger.debug(f' vari  shape= {vari.shape}')
    logger.debug(f' surf  shape= {surf.shape}')
    logger.debug(f' uwnd shape= {uwnd.shape}')
    logger.debug(f' vwnd shape= {vwnd.shape}')
    logger.debug(f' wdir shape= {wdir.shape}')
    logger.debug(f' wspd shape= {wspd.shape}')
    logger.debug(f' qm   shape= {qm.shape}')
    logger.debug(f' otyp shape= {otyp.shape}')
    logger.debug(f' qifn shape= {qifn.shape}')
    logger.debug(f' ee   shape= {ee.shape}')
    logger.debug(f' oer  shape= {oer.shape}')

    logger.debug(f' lat  type= {lat.dtype}')
    logger.debug(f' lon  type= {lon.dtype}')
    logger.debug(f' said type= {said.dtype}')
    logger.debug(f' zen  type= {zen.dtype}')
    logger.debug(f' fre  type= {fre.dtype}')
    logger.debug(f' cen  type= {cen.dtype}')
    logger.debug(f' meth  type= {meth.dtype}')
    logger.debug(f' pob  type= {pob.dtype}')
    logger.debug(f' cor  type= {cor.dtype}')
    logger.debug(f' vari  type= {vari.dtype}')
    logger.debug(f' surf  type= {surf.dtype}')
    logger.debug(f' uwnd type= {uwnd.dtype}')
    logger.debug(f' vwnd type= {vwnd.dtype}')
    logger.debug(f' wdir type= {wdir.dtype}')
    logger.debug(f' wspd type= {wspd.dtype}')
    logger.debug(f' qm   type= {qm.dtype}')
    logger.debug(f' otyp type= {otyp.dtype}')
    logger.debug(f' qifn type= {qifn.dtype}')
    logger.debug(f' ee   type= {ee.dtype}')
    logger.debug(f' oer  type= {oer.dtype}')

    # -----------
    # output file
    # -----------
    dims = {'Location': np.arange(0, lat.shape[0])}
    iodafile = f"{cycle_type}.t{hh}z.{data_type}.tm00.{cycle}.nc"

    OUTPUT_PATH = os.path.join(ioda_dir, iodafile)
    logger.info(f"Create output: {OUTPUT_PATH}")
    obsspace = ioda_ospace.ObsSpace(OUTPUT_PATH, mode='w', dim_dict=dims)

    # Global attributes
    obsspace.write_attr('sourceFiles', bufrfile)
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
        .write_attr('long_name', 'Satellite ID') \
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

    obsspace.create_var('MetaData/surfaceQualifier', dtype=surf.dtype, fillval=surf.fill_value) \
        .write_attr('units', '') \
        .write_attr('long_name', 'Land/Sea Qualifier') \
        .write_data(surf)

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
