#!/usr/bin/env python3
# (C) Copyright 2024 NOAA/NWS/NCEP/EMC
#
# This software is licensed under the terms of the Apache Licence Version 2.0
# which can be obtained at http://www.apache.org/licenses/LICENSE-2.0.

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


def Compute_WindComponents_from_WindDirection_and_WindSpeed(wdir, wspd):

    uob = (-wspd * np.sin(np.radians(wdir))).astype(np.float32)
    vob = (-wspd * np.cos(np.radians(wdir))).astype(np.float32)

    uob = ma.array(uob)
    uob = ma.masked_values(uob, uob.fill_value)
    vob = ma.array(vob)
    vob = ma.masked_values(vob, vob.fill_value)

    return uob, vob


def Mask_typ_for_var(typ, var):

    typ_var = copy.deepcopy(typ)
    for i in range(len(typ_var)):
        if ma.is_masked(var[i]):
            typ_var[i] = typ.fill_value

    return typ_var


def bufr_to_ioda(config, logger):

    subsets = config["subsets"]
    logger.debug(f"Checking subsets = {subsets}")

    # Get parameters from configuration
    data_format = config["data_format"]
    data_type = config["data_type"]
    data_description = config["data_description"]
    data_provider = config["data_provider"]
    cycle_type = config["cycle_type"]
    dump_dir = config["dump_directory"]
    ioda_dir = config["ioda_directory"]
    cycle = config["cycle_datetime"]

    # Get derived parameters
    yyyymmdd = cycle[0:8]
    hh = cycle[8:10]
    reference_time = datetime.strptime(cycle, "%Y%m%d%H")
    reference_time = reference_time.strftime("%Y-%m-%dT%H:%M:%SZ")

    # General informaton
    converter = 'BUFR to IODA Converter'
    platform_description = 'MSONET'

    logger.info(f"reference_time = {reference_time}")

    bufrfile = f"{cycle_type}.t{hh}z.{data_type}.tm00.{data_format}"
    DATA_PATH = os.path.join(dump_dir, bufrfile)
    if not os.path.isfile(DATA_PATH):
        logger.info(f"DATA_PATH {DATA_PATH} does not exist")
        return
    logger.debug(f"The DATA_PATH is: {DATA_PATH}")

    # ============================================
    # Make the QuerySet for all the data we want
    # ============================================
    start_time = time.time()

    logger.info('Making QuerySet')
    q = bufr.QuerySet(subsets)

    # MetaData
    q.add('year', '*/YEAR')
    q.add('month', '*/MNTH')
    q.add('day', '*/DAYS')
    q.add('hour', '*/HOUR')
    q.add('minute', '*/MINU')
    q.add('latitude', '*/CLATH')
    q.add('longitude', '*/CLONH')
    q.add('stationIdentification', '*/RPID')
    q.add('stationElevation', '*/SELV')
    q.add('pressure', '*/MNPRESSQ/PRES')
    q.add('height', '*/HSMSL')
    q.add('dataProviderRestricted', '*/RSRD')
    q.add('dataRestrictedExpiration', '*/EXPRSRD')

    # ObsValue
    q.add('altimeterSetting', '*/MNALSESQ/ALSE')
    q.add('snowWaterEquivalentRate', '*/MNREQVSQ/REQV')
    q.add('airTemperature', '*/MNTMDBSQ/TMDB')
    q.add('dewPointTemperature', '*/MNTMDPSQ/TMDP')
    q.add('windDirection', '*/MNWDIRSQ/WDIR')
    q.add('windSpeed', '*/MNWSPDSQ/WSPD')
    q.add('maximumWindGustDirection', '*/MNGUSTSQ/MXGD')
    q.add('maximumWindGustSpeed', '*/MNGUSTSQ/MXGS')
    q.add('totalPrecipitation', '*/TOPC')
    q.add('horizontalVisibility', '*/MNHOVISQ/HOVI')

    # QualityMark
    q.add('pressureQM', '*/QMPR')
    q.add('airTemperatureQM', '*/QMAT')
    q.add('dewPointTemperatureQM', '*/QMDD')
    q.add('windSpeedQM', '*/QMWN')

    end_time = time.time()
    running_time = end_time - start_time
    logger.debug(f'Running time for making QuerySet : {running_time} seconds')

    # ==============================================================
    # Open the BUFR file and execute the QuerySet to get ResultSet
    # Use the ResultSet returned to get numpy arrays of the data
    # ==============================================================
    start_time = time.time()

    logger.info('Executing QuerySet to get ResultSet')
    with bufr.File(DATA_PATH) as f:
        try:
            r = f.execute(q)
        except Exception as err:
            logger.info(f'Return with {err}')
            return

    # MetaData
    clath = r.get('latitude')
    clonh = r.get('longitude')
    rpid = r.get('stationIdentification')
    selv = r.get('stationElevation', type='float')
    pres = r.get('pressure')
    hsmsl = r.get('height', type='float')
    rsrd = r.get('dataProviderRestricted')
    exprsrd = r.get('dataRestrictedExpiration')

    # MetaData/Observation Time
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
    alse = r.get('altimeterSetting')
    reqv = r.get('snowWaterEquivalentRate')
    tmdb = r.get('airTemperature')
    tmdp = r.get('dewPointTemperature')
    wdir = r.get('windDirection')
    wspd = r.get('windSpeed')
    mxgd = r.get('maximumWindGustDirection')
    mxgs = r.get('maximumWindGustSpeed')
    topc = r.get('totalPrecipitation')
    hovi = r.get('horizontalVisibility')

    # QualityMark
    qmpr = r.get('pressureQM')
    qmat = r.get('airTemperatureQM')
    qmdd = r.get('dewPointTemperatureQM')
    qmwn = r.get('windSpeedQM')

    logger.info('Executing QuerySet Done!')

    # =========================
    # Create derived variables
    # =========================
    start_time = time.time()

    logger.info('Creating derived variables')
    logger.debug('Creating derived variables - wind components (uob and vob)')

    uob, vob = Compute_WindComponents_from_WindDirection_and_WindSpeed(wdir, wspd)
    logger.debug(f'   uob min/max = {uob.min()} {uob.max()}')
    logger.debug(f'   vob min/max = {vob.min()} {vob.max()}')

    end_time = time.time()
    running_time = end_time - start_time
    logger.info(f'Processing time for creating derived variables : {running_time} seconds')

    logger.debug('Executing QuerySet: Check BUFR variable generic dimension and type')
    # Check BUFR variable generic dimension and type
    logger.debug(f'     clath         shape = {clath.shape}')
    logger.debug(f'     clonh         shape = {clonh.shape}')
    logger.debug(f'     rpid          shape = {rpid.shape}')
    logger.debug(f'     selv          shape = {selv.shape}')
    logger.debug(f'     pres          shape = {pres.shape}')
    logger.debug(f'     hsmsl         shape = {hsmsl.shape}')
    logger.debug(f'     rsrd          shape = {rsrd.shape}')
    logger.debug(f'     exprsrd       shape = {exprsrd.shape}')

    logger.debug(f'     alse      	  shape = {alse.shape}')
    logger.debug(f'     reqv          shape = {reqv.shape}')
    logger.debug(f'     tmdb          shape = {tmdb.shape}')
    logger.debug(f'     tmdp          shape = {tmdp.shape}')
    logger.debug(f'     wdir          shape = {wdir.shape}')
    logger.debug(f'     wspd          shape = {wspd.shape}')
    logger.debug(f'     mxgd          shape = {mxgd.shape}')
    logger.debug(f'     mxgs          shape = {mxgs.shape}')
    logger.debug(f'     topc          shape = {topc.shape}')
    logger.debug(f'     hovi          shape = {hovi.shape}')
    logger.debug(f'     uob           shape = {uob.shape}')
    logger.debug(f'     vob           shape = {vob.shape}')

    logger.debug(f'     qmpr          shape = {qmpr.shape}')
    logger.debug(f'     qmat          shape = {qmat.shape}')
    logger.debug(f'     qmdd          shape = {qmdd.shape}')
    logger.debug(f'     qmwn          shape = {qmwn.shape}')

    logger.debug(f'     clath         type = {clath.dtype}')
    logger.debug(f'     clonh         type = {clonh.dtype}')
    logger.debug(f'     rpid          type = {rpid.dtype}')
    logger.debug(f'     selv          type = {selv.dtype}')
    logger.debug(f'     pres          type = {pres.dtype}')
    logger.debug(f'     hsmsl         type = {hsmsl.dtype}')
    logger.debug(f'     rsrd          type = {rsrd.dtype}')
    logger.debug(f'     exprsrd       type = {exprsrd.dtype}')
    logger.debug(f'     uob           type  = {uob.dtype}')
    logger.debug(f'     vob           type  = {vob.dtype}')

    logger.debug(f'     alse          type = {alse.dtype}')
    logger.debug(f'     reqv          type = {reqv.dtype}')
    logger.debug(f'     tmdb          type = {tmdb.dtype}')
    logger.debug(f'     tmdp          type = {tmdp.dtype}')
    logger.debug(f'     wdir          type = {wdir.dtype}')
    logger.debug(f'     wspd          type = {wspd.dtype}')
    logger.debug(f'     mxgd          type = {mxgd.dtype}')
    logger.debug(f'     mxgs          type = {mxgs.dtype}')
    logger.debug(f'     topc          type = {topc.dtype}')
    logger.debug(f'     hovi          type = {hovi.dtype}')

    logger.debug(f'     qmpr          type = {qmpr.dtype}')
    logger.debug(f'     qmat          type = {qmat.dtype}')
    logger.debug(f'     qmdd          type = {qmdd.dtype}')
    logger.debug(f'     qmwn          type = {qmwn.dtype}')

    end_time = time.time()
    running_time = end_time - start_time
    logger.info(f"Running time for executing QuerySet to get ResultSet : {running_time} seconds")

    # =====================================
    # Create IODA ObsSpace
    # Write IODA output
    # =====================================

    # Create the dimensions
    dims = {'Location': np.arange(0, clath.shape[0])}

    # Create IODA ObsSpace
    iodafile = f"{cycle_type}.t{hh}z.{data_type}.tm00.{data_format}.api.nc"
    OUTPUT_PATH = os.path.join(ioda_dir, iodafile)
    logger.info(f"Create output file: {OUTPUT_PATH}")
    obsspace = ioda_ospace.ObsSpace(OUTPUT_PATH, mode='w', dim_dict=dims)

    # Create Global attributes
    logger.debug(' ... ... Create global attributes')
    obsspace.write_attr('sourceFiles', bufrfile)
    obsspace.write_attr('description', data_description)

    # Create IODA variables
    logger.debug(' ... ... Create variables: name, type, units, and attributes')

    # MetaData: Datetime
    obsspace.create_var('MetaData/dateTime', dtype=timestamp.dtype, fillval=timestamp.fill_value) \
        .write_attr('units', 'seconds since 1970-01-01T00:00:00Z') \
        .write_attr('long_name', 'Datetime') \
        .write_data(timestamp)

    # MetaData: Latitude
    obsspace.create_var('MetaData/latitude', dtype=clath.dtype, fillval=clath.fill_value) \
        .write_attr('units', 'degrees_north') \
        .write_attr('valid_range', np.array([-90, 90], dtype=np.float32)) \
        .write_attr('long_name', 'Latitude') \
        .write_data(clath)

    # MetaData: Longitude
    obsspace.create_var('MetaData/longitude', dtype=clonh.dtype, fillval=clonh.fill_value) \
        .write_attr('units', 'degrees_east') \
        .write_attr('valid_range', np.array([-180, 180], dtype=np.float32)) \
        .write_attr('long_name', 'Longitude') \
        .write_data(clonh)

    # MetaData: Station Identification
    obsspace.create_var('MetaData/stationIdentification', dtype=rpid.dtype, fillval=rpid.fill_value) \
        .write_attr('long_name', 'Station Identification') \
        .write_data(rpid)

    # MetaData: Station Elevation
    obsspace.create_var('MetaData/stationElevation', dtype=selv.dtype, fillval=selv.fill_value) \
        .write_attr('units', 'm') \
        .write_attr('long_name', 'Station Elevation') \
        .write_data(selv)

    # MetaData: Pressure
    obsspace.create_var('MetaData/pressure', dtype=pres.dtype, fillval=pres.fill_value) \
        .write_attr('units', 'Pa') \
        .write_attr('long_name', 'Pressure') \
        .write_data(pres)

    # MetaData: Height of Observation
    obsspace.create_var('MetaData/height', dtype=hsmsl.dtype, fillval=hsmsl.fill_value) \
        .write_attr('units', 'm') \
        .write_attr('long_name', 'Height of Observation') \
        .write_data(hsmsl)

    # MetaData: Data Provider Restricted
    obsspace.create_var('MetaData/dataProviderRestricted', dtype=rsrd.dtype, fillval=rsrd.fill_value) \
        .write_attr('long_name', 'Data Provider Restricted') \
        .write_data(rsrd)

    # MetaData: Data Restricted Expiration
    obsspace.create_var('MetaData/dataRestrictedExpiration', dtype=exprsrd.dtype, fillval=exprsrd.fill_value) \
        .write_attr('long_name', 'Data Restricted Expiration') \
        .write_data(exprsrd)

    # ObsValue: Altimeter Setting 
    obsspace.create_var('ObsValue/altimeterSetting', dtype=alse.dtype, fillval=alse.fill_value) \
        .write_attr('units', '') \
        .write_attr('long_name', 'Altimeter Setting') \
        .write_data(alse)

    # ObsValue: Snow Water Equivalent Rate
    obsspace.create_var('ObsValue/snowWaterEquivalentRate', dtype=reqv.dtype, fillval=reqv.fill_value) \
        .write_attr('units', '') \
        .write_attr('long_name', 'Snow Water Equivalent Rate') \
        .write_data(reqv)

    # ObsValue: Air Temperature
    obsspace.create_var('ObsValue/airTemperature', dtype=tmdb.dtype, fillval=tmdb.fill_value) \
        .write_attr('units', 'K') \
        .write_attr('long_name', 'Air Temperature') \
        .write_data(tmdb)

    # ObsValue: DewPoint Temperature
    obsspace.create_var('ObsValue/dewPointTemperature', dtype=tmdp.dtype, fillval=tmdp.fill_value) \
        .write_attr('units', 'K') \
        .write_attr('long_name', 'DewPoint Temperature') \
        .write_data(tmdp)

    # ObsValue: Eastward Wind
    obsspace.create_var('ObsValue/windEastward', dtype=uob.dtype, fillval=uob.fill_value) \
        .write_attr('units', 'm s-1') \
        .write_attr('long_name', 'Eastward Wind') \
        .write_data(uob)

    # ObsValue: Northward Wind
    obsspace.create_var('ObsValue/windNorthward', dtype=vob.dtype, fillval=vob.fill_value) \
        .write_attr('units', 'm s-1') \
        .write_attr('long_name', 'Northward Wind') \
        .write_data(vob)

    # ObsValue: Maximum Wind Gust Direction
    obsspace.create_var('ObsValue/maximumWindGustDirection', dtype=mxgd.dtype, fillval=mxgd.fill_value) \
        .write_attr('units', 'degree') \
        .write_attr('long_name', 'Maximum Wind Gust Direction') \
        .write_data(mxgd)

    # ObsValue: Maximum Wind Gust Speed
    obsspace.create_var('ObsValue/maximumWindGustSpeed', dtype=mxgs.dtype, fillval=mxgs.fill_value) \
        .write_attr('units', 'm s-1') \
        .write_attr('long_name', 'Maximum Wind Gust Speed') \
        .write_data(mxgs)        

    # ObsValue: totalPrecipitation
    obsspace.create_var('ObsValue/totalPrecipitation', dtype=topc.dtype, fillval=topc.fill_value) \
        .write_attr('units', 'kg m-2') \
        .write_attr('long_name', 'Total Precipitation') \
        .write_data(topc)

    # ObsValue: horizontalVisibility
    obsspace.create_var('ObsValue/horizontalVisibility', dtype=hovi.dtype, fillval=hovi.fill_value) \
        .write_attr('units', 'm') \
        .write_attr('long_name', 'Horizontal Visibility') \
        .write_data(hovi)

    # Quality Marker: Pressure Quality Marker
    obsspace.create_var('QualityMarker/pressure', dtype=qmpr.dtype, fillval=qmpr.fill_value) \
        .write_attr('long_name', 'Pressure Quality Marker') \
        .write_data(qmpr)

    # Quality Marker: Air Temperature Quality Marker
    obsspace.create_var('QualityMarker/airTemperature', dtype=qmat.dtype, fillval=qmat.fill_value) \
        .write_attr('long_name', 'Temperature Quality Marker') \
        .write_data(qmat)

    # Quality Marker: DewPoint Temperature Quality Marker
    obsspace.create_var('QualityMarker/dewPointTemperature', dtype=qmdd.dtype, fillval=qmdd.fill_value) \
        .write_attr('long_name', 'DewPoint Temperature Quality Marker') \
        .write_data(qmdd)

    # Quality Marker: Wind Quality Marker
    obsspace.create_var('QualityMarker/windEastward', dtype=qmwn.dtype, fillval=qmwn.fill_value) \
        .write_attr('long_name', 'Eastward Wind Quality Marker') \
        .write_data(qmwn)

    # Quality Marker: Wind Quality Marker
    obsspace.create_var('QualityMarker/windNorthward', dtype=qmwn.dtype, fillval=qmwn.fill_value) \
        .write_attr('long_name', 'Northward Wind Quality Marker') \
        .write_data(qmwn)        

    end_time = time.time()
    running_time = end_time - start_time
    logger.info(f"Running time for splitting and output IODA: {running_time} seconds")

    logger.info("All Done!")


if __name__ == '__main__':

    start_time = time.time()

    parser = argparse.ArgumentParser()
    parser.add_argument('-c', '--config', type=str, help='Input JSON configuration', required=True)
    parser.add_argument('-v', '--verbose', help='print debug logging information',
                        action='store_true')
    args = parser.parse_args()

    log_level = 'DEBUG' if args.verbose else 'INFO'
    logger = Logger('BUFR2IODA_msonet.py', level=log_level, colored_log=True)

    with open(args.config, "r") as json_file:
        config = json.load(json_file)

    bufr_to_ioda(config, logger)

    end_time = time.time()
    running_time = end_time - start_time
    logger.info(f"Total running time: {running_time} seconds")
