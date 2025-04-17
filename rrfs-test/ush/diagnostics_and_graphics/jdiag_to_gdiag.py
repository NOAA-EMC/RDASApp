#!/usr/bin/env python
import netCDF4 as nc
import numpy as np
from datetime import datetime
import sys
import os

# Mapping from JEDI variable names to GSI variable types
variable_map = {
    "airTemperature": "t",
    "specificHumidity": "q",
    "stationPressure": "ps",
    "winds": "uv"
}

def parse_jdiag_filename(filename):
    """
    Parse a jdiag filename to extract platform, variable, and observation type.

    Args:
        filename (str): Path or name of the jdiag file

    Returns:
        tuple: (platform, var, obs_type)
    """
    base = os.path.basename(filename)
    parts = base.split('_')
    if len(parts) != 4 or parts[0] != 'jdiag' or not parts[3].endswith(('.nc4', '.nc')):
        raise ValueError(f"Invalid jdiag file name: {filename}")
    platform = parts[1]
    var = parts[2]
    type_str = parts[3].split('.')[0]
    try:
        obs_type = int(type_str)
    except ValueError:
        raise ValueError(f"Invalid observation type in file name: {filename}")
    return platform, var, obs_type

def read_jdiag_non_wind(file_path, jedi_var):
    """
    Read data from a non-wind jdiag file.

    Args:
        file_path (str): Path to the jdiag file
        jedi_var (str): JEDI variable name (e.g., 'airTemperature')

    Returns:
        tuple: Arrays of station_id, latitude, longitude, pressure, date_time,
               observation, effective_error_0, ombg, oman
    """
    with nc.Dataset(file_path, 'r') as f:
        station_id = f['MetaData/stationIdentification'][:]
        latitude = f['MetaData/latitude'][:]
        longitude = f['MetaData/longitude'][:]
        pressure = f['MetaData/pressure'][:]
        date_time = f['MetaData/dateTime'][:]
        observation = f['ObsValue'][jedi_var][:]
        effective_error_0 = f['EffectiveError0'][jedi_var][:]
        ombg = f['ombg'][jedi_var][:]
        oman = f['oman'][jedi_var][:]
    return (station_id, latitude, longitude, pressure, date_time,
            observation, effective_error_0, ombg, oman)

def read_jdiag_wind(file_path):
    """
    Read data from a wind jdiag file.

    Args:
        file_path (str): Path to the jdiag file

    Returns:
        tuple: Arrays of station_id, latitude, longitude, pressure, date_time,
               u_observation, v_observation, effective_error_0, u_ombg, v_ombg,
               u_oman, v_oman
    """
    with nc.Dataset(file_path, 'r') as f:
        station_id = f['MetaData/stationIdentification'][:]
        latitude = f['MetaData/latitude'][:]
        longitude = f['MetaData/longitude'][:]
        pressure = f['MetaData/pressure'][:]
        date_time = f['MetaData/dateTime'][:]
        u_observation = f['ObsValue/windEastward'][:]
        v_observation = f['ObsValue/windNorthward'][:]
        effective_error_0 = f['EffectiveError0/windEastward'][:]  # Same for u and v
        u_ombg = f['ombg/windEastward'][:]
        v_ombg = f['ombg/windNorthward'][:]
        u_oman = f['oman/windEastward'][:]
        v_oman = f['oman/windNorthward'][:]
    return (station_id, latitude, longitude, pressure, date_time,
            u_observation, v_observation, effective_error_0,
            u_ombg, v_ombg, u_oman, v_oman)

