"""Painted nameplate plates for the painted looks, cut from each look's unit frame plate.

python tools/painted/nameplates.py            build the files, previews and the Lua numbers
python tools/painted/nameplates.py --check    only compare Themes/Painted.lua with the files

Writes, for each look in LOOKS:
  Themes/<look>/Images/Nameplate.png   one picture, cut in nine by the game (Painted.NAMEPLATES)
  tools/painted/out/nameplate-<look>.png   the plate at Small, Medium, Large and on a target, at the
                                            default UI scale and at 2x, on a dark background
  tools/painted/out/nameplates.png          all looks on one sheet
  tools/painted/out/nameplates.json         the numbers, also printed as the Lua table for Painted.lua
  tools/painted/out/nameplates.lua          the same table as Lua, for the nameplate tests

How a plate is made (patterns.md "Screen-Wide Art Is Left, Center And Right Pictures", pitfall "Art
Cut To A Fixed File Size Gets Stretched"):
  1. The look's UnitFrame-NoPortrait.png plate is cut apart at its own resolution: the frame above
     and below the bar window, a few rows of the window next to each painted end, and both ends.
     Each end keeps its own rows (so a leaf or bracket stays whole); the bands between them are
     the same rows for all three columns.
  2. The middle is one column: the average of a run of the plate's middle columns, so the game can
     stretch it to any width without smearing anything.
  3. Ornaments the plate keeps elsewhere (Observatory's sea-glass beads) are pasted onto the ends.
  4. The whole picture is scaled evenly (Lanczos) to twice its drawn size, so the game draws it at
     half size; every slice edge and the bar window land on whole drawn pixels.
  5. It is put at the top left of a power-of-two file; the padding repeats the last column and row,
     so nothing bleeds in at the edge, and the game draws only the painted part (slice.size).

The game draws the picture with the art part's slice (Engine/Parts/Highlight.lua): the four corners
keep their shape, the top and bottom edges and the middle stretch sideways, the side edges stretch
up and down through a short plain band. The bar window lines up with the health bar through the
part's outset. Python 3 with Pillow and numpy; lupa reads the layout and the look colors.
"""

import argparse
import json
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', '..'))
OUT = os.path.join(HERE, 'out')
sys.path.insert(0, HERE)

LANCZOS = Image.Resampling.LANCZOS

# Drawn pixels per texel: pictures are made at twice their drawn size
SCALE = 0.5
# The smallest bar the plate is made for (Small): every corner fits around it
MIN_BAR = 8
# Window texels held by each corner at the smallest bar; the rest of the window is the stretch band
CORNER_WINDOW = 6
# Texels of the stretchable middle column (any width works, it is one repeated column)
MIDDLE = 8
# Columns of each end blended into the middle column, in source pixels
BLEND = 4

# Plate sizes of the painted style (whole pixels, never SetScale) and the target growth
SIZES = {'small': (112, 8), 'medium': (132, 10), 'large': (156, 12)}
TARGET_GROW = (14, 2)

