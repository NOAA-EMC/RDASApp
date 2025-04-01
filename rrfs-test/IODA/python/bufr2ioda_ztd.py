#!/usr/bin/env python3
# (C) Copyright 2025 NOAA/NWS/NCEP/EMC
#     This software is licensed under the terms of the Apache Licence 
#     Version 2.0 which can be obtained at 
#     http://www.apache.org/licenses/LICENSE-2.0.
# -------------------------------------------------------------------
# This tool converts GNSS Zenith Total Delay (ZTD) data from the RAP 
# Bufr gpsipw dump to JEDI/IODA netcdf input file.
# -------------------------------------------------------------------

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

# ========================================================
# rap hourly gpsipw bufr dump(rap.t??z.gpsipw.tm00.bufr_d)
# ========================================================
# MNEMONIC | NUMBER | DESCRIPTION
# ---------|----------------------------------------------
# NC012004 | A62005 | M TYPE 012-004 Ground-based GNSS ZTD
# ========================================================

def bufr_to_ioda(config, logger):

#  read in the configuration parameters
    cycle = config["cycle_datetime"]
    subsets = [ "NC012004" ]

#   subsets = config["subsets"]
#   data_description = config["data_description"]
#   data_product = config["data_product"]

    logger.info(f"-----------------")
    logger.info(f"cycle= {cycle} ")
    logger.info(f"-----------------")

    # Get derived parameters
    yyyymmdd = cycle[0:8]
    hh = cycle[8:10]
    reference_time = datetime.strptime(cycle, "%Y%m%d%H")
    reference_time = reference_time.strftime("%Y-%m-%dT%H:%M:%SZ")
    logger.info(f"reference_time = {reference_time}")

    bufrfile = "./ztdbufr"

    # =================================
    # Make QuerySet for the data wanted
    # =================================
    logger.info('Making QuerySet')

    q = bufr.QuerySet(subsets)

    # --------
    # MetaData
    # --------
    q.add('year', '*/YEAR')
    q.add('month', '*/MNTH')
    q.add('day', '*/DAYS')
    q.add('hour', '*/HOUR')
    q.add('minute', '*/MINU')

    q.add('latitude', '*/CLATH')
    q.add('longitude', '*/CLONH')
    q.add('stationIdentification', '*/STSN')
    q.add('stationElevation', '*/SELV')
    q.add('pressure', '*/PRES')
    q.add('height', '*/SELV')
    q.add('airTemperature', '*/TMDBST')
    q.add('pathAzimuth', '*/GNSSRPSQ{1}/BEARAZ')
    q.add('pathElevation', '*/GNSSRPSQ{1}/ELEV')

    q.add('tpmi', '*/TPMI')
    q.add('rcmi', '*/RCMI')

    # ObsValue
    q.add('zenithTotalDelay', '*/GNSSRPSQ{1}/APDS')
    q.add('zenithWetDelay', '*/ZPDW')
    q.add('totalPrecipitableWater', '*/TPWT')

    # ObsError
    q.add('zenithTotalDelayErr', '*/GNSSRPSQ{1}/APDE')

    # QualityMark  (initially using Obs Error)
    q.add('zenithTotalDelayQM', '*/GNSSRPSQ{1}/APDE')
