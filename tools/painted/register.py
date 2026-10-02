"""Turn a painted look's colors.json into the Lua it needs.

python register.py <colors.json> <theme_id> <kit_id> <display name>

Prints:
- the Register(...) block for Core/Handlers/WindowKits.lua (window kit colors, with the crest)
- the accent / frame colors for Themes/<theme_id>/Style.lua
"""

import json
import sys


def hexcode(value):
    v = value.lstrip('#')
    return v[:6], (int(v[6:8], 16) / 255 if len(v) == 8 else None)


def lua_hex(value, alpha=None):
    code, a = hexcode(value)
    a = alpha if alpha is not None else a
    return "Hex('%s'%s)" % (code, ', %.2f' % a if a is not None else '')


def rgb(value, alpha=None):
    code, a = hexcode(value)
    r, g, b = (int(code[i:i + 2], 16) / 255 for i in (0, 2, 4))
    a = alpha if alpha is not None else a
    parts = ['%.3f' % r, '%.3f' % g, '%.3f' % b] + (['%.2f' % a] if a is not None else [])
    return '{ ' + ', '.join(parts) + ' }'


def main():
    path, theme, kit, name = sys.argv[1:5]
    c = json.load(open(path, encoding='utf-8'))
    s = c['surfaces']
    print("""	Register('%(kit)s', {
		name = '%(name)s',
		layout = PAINTED_LAYOUT,
		backdropAspect = 2,
		backdropDim = 0.32,
		windowSurfaceAlpha = 0.1,
		materialAlpha = 0.12,
		colors = {
			surface = { [0] = %(s0)s, [1] = %(s1)s, [2] = %(s2)s, [3] = %(s3)s },
			bar = %(bar)s,
			text = %(t0)s,
			secondary = %(t1)s,
			muted = %(t2)s,
			trim = %(tr0)s,
			trimHi = %(tr1)s,
			path = %(p0)s,
			pathAhead = %(p1)s,
			tick = %(tick)s,
		},
		button = {
			primary = { top = %(pr0)s, bottom = %(pr1)s, edge = %(pr2)s, text = %(pr3)s },
			secondary = { top = %(se0)s, bottom = %(se1)s, edge = %(se2)s, text = %(se3)s },
		},
		assets = LookAssets('%(kit)s'%(crest)s),
	})""" % dict(
        kit=kit, name=name,
        crest=(', { width = %(width)d, height = %(height)d, overlap = %(overlap)d }' % c['crest']) if c.get('crest') else '',
        s0=lua_hex(s[0], 0.94), s1=lua_hex(s[1], 0.88), s2=lua_hex(s[2], 0.94), s3=lua_hex(s[3], 0.98),
        bar=lua_hex(s[1], 0.92),
        t0=lua_hex(c['text'][0]), t1=lua_hex(c['text'][1]), t2=lua_hex(c['text'][2]),
        tr0=lua_hex(c['trim'][0]), tr1=lua_hex(c['trim'][1]),
        p0=lua_hex(c['path'][0]), p1=lua_hex(c['path'][1]), tick=lua_hex(c['tick']),
        pr0=lua_hex(c['primary'][0]), pr1=lua_hex(c['primary'][1]), pr2=lua_hex(c['primary'][2]), pr3=lua_hex(c['primary'][3]),
        se0=lua_hex(c['secondary'][0]), se1=lua_hex(c['secondary'][1]), se2=lua_hex(c['secondary'][2]), se3=lua_hex(c['secondary'][3]),
    ))
    print()
    print('-- Themes/%s/Style.lua' % theme)
    print('	accent = %s,' % rgb(c['accent']))
    print('	frameBg = %s,' % rgb(c['frameBg']))
    print('	frameBorder = %s,' % rgb(c['trim'][0], 1))
    print('	bed = %s' % c.get('bed'))


if __name__ == '__main__':
    main()