def process_non_wind_group(files, jedi_var, gsi_var, analysis_time):
    """
    Process a group of non-wind jdiag files and create corresponding gdiag files.

    Args:
        files (list): List of jdiag file paths
        jedi_var (str): JEDI variable name
        gsi_var (str): GSI variable type (t, q, ps)
        analysis_time (str): Analysis time string (e.g., '2024050701')
    """
    station_id_list = []
    obs_type_list = []
    latitude_list = []
    longitude_list = []
    pressure_list = []
    time_list = []
    errinv_input_list = []
    observation_list = []
    ombg_list = []
    oman_list = []

    for file_path in files:
        platform, var, obs_type = parse_jdiag_filename(file_path)
        if var != jedi_var:
            continue
        data = read_jdiag_non_wind(file_path, jedi_var)
        (station_id, latitude, longitude, pressure, date_time,
         observation, effective_error_0, ombg, oman) = data
        nobs = len(station_id)
        pressure_hpa = pressure / 100.0  # Pa to hPa
        analysis_dt = datetime.strptime(analysis_time, '%Y%m%d%H')
        time_offset = [(datetime.fromtimestamp(dt) - analysis_dt).total_seconds() / 3600.0
                       for dt in date_time]
        errinv_input = np.where(effective_error_0 > 0, 1.0 / effective_error_0, 0.0)
        station_id_list.extend(station_id)
        obs_type_list.extend([obs_type] * nobs)
        latitude_list.extend(latitude)
        longitude_list.extend(longitude)
        pressure_list.extend(pressure_hpa)
        time_list.extend(time_offset)
        errinv_input_list.extend(errinv_input)
        observation_list.extend(observation)
        ombg_list.extend(ombg)
        oman_list.extend(oman)

    total_nobs = len(station_id_list)
    if total_nobs == 0:
        print(f"No observations for {gsi_var}")
        return

    maxstrlen = max(len(str(s)) for s in station_id_list)
    station_id_array = np.array([list(str(s).ljust(maxstrlen)) for s in station_id_list], dtype='S1')
    obs_class_array = np.array([list('conv'.ljust(7)) for _ in range(total_nobs)], dtype='S1')

    for stage, omf_list in zip(['ges', 'anl'], [ombg_list, oman_list]):
        output_file = f"diag_conv_{gsi_var}_{stage}.nc"
        with nc.Dataset(output_file, 'w', format='NETCDF4') as f:
            f.createDimension('nobs', total_nobs)
            f.createDimension('Station_ID_maxstrlen', maxstrlen)
            f.createDimension('Observation_Class_maxstrlen', 7)

            f.createVariable('Station_ID', 'S1', ('nobs', 'Station_ID_maxstrlen'))[:] = station_id_array
            f.createVariable('Observation_Class', 'S1', ('nobs', 'Observation_Class_maxstrlen'))[:] = obs_class_array
            f.createVariable('Observation_Type', 'i4', ('nobs',))[:] = obs_type_list
            f.createVariable('Latitude', 'f4', ('nobs',))[:] = latitude_list
            f.createVariable('Longitude', 'f4', ('nobs',))[:] = longitude_list
            f.createVariable('Pressure', 'f4', ('nobs',))[:] = pressure_list
            f.createVariable('Time', 'f4', ('nobs',))[:] = time_list
            f.createVariable('Errinv_Input', 'f4', ('nobs',))[:] = errinv_input_list
            f.createVariable('Observation', 'f4', ('nobs',))[:] = observation_list
            f.createVariable('Obs_Minus_Forecast_unadjusted', 'f4', ('nobs',))[:] = omf_list

            # Additional variables set to fill values
            other_vars = ['Prep_QC_Mark', 'Setup_QC_Mark', 'Prep_Use_Flag', 'Analysis_Use_Flag',
                          'Nonlinear_QC_Rel_Wgt', 'Errinv_Adjust', 'Errinv_Final']
            for var_name in other_vars:
                var = f.createVariable(var_name, 'f4', ('nobs',), fill_value=-9999.0)
                var[:] = -9999.0
            f.date_time = int(analysis_time)

