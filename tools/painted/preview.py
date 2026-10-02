"""Draw a painted look as it sits on screen, from its game files and the layout in Themes/Painted.lua.

python preview.py <theme_images_dir> <out.png> [--size 1920x1080] [--background image] [--accent R,G,B]
                  [--variant docked|corner] [--noportrait] [--narrow]

Stand-ins for the game: grey action buttons on the bar sockets, a round map in the minimap
socket, filled status bars, and player / target frames (bars, name, round portrait) on their
plates. The UI is drawn at the default scale (UIParent 768 units tall, SpartanUI at 0.92).
"""

import argparse
import os
import random

from PIL import Image, ImageDraw, ImageFilter, ImageFont

from layout import layout

ART_SCALE = 0.92


def font(size):
    for name in ('arialbd.ttf', 'arial.ttf', 'DejaVuSans-Bold.ttf'):
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            pass
    return ImageFont.load_default()


class Screen:
    def __init__(self, width, height):
        self.w, self.h = width, height
        self.px = height / 768 * ART_SCALE  # screen pixels per art unit

    def pt(self, x, y):
        return self.w / 2 + x * self.px, self.h - y * self.px

    def rect(self, x1, y1, x2, y2):
        ax, ay = self.pt(x1, y2)
        bx, by = self.pt(x2, y1)
        return [ax, ay, bx, by]


