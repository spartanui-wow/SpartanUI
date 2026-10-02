"""Check painted frame geometry and build the before/after review sheet."""

import os
import ast

from PIL import Image, ImageChops, ImageDraw

from layout import ROOT, external_layout, layout, theme_spec
from preview import Screen, draw_unitframe, draw_plate


def main():
    lay = layout()
    frames, plate, mount = lay['frames'], lay['plate'], lay['mount']
    inset = frames['inset']
    assert frames['width'] == 230
    assert lay['frameHeight'] == 48
    assert frames['width'] - inset['side'] * 2 == 222
    assert lay['frameHeight'] - inset['top'] - inset['bottom'] - frames['power'] == 30
    if os.environ.get('PAINTED_LUA'):
        points = external_layout()['barPoints']
        assert points['health'][0]['x'] == inset['side']
        assert points['health'][0]['y'] == -inset['top']
        assert points['health'][2]['y'] == inset['bottom'] + frames['power']
        assert points['lower'][0]['y'] == inset['bottom']
    folder = os.path.join(ROOT, 'openspec', 'setup-cards', 'painted')
    sheet = Image.new('RGB', (1024, 3 * 284 + 28), (24, 24, 24))
    draw = ImageDraw.Draw(sheet)
    draw.text((12, 8), 'Before (existing TGA)', fill='white')
    draw.text((524, 8), 'After (regenerated TGA)', fill='white')
    for row, theme in enumerate(('Atlas', 'Boughs', 'Meridian')):
        spec = theme_spec(theme)
        assert spec.get('nameAbove', False) == (theme != 'Meridian')
        assert spec.get('nameInset', inset['side'] + 2) == (16 if theme == 'Meridian' else 6)
        images = os.path.join(ROOT, 'Themes', theme, 'Images')
        sc = Screen(1920, 1080)
        for unit in ('player', 'target'):
            # Paint bars without art to check every edge independently of painted pixels.
            canvas = Image.new('RGBA', (1920, 1080))
            draw_unitframe(canvas, sc, lay, '', unit, False, spec)
            spot = frames[unit]
            left, bottom = spot['x'] - frames['width'] / 2, spot['y'] - lay['frameHeight'] / 2
            expected = sc.rect(left + inset['side'], bottom + inset['bottom'],
                               left + frames['width'] - inset['side'], bottom + lay['frameHeight'] - inset['top'])
            # Pillow rectangles include their far edge; allow that single raster pixel.
            colors = canvas.getdata()
            mask = Image.new('L', canvas.size)
            mask.putdata([255 if p in ((40, 170, 60, 235), (40, 80, 200, 235), (220, 170, 40, 200)) else 0 for p in colors])
            actual = mask.getbbox()
            assert all(abs(a - b) <= 1.1 for a, b in zip(actual, expected)), (theme, unit, actual, expected)
            cx = left + mount['x'] if unit == 'player' else left + frames['width'] - mount['x']
            assert abs(cx - spot['x']) == frames['width'] / 2 - mount['x']
        # At several widths the outside caps must be byte-identical, while only the middle changes.
        art = Image.open(os.path.join(images, 'UnitFrame-NoPortrait.png')).convert('RGBA')
        for mirrored in (False, True):
            caps = []
            for width in (180, 230, 320):
                canvas = Image.new('RGBA', (1000, 300))
                unit_sc = Screen(1000, 300)
                unit_sc.px = 1
                draw_plate(canvas, unit_sc, lay, art, 0, 100, width, 48, mirrored)
                extra = plate['width'] - plate['left'] - frames['width'] if mirrored else plate['left']
                cap = plate['slice']['right' if mirrored else 'left'] * plate['width'] / plate['file']['width']
                x = round(500 - extra)
                caps.append(canvas.crop((x, 134, round(500 - extra + cap), 212)))
            assert ImageChops.difference(caps[0], caps[1]).getbbox() is None
            assert ImageChops.difference(caps[1], caps[2]).getbbox() is None
        after = Image.open(os.path.join(ROOT, 'images', 'setup', f'Style_{theme}.tga'))
        assert after.size == (512, 256) and after.mode == 'RGBA'
        assert after.getchannel('A').getextrema() == (255, 255)
        after = after.convert('RGB')
        after.save(os.path.join(folder, f'{theme}-after.png'))
        before = Image.open(os.path.join(folder, f'{theme}-before.png')).convert('RGB')
        diff = ImageChops.difference(before, after)
        assert diff.crop((0, 0, 512, 100)).getbbox() is None
        assert diff.crop((20, 204, 110, 209)).getbbox() is None
        y = 28 + row * 284
        draw.text((12, y + 4), spec['displayName'] + ' (' + theme + ')', fill='white')
        sheet.paste(before, (0, y + 28))
        sheet.paste(after, (512, y + 28))
    sheet.save(os.path.join(folder, 'compare.png'))
    for name in ('preview.py', 'layout.py', 'card.py', 'check_frames.py'):
        ast.parse(open(os.path.join(ROOT, 'tools', 'painted', name), encoding='utf-8').read())
    print('PASS: bars, widths, mirrored fixed caps, portrait centres, names, TGA format, backdrops and accents')


if __name__ == '__main__':
    main()
