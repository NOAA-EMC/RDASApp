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
    platform_description = 'LGHTNG'

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

    # ObsType
    #q.add('observationType', '*/TYP')

    # MetaData
    q.add('year', '*/YEAR')
    q.add('month', '*/MNTH')
    q.add('day', '*/DAYS')
    q.add('hour', '*/HOUR')
    q.add('minute', '*/MINU')
    q.add('second', '*/SECO')
    q.add('latitude', '*/CLATH')
    q.add('longitude', '*/CLONH')
    q.add('dataProviderRestricted', '*/RSRD')
    q.add('dataRestrictedExpiration', '*/EXPRSRD')

    # ObsValue
    q.add('lightningDischargePolarity', '*/PLRTS')
    q.add('amplitudeOfLightningStrike', '*/AMPLS')
    q.add('lightningMultiStrikes', '*/NOFL')

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

    # ObsType
    logger.debug(" ... Executing QuerySet for LGHTNG: get ObsType ...")
    #obstyp = r.get('observationType', type='int32')
    logger.info('Executing QuerySet: get metadata')

    # MetaData
    clath = r.get('latitude')
    clonh = r.get('longitude')
    rsrd = r.get('dataProviderRestricted')
    exprsrd = r.get('dataRestrictedExpiration')

    # MetaData/Observation Time
    year = r.get('year')
    month = r.get('month')
    day = r.get('day')
    hour = r.get('hour')
    minute = r.get('minute')
    second = r.get('second')
    # DateTime: seconds since Epoch time
    # IODA has no support for numpy datetime arrays dtype=datetime64[s]
    timestamp = r.get_datetime('year', 'month', 'day', 'hour', 'minute', 'second').astype(np.int64)
    int64_fill_value = np.int64(0)
    timestamp = ma.array(timestamp)
    timestamp = ma.masked_values(timestamp, int64_fill_value)

    # ObsValue
    plrts = r.get('lightningDischargePolarity')
    ampls = r.get('amplitudeOfLightningStrike')
    nofl  = r.get('lightningMultiStrikes')

    logger.info('Executing QuerySet Done!')
    end_time = time.time()
    running_time = end_time - start_time
    logger.info(f"Running time for executing QuerySet to get ResultSet : {running_time} seconds")

    logger.debug('Executing QuerySet: Check BUFR variable generic dimension and type')
    # Check BUFR variable generic dimension and type
    logger.debug(f'     clath         shape = {clath.shape}')
    logger.debug(f'     clonh         shape = {clonh.shape}')
    logger.debug(f'     rsrd          shape = {rsrd.shape}')
    logger.debug(f'     exprsrd       shape = {exprsrd.shape}')

    logger.debug(f'     plrts      	  shape = {plrts.shape}')
    logger.debug(f'     ampls         shape = {ampls.shape}')
    logger.debug(f'     nofl          shape = {nofl.shape}')

    logger.debug(f'     clath         type = {clath.dtype}')
    logger.debug(f'     clonh         type = {clonh.dtype}')
    logger.debug(f'     rsrd          type = {rsrd.dtype}')
    logger.debug(f'     exprsrd       type = {exprsrd.dtype}')

    logger.debug(f'     plrts         type = {plrts.dtype}')
    logger.debug(f'     ampls         type = {ampls.dtype}')
    logger.debug(f'     nofl          type = {nofl.dtype}')

    # Mask Certain Variables
    logger.debug(f"Mask typ for certain variables where data is available...")

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

    # MetaData: Data Provider Restricted
    obsspace.create_var('MetaData/dataProviderRestricted', dtype=rsrd.dtype, fillval=rsrd.fill_value) \
        .write_attr('long_name', 'Data Provider Restricted') \
        .write_data(rsrd)

    # MetaData: Data Restricted Expiration
    obsspace.create_var('MetaData/dataRestrictedExpiration', dtype=exprsrd.dtype, fillval=exprsrd.fill_value) \
        .write_attr('long_name', 'Data Restricted Expiration') \
        .write_data(exprsrd)

    # ObsValue: Lightning Discharge Polarity
    obsspace.create_var('ObsValue/lightningDischargePolarity', dtype=plrts.dtype, fillval=plrts.fill_value) \
        .write_attr('long_name', 'Lightning Discharge Polarity') \
        .write_data(plrts)

    # ObsValue: Amplitude Of Lightning Strike
    obsspace.create_var('ObsValue/amplitudeOfLightningStrike', dtype=ampls.dtype, fillval=ampls.fill_value) \
        .write_attr('units', 'amps') \
        .write_attr('long_name', 'Amplitude Of Lightning Strike') \
        .write_data(ampls)

    # ObsValue: Lightning Multi Strikes
    obsspace.create_var('ObsValue/lightningMultiStrikes', dtype=nofl.dtype, fillval=nofl.fill_value) \
        .write_attr('units', '1') \
        .write_attr('long_name', 'Lightning Multi Strikes') \
        .write_data(nofl)

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
    logger = Logger('BUFR2IODA_lghtng.py', level=log_level, colored_log=True)

    with open(args.config, "r") as json_file:
        config = json.load(json_file)

    bufr_to_ioda(config, logger)

    end_time = time.time()
    running_time = end_time - start_time
    logger.info(f"Total running time: {running_time} seconds")