# Each look, in its plate picture's own pixels (x right, y down):
#   k          texels per source pixel (the drawn plate is k / 2 of the painting's size)
#   x          the painted plate's first and last + 1 column
#   window     the bar window's left and right edge (the dark inside of the frame)
#   caps       where the left end stops and the right end starts
#   middle     columns averaged into the middle column
#   top        rows of the frame above the window (top[1] is the window's top edge)
#   bottom     rows of the frame below the window (bottom[0] is the window's bottom edge)
#   rows       window rows kept for the middle; leftRows / rightRows for each end. Each list adds
#              up to the same count, about (MIN_BAR * 2) / k rows, so the window is MIN_BAR at
#              Small. The corners hold the first and last CORNER_WINDOW texels of them; what sits
#              between is the stretch band, so it must be plain (no leaf, bead or bracket)
#   pad        clear source pixels added on each side (left, top, right, bottom), room for extras
#   extras     pieces pasted on after cutting: a source box and the source spot its centre goes to
#              (spots left of caps[0] land on the left end, right of caps[1] on the right end,
#              rows of the top band or above it); mirror flips the piece
LOOKS = {
    'Atlas': {
        'k': 0.6,
        'x': (93, 511),
        'window': (134, 478),
        'caps': (150, 452),
        'leftCols': [(93, 113), (124, 150)],
        'rightCols': [(452, 482), (493, 511)],
        'middle': (200, 420),
        'top': (20, 38),
        'bottom': (102, 128),
        'rows': [(38, 52), (89, 102)],
        'leftRows': [(38, 52), (89, 102)],
        'rightRows': [(38, 52), (89, 102)],
    },
    'Boughs': {
        'k': 0.8,
        'x': (84, 512),
        'window': (114, 492),
        'caps': (126, 484),
        'middle': (200, 420),
        'top': (20, 28),
        'bottom': (108, 128),
        'rows': [(28, 38), (98, 108)],
        'leftRows': [(42, 52), (80, 90)],
        'rightRows': [(40, 50), (98, 108)],
    },
    'Meridian': {
        'k': 0.8,
        'x': (98, 504),
        'window': (116, 490),
        'caps': (134, 472),
        'middle': (200, 420),
        'top': (24, 32),
        'bottom': (100, 127),
        'bottomRows': [(100, 114), (121, 127)],
        'rows': [(32, 42), (90, 100)],
        'pad': (2, 8, 6, 0),
        'extras': [
            {'box': (109, 9, 131, 31), 'center': (110, 28), 'radius': 10},
            {'box': (477, 9, 499, 31), 'center': (494, 28), 'radius': 10},
        ],
    },
}


def load(look):
    path = os.path.join(ROOT, 'Themes', look, 'Images', 'UnitFrame-NoPortrait.png')
    return np.asarray(Image.open(path).convert('RGBA')).astype(np.float32)


def premultiply(a):
    out = a.copy()
    out[..., :3] *= out[..., 3:4] / 255
    return out


def unpremultiply(a):
    out = a.copy()
    alpha = out[..., 3:4]
    safe = np.where(alpha > 0, alpha, 1)
    out[..., :3] = np.where(alpha > 0, out[..., :3] * 255 / safe, 0)
    return out


def stack(src, cols, spec, rows):
    """One column group, top band + window rows + bottom band, at source resolution. cols is a list
    of column ranges joined side by side (an end can drop a plain stretch of its post)."""
    bands = [spec['top']] + list(rows) + list(spec.get('bottomRows', [spec['bottom']]))
    return np.concatenate([np.concatenate([src[a:b, c0:c1] for c0, c1 in cols], axis=1) for a, b in bands], axis=0)


def width_of(cols):
    return sum(b - a for a, b in cols)


