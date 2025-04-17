#!/usr/bin/env python
import netCDF4 as nc
import numpy as np
from datetime import datetime, timedelta
import sys
import os

# Platform mapping inferred from jdiag file list
platform_map = {
    120: "adpupa", 132: "adpupa", 220: "adpupa", 232: "adpupa",
    130: "aircft", 131: "aircft", 134: "aircft", 135: "aircft",
    230: "aircft", 231: "aircft", 234: "aircft", 235: "aircft",
    133: "aircar", 233: "aircar",
    180: "sfcshp", 182: "sfcshp", 183: "sfcshp",
    280: "sfcshp", 282: "sfcshp", 284: "sfcshp",
    181: "adpsfc", 183: "adpsfc", 187: "adpsfc",
    281: "adpsfc", 284: "adpsfc", 287: "adpsfc",
    188: "msonet", 288: "msonet",
    224: "vadwnd",
    227: "proflr",
    126: "rassda"
}

# Variable mapping from GSI to JEDI
variable_map = {
    "t": "airTemperature",
    "q": "specificHumidity",
    "ps": "stationPressure",
    "uv": "winds"  # Special case for windEastward and windNorthward
}

def gsi_time_to_epoch(gsi_time, analysis_time_str):
    """Convert GSI time offset to epoch time in seconds since 1970-01-01."""
    analysis_time = datetime.strptime(analysis_time_str, '%Y%m%d%H')
    obs_time = analysis_time + timedelta(hours=float(gsi_time))
    epoch = datetime(1970, 1, 1)
    return int((obs_time - epoch).total_seconds())

def char_array_to_strings(char_array):
    """
    Convert a 2D character array to a list of strings, handling masked arrays.

    Args:
        char_array: 2D numpy array or masked array of characters (nobs, maxstrlen)

    Returns:
        List of strings, with masked rows replaced by 'MISSING'
    """
    if isinstance(char_array, np.ma.MaskedArray):
        # Check if entire rows are masked
        #row_mask = char_array.mask.all(axis=1)
        row_mask = np.zeros(char_array.shape[0], dtype=bool)
    else:
        # If not a masked array, assume no rows are masked
        row_mask = np.zeros(char_array.shape[0], dtype=bool)

    strings = []
    for i, row in enumerate(char_array):
        if row_mask[i]:
            strings.append('MISSING')
        else:
            # Convert character array to string and remove trailing spaces
            s = ''.join(row.astype(str)).strip()
            strings.append(s)
    return strings

def map_prep_use_flag_to_qc(flag):
    """Map GSI Prep_Use_Flag to JEDI EffectiveQC values."""
    if flag == 1.0:
        return 0  # Assimilated
    elif flag == -1.0:
        return 1  # Monitored
    else:
        return 12  # Rejected

