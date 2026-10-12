"""Client flavors the nameplate harness knows about, shared by run.py and api_matrix.py.

ref        the wow-ui-source branch the API lists are generated from (read with git show, never checked out)
project    WOW_PROJECT_ID the mock reports
interface  the fourth return of GetBuildInfo
default    run by run.py when no --flavor is given

The interface numbers come from .context/common-pitfalls.md ("Current interface numbers", 2026-09-28).
Titan's project id is an assumption (it is a Wrath-era client); there is no Titan client to check it on.
"""
import os

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', '..'))
UI_SOURCE = os.environ.get('WOW_UI_SOURCE', 'C:/code/WOWUICode/wow-ui-source')

FLAVORS = {
    'retail': {'ref': 'origin/live', 'project': 1, 'interface': 120100, 'default': True},
    'ptr': {'ref': 'origin/ptr2', 'project': 1, 'interface': 120105, 'default': False},
    'forever': {'ref': 'forever', 'project': 18, 'interface': 16001, 'default': True},
    'mists': {'ref': 'classic', 'project': 19, 'interface': 50504, 'default': True},
    'titan': {'ref': 'classic_titan', 'project': 11, 'interface': 38002, 'default': True},
    'tbc': {'ref': 'classic_anniversary', 'project': 5, 'interface': 20506, 'default': True},
    'era': {'ref': 'classic_era', 'project': 2, 'interface': 11509, 'default': True},
}
ORDER = ['retail', 'ptr', 'forever', 'mists', 'titan', 'tbc', 'era']
DEFAULT_FLAVORS = [f for f in ORDER if FLAVORS[f]['default']]


def data_path(flavor):
    return os.path.join(HERE, 'data', flavor + '.lua')
