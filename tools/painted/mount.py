"""The portrait mount: the portrait ring plus the piece that joins it to the unit frame plate.

python mount.py template <theme_images_dir> <out.png> [ring_reference.png]
python mount.py preview <theme_images_dir> <mount.png> <out.png>

The mount is one 256 x 256 picture at the plate's scale, centred on the portrait (layout `mount`). It is
drawn BEHIND the plate at a fixed size, so the plate can stretch for taller bars while the ring stays
round; the joining piece tucks under the plate's end.

Template colours:
- red          the portrait: cut to transparent (the portrait shows through)
- the ring     the look's current ring, as a reference for its style (keep or repaint it)
- blue         the gap the joining piece must bridge, from the ring to under the plate's end
- grey veil    where the plate is drawn on top; paint here only what should tuck under it
"""

import os
import sys

from PIL import Image, ImageDraw

from layout import layout, PlateMap

FILE = 256


class MountMap:
    """Frame units (x right from the frame's left edge, y down from its top) <-> mount picture pixels."""

    def __init__(self):
        lay = layout()
        self.s = lay['plate']['file']['width'] / lay['plate']['width']
        self.cx = lay['mount']['x']
        self.cy = lay['frameHeight'] / 2

    def px(self, x, y):
        return FILE / 2 + (x - self.cx) * self.s, FILE / 2 + (y - self.cy) * self.s


def plate_layer(images, height=None):
    """The plate without a ring, placed (and stretched for a taller frame) as the game draws it, in
    mount pixels. Returns an image the size of the mount canvas, or a wider one for previews."""
    lay = layout()
    plate = lay['plate']
    img = Image.open(os.path.join(images, 'UnitFrame-NoPortrait.png')).convert('RGBA')
    mm = MountMap()
    frame_h = height or lay['frameHeight']
    total_h = plate['top'] + frame_h + (plate['height'] - plate['top'] - lay['frameHeight'])
    x1, y1 = mm.px(-plate['left'], -plate['top'])
    x2, y2 = mm.px(plate['width'] - plate['left'], total_h - plate['top'])
    m = plate['slice']
    fw, fh = plate['file']['width'], plate['file']['height']
    W, H = int(round(x2 - x1)), int(round(y2 - y1))
    out = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    xs, ys = [0, m['left'], fw - m['right'], fw], [0, m['top'], fh - m['bottom'], fh]
    dx = [0, m['left'], W - m['right'], W]
    dy = [0, m['top'], H - m['bottom'], H]
    for r in range(3):
        for c in range(3):
            w, h = int(dx[c + 1] - dx[c]), int(dy[r + 1] - dy[r])
            if w > 0 and h > 0:
                out.alpha_composite(img.crop((xs[c], ys[r], xs[c + 1], ys[r + 1])).resize((w, h), Image.LANCZOS), (int(dx[c]), int(dy[r])))
    return out, (int(round(x1)), int(round(y1)))


def template(images, out_path, ring_ref=None):
    lay = layout()
    mm = MountMap()
    canvas = Image.new('RGBA', (FILE, FILE), (0, 0, 0, 0))
    # The old plate's ring, kept beside the paintings by enforce.py, shows the look's ring style
    ring_path = ring_ref or os.path.join(images, 'UnitFrame-Ring.png')
    if os.path.exists(ring_path):
        canvas.alpha_composite(Image.open(ring_path).convert('RGBA'))
    d = ImageDraw.Draw(canvas)
    size = lay['mount']['size']
    r = size / 2 * mm.s
    c = FILE / 2
    d.ellipse([c - r, c - r, c + r, c + r], fill=(230, 40, 40, 220))
    # The gap to bridge: from the ring's outer edge to under the plate's end
    gx1, gy1 = mm.px(lay['mount']['x'] + size / 2 + 6, -6)
    gx2, gy2 = mm.px(10, lay['frameHeight'] + 6)
    d.rectangle([gx1, gy1, gx2, gy2], fill=(40, 110, 230, 150))
    plate, (px, py) = plate_layer(images)
    veil = Image.new('RGBA', plate.size, (200, 200, 200, 0))
    veil.putalpha(plate.getchannel('A').point(lambda v: int(v * 0.55)))
    tinted = Image.alpha_composite(plate, veil)
    layer = Image.new('RGBA', (FILE, FILE), (0, 0, 0, 0))
    layer.alpha_composite(tinted.crop((max(0, -px), max(0, -py), plate.width, plate.height)), (max(0, px), max(0, py)))
    canvas.alpha_composite(layer)
    canvas.save(out_path)


def preview(images, mount_path, out_path):
    """Mount behind the plate with a stand-in portrait and bars, at the normal height and a tall one."""
    lay = layout()
    mm = MountMap()
    mount = Image.open(mount_path).convert('RGBA')
    shots = []
    for height in (lay['frameHeight'], lay['frameHeight'] + 40):
        plate, (px, py) = plate_layer(images, height)
        # A canvas wide enough for the plate and the mount, in mount pixels
        left, top = min(0, px), min(0, py - 20)
        right, bottom = max(FILE, px + plate.width), max(FILE, py + plate.height + 20)
        canvas = Image.new('RGBA', (right - left, bottom - top), (58, 74, 60, 255))
        # Mount: centred on the frame's vertical middle, which moves down as the frame grows
        my = int(round((height - lay['frameHeight']) / 2 * mm.s))
        portrait = Image.new('RGBA', (FILE, FILE), (0, 0, 0, 0))
        pd = ImageDraw.Draw(portrait)
        r = lay['mount']['size'] / 2 * mm.s
        pd.ellipse([FILE / 2 - r, FILE / 2 - r, FILE / 2 + r, FILE / 2 + r], fill=(120, 110, 100, 255))
        canvas.alpha_composite(portrait, (-left, my - top))
        canvas.alpha_composite(mount, (-left, my - top))
        canvas.alpha_composite(plate, (px - left, py - top))
        d = ImageDraw.Draw(canvas)
        inset = lay['frames']['inset']
        x0, y0 = mm.px(inset['side'], inset['top'])
        x1, y1 = mm.px(lay['frames']['width'] - inset['side'], height - inset['bottom'])
        d.rectangle([x0 - left, y0 - top, x1 - left, y1 - top + my * 0], fill=(150, 205, 120, 255))
        shots.append(canvas)
    w = max(s.width for s in shots)
    sheet = Image.new('RGBA', (w * 2, sum(s.height for s in shots) * 2 + 20), (20, 20, 22, 255))
    y = 0
    for s in shots:
        sheet.alpha_composite(s.resize((s.width * 2, s.height * 2), Image.LANCZOS), (0, y))
        y += s.height * 2 + 20
    sheet.convert('RGB').save(out_path)


if __name__ == '__main__':
    cmd = sys.argv[1]
    if cmd == 'template':
        template(sys.argv[2], sys.argv[3], sys.argv[4] if len(sys.argv) > 4 else None)
    elif cmd == 'preview':
        preview(sys.argv[2], sys.argv[3], sys.argv[4])
    print(sys.argv[-1])
