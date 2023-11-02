import argparse
import datetime as dt
import os
from wxflow import parse_j2yaml, cast_strdict_as_dtypedict, save_as_yaml
from wxflow import add_to_datetime, to_timedelta, to_datetime

my_dir = os.path.dirname(__file__)
rdas_dir = os.path.join(my_dir, '../')

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument('-i', '--input', type=str, help='Input YAML Template', required=True)
    parser.add_argument('-o', '--output', type=str, help='Output YAML File', required=True)
    args = parser.parse_args()

    os.environ['BERROR_YAML'] = os.path.join(rdas_dir, 'parm', 'atm', 'berror', 'staticb_identity.yaml')
    os.environ['OBS_LIST'] = os.path.join(rdas_dir, 'parm', 'atm', 'obs', 'lists', 'rdas_prototype.yaml')
    os.environ['OBS_YAML_DIR'] = os.path.join(rdas_dir, 'parm', 'atm', 'obs', 'config')

    # let us define a configuration dictionary, note this will be incomplete and an example
    config = {
        'ATM_WINDOW_BEGIN': to_datetime('2023-11-01T23:30:00Z'),
        'ATM_WINDOW_LENGTH': 'PT1H',
        'layout_x': 1,
        'layout_y': 1,
        'npx_ges': 201,
        'npy_ges': 151,
        'npz_ges': 65,
        'current_cycle': to_datetime('2023-11-02T00:00:00Z'),
        'npx_anl': 201,
        'npy_anl': 151,
        'npz_anl': 65,
        'DATA': os.path.join(os.path.dirname(args.output)),
        'GPREFIX': 'rrfs.t23z.',
        'APREFIX': 'rrfs.t00z.',
    }

    final_config = parse_j2yaml(args.input, config)
    save_as_yaml(final_config, args.output)
