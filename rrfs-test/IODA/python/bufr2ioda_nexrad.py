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
    platform_description = 'NEXRAD'

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
    q.add('latitude', '[*/CLATH, */CLAT]')
    q.add('longitude', '[*/CLONH, */CLON]')
    q.add('stationIdentification', '*/SSTN')
    q.add('height', '*/HSMSL')
    q.add('heightOfAntenna', '*/HSALG')
    q.add('volumeIndex', '*/VOID')
    q.add('scanIndex', '*/SCID')
    q.add('ppiVolume', '*/VOCP')

    # ObsValue
    q.add('beamAzimuthAngle', '*/ANAZ')
    q.add('beamTiltAngle', '*/ANEL')
    q.add('gateRange', '*/NL2RW{1}/DIST125M')
    q.add('radialVelocity', '*/NL2RW{1}/DMVR')
    q.add('spectralWidth', '*/NL2RW{1}/DVSW')
    q.add('unfoldingVelocity', '*/HNQV')

    # QualityMarker
    q.add('radialVelocityQM', '*/QCRW')

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
    logger.debug(" ... Executing QuerySet for NEXRAD: get ObsType ...")
    #obstyp = r.get('observationType', type='int32')
    logger.info('Executing QuerySet: get metadata')

    # MetaData
    dvsw = r.get('spectralWidth', 'spectralWidth')
    clath = r.get('latitude', 'spectralWidth')
    clonh = r.get('longitude', 'spectralWidth')
    sstn = r.get('stationIdentification', 'spectralWidth')
    hsmsl = r.get('height', 'spectralWidth')
    hsalg = r.get('heightOfAntenna', 'spectralWidth')
    void     = r.get('volumeIndex', 'spectralWidth')
    scid     = r.get('scanIndex', 'spectralWidth')
    vocp     = r.get('ppiVolume', 'spectralWidth')

    # MetaData/Observation Time
    year = r.get('year')
    month = r.get('month')
    day = r.get('day')
    hour = r.get('hour')
    minute = r.get('minute')
    second = r.get('second')
    # DateTime: seconds since Epoch time
    # IODA has no support for numpy datetime arrays dtype=datetime64[s]
    timestamp = r.get_datetime('year', 'month', 'day', 'hour', 'minute', 'second', 'spectralWidth').astype(np.int64)
    int64_fill_value = np.int64(0)
    timestamp = ma.array(timestamp)
    timestamp = ma.masked_values(timestamp, int64_fill_value)

    # ObsValue
    anaz     = r.get('beamAzimuthAngle', 'spectralWidth')
    anel     = r.get('beamTiltAngle', 'spectralWidth')
    dist125m = r.get('gateRange', 'spectralWidth')
    dist125m *= 125
    dmrv     = r.get('radialVelocity', 'spectralWidth')
    hnqv     = r.get('unfoldingVelocity', 'spectralWidth')

    # QualityMarker
    qcrw = r.get('radialVelocityQM', 'spectralWidth')

    logger.info('Executing QuerySet Done!')
    end_time = time.time()
    running_time = end_time - start_time
    logger.info(f"Running time for executing QuerySet to get ResultSet : {running_time} seconds")

    logger.debug('Executing QuerySet: Check BUFR variable generic dimension and type')
    # Check BUFR variable generic dimension and type
    logger.debug(f'     clath         shape = {clath.shape}')
    logger.debug(f'     clonh         shape = {clonh.shape}')
    logger.debug(f'     sstn          shape = {sstn.shape}')
    logger.debug(f'     hsmsl         shape = {hsmsl.shape}')
    logger.debug(f'     hsalg         shape = {hsalg.shape}')
    logger.debug(f'     void          shape = {void.shape}')
    logger.debug(f'     scid          shape = {scid.shape}')
    logger.debug(f'     vocp          shape = {vocp.shape}')

    logger.debug(f'     anaz          shape = {anaz.shape}')
    logger.debug(f'     anel          shape = {anel.shape}')
    logger.debug(f'     dist125m      shape = {dist125m.shape}')
    logger.debug(f'     dmrv          shape = {dmrv.shape}')
    logger.debug(f'     dvsw          shape = {dvsw.shape}')
    logger.debug(f'     hnqv          shape = {hnqv.shape}')


    logger.debug(f'     qcrw          shape = {qcrw.shape}')

    logger.debug(f'     clath         type = {clath.dtype}')
    logger.debug(f'     clonh         type = {clonh.dtype}')
    logger.debug(f'     sstn          type = {sstn.dtype}')
    logger.debug(f'     hsmsl         type = {hsmsl.dtype}')
    logger.debug(f'     hsalg         type = {hsalg.dtype}')
    logger.debug(f'     void          type = {void.dtype}')
    logger.debug(f'     scid          type = {scid.dtype}')
    logger.debug(f'     vocp          type = {vocp.dtype}')

    logger.debug(f'     anaz          type = {anaz.dtype}')
    logger.debug(f'     anel          type = {anel.dtype}')
    logger.debug(f'     dist125m      type = {dist125m.dtype}')
    logger.debug(f'     dmrv          type = {dmrv.dtype}')
    logger.debug(f'     dvsw          type = {dvsw.dtype}')
    logger.debug(f'     hnqv          type = {hnqv.dtype}')

    logger.debug(f'     qcrw          type = {qcrw.dtype}')

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

    # MetaData: Station Identification
    obsspace.create_var('MetaData/stationIdentification', dtype=sstn.dtype, fillval=sstn.fill_value) \
        .write_attr('long_name', 'Station Identification') \
        .write_data(sstn)

    # MetaData: Height Of Station Ground Above MSL 
    obsspace.create_var('MetaData/height', dtype=hsmsl.dtype, fillval=hsmsl.fill_value) \
        .write_attr('units', 'm') \
        .write_attr('long_name', 'Height Of Station Ground Above MSL') \
        .write_data(hsmsl)

    # MetaData: Height Of Antenna Above Ground
    obsspace.create_var('MetaData/heightOfAntenna', dtype=hsalg.dtype, fillval=hsalg.fill_value) \
        .write_attr('units', 'm') \
        .write_attr('long_name', 'Height Of Antenna Above Ground') \
        .write_data(hsalg)

    # MetaData: Radar Volume Id
    obsspace.create_var('MetaData/volumeIndex', dtype=void.dtype, fillval=void.fill_value) \
        .write_attr('long_name', 'Radar Volume Id') \
        .write_data(void)

    # MetaData: Radar Scan Id
    obsspace.create_var('MetaData/scanIndex', dtype=scid.dtype, fillval=scid.fill_value) \
        .write_attr('long_name', 'Radar Scan Id') \
        .write_data(scid)

    # MetaData: Volume Coverage Pattern
    obsspace.create_var('MetaData/ppiVolume', dtype=vocp.dtype, fillval=vocp.fill_value) \
        .write_attr('long_name', 'Volume Coverage Pattern') \
        .write_data(vocp)

    # ObsValue: Antenna Azimuth Angle
    obsspace.create_var('ObsValue/beamAzimuthAngle', dtype=anaz.dtype, fillval=anaz.fill_value) \
        .write_attr('units', 'degree') \
        .write_attr('long_name', 'Antenna Azimuth Angle') \
        .write_data(anaz)

    # ObsValue: Antenna Elevation Angle
    obsspace.create_var('ObsValue/beamTiltAngle', dtype=anel.dtype, fillval=anel.fill_value) \
        .write_attr('units', 'degree') \
        .write_attr('long_name', 'Antenna Elevation Angle') \
        .write_data(anel)

    # ObsValue: Distance From Antenna
    obsspace.create_var('ObsValue/gateRange', dtype=dist125m.dtype, fillval=dist125m.fill_value) \
        .write_attr('units', 'm') \
        .write_attr('long_name', 'Distance From Antenna') \
        .write_data(dist125m)

    # ObsValue: Doppler Mean Radial Velocity
    obsspace.create_var('ObsValue/radialVelocity', dtype=dmrv.dtype, fillval=dmrv.fill_value) \
        .write_attr('units', 'm s-1') \
        .write_attr('long_name', 'Doppler Mean Radial Velocity') \
        .write_data(dmrv)

    # ObsValue: Doppler Velocity Spectral Width
    #obsspace.create_var('ObsValue/spectralWidth', dtype=dvsw.dtype, fillval=dvsw.fill_value) \
    #    .write_attr('units', 'm s-1') \
    #    .write_attr('long_name', 'Doppler Velocity Spectral Width') \
    #    .write_data(dvsw)

    # ObsValue: Unfolding Velocity (to compute Nyquist frequency)
    obsspace.create_var('ObsValue/unfoldingVelocity', dtype=hnqv.dtype, fillval=hnqv.fill_value) \
        .write_attr('units', 'm s-1') \
        .write_attr('long_name', 'Unfolding Velocity (to compute Nyquist frequency)') \
        .write_data(hnqv)

    # QlalityMarker: Quality Marker For Wind Along Radial Line 
    obsspace.create_var('QualityMarker/radialVelocity', dtype=qcrw.dtype, fillval=qcrw.fill_value) \
        .write_attr('long_name', 'Quality Marker For Wind Along Radial Line') \
        .write_data(qcrw)

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
    logger = Logger('BUFR2IODA_nexrad.py', level=log_level, colored_log=True)

    with open(args.config, "r") as json_file:
        config = json.load(json_file)

    bufr_to_ioda(config, logger)

    end_time = time.time()
    running_time = end_time - start_time
    logger.info(f"Total running time: {running_time} seconds")