def cut(look):
    """The plate picture at source resolution, plus where its pieces sit."""
    spec = LOOKS[look]
    src = premultiply(load(look))
    x0, x1 = spec['x']
    c0, c1 = spec['caps']
    left_cols = spec.get('leftCols', [(x0, c0)])
    right_cols = spec.get('rightCols', [(c1, x1)])
    rows, left_rows, right_rows = spec['rows'], spec.get('leftRows', spec['rows']), spec.get('rightRows', spec['rows'])
    counts = {sum(b - a for a, b in r) for r in (rows, left_rows, right_rows)}
    assert len(counts) == 1, look + ': every column group keeps the same number of window rows'
    window_rows = counts.pop()
    assert abs(window_rows * spec['k'] - MIN_BAR / SCALE) <= 1, look + ': the kept window rows must make the Small bar'

    left = stack(src, left_cols, spec, left_rows)
    right = stack(src, right_cols, spec, right_rows)
    middle_rows = stack(src, [spec['middle']], spec, rows)
    profile = middle_rows.mean(axis=1, keepdims=True)
    width = int(round(MIDDLE / spec['k']))
    middle = np.repeat(profile, width, axis=1)

    # Ease each end into the middle column, so the join has no step
    for i in range(BLEND):
        t = (i + 1) / (BLEND + 1)
        left[:, left.shape[1] - BLEND + i] = left[:, left.shape[1] - BLEND + i] * (1 - t) + profile[:, 0] * t
        right[:, BLEND - 1 - i] = right[:, BLEND - 1 - i] * (1 - t) + profile[:, 0] * t

    body = np.concatenate([left, middle, right], axis=1)
    pl, pt, pr, pb = spec.get('pad', (0, 0, 0, 0))
    plate = np.zeros((body.shape[0] + pt + pb, body.shape[1] + pl + pr, 4), np.float32)
    plate[pt:pt + body.shape[0], pl:pl + body.shape[1]] = body

    def column(sx, cols):
        """Where source column sx lands inside a list of kept column ranges."""
        x = 0
        for a, b in cols:
            if sx < b:
                return x + max(0, sx - a)
            x += b - a
        return x

    def spot(sx, sy):
        if sx < c0:
            x = pl + column(sx, left_cols)
        else:
            x = plate.shape[1] - pr - width_of(right_cols) + column(sx, right_cols)
        return x, pt + (sy - spec['top'][0])

    for extra in spec.get('extras', []):
        bx0, by0, bx1, by1 = extra['box']
        piece = src[by0:by1, bx0:bx1].copy()
        if extra.get('radius'):
            # Keep only the round piece (a bead in its ring), with a soft one pixel edge
            yy, xx = np.mgrid[0:piece.shape[0], 0:piece.shape[1]]
            d = np.hypot(xx + 0.5 - piece.shape[1] / 2, yy + 0.5 - piece.shape[0] / 2)
            piece *= np.clip(extra['radius'] + 0.5 - d, 0, 1)[..., None]
        if extra.get('mirror'):
            piece = piece[:, ::-1]
        cx, cy = spot(*extra['center'])
        px, py = int(round(cx - piece.shape[1] / 2)), int(round(cy - piece.shape[0] / 2))
        assert px >= 0 and py >= 0 and px + piece.shape[1] <= plate.shape[1] and py + piece.shape[0] <= plate.shape[0], look + ': an extra needs more pad'
        region = plate[py:py + piece.shape[0], px:px + piece.shape[1]]
        alpha = piece[..., 3:4] / 255
        region[...] = piece + region * (1 - alpha)
    bottom = sum(b - a for a, b in spec.get('bottomRows', [spec['bottom']]))
    geometry = {
        'left': pl + width_of(left_cols),  # left end width
        'right': pr + width_of(right_cols),  # right end width
        'top': pt + spec['top'][1] - spec['top'][0],
        'bottom': pb + bottom,
        'windowLeft': pl + column(spec['window'][0], left_cols),
        'windowRight': pr + width_of(right_cols) - column(spec['window'][1], right_cols),
        'windowRows': window_rows,
    }
    return plate, geometry


def even(v):
    return int(round(v / 2.0)) * 2