def process_non_wind_file(anl_file_path, ges_file_path, jedi_var, analysis_time_str):
    """
    Process a non-wind GSI diagnostic file and convert it to JEDI jdiag format.

    Args:
        file_path (str): Path to the GSI diagnostic netCDF file
        jedi_var (str): JEDI variable name corresponding to the observation
        analysis_time_str (str): Analysis time string for time conversion
    """
    with nc.Dataset(ges_file_path, 'r') as ges_f, nc.Dataset(anl_file_path, 'r') as anl_f:
        # Read variables from the GSI file
        station_id_char = ges_f.variables['Station_ID'][:]  # 2D char array (nobs, maxstrlen)
        obs_type = ges_f.variables['Observation_Type'][:]
        latitude = ges_f.variables['Latitude'][:]
        longitude = ges_f.variables['Longitude'][:]
        pressure = ges_f.variables['Pressure'][:]
        time = ges_f.variables['Time'][:]
        effective_error_0 = 1.0 / ges_f.variables['Errinv_Input'][:]  # Invert
        observation = ges_f.variables['Observation'][:]
        ombg = ges_f.variables['Obs_Minus_Forecast_unadjusted'][:]
        oman = anl_f.variables['Obs_Minus_Forecast_unadjusted'][:]
        analysis_use_flag = anl_f.variables['Analysis_Use_Flag'][:]
        prep_use_flag = anl_f.variables['Prep_Use_Flag'][:]

        # Process each unique observation type
        unique_types = np.unique(obs_type)
        for typ in unique_types:
            if typ not in platform_map:
                print(f"Warning: Observation_Type {typ} not in platform_map, skipping.")
                continue
            platform = platform_map[typ]
            mask = obs_type == typ
            nobs = np.sum(mask)
            if nobs == 0:
                print(f"No observations for type {typ} in file {file_path}, skipping.")
                continue

            # Convert selected station IDs to strings
            selected_station_ids = char_array_to_strings(station_id_char[mask])

            # Use combination of Prep_Use and Analysis_Use flags to determine asm, rej, mon
            iuse = prep_use_flag[mask]
            ause = analysis_use_flag[mask]
            iuse_valid = iuse.compressed()
            ause_valid = ause.compressed()

            # Initialize flag array with zeros (default for rejected)
            flag = np.zeros_like(ause_valid, dtype=float)

            # Set flag for assimilated observations
            flag[ause_valid == 1] = 1.0

            # Set flag for monitored observations
            flag[(ause_valid == -1) & (iuse_valid > 0)] = -1.0

            # Map to JEDI EffectiveQC2 equivalent
            qc_flags = np.array([map_prep_use_flag_to_qc(f) for f in flag], dtype=np.int32)

            # Create output jdiag file
            jdiag_file = f"jdiag_{platform}_{jedi_var}_{typ}.nc"
            with nc.Dataset(jdiag_file, 'w', format='NETCDF4') as g:
                g.setncattr('_ioda_layout', 'ObsGroup')
                g.setncattr('_ioda_layout_version', 0)
                g.createDimension('Location', nobs)

                # MetaData group
                meta = g.createGroup('MetaData')
                # Create the variable for station IDs
                station_var = meta.createVariable('stationIdentification', 'str', ('Location',))
                # Assign each string individually to avoid VLEN assignment error
                for i, s in enumerate(selected_station_ids):
                    station_var[i] = s
                meta.createVariable('latitude', 'f4', ('Location',))[:] = latitude[mask]
                meta.createVariable('longitude', 'f4', ('Location',))[:] = longitude[mask]
                meta.createVariable('pressure', 'f4', ('Location',))[:] = pressure[mask] * 100  # hPa to Pa
                date_times = [gsi_time_to_epoch(t, analysis_time_str) for t in time[mask]]
                meta.createVariable('dateTime', 'i8', ('Location',))[:] = date_times

                # ObsValue group
                obs_val = g.createGroup('ObsValue')
                obs_val.createVariable(jedi_var, 'f4', ('Location',))[:] = observation[mask]

                # EffectiveError0 group
                eff_err_0 = g.createGroup('EffectiveError0')
                eff_err_0.createVariable(jedi_var, 'f4', ('Location',))[:] = effective_error_0[mask]

                # hofx0 (background)
                hofx0 = g.createGroup('hofx0')
                hofx0.createVariable(jedi_var, 'f4', ('Location',))[:] = observation[mask] - ombg[mask]

                # hofx1 (analysis)
                hofx1 = g.createGroup('hofx1')
                hofx1.createVariable(jedi_var, 'f4', ('Location',))[:] = observation[mask] - oman[mask]

                # ombg group
                ombg_group = g.createGroup('ombg')
                ombg_group.createVariable(jedi_var, 'f4', ('Location',))[:] = ombg[mask]

                # oman group
                oman_group = g.createGroup('oman')
                oman_group.createVariable(jedi_var, 'f4', ('Location',))[:] = oman[mask]

                # EffectiveQC2 group
                eff_qc2 = g.createGroup('EffectiveQC2')
                eff_qc2.createVariable(jedi_var, 'i4', ('Location',))[:] = qc_flags

