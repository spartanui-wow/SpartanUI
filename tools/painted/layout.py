"""Read the painted-look layout straight from Themes/Painted.lua, so every tool uses the game's numbers.

Coordinates:
- art units: SpartanUI frame space, origin at the bottom centre of the screen, x right, y up
- file pixels: a picture's own pixels, origin top left, y down
"""

import os
import json
import subprocess
from functools import lru_cache

try:
    import lupa
except ImportError:
    lupa = None

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
PAINTED = os.path.join(ROOT, 'Themes', 'Painted.lua')


@lru_cache(maxsize=None)
def external_layout(native=45):
    """Use an explicitly supplied Lua executable on offline machines without lupa."""
    executable = os.environ.get('PAINTED_LUA')
    if not executable:
        raise RuntimeError('Install lupa or set PAINTED_LUA to a Lua executable')
    script = os.path.join(os.path.dirname(__file__), 'dump_layout.lua')
    return json.loads(subprocess.check_output([executable, script, ROOT, str(native)], text=True))


@lru_cache(maxsize=None)
def theme_spec(theme):
    if not theme:
        return {}
    if lupa is None:
        return external_layout()['specs'].get(theme, {})
    lua = lupa.LuaRuntime(unpack_returned_tuples=True)
    path = os.path.join(ROOT, 'Themes', theme, 'Style.lua')
    if not os.path.exists(path):
        return {}
    lua.execute('SUI = { ThemePainted = { Register = function(spec) captured = spec end } }')
    source = open(path, encoding='utf-8').read()
    lua.execute(source)
    return to_py(lua.globals().captured)


def to_py(value):
    if hasattr(value, 'items'):
        items = dict(value.items())
        if items and all(isinstance(k, int) for k in items):
            return [to_py(items[k]) for k in sorted(items)]
        return {k: to_py(v) for k, v in items.items()}
    return value


@lru_cache(maxsize=1)
def painted_module():
    lua = lupa.LuaRuntime(unpack_returned_tuples=True)
    lua.execute('SUI = nil')
    return lua.execute(open(PAINTED, encoding='utf-8').read())


def fit_bars(theme, native=45):
    """The bars fitted into a look's painted trays, as the game places them (Painted.FitBars)."""
    if lupa is None:
        return external_layout(native)['bars'].get(theme or '', external_layout(native)['bars']['default'])
    return to_py(painted_module().FitBars(theme, native))


def theme_from_images(images):
    """Themes/<theme>/Images -> theme id, or None for a folder outside the addon."""
    parts = os.path.normpath(images).split(os.sep)
    if len(parts) >= 3 and parts[-1].lower() == 'images' and parts[-3].lower() == 'themes':
        return parts[-2]
    return None


@lru_cache(maxsize=1)
def layout():
    if lupa is None:
        return external_layout()['layout']
    painted = painted_module()
    data = to_py(painted.LAYOUT)
    width, height = painted.BarSize(False)
    bw, bh = painted.BarSize(True)
    data['barSize'] = {'row': (width, height), 'block': (bw, bh)}
    data['frameHeight'] = painted.FrameHeight()
    return data


class HalfMap:
    """Art units <-> pixels of one bottom-art half (left: x in [-768, 0], right: [0, 768])."""

    def __init__(self, side):
        lay = layout()
        art = lay['art']
        self.side = side
        self.w, self.h = art['file']['width'], art['file']['height']
        self.sx = self.w / art['halfWidth']
        self.sy = self.h / art['height']
        self.x0 = -art['halfWidth'] if side == 'left' else 0

    def px(self, x, y):
        return (x - self.x0) * self.sx, self.h - y * self.sy

    def rect(self, x1, y1, x2, y2):
        ax, ay = self.px(x1, y2)
        bx, by = self.px(x2, y1)
        return ax, ay, bx, by


class PlateMap:
    """Frame units (frame top left origin, x right, y down) <-> unit frame plate pixels."""

    def __init__(self):
        plate = layout()['plate']
        self.w, self.h = plate['file']['width'], plate['file']['height']
        self.s = self.w / plate['width']
        self.left, self.top = plate['left'], plate['top']

    def px(self, x, y):
        return (x + self.left) * self.s, (y + self.top) * self.s