def background(size, path=None):
    if path and os.path.exists(path):
        img = Image.open(path).convert('RGB')
        sw, sh = size
        scale = max(sw / img.width, sh / img.height)
        img = img.resize((int(img.width * scale) + 1, int(img.height * scale) + 1), Image.LANCZOS)
        left, top = (img.width - sw) // 2, (img.height - sh) // 2
        return img.crop((left, top, left + sw, top + sh)).convert('RGBA')
    # A soft, game-like ground so transparency and edges are easy to judge
    random.seed(7)
    small = Image.new('RGB', (48, 27))
    for x in range(48):
        for y in range(27):
            g = 70 + random.randint(-20, 20) + y
            small.putpixel((x, y), (g // 2 + 25, g, g // 2 + 15))
    return small.resize(size, Image.BICUBIC).filter(ImageFilter.GaussianBlur(8)).convert('RGBA')


def paste_scaled(canvas, img, box):
    x1, y1, x2, y2 = [int(round(v)) for v in box]
    if x2 <= x1 or y2 <= y1:
        return
    canvas.alpha_composite(img.resize((x2 - x1, y2 - y1), Image.LANCZOS), (x1, y1))


def slide(x, shift):
    """Move an art x toward the centre by shift (the narrow-centre bar)."""
    return x + shift if x < 0 else x - shift


def draw_buttons(canvas, sc, lay, images, shift=0, theme=None):
    from layout import fit_bars
    from templates import BUTTON_FRAME

    d = ImageDraw.Draw(canvas)
    path = os.path.join(images, 'Button.png')
    frame = Image.open(path).convert('RGBA') if os.path.exists(path) else None
    for key, spot in fit_bars(theme).items():
        block = key in ('BT4Bar5', 'BT4Bar6')
        cols, rows = (4, 3) if block else (12, 1)
        b = spot['button']
        gap = b * (4 if block else 3) / 45
        x = slide(spot['x'], shift)
        nc = lay['narrowCentre']
        if shift and nc['keep'] == 0 and abs(x) - spot['width'] / 2 < nc['centreGap'] / 2:
            x = (nc['centreGap'] / 2 + spot['width'] / 2) * (1 if x > 0 else -1)
        left = x - spot['width'] / 2
        bottom = spot['y'] - spot['height'] / 2
        for c in range(cols):
            for r in range(rows):
                x1 = left + c * (b + gap)
                y1 = bottom + r * (b + gap)
                box = sc.rect(x1, y1, x1 + b, y1 + b)
                shade = 60 + (c * 13 + r * 29) % 50
                d.rectangle(box, fill=(shade, shade - 5, shade - 12, 255), outline=(10, 10, 10, 255), width=1)
                if frame:
                    cx, cy = (box[0] + box[2]) / 2, (box[1] + box[3]) / 2
                    half = (box[2] - box[0]) * BUTTON_FRAME / 2
                    paste_scaled(canvas, frame, [cx - half, cy - half, cx + half, cy + half])
                    d = ImageDraw.Draw(canvas)
                else:
                    inner = [box[0] + 3, box[1] + 3, box[2] - 3, box[3] - 3]
                    d.rectangle(inner, outline=(shade + 40, shade + 30, shade + 10, 255), width=1)


def draw_minimap(canvas, sc, lay, images=None, corner=False):
    mm = lay['minimap']
    if corner:
        # Socket's top right corner at the screen's top right plus the layout offset
        c = lay['cornerMinimap']
        right = sc.w + c['x'] * sc.px
        top = -c['y'] * sc.px
        size = mm['size'] * sc.px
        box = [right - size, top, right, top + size]
        bezel_path = images and os.path.join(images, 'Minimap.png')
        if bezel_path and os.path.exists(bezel_path):
            cx, cy = (box[0] + box[2]) / 2, (box[1] + box[3]) / 2
            half = c['bezel'] * sc.px / 2
            paste_scaled(canvas, Image.open(bezel_path).convert('RGBA'), [cx - half, cy - half, cx + half, cy + half])
    else:
        box = sc.rect(mm['x'] - mm['size'] / 2, mm['y'] - mm['size'] / 2, mm['x'] + mm['size'] / 2, mm['y'] + mm['size'] / 2)
    size = int(box[2] - box[0])
    random.seed(3)
    tiny = Image.new('RGB', (12, 12))
    for x in range(12):
        for y in range(12):
            v = random.random()
            tiny.putpixel((x, y), (60, 110, 160) if v < 0.3 else (90, 130, 60) if v < 0.8 else (150, 140, 100))
    terrain = tiny.resize((size, size), Image.BICUBIC).convert('RGBA')
    circle = Image.new('L', (size, size), 0)
    ImageDraw.Draw(circle).ellipse([0, 0, size - 1, size - 1], fill=255)
    terrain.putalpha(circle)
    if corner:
        # The bezel sits behind the map, as in the game
        canvas.alpha_composite(terrain, (int(box[0]), int(box[1])))
        return
    canvas.alpha_composite(terrain, (int(box[0]), int(box[1])))


def draw_statusbars(canvas, sc, lay, images, accent, shift=0, narrow_look=False):
    groove = Image.open(os.path.join(images, 'StatusBar.png')).convert('RGBA') if os.path.exists(os.path.join(images, 'StatusBar.png')) else None
    d = ImageDraw.Draw(canvas)
    for key, bar in lay['statusBars'].items():
        width = bar['width'] - (lay['narrowCentre']['statusTrim'] if narrow_look else 0)
        outer = abs(bar['x']) + bar['width'] / 2
        x = slide((outer - width / 2) * (1 if bar['x'] > 0 else -1), shift)
        box = sc.rect(x - width / 2, bar['y'] - bar['height'] / 2, x + width / 2, bar['y'] + bar['height'] / 2)
        if groove:
            paste_scaled(canvas, groove.transpose(Image.FLIP_LEFT_RIGHT) if key == 'Right' else groove, box)
        fill = box[:]
        fill[2] = fill[0] + (fill[2] - fill[0]) * (0.62 if key == 'Left' else 0.35)
        d.rectangle(fill, fill=accent + (200,))


def draw_unitframe(canvas, sc, lay, images, unit, portrait=True):
    plate_info = lay['plate']
    frames = lay['frames']
    spot = frames[unit]
    width, height = frames['width'], lay['frameHeight']
    left, bottom = spot['x'] - width / 2, spot['y'] - height / 2
    top = bottom + height
    is_target = unit == 'target'
    # The plate is always the one without a ring; the ring is drawn on its own over it
    path = os.path.join(images, 'UnitFrame-NoPortrait.png')
    if os.path.exists(path):
        plate = Image.open(path).convert('RGBA')
        if is_target:
            plate = plate.transpose(Image.FLIP_LEFT_RIGHT)
            px1 = left + width + plate_info['left'] - plate_info['width']
        else:
            px1 = left - plate_info['left']
        py2 = top + plate_info['top']
        paste_scaled(canvas, plate, sc.rect(px1, py2 - plate_info['height'], px1 + plate_info['width'], py2))
    mount = lay['mount']
    mount_path = os.path.join(images, 'UnitFrame-Mount.png')
    if portrait and os.path.exists(mount_path):
        # The ring and its joining piece sit behind the plate: draw them, then the plate again on top
        art = Image.open(mount_path).convert('RGBA')
        if is_target:
            art = art.transpose(Image.FLIP_LEFT_RIGHT)
        size = mount['file'] * plate_info['width'] / plate_info['file']['width']
        rx = left + mount['x'] if not is_target else left + width - mount['x']
        ry = bottom + height / 2
        paste_scaled(canvas, art, sc.rect(rx - size / 2, ry - size / 2, rx + size / 2, ry + size / 2))
        if os.path.exists(path):
            paste_scaled(canvas, plate, sc.rect(px1, py2 - plate_info['height'], px1 + plate_info['width'], py2))
    d = ImageDraw.Draw(canvas)
    # Bars, inset inside the plate's window: power along the
    # bottom, health over everything above it, the cast bar over the power bar
    inset = frames['inset']
    bl = left + inset['side']
    br = left + width - inset['side']
    low = bottom + inset['bottom']
    d.rectangle(sc.rect(bl, low + frames['power'], br, top - inset['top']), fill=(40, 170, 60, 235))
    d.rectangle(sc.rect(bl, low, br, low + frames['power']), fill=(40, 80, 200, 235))
    d.rectangle(sc.rect(bl, low, bl + (br - bl) * 0.6, low + frames['power']), fill=(220, 170, 40, 200))
    name_off = inset['side'] + 2
    name_x, name_y = sc.pt(left + (width - name_off if is_target else name_off), top + 2)
    f = font(max(10, int(12 * sc.px)))
    text = 'Target Name' if is_target else '60 Player Name'
    tw = d.textlength(text, font=f)
    d.text((name_x - (tw if is_target else 0), name_y - f.size - 2), text, font=f, fill=(255, 235, 200, 255), stroke_width=1, stroke_fill=(0, 0, 0, 255))
    if not portrait:
        return
    # Round portrait
    p = lay['mount']
    cx = left + p['x'] if not is_target else left + width - p['x']
    cy = bottom + height / 2
    box = [int(v) for v in sc.rect(cx - p['size'] / 2, cy - p['size'] / 2, cx + p['size'] / 2, cy + p['size'] / 2)]
    size = box[2] - box[0]
    face = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    fd = ImageDraw.Draw(face)
    for i in range(size // 2, 0, -1):
        shade = int(30 + 40 * (1 - i / (size / 2)))
        fd.ellipse([size / 2 - i, size / 2 - i, size / 2 + i, size / 2 + i], fill=(shade, shade - 4, shade - 8, 255))
    fd.ellipse([size * 0.34, size * 0.2, size * 0.66, size * 0.52], fill=(120, 100, 88, 255))
    fd.ellipse([size * 0.18, size * 0.56, size * 0.82, size * 1.15], fill=(92, 78, 70, 255))
    circle = Image.new('L', (size, size), 0)
    ImageDraw.Draw(circle).ellipse([0, 0, size - 1, size - 1], fill=255)
    face.putalpha(circle)
    canvas.alpha_composite(face, (box[0], box[1]))


def render(images, out, size, bg=None, accent=(150, 110, 230), variant='docked', portrait=True, narrow=False, theme=None):
    lay = layout()
    sc = Screen(*size)
    canvas = background(size, bg)
    art = lay['art']
    corner = variant == 'corner'
    suffix = '-Closed' if corner else ''
    for side, name in (('left', 'Bottom-Left%s.png' % suffix), ('right', 'Bottom-Right%s.png' % suffix)):
        path = os.path.join(images, name)
        if not os.path.exists(path):
            continue
        img = Image.open(path).convert('RGBA')
        x1 = -art['halfWidth'] if side == 'left' else 0
        paste_scaled(canvas, img, sc.rect(x1, 0, x1 + art['halfWidth'], art['height']))
    draw_minimap(canvas, sc, lay, images, corner)
    nc = lay['narrowCentre']
    shift = nc['plaque'] - nc['keep'] if corner and narrow else 0
    from layout import ROOT, theme_from_images

    look = theme or theme_from_images(images)
    style = os.path.join(ROOT, 'Themes', look, 'Style.lua') if look else None
    narrow_look = bool(style and os.path.exists(style) and 'narrowCentre = true' in open(style, encoding='utf-8').read())
    draw_statusbars(canvas, sc, lay, images, accent, shift, narrow_look)
    draw_buttons(canvas, sc, lay, images, shift, look)
    for unit in ('player', 'target'):
        draw_unitframe(canvas, sc, lay, images, unit, portrait)
    canvas.convert('RGB').save(out)
    return out


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('images')
    parser.add_argument('out')
    parser.add_argument('--size', default='1920x1080')
    parser.add_argument('--background')
    parser.add_argument('--accent', default='150,110,230')
    parser.add_argument('--variant', default='docked', choices=('docked', 'corner'))
    parser.add_argument('--noportrait', action='store_true')
    parser.add_argument('--narrow', action='store_true', help='the look closes up its centre with the minimap top right')
    args = parser.parse_args()
    size = tuple(int(v) for v in args.size.lower().split('x'))
    render(args.images, args.out, size, args.background, tuple(int(v) for v in args.accent.split(',')), args.variant, not args.noportrait, args.narrow)
    print(args.out)


if __name__ == '__main__':
    main()
