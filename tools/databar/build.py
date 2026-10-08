"""Cut the DataBar strips out of the original paintings, without stretching them.

Each painting (openspec/databar-art/sources/<Name>-raw.png) holds one bar band, located by
sources/crops.json. The band is scaled evenly to the file height and cut into DataBar 'multi' art:

  <base>-Left.png    the left end: the ornament plus a short run of plain material
  <base>-Center.png  one repeat of the trim pattern; its last columns blend into the material just
                     before it, so copies placed side by side join without a seam
  <base>-Right.png   the left end mirrored
  <base>-Card.png    the setup card picture (512 x 256), over the look's own setup picture

Pieces are padded to power-of-two files (the padding repeats the last column, so nothing bleeds in at
the edge); the drawn part is given to DataBar through texture coordinates. Writes tools/databar/looks.json
for SpartanUI/Themes/DataBarArt.lua, and previews to openspec/databar-art/.

Run with Codex's bundled Python (Pillow and numpy):
  C:\\Users\\jerem\\.cache\\codex-runtimes\\codex-primary-runtime\\dependencies\\python\\python.exe tools/databar/build.py
"""
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageEnhance, ImageFilter, ImageFont, ImageOps

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'openspec/databar-art'
SRC = OUT / 'sources'
FONT = ROOT / 'fonts/RobotoCondensed-Bold.ttf'
LANCZOS = Image.Resampling.LANCZOS
HEIGHT = 64  # file height; the bar draws every piece at the bar's height, keeping its shape

# Where each left ornament ends, in band heights from the band's left edge
ORNAMENT = {
    'Arcane-Blue': 0.85, 'Arcane-Red': 0.9, 'Classic': 0.6, 'Digital': 0.6, 'Fel': 0.65, 'Tribal': 0.65,
    'War-Alliance': 0.6, 'War-Horde': 0.65, 'Midnight': 0.85, 'Voyager': 0.5, 'Grove': 1.4, 'Meridian': 0.75,
}
# The look's setup picture, used behind the bar on its card
SETUP = {'Arcane-Blue': 'Arcane', 'Arcane-Red': 'Arcane', 'War-Alliance': 'War_Alliance', 'War-Horde': 'War', 'Voyager': 'Atlas', 'Grove': 'Boughs'}
BLEND = 0.2  # length of the seam blend, in band heights
PLUGINS = [(0.05, ('Gold', '12,345g')), (0.24, ('Bags', '42/120')), (0.43, ('Durability', '87%')), (0.66, ('FPS', '120')), (0.79, ('MS', '34')), (0.91, ('', '12:34'))]


def pot(n):
    size = 16
    while size < n:
        size *= 2
    return size


def padded(img, width):
    """Put img at the left of a power-of-two canvas; the padding repeats the last column."""
    canvas = Image.new('RGBA', (width, img.height))
    canvas.paste(img, (0, 0))
    edge = img.crop((img.width - 1, 0, img.width, img.height))
    for x in range(img.width, width):
        canvas.paste(edge, (x, 0))
    return canvas


def find_period(band, start, lo, hi, window):
    """Tile length in [lo, hi] whose start best matches what follows it (the trim's own repeat)."""
    a = band[:, start:start + window].astype(np.float32)
    best, best_len = None, lo
    for length in range(lo, hi + 1):
        b = band[:, start + length:start + length + window].astype(np.float32)
        if b.shape[1] < window:
            break
        score = float(np.abs(a - b).mean())
        if best is None or score < best:
            best, best_len = score, length
    return best_len, best


def luminance(rgb):
    c = [v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4 for v in rgb]
    return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]


def contrast(a, b):
    la, lb = luminance(a), luminance(b)
    return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)


def cut(name, box):
    raw = Image.open(SRC / (name + '-raw.png')).convert('RGB').crop(tuple(box))
    band = np.asarray(raw)
    h, w = band.shape[0], band.shape[1]
    blend = round(BLEND * h)
    start = round(ORNAMENT[name] * h)  # plain material begins here
    tile_start = start + blend  # the blend run (start .. tile_start) stays on the left end
    room = w - round(0.35 * h) - tile_start  # keep clear of the painting's own right end
    window = round(0.3 * h)
    length, score = find_period(band, tile_start, round(2.0 * h), min(round(4.0 * h), room - window), window)

    tile = band[:, tile_start:tile_start + length].astype(np.float32).copy()
    lead = band[:, start:tile_start].astype(np.float32)  # what comes just before the tile
    for i in range(blend):
        t = (i + 1) / blend
        t = t * t * (3 - 2 * t)
        col = length - blend + i
        tile[:, col] = tile[:, col] * (1 - t) + lead[:, i] * t
    tile = Image.fromarray(tile.round().clip(0, 255).astype(np.uint8))
    left = raw.crop((0, 0, tile_start, h))

    scale = HEIGHT / h
    left = left.resize((max(1, round(left.width * scale)), HEIGHT), LANCZOS).convert('RGBA')
    tile = tile.resize((max(1, round(tile.width * scale)), HEIGHT), LANCZOS).convert('RGBA')
    right = left.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
    return left, tile, right, score