#   QFGN not defined in the RAP dataset
#   q.add('zenithTotalDelayQM', '*/QFGN')

    # ============================================================
    # Open the BUFR file and execute the QuerySet to get ResultSet
    # Use the ResultSet returned to get numpy arrays of the data
    # ============================================================

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
    lon[lon < 0] += 360  # Convert to [0, 360]

    sid = r.get('stationIdentification')
    elv = r.get('stationElevation', type='float')
    pob = r.get('pressure', type='float')
    zob = r.get('height', type='float')
    tob = r.get('airTemperature', type='float')
    paz = r.get('pathAzimuth', type='float')
    pel = r.get('pathElevation', type='float')

    tpmi = r.get('tpmi', type='float')
    rcmi = r.get('rcmi', type='float')

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
    ztd = r.get('zenithTotalDelay', type='float32')
    zwd = r.get('zenithWetDelay', type='float32')
    tpw = r.get('totalPrecipitableWater', type='float32')

    # ObsError
    ztdoe = r.get('zenithTotalDelayErr', type='float32')

    # QualityMark
    ztdqm = r.get('zenithTotalDelayQM', type='float32')
    ztdqm = ztdqm*1000
    ztdqm = ztdqm.astype(int)   # to integer

    logger.info(' QuerySet Done!')

    logger.info('Executing QuerySet: Check BUFR variable generic dimension and type')
    # Check prepBUFR variable generic dimension and type
    logger.info(f'     lat       shape = {lat.shape}')
    logger.info(f'     lon       shape = {lon.shape}')
    logger.info(f'     sid       shape = {sid.shape}')
    logger.info(f'     elv       shape = {elv.shape}')
    logger.info(f'     pob       shape = {pob.shape}')
    logger.info(f'     zob       shape = {zob.shape}')
    logger.info(f'     tob       shape = {tob.shape}')
    logger.info(f'     ztd       shape = {ztd.shape}')
    logger.info(f'     zwd       shape = {zwd.shape}')
    logger.info(f'     tpw       shape = {tpw.shape}')
    logger.info(f'     ztdoe     shape = {ztdoe.shape}')
    logger.info(f'     ztdqm     shape = {ztdqm.shape}')

    logger.info(f'     lat       type  = {lat.dtype}')
    logger.info(f'     lon       type  = {lon.dtype}')
    logger.info(f'     sid       type  = {sid.dtype}')
    logger.info(f'     elv       type  = {elv.dtype}')
    logger.info(f'     pob       type  = {pob.dtype}')
    logger.info(f'     zob       type  = {zob.dtype}')
    logger.info(f'     tob       type  = {tob.dtype}')
    logger.info(f'     ztd       type  = {ztd.dtype}')
    logger.info(f'     zwd       type  = {zwd.dtype}')
    logger.info(f'     tpw       type  = {tpw.dtype}')
    logger.info(f'     ztdoe     type  = {ztdoe.dtype}')
    logger.info(f'     ztdqm     type  = {ztdqm.dtype}')


    #----------------------------------------
    # Separate product anme and station name
    #----------------------------------------
    stn0 = np.empty(sid.shape, dtype=object)  # dtype=object for string
    prod = np.empty(sid.shape, dtype=object)  # dtype=object for string

    for i in range(len(sid)):
        sid0 = sid[i]
        stn0[i] = sid0[0:4]   # not include 4, station name
        prod[i] = sid0[5:9]   # not include 9, product name

    # ------------------------------------------
    #  Do superobs for Product MTGH, MTRH, ROBG 
    # ------------------------------------------

    # select these products
    indm = np.where((prod == "MTGH") | (prod == "MTRH") | (prod == "ROBG") )[:]

    ztd2 = ztd[indm]
    ztdoe2 = ztdoe[indm]
    stn2 = stn0[indm]

    # ----- unique stations of MTGH/MTRH/ROBG -----
    stn3, ind3 = np.unique(stn2, return_index=True)

    # ---------------- Do superob ------------------
    supob = np.zeros(stn3.shape[0], dtype='float32')
    supoe = np.zeros(stn3.shape[0], dtype='float32')

    for i in range(len(stn3)):         
        count = 0
        supob[i] = 0.0
        supoe[i] = 0.0
        for k in range(len(ztd2)):         
            if(stn2[k] == stn3[i]):
              supob[i] += ztd2[k]
              supoe[i] += ztdoe2[k]
              ztd2[k]   = ztd.fill_value    # set missing after superob
              ztdoe2[k] = ztd.fill_value    # set missing after superob
              count+=1
        supob[i] = supob[i]/count
        supoe[i] = supoe[i]/count