def process_wind_file(anl_file_path, ges_file_path, analysis_time_str):
    """
    Process a wind GSI diagnostic file and convert it to JEDI jdiag format.

    Args:
        file_path (str): Path to the GSI diagnostic netCDF file
        analysis_time_str (str): Analysis time string for time conversion

    Notes:
        Assumes platform_map and gsi_time_to_epoch are defined elsewhere.
    """
    with nc.Dataset(ges_file_path, 'r') as ges_f, nc.Dataset(anl_file_path, 'r') as anl_f:
        # Read variables from the GSI file
        station_id_char = ges_f.variables['Station_ID'][:]  # 2D char array (nobs, maxstrlen)
        obs_type = ges_f.variables['Observation_Type'][:]
        latitude = ges_f.variables['Latitude'][:]
        longitude = ges_f.variables['Longitude'][:]
        pressure = ges_f.variables['Pressure'][:]
        time = ges_f.variables['Time'][:]
        effective_error_0 = 1.0 / ges_f.variables['Errinv_Input'][:]  # Invert
        u_observation = ges_f.variables['u_Observation'][:]
        v_observation = ges_f.variables['v_Observation'][:]
        u_ombg = ges_f.variables['u_Obs_Minus_Forecast_unadjusted'][:]
        v_ombg = ges_f.variables['v_Obs_Minus_Forecast_unadjusted'][:]
        u_oman = anl_f.variables['u_Obs_Minus_Forecast_unadjusted'][:]
        v_oman = anl_f.variables['v_Obs_Minus_Forecast_unadjusted'][:]
        analysis_use_flag = anl_f.variables['Analysis_Use_Flag'][:]
        prep_use_flag = anl_f.variables['Prep_Use_Flag'][:]

        # Process each unique observation type
        unique_types = np.unique(obs_type)
        for typ in unique_types:
            if typ not in platform_map:
                print(f"Warning: Observation_Type {typ} not in platform_map, skipping.")
                continue
            platform = platform_map[typ]
            mask = obs_type == typ  # Boolean mask for this obs_type
            nobs = np.sum(mask)
            if nobs == 0:
                print(f"No observations for type {typ} in file {file_path}, skipping.")
                continue

            # Select station IDs for u components, limited to nobs
            selected_station_ids = char_array_to_strings(station_id_char[mask])

            # Use combination of Prep_Use and Analysis_Use flags to determine asm, rej, mon
            iuse = prep_use_flag[mask]
            ause = analysis_use_flag[mask]
            iuse_valid = iuse.compressed()
            ause_valid = ause.compressed()

            # Initialize flag array with zeros (default for rejected)
            flag = np.zeros_like(ause_valid, dtype=float)

            # Set flag for assimilated observations
            flag[ause_valid == 1] = 1.0

            # Set flag for monitored observations
            flag[(ause_valid == -1) & (iuse_valid > 0)] = -1.0

            # Map to JEDI EffectiveQC2 equivalent
            qc_flags = np.array([map_prep_use_flag_to_qc(f) for f in flag], dtype=np.int32)

            # Create output jdiag file
            jdiag_file = f"jdiag_{platform}_winds_{typ}.nc"
            with nc.Dataset(jdiag_file, 'w', format='NETCDF4') as g:
                g.setncattr('_ioda_layout', 'ObsGroup')
                g.setncattr('_ioda_layout_version', 0)
                g.createDimension('Location', nobs)

                # MetaData group
                meta = g.createGroup('MetaData')
                # Create the variable for station IDs
                station_var = meta.createVariable('stationIdentification', 'str', ('Location',))
                # Assign each string individually to avoid VLEN assignment error
                for i, s in enumerate(selected_station_ids):
                    station_var[i] = s
                meta.createVariable('latitude', 'f4', ('Location',))[:] = latitude[mask]
                meta.createVariable('longitude', 'f4', ('Location',))[:] = longitude[mask]
                meta.createVariable('pressure', 'f4', ('Location',))[:] = pressure[mask] * 100  # hPa to Pa
                date_times = [gsi_time_to_epoch(t, analysis_time_str) for t in time[mask]]
                meta.createVariable('dateTime', 'i8', ('Location',))[:] = date_times

                # ObsValue group
                obs_val = g.createGroup('ObsValue')
                obs_val.createVariable('windEastward', 'f4', ('Location',))[:] = u_observation[mask]
                obs_val.createVariable('windNorthward', 'f4', ('Location',))[:] = v_observation[mask]

                # EffectiveError0 group
                eff_err_0 = g.createGroup('EffectiveError0')
                eff_err_0.createVariable('windEastward', 'f4', ('Location',))[:] = effective_error_0[mask]
                eff_err_0.createVariable('windNorthward', 'f4', ('Location',))[:] = effective_error_0[mask]

                # hofx0 (background)
                hofx0 = g.createGroup('hofx0')
                hofx0.createVariable('windEastward', 'f4', ('Location',))[:] = u_observation[mask] - u_ombg[mask]
                hofx0.createVariable('windNorthward', 'f4', ('Location',))[:] = v_observation[mask] - v_ombg[mask]

                # hofx1 (analysis)
                hofx1 = g.createGroup('hofx1')
                hofx1.createVariable('windEastward', 'f4', ('Location',))[:] = u_observation[mask] - u_oman[mask]
                hofx1.createVariable('windNorthward', 'f4', ('Location',))[:] = v_observation[mask] - v_oman[mask]

                # ombg group
                ombg_group = g.createGroup('ombg')
                ombg_group.createVariable('windEastward', 'f4', ('Location',))[:] = u_ombg[mask]
                ombg_group.createVariable('windNorthward', 'f4', ('Location',))[:] = v_ombg[mask]

                # oman group
                oman_group = g.createGroup('oman')
                oman_group.createVariable('windEastward', 'f4', ('Location',))[:] = u_oman[mask]
                oman_group.createVariable('windNorthward', 'f4', ('Location',))[:] = v_oman[mask]
                # EffectiveQC2 group
                eff_qc2 = g.createGroup('EffectiveQC2')
                eff_qc2.createVariable('windEastward', 'i4', ('Location',))[:] = qc_flags
                eff_qc2.createVariable('windNorthward', 'i4', ('Location',))[:] = qc_flags

