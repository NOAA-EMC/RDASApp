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
    platform_description = 'SATMAR'

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
    q.add('second', '*/SECO')
    # MetaData/Receipt Time
    q.add('receiptYear', '*/RCYR')
    q.add('receiptMonth', '*/RCMO')
    q.add('receiptDay', '*/RCDY')
    q.add('receiptHour', '*/RCHR')
    q.add('receiptMinute', '*/RCMI')
    q.add('latitude', '*/CLATH')
    q.add('longitude', '*/CLONH')
    q.add('satelliteIdentifier', '*/SAID')
    q.add('height', '*/ALTPE')

    # ObsValue
    q.add('brightnessTemperature', '*/TMBRST')
    q.add('windSpeed', '*/WSPA')
    q.add('heightOfWaves', '*/HOWV')
    q.add('windEastward', '*/UMWV')
    q.add('windNorthward', '*/VWMV')

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
    logger.debug(" ... Executing QuerySet for LGYCLD: get ObsType ...")
    logger.info('Executing QuerySet: get metadata')

    # MetaData
    clath = r.get('latitude')
    clonh = r.get('longitude')
    said = r.get('satelliteIdentifier')
    altpe = r.get('height')

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

    # MetaData/Receipt Time
    receiptYear = r.get('receiptYear')
    receiptMonth = r.get('receiptMonth')
    receiptDay = r.get('receiptDay')
    receiptHour = r.get('receiptHour')
    receiptMinute = r.get('receiptMinute')
    logger.debug(f" ... Executing QuerySet: get datatime: receipt time ...")
    receipttime = r.get_datetime('receiptYear', 'receiptMonth', 'receiptDay', 'receiptHour', 'receiptMinute').astype(np.int64)
    int64_fill_value = np.int64(0)
    receipttime = ma.array(receipttime)
    receipttime = ma.masked_values(receipttime, int64_fill_value)

    # ObsValue
    tmbrst  = r.get('brightnessTemperature')
    wspa    = r.get('windSpeed')
    howv    = r.get('heightOfWaves')
    umwv    = r.get('windEastward')
    vwmv    = r.get('windNorthward')

    logger.info('Executing QuerySet Done!')
    end_time = time.time()
    running_time = end_time - start_time
    logger.info(f"Running time for executing QuerySet to get ResultSet : {running_time} seconds")

    logger.debug('Executing QuerySet: Check BUFR variable generic dimension and type')
    # Check BUFR variable generic dimension and type
    logger.debug(f'     clath         shape = {clath.shape}')
    logger.debug(f'     clonh         shape = {clonh.shape}')
    logger.debug(f'     said          shape = {said.shape}')
    logger.debug(f'     altpe         shape = {altpe.shape}')

    logger.debug(f'     rcyr          shape = {receiptYear.shape}')
    logger.debug(f'     rcmo          shape = {receiptMonth.shape}')
    logger.debug(f'     rcdy          shape = {receiptDay.shape}')
    logger.debug(f'     rchr          shape = {receiptHour.shape}')
    logger.debug(f'     rcmi          shape = {receiptMinute.shape}')

    logger.debug(f'     tmbrst        shape = {tmbrst.shape}')
    logger.debug(f'     wspa      	  shape = {wspa.shape}')
    logger.debug(f'     howv      	  shape = {howv.shape}')
    logger.debug(f'     umwv      	  shape = {umwv.shape}')
    logger.debug(f'     vwmv      	  shape = {vwmv.shape}')

    logger.debug(f'     clath         type = {clath.dtype}')
    logger.debug(f'     clonh         type = {clonh.dtype}')
    logger.debug(f'     said          type = {said.dtype}')
    logger.debug(f'     altpe         type = {altpe.dtype}')

    logger.debug(f'     rcyr          type  = {receiptYear.dtype}')
    logger.debug(f'     rcmo          type  = {receiptMonth.dtype}')
    logger.debug(f'     rcdy          type  = {receiptDay.dtype}')
    logger.debug(f'     rchr          type  = {receiptHour.dtype}')
    logger.debug(f'     rcmi          type  = {receiptMinute.dtype}')

    logger.debug(f'     tmbrst        type = {tmbrst.dtype}')
    logger.debug(f'     wspa          type = {wspa.dtype}')
    logger.debug(f'     howv          type = {howv.dtype}')
    logger.debug(f'     umwv          type = {umwv.dtype}')
    logger.debug(f'     vwmv          type = {vwmv.dtype}')

    # Mask Certain Variables
    logger.debug(f"Mask typ for certain variables where data is available...")

    # =====================================
    # Create IODA ObsSpace
    # Write IODA output
    # =====================================

    # Create the dimensions
    dims = {'Location': np.arange(0, clath.shape[0])}

    # Create IODA ObsSpace
    iodafile = f"{cycle_type}.t{hh}z.{data_type}.tm00.api.nc"
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

    # MetaData: ReceiptTime
    obsspace.create_var('MetaData/receiptTime', dtype=timestamp.dtype, fillval=timestamp.fill_value) \
        .write_attr('units', 'seconds since 1970-01-01T00:00:00Z') \
        .write_attr('long_name', 'Receipt Time') \
        .write_data(receipttime)

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

    # MetaData: Satellite Identifier
    obsspace.create_var('MetaData/satelliteIdentifier', dtype=said.dtype, fillval=said.fill_value) \
        .write_attr('long_name', 'Satellite Identifier') \
        .write_data(said)

    # MetaData: Height
    obsspace.create_var('MetaData/height', dtype=altpe.dtype, fillval=altpe.fill_value) \
        .write_attr('units', 'm') \
        .write_attr('long_name', 'Altitude (Platform to Ellipsoid)') \
        .write_data(altpe)    

    # ObsValue: Brightness Temperature 
    obsspace.create_var('ObsValue/brightnessTemperature', dtype=tmbrst.dtype, fillval=tmbrst.fill_value) \
        .write_attr('units', 'K') \
        .write_attr('long_name', 'Brightness temperature') \
        .write_data(tmbrst)

    # ObsValue: Wind Speed
    obsspace.create_var('ObsValue/windSpeed', dtype=wspa.dtype, fillval=wspa.fill_value) \
        .write_attr('units', 'm s-1') \
        .write_attr('long_name', 'Wind Speed') \
        .write_data(wspa)

    # ObsValue: Height Of Waves
    obsspace.create_var('ObsValue/heightOfWaves', dtype=howv.dtype, fillval=howv.fill_value) \
        .write_attr('units', 'm') \
        .write_attr('long_name', 'Height Of Waves') \
        .write_data(howv)

    # ObsValue: Eastward Wind
    obsspace.create_var('ObsValue/windEastward', dtype=umwv.dtype, fillval=umwv.fill_value) \
        .write_attr('units', 'm s-1') \
        .write_attr('long_name', 'Eastward Wind') \
        .write_data(umwv)

    # ObsValue: Northward Wind
    obsspace.create_var('ObsValue/windNorthward', dtype=vwmv.dtype, fillval=vwmv.fill_value) \
        .write_attr('units', 'm s-1') \
        .write_attr('long_name', 'Northward Wind') \
        .write_data(vwmv)

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
    logger = Logger('BUFR2IODA_satmar.py', level=log_level, colored_log=True)

    with open(args.config, "r") as json_file:
        config = json.load(json_file)

    bufr_to_ioda(config, logger)

    end_time = time.time()
    running_time = end_time - start_time
    logger.info(f"Total running time: {running_time} seconds")