def build(look):
    """Scale the cut plate to texels; returns the picture and the numbers the game needs."""
    spec = LOOKS[look]
    k = spec['k']
    plate, g = cut(look)
    texel = {
        'left': even(g['left'] * k),
        'right': even(g['right'] * k),
        'top': even(g['top'] * k),
        'bottom': even(g['bottom'] * k),
    }
    width = texel['left'] + MIDDLE + texel['right']
    height = texel['top'] + MIN_BAR * 2 + texel['bottom']
    # Cutting works on premultiplied colors; Pillow resamples RGBA premultiplied by itself, so clear
    # pixels never darken the painted edge
    image = Image.fromarray(np.clip(unpremultiply(plate), 0, 255).round().astype(np.uint8), 'RGBA')
    picture = image.resize((width, height), LANCZOS)

    kx = width / plate.shape[1]
    outset = {
        'left': even(g['windowLeft'] * kx) // 2,
        'right': even(g['windowRight'] * kx) // 2,
        'top': texel['top'] // 2,
        'bottom': texel['bottom'] // 2,
    }
    corner = CORNER_WINDOW
    slice_ = {
        'file': [pot(width), pot(height)],
        'size': [width, height],
        'left': texel['left'],
        'right': texel['right'],
        'top': texel['top'] + corner,
        'bottom': texel['bottom'] + corner,
        'scale': SCALE,
    }
    assert slice_['top'] + slice_['bottom'] < height, look + ': the corners leave a stretch band'
    assert texel['left'] >= outset['left'] * 2 and texel['right'] >= outset['right'] * 2, look + ': the ends hold the window edge'
    ky = height / plate.shape[0]
    assert abs(kx / ky - 1) < 0.04, look + ': the picture is scaled evenly'

    # How far the frame's middle band shows above and below the window (drawn pixels), so the
    # name and the cast bar sit just clear of the paint rather than of the clear rows around it
    pixels = np.asarray(picture)
    alpha = pixels[:, texel['left'] + MIDDLE // 2, 3]
    shown = np.nonzero(alpha > 24)[0]
    # Over the first few pixels of the bar, where the name starts, an end's ornament may rise higher
    start = outset['left'] * 2
    name_cols = pixels[: texel['top'], start:start + 8, 3]
    rising = np.nonzero((name_cols > 24).any(axis=1))[0]
    band = {
        'top': int(np.ceil((texel['top'] - shown.min()) / 2)),
        'bottom': int(np.ceil((shown.max() + 1 - texel['top'] - MIN_BAR * 2) / 2)),
        'name': int(np.ceil((texel['top'] - rising.min()) / 2)) if len(rising) else 0,
    }
    return picture, {'slice': slice_, 'outset': outset, 'band': band}


def pot(n):
    size = 8
    while size < n:
        size *= 2
    return size


def padded(img, width, height):
    """img at the top left of a width x height canvas; the padding repeats the last column and row."""
    canvas = Image.new('RGBA', (width, height))
    canvas.paste(img, (0, 0))
    edge = img.crop((img.width - 1, 0, img.width, img.height))
    for x in range(img.width, width):
        canvas.paste(edge, (x, 0))
    row = canvas.crop((0, img.height - 1, width, img.height))
    for y in range(img.height, height):
        canvas.paste(row, (0, y))
    return canvas


# ------------------------------------------------------------------------------------------------
# Drawing the plate the way the game does
# ------------------------------------------------------------------------------------------------


def slice_geometry(sl, w, h):
    """Same as Highlight.SliceGeometry: drawn corner sizes and the texels each corner shows."""
    scale = sl['scale']

    def pair(a, b, room):
        da, db = int(np.floor(a * scale + 0.5)), int(np.floor(b * scale + 0.5))
        if da + db > room and da + db > 0:
            share = room / (da + db)
            na = int(np.floor(da * share))
            nb = max(0, int(np.floor(room)) - na)
            return na, nb, na / scale, nb / scale
        return da, db, a, b

    l, r, tl, tr = pair(sl['left'], sl['right'], w)
    t, b, tt, tb = pair(sl['top'], sl['bottom'], h)
    return (l, r, t, b), (tl, tr, tt, tb)


def draw_sliced(picture, sl, w, h, zoom):
    """The nine pieces for an area of w x h drawn pixels, at zoom screen pixels per drawn pixel."""
    (L, R, T, B), (tl, tr, tt, tb) = slice_geometry(sl, w, h)
    sw, sh = sl['size']
    us = [0, tl, sw - tr, sw]
    vs = [0, tt, sh - tb, sh]
    xs = [0, L, w - R, w]
    ys = [0, T, h - B, h]
    out = Image.new('RGBA', (int(round(w * zoom)), int(round(h * zoom))))
    for row in range(3):
        for col in range(3):
            dw, dh = xs[col + 1] - xs[col], ys[row + 1] - ys[row]
            if dw <= 0 or dh <= 0 or us[col + 1] <= us[col] or vs[row + 1] <= vs[row]:
                continue
            piece = picture.crop((int(us[col]), int(vs[row]), int(round(us[col + 1])), int(round(vs[row + 1]))))
            x, y = int(round(xs[col] * zoom)), int(round(ys[row] * zoom))
            x2, y2 = int(round(xs[col + 1] * zoom)), int(round(ys[row + 1] * zoom))
            out.alpha_composite(piece.resize((x2 - x, y2 - y), Image.Resampling.BILINEAR, reducing_gap=None), (x, y))
    return out


def font(size):
    for name in (os.path.join(ROOT, 'fonts', 'RobotoCondensed-Bold.ttf'), 'arialbd.ttf', 'arial.ttf'):
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            pass
    return ImageFont.load_default()


def look_spec(look):
    try:
        from layout import theme_spec

        return theme_spec(look)
    except Exception:  # lupa missing: plain colors are enough for a preview
        return {}


def draw_plate(canvas, picture, data, look, origin, bar, zoom, health=0.62, name='Gnoll Mystic', casting=False, trim=(150, 115, 75)):
    """One plate as the painted style places it (Painted.NameplateStyle): frame, health bar with its
    1 px border, name above the paint, percent inside, and the cast bar below the paint."""
    sl, out, band = data['slice'], data['outset'], data['band']
    bw, bh = bar
    ox, oy = origin
    z = zoom
    frame = draw_sliced(picture, sl, bw + out['left'] + out['right'], bh + out['top'] + out['bottom'], z)
    canvas.alpha_composite(frame, (int(round(ox - out['left'] * z)), int(round(oy - out['top'] * z))))
    d = ImageDraw.Draw(canvas)
    px = max(1, int(round(z)))

    def bar_box(x1, y1, w, h, fill_part, colors, border):
        shade = Image.new('RGBA', (int(round(w * z)), int(round(h * z))), (0, 0, 0, 140))
        canvas.alpha_composite(shade, (int(x1), int(y1)))
        fill = int(round(w * fill_part * z))
        rows = int(round(h * z))
        for i in range(rows):
            t = i / max(1, rows - 1)
            c = tuple(int(colors[0][k] + (colors[1][k] - colors[0][k]) * t) for k in range(3)) + (255,)
            d.line((x1, y1 + i, x1 + fill - 1, y1 + i), fill=c)
        x2, y2 = x1 + int(round(w * z)), y1 + rows
        d.rectangle((x1 - px, y1 - px, x2 + px - 1, y1 - 1), fill=border)
        d.rectangle((x1 - px, y2, x2 + px - 1, y2 + px - 1), fill=border)
        d.rectangle((x1 - px, y1, x1 - 1, y2 - 1), fill=border)
        d.rectangle((x2, y1, x2 + px - 1, y2 - 1), fill=border)
        return x2, y2

    x2, y2 = bar_box(ox, oy, bw, bh, health, ((200, 40, 30), (140, 30, 22)), (0, 0, 0, 255))
    stroke = {'stroke_width': max(1, int(z)), 'stroke_fill': (0, 0, 0, 255)}
    name_y = oy - (max(band['top'], band['name']) + 1) * z
    d.text((ox, name_y), name, font=font(int(round(10 * z))), fill=(255, 230, 200, 255), anchor='ls', **stroke)
    d.text((x2 - 2 * z, (oy + y2) / 2), '62%', font=font(int(round(9 * z))), fill=(255, 255, 255, 255), anchor='rm', **stroke)
    if casting:
        cy = y2 + (band['bottom'] + 2) * z
        bar_box(ox, cy, bw, 8, 0.45, ((240, 190, 60), (190, 140, 40)), trim + (255,))
        icon = int(round(8 * z))
        d.rectangle((ox - px - icon, cy, ox - px - 1, cy + icon - 1), fill=(90, 70, 160, 255))


def preview(look, picture, data):
    spec = look_spec(look)
    title = spec.get('displayName', look)
    trim = tuple(int(v * 255) for v in spec.get('colors', {}).get('frameBorder', (0.6, 0.45, 0.3))[:3])
    rows = [(key, SIZES[key], False) for key in ('small', 'medium', 'large')]
    rows.append(('target, casting', (SIZES['medium'][0] + TARGET_GROW[0], SIZES['medium'][1] + TARGET_GROW[1]), True))
    rows.append(('wide 260 x 16', (260, 16), False))
    zooms = (1, 1.4, 3)
    width = 140 + sum(int((260 + 60) * z) for z in zooms[:2]) + int((SIZES['large'][0] + 60) * 3) + 40
    height = 50 + sum(int((bar[1] + 56) * max(zooms)) for _, bar, _ in rows) + 20
    canvas = Image.new('RGBA', (width, height), (22, 24, 28, 255))
    d = ImageDraw.Draw(canvas)
    d.text((16, 12), f'{title}: painted nameplate at 1 pixel per unit, at 1080p with UI scale 1 (1.4), and 3x', font=font(16), fill=(220, 220, 220, 255))
    y = 50
    for label, bar, casting in rows:
        rh = int((bar[1] + 56) * max(zooms))
        d.text((16, y + rh / 2), label, font=font(13), fill=(170, 170, 170, 255), anchor='lm')
        x = 140
        for z in zooms:
            if z == zooms[-1] and bar[0] > SIZES['large'][0] + TARGET_GROW[0]:
                break
            draw_plate(canvas, picture, data, look, (x + data['outset']['left'] * z, y + 20 * z), bar, z, casting=casting, trim=trim)
            x += int((bar[0] + 60) * z)
        y += rh
    return canvas


def lua_table(results):
    """The numbers as a Lua table, laid out the way StyLua formats it."""
    lines = ['Painted.NAMEPLATES = {']
    for look in LOOKS:
        sl, out, band = results[look]['slice'], results[look]['outset'], results[look]['band']
        lines += [
            '\t%s = {' % look,
            '\t\tslice = { file = { %d, %d }, size = { %d, %d }, left = %d, top = %d, right = %d, bottom = %d, scale = %s },'
            % (sl['file'][0], sl['file'][1], sl['size'][0], sl['size'][1], sl['left'], sl['top'], sl['right'], sl['bottom'], sl['scale']),
            '\t\toutset = { left = %d, top = %d, right = %d, bottom = %d },' % (out['left'], out['top'], out['right'], out['bottom']),
            '\t\tband = { top = %d, bottom = %d, name = %d },' % (band['top'], band['bottom'], band['name']),
            '\t},',
        ]
    lines.append('}')
    return '\n'.join(lines)


def painted_numbers():
    """The numbers Themes/Painted.lua carries, or None when lupa is missing."""
    try:
        from layout import painted_module, to_py

        return to_py(painted_module().NAMEPLATES)
    except Exception as error:  # lupa missing, or a Lua error in Painted.lua
        print('Could not read Themes/Painted.lua: %s' % error)
        return None


def compare(results):
    current = painted_numbers()
    if current is None:
        print('Paste the table above into Themes/Painted.lua by hand.')
        return False
    ok = not results.pop('_stale', False)
    for look, data in results.items():
        have = current.get(look) if isinstance(current, dict) else None
        if have != data:
            ok = False
            print(f'Themes/Painted.lua NAMEPLATES.{look} differs from the files: {have} vs {data}')
    if ok:
        print('Themes/Painted.lua matches the files.')
    return ok


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--check', action='store_true', help='only compare Themes/Painted.lua with the built numbers')
    args = parser.parse_args()
    os.makedirs(OUT, exist_ok=True)
    results, sheets = {}, []
    for look in LOOKS:
        picture, data = build(look)
        results[look] = data
        path = os.path.join(ROOT, 'Themes', look, 'Images', 'Nameplate.png')
        made = padded(picture, *data['slice']['file'])
        if args.check:
            same = os.path.exists(path) and np.array_equal(np.asarray(Image.open(path).convert('RGBA')), np.asarray(made))
            if not same:
                print(f'{path} is missing or differs from a fresh build; run without --check')
                results['_stale'] = True
            continue
        made.save(path, optimize=True)
        sheet = preview(look, picture, data)
        sheet.save(os.path.join(OUT, f'nameplate-{look}.png'))
        sheets.append(sheet)
        print(f'{look:9s} {data}')
    if not args.check:
        total = Image.new('RGBA', (max(s.width for s in sheets), sum(s.height for s in sheets)), (22, 24, 28, 255))
        y = 0
        for s in sheets:
            total.alpha_composite(s, (0, y))
            y += s.height
        total.save(os.path.join(OUT, 'nameplates.png'))
        with open(os.path.join(OUT, 'nameplates.json'), 'w', encoding='utf-8') as f:
            json.dump(results, f, indent=2)
            f.write('\n')
        # The same numbers as Lua, so the nameplate tests can compare Painted.lua with this build
        with open(os.path.join(OUT, 'nameplates.lua'), 'w', encoding='utf-8', newline='\n') as f:
            f.write('-- Made by tools/painted/nameplates.py; Themes/Painted.lua carries the same table\n')
            f.write(lua_table(results).replace('Painted.NAMEPLATES = ', 'return ', 1) + '\n')
        print()
        print(lua_table(results))
    sys.exit(0 if compare(results) or not args.check else 1)


if __name__ == '__main__':
    main()