#       print('count  = ', count)

    # push back superobed into the unique MTGH/MTRH/ROBG list
    ztd2[ind3] = supob
    ztdoe2[ind3] = supoe

    # push back to original ztd array
    ztd[indm] = ztd2
    ztdoe[indm] = ztdoe2

    # --- update QCs for superobed ZTD OBS ---
    for i in range(len(ztd)):         
        if(ztd[i] == ztd.fill_value ):
          ztdqm[i] = 11      # Skipped due to superob
    # ----------- end superobing -------------

    # -----------------------
    # Create IODA output file
    # -----------------------
    dims = {'Location': np.arange(0, lat.shape[0])}

    iodafile = "./ioda_gnss_ztd.nc"
    obsspace = ioda_ospace.ObsSpace(iodafile, mode='w', dim_dict=dims)

    # Create Global attributes
    data_product= "ZTD products from RAP gpsipw dump"
    data_description= "GNSS ZTD from gpsipw"

    logger.info(' Create global attributes')
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
        .write_attr('valid_range', np.array([-90, 90])) \
        .write_attr('long_name', 'Latitude') \
        .write_data(lat)

    obsspace.create_var('MetaData/longitude', dtype=lon.dtype, fillval=lon.fill_value) \
        .write_attr('units', 'degrees_east') \
        .write_attr('valid_range', np.array([-180, 180])) \
        .write_attr('long_name', 'Longitude') \
        .write_data(lon)

    obsspace.create_var('MetaData/stationProductName', dtype=sid.dtype, fillval=sid.fill_value) \
        .write_attr('long_name', 'Station-Product pair name String') \
        .write_data(sid)

    obsspace.create_var('MetaData/productName', dtype=prod.dtype, fillval=sid.fill_value) \
        .write_attr('long_name', 'Product name String') \
        .write_data(prod)

    obsspace.create_var('MetaData/stationName', dtype=stn0.dtype, fillval=sid.fill_value) \
        .write_attr('long_name', 'Station Name') \
        .write_data(stn0)

    obsspace.create_var('MetaData/stationElevation', dtype=elv.dtype, fillval=elv.fill_value) \
        .write_attr('units', 'm') \
        .write_attr('long_name', 'Station Elevation above MSL') \
        .write_data(elv)

    obsspace.create_var('MetaData/pressure', dtype=pob.dtype, fillval=pob.fill_value) \
        .write_attr('units', 'Pa') \
        .write_attr('long_name', 'Pressure at Station height') \
        .write_data(pob)

    obsspace.create_var('MetaData/height', dtype=zob.dtype, fillval=zob.fill_value) \
        .write_attr('units', 'm') \
        .write_attr('long_name', 'Station height') \
        .write_data(zob)

    obsspace.create_var('MetaData/airTemperature', dtype=tob.dtype, fillval=tob.fill_value) \
        .write_attr('units', 'K') \
        .write_attr('long_name', 'Air Temperature at Station height') \
        .write_data(tob)

    obsspace.create_var('MetaData/pathAzimuth', dtype=paz.dtype, fillval=paz.fill_value) \
        .write_attr('units', 'Degree_from_north') \
        .write_attr('valid_range', np.array([0, 360])) \
        .write_attr('long_name', 'Signal path clockwise from True North') \
        .write_data(paz)

    obsspace.create_var('MetaData/pathElevation', dtype=pel.dtype, fillval=pel.fill_value) \
        .write_attr('units', 'Degree_above_horizon') \
        .write_attr('valid_range', np.array([-90, 90])) \
        .write_attr('long_name', 'Signal path angle above horizon') \
        .write_data(pel)

    obsspace.create_var('MetaData/timePeriod', dtype=tpmi.dtype, fillval=tpmi.fill_value) \
        .write_attr('units', 'minute') \
        .write_attr('valid_range', np.array([0, 60])) \
        .write_attr('long_name', 'Time period/displacement') \
        .write_data(tpmi)

    obsspace.create_var('MetaData/timeOfReceipt', dtype=rcmi.dtype, fillval=rcmi.fill_value) \
        .write_attr('units', 'minute') \
        .write_attr('valid_range', np.array([0, 60])) \
        .write_attr('long_name', 'TIME OF RECEIPT') \
        .write_data(rcmi)

    #----------
    # ObsValue
    #----------
    obsspace.create_var('ObsValue/zenithTotalDelay', dtype=ztd.dtype, fillval=ztd.fill_value) \
        .write_attr('units', 'm') \
        .write_attr('valid_range', np.array([0.0001, 5])) \
        .write_attr('long_name', 'Zenith Total Delay') \
        .write_data(ztd)

    obsspace.create_var('ObsValue/zenithWetDelay', dtype=zwd.dtype, fillval=zwd.fill_value) \
        .write_attr('units', 'm') \
        .write_attr('valid_range', np.array([0.0001, 5])) \
        .write_attr('long_name', 'Zenith Wet Delay') \
        .write_data(zwd)

    obsspace.create_var('ObsValue/totalPrecipitableWater', dtype=tpw.dtype, fillval=tpw.fill_value) \
        .write_attr('units', 'kg/m**2') \
        .write_attr('valid_range', np.array([0.0001, 100.0])) \
        .write_attr('long_name', 'Total Precipitable Water') \
        .write_data(tpw)

    #----------
    # ObsError
    #----------
    obsspace.create_var('ObsError/zenithTotalDelay', dtype=ztdoe.dtype, fillval=ztdoe.fill_value) \
        .write_attr('units', 'm') \
        .write_attr('valid_range', np.array([0, 100])) \
        .write_attr('long_name', 'Estimated Error in Atmospheric Path Delay') \
        .write_data(ztdoe)

    #---------------
    # Quality Marker
    #---------------
    obsspace.create_var('QualityMarker/zenithTotalDelay', dtype=ztdqm.dtype, fillval=ztdqm.fill_value) \
        .write_attr('long_name', 'ZenithTotalDelay Quality Marker') \
        .write_data(ztdqm)

    logger.info("All Done!")


if __name__ == '__main__':

    parser = argparse.ArgumentParser()
    parser.add_argument('-c', '--config', type=str, help='Input JSON configuration', required=True)
    parser.add_argument('-v', '--verbose', help='print debug logging information',
                        action='store_true')
    args = parser.parse_args()

#--------- LOG info format ------------------------
    log_level = 'DEBUG' if args.verbose else 'INFO'
    logger = Logger('ZTD:', level=log_level, colored_log=True)

    with open(args.config, "r") as json_file:
        config = json.load(json_file)

    bufr_to_ioda(config, logger)