def convert_gsi_to_jdiag(file_list, analysis_time_str):
    """Convert a list of GSI diagnostic files to JEDI jdiag format."""
    red = "\x1b[31m"
    green = "\x1b[32m"
    normal = "\x1b[0m"
    for file_path in file_list:
        if '_anl' not in file_path:
            #print(f"{red}Skipping non-analysis file: {file_path}{normal}")
            continue
        filename = os.path.basename(file_path)
        parts = filename.split('_')
        if len(parts) < 4 or parts[1] != 'conv':
            #print(f"{red}Skipping invalid file: {filename}{normal}")
            continue
        var = parts[2]  # e.g., 't', 'uv', 'q', 'ps'
        stage = parts[3].split('.')[0]  # Should be 'anl'
        if stage != 'anl':
            #print(f"{red}Skipping non-anl file: {filename}{normal}")
            continue
        if var not in variable_map:
            #print(f"{red}Skipping unhandled variable: {var} in {filename}{normal}")
            continue
        jedi_var = variable_map[var]
        anl_file_path = file_path
        ges_file_path = file_path.replace("_anl", "_ges")
        if var == 'uv':
            process_wind_file(anl_file_path, ges_file_path, analysis_time_str)
        else:
            process_non_wind_file(anl_file_path, ges_file_path, jedi_var, analysis_time_str)
        anl_filename = filename
        ges_filename = filename.replace("_anl", "_ges")
        print(f"{green}Processed {ges_filename} & {anl_filename} into jdiag files.{normal}")

if __name__ == "__main__":
    """Entry point to handle command-line arguments."""
    if len(sys.argv) < 3:
        print("Usage: python nc_gsi_diag.py <analysis_time> <file1> <file2> ...")
        print("Example: python nc_gsi_diag.py 2024050606 /path/to/diag_conv_t_anl.2024050606.nc4 ...")
        sys.exit(1)
    analysis_time = sys.argv[1]
    files = sys.argv[2:]
    convert_gsi_to_jdiag(files, analysis_time)