def process_wind_group(files, analysis_time):
    """
    Process a group of wind jdiag files and create corresponding gdiag files.

    Args:
        files (list): List of jdiag file paths
        analysis_time (str): Analysis time string (e.g., '2024050701')
    """
    station_id_list = []
    obs_type_list = []
    latitude_list = []
    longitude_list = []
    pressure_list = []
    time_list = []
    errinv_input_list = []
    u_observation_list = []
    v_observation_list = []
    u_ombg_list = []
    v_ombg_list = []
    u_oman_list = []
    v_oman_list = []

    for file_path in files:
        platform, var, obs_type = parse_jdiag_filename(file_path)
        if var != 'winds':
            continue
        data = read_jdiag_wind(file_path)
        (station_id, latitude, longitude, pressure, date_time,
         u_observation, v_observation, effective_error_0,
         u_ombg, v_ombg, u_oman, v_oman) = data
        nobs = len(station_id)
        pressure_hpa = pressure / 100.0
        analysis_dt = datetime.strptime(analysis_time, '%Y%m%d%H')
        time_offset = [(datetime.fromtimestamp(dt) - analysis_dt).total_seconds() / 3600.0
                       for dt in date_time]
        errinv_input = np.where(effective_error_0 > 0, 1.0 / effective_error_0, 0.0)
        station_id_list.extend(station_id)
        obs_type_list.extend([obs_type] * nobs)
        latitude_list.extend(latitude)
        longitude_list.extend(longitude)
        pressure_list.extend(pressure_hpa)
        time_list.extend(time_offset)
        errinv_input_list.extend(errinv_input)
        u_observation_list.extend(u_observation)
        v_observation_list.extend(v_observation)
        u_ombg_list.extend(u_ombg)
        v_ombg_list.extend(v_ombg)
        u_oman_list.extend(u_oman)
        v_oman_list.extend(v_oman)

    total_nobs = len(station_id_list)
    if total_nobs == 0:
        print("No wind observations")
        return

    maxstrlen = max(len(str(s)) for s in station_id_list)
    station_id_array = np.array([list(str(s).ljust(maxstrlen)) for s in station_id_list], dtype='S1')
    obs_class_array = np.array([list('conv'.ljust(7)) for _ in range(total_nobs)], dtype='S1')

    for stage, u_omf_list, v_omf_list in zip(['ges', 'anl'],
                                             [u_ombg_list, u_oman_list],
                                             [v_ombg_list, v_oman_list]):
        output_file = f"diag_conv_uv_{stage}.nc"
        with nc.Dataset(output_file, 'w', format='NETCDF4') as f:
            f.createDimension('nobs', total_nobs)
            f.createDimension('Station_ID_maxstrlen', maxstrlen)
            f.createDimension('Observation_Class_maxstrlen', 7)

            f.createVariable('Station_ID', 'S1', ('nobs', 'Station_ID_maxstrlen'))[:] = station_id_array
            f.createVariable('Observation_Class', 'S1', ('nobs', 'Observation_Class_maxstrlen'))[:] = obs_class_array
            f.createVariable('Observation_Type', 'i4', ('nobs',))[:] = obs_type_list
            f.createVariable('Latitude', 'f4', ('nobs',))[:] = latitude_list
            f.createVariable('Longitude', 'f4', ('nobs',))[:] = longitude_list
            f.createVariable('Pressure', 'f4', ('nobs',))[:] = pressure_list
            f.createVariable('Time', 'f4', ('nobs',))[:] = time_list
            f.createVariable('Errinv_Input', 'f4', ('nobs',))[:] = errinv_input_list
            f.createVariable('u_Observation', 'f4', ('nobs',))[:] = u_observation_list
            f.createVariable('v_Observation', 'f4', ('nobs',))[:] = v_observation_list
            f.createVariable('u_Obs_Minus_Forecast_unadjusted', 'f4', ('nobs',))[:] = u_omf_list
            f.createVariable('v_Obs_Minus_Forecast_unadjusted', 'f4', ('nobs',))[:] = v_omf_list

            # Additional variables set to fill values
            other_vars = ['Prep_QC_Mark', 'Setup_QC_Mark', 'Prep_Use_Flag', 'Analysis_Use_Flag',
                          'Nonlinear_QC_Rel_Wgt', 'Errinv_Adjust', 'Errinv_Final']
            for var_name in other_vars:
                var = f.createVariable(var_name, 'f4', ('nobs',), fill_value=-9999.0)
                var[:] = -9999.0
            f.date_time = int(analysis_time)

def main():
    """
    Main function to convert jdiag files to gdiag files.

    Command-line usage: python jdiag_to_gdiag.py <analysis_time> <jdiag_file1> <jdiag_file2> ...
    """
    if len(sys.argv) < 3:
        print("Usage: python jdiag_to_gdiag.py <analysis_time> <jdiag_file1> <jdiag_file2> ...")
        print("Example: python jdiag_to_gdiag.py 2024050701 jdiag_*.nc")
        sys.exit(1)

    analysis_time = sys.argv[1]
    jdiag_files = sys.argv[2:]

    # Group files by variable type
    groups = {'t': [], 'q': [], 'ps': [], 'uv': []}
    for file_path in jdiag_files:
        try:
            platform, var, obs_type = parse_jdiag_filename(file_path)
            if var in variable_map:
                gsi_var = variable_map[var]
                groups[gsi_var].append(file_path)
            else:
                print(f"Skipping file with unrecognized variable: {file_path}")
        except ValueError as e:
            print(f"Skipping invalid file: {file_path} ({e})")

    # Process each group
    for gsi_var, jedi_var in [('t', 'airTemperature'), ('q', 'specificHumidity'), ('ps', 'stationPressure')]:
        process_non_wind_group(groups[gsi_var], jedi_var, gsi_var, analysis_time)
    process_wind_group(groups['uv'], analysis_time)

    print(f"Generated gdiag files for analysis time {analysis_time}")

if __name__ == "__main__":
    main()