def assemble(left, tile, right, width, height):
    """Draw the bar the way DataBar does: ends at their shape, copies of the middle between them."""
    scale = height / HEIGHT
    lw, tw, rw = (max(1, round(p.width * scale)) for p in (left, tile, right))
    if lw + rw > width:
        shown = width / (lw + rw)
        lw2, rw2 = round(lw * shown), width - round(lw * shown)
        bar = Image.new('RGBA', (width, height))
        bar.paste(left.resize((lw, height), LANCZOS).crop((0, 0, lw2, height)), (0, 0))
        bar.paste(right.resize((rw, height), LANCZOS).crop((rw - rw2, 0, rw, height)), (lw2, 0))
        return bar
    bar = Image.new('RGBA', (width, height))
    t = tile.resize((tw, height), LANCZOS)
    x = lw
    while x < width - rw:
        bar.paste(t.crop((0, 0, min(tw, width - rw - x), height)), (x, 0))
        x += tw
    bar.paste(left.resize((lw, height), LANCZOS), (0, 0))
    bar.paste(right.resize((rw, height), LANCZOS), (width - rw, 0))
    return bar


def label(draw, bar_box, entries, colors, size):
    font = ImageFont.truetype(str(FONT), size)
    x0, y0, x1, y1 = bar_box
    for frac, (name, value) in entries:
        x, y = x0 + (x1 - x0) * frac, (y0 + y1) / 2
        if name:
            draw.text((x, y), name, font=font, fill=colors[1], anchor='lm')
            x += draw.textlength(name + ' ', font=font)
        draw.text((x, y), value, font=font, fill=colors[0], anchor='lm')


def card_backdrop(name):
    look = SETUP.get(name, name)
    picture = ROOT / 'images/setup' / ('Style_' + look + '.tga')
    if not picture.exists():
        return Image.new('RGBA', (512, 256), '#10151b')
    scene = ImageOps.fit(Image.open(picture).convert('RGB'), (512, 256), LANCZOS)
    scene = ImageEnhance.Brightness(scene.filter(ImageFilter.GaussianBlur(10))).enhance(0.45)
    return scene.convert('RGBA')


def main():
    jobs = json.loads((SRC / 'jobs.json').read_text())
    boxes = json.loads((SRC / 'crops.json').read_text())
    colors_by_base = {entry['base'].replace('\\', '/'): entry for entry in json.loads((ROOT / 'tools/databar/looks.json').read_text())}
    looks, previews, cards = [], [], []
    for name, base, *_ in jobs:
        left, tile, right, score = cut(name, boxes[name])
        lc, cc = pot(left.width), pot(tile.width)
        path = ROOT / base
        padded(left, lc).save(str(path) + '-Left.png')
        padded(right, lc).save(str(path) + '-Right.png')
        padded(tile, cc).save(str(path) + '-Center.png')

        colors = colors_by_base[base]
        text = tuple(round(v * 255) for v in colors['textColor'])
        lab = tuple(round(v * 255) for v in colors['labelColor'])
        middle = np.asarray(tile.convert('RGB'))[round(HEIGHT * 0.2):round(HEIGHT * 0.8)].reshape(-1, 3).mean(axis=0) / 255
        ratio = min(contrast(colors['textColor'], middle), contrast(colors['labelColor'], middle))

        card = card_backdrop(name)
        card.alpha_composite(assemble(left, tile, right, 512, 64), (0, 150))
        label(ImageDraw.Draw(card), (82, 150, 430, 214), [(0.0, ('Gold', '12,345g')), (0.55, ('Bags', '42/120'))], (text, lab), 19)
        card.save(str(path) + '-Card.png')
        cards.append(card)

        scene = Image.new('RGBA', (1960, 160), '#10151b')
        for i, width in enumerate((1920, 640, 120)):
            y = 10 + i * 50
            scene.alpha_composite(assemble(left, tile, right, width, 31), (20, y))
            if width >= 640:
                label(ImageDraw.Draw(scene), (20, y, 20 + width, y + 31), PLUGINS if width > 1000 else PLUGINS[:3], (text, lab), 15)
        scene.save(OUT / (name + '-preview.png'))
        previews.append(scene)

        looks.append({
            'base': base.replace('/', '\\'),
            'leftWidth': left.width, 'leftFile': lc,
            'centerWidth': tile.width, 'centerFile': cc,
            'textColor': colors['textColor'], 'labelColor': colors['labelColor'], 'highlight': colors['highlight'],
            'contrast': round(ratio, 2), 'seam': round(score, 2),
        })
        print(f'{name:13s} left {left.width:3d}/{lc}  center {tile.width:3d}/{cc}  contrast {ratio:5.2f}  match {score:5.1f}')

    (ROOT / 'tools/databar/looks.json').write_text(json.dumps(looks, indent=2) + '\n')
    sheet = Image.new('RGBA', (1960, 160 * len(previews) + 160), '#10151b')
    for i, scene in enumerate(previews):
        sheet.alpha_composite(scene, (0, i * 160))
    for i, card in enumerate(cards):
        sheet.alpha_composite(card.resize((150, 75), LANCZOS), (20 + i * 160, 160 * len(previews) + 40))
    sheet.save(OUT / 'contact.png')


if __name__ == '__main__':
    main()
