"""Make painted art fit the layout exactly, then write the game files.

python enforce.py <painted_dir> <theme_images_dir> [--bed R,G,B]

<painted_dir> holds the paintings made against the templates:
- bottom.png      2048 x 512 (any size with the same 4:1 shape is resized)
- unitframe.png   512 x 128
- statusbar.png   512 x 32
- button.png      128 x 128 (the frame around every action button)
- bottom_closed.png        2048 x 512, the bar with its centre closed (Minimap top right variant)
- minimap.png              512 x 512, the corner minimap bezel
- unitframe_noportrait.png 512 x 128, the plate for frames with the portrait turned off

Every bar picture must end inside its canvas: the outermost columns are checked, and paint
touching the left or right edge is reported (it shows as a hard cut on wide screens).

The paintings only need to be close. This script:
- cuts the minimap hole and the portrait hole to full transparency (soft 1px edge)
- darkens the button beds and the unit frame's bar window so buttons and bars read
- clears anything painted far outside the bar's body, where the game world must show
- splits the bottom bar into Bottom-Left.png and Bottom-Right.png
- writes StatusBar.png (groove with a dark middle, drawn behind the bar fill) and StatusBar-Frame.png
  (the same groove with its middle cut out, drawn over the fill)
- cuts the portrait opening out of portrait_mount.png (the ring and the piece joining it to the plate,
  see mount.py) into UnitFrame-Mount.png, drawn behind the plate at a fixed size so a taller frame
  never stretches it; the plate itself is always UnitFrame-NoPortrait.png
- keeps a copy of the old plate's ring beside the paintings (ring_reference.png), for mount templates
- with --narrow, closes up the bar's centre for the "Minimap top right" variant (the layout's
  narrowCentre: the centre panel shrinks and both halves slide in)

It prints a short report; a warning means the painting misses part of the layout.
"""

import argparse
import math
import os

from PIL import Image, ImageChops, ImageDraw, ImageFilter

from layout import layout, PlateMap
from templates import CENTER_PLAQUE, NOPORTRAIT_LEFT, BezelMap, FullMap, body_top, ring_outer


def mask_from(size, draw_fn, blur=1.0):
    mask = Image.new('L', size, 0)
    draw_fn(ImageDraw.Draw(mask))
    if blur:
        mask = mask.filter(ImageFilter.GaussianBlur(blur))
    return mask


def darken(img, mask, color, strength):
    """Blend toward color where mask is set, and make those pixels opaque."""
    flat = Image.new('RGBA', img.size, color + (255,))
    blended = Image.blend(img.convert('RGBA'), flat, strength)
    opaque = blended.copy()
    opaque.putalpha(255)
    return Image.composite(opaque, img, mask)


def cut(img, mask):
    """Make pixels transparent where mask is set."""
    alpha = img.getchannel('A')
    alpha = ImageChops.subtract(alpha, mask)
    out = img.copy()
    out.putalpha(alpha)
    return out


def coverage(img, mask):
    """Share of the mask area that is painted (alpha above half)."""
    alpha = img.getchannel('A').point(lambda v: 255 if v > 128 else 0)
    hit = ImageChops.multiply(alpha, mask.point(lambda v: 255 if v > 128 else 0))
    total = sum(1 for v in mask.getdata() if v > 128) or 1
    return sum(1 for v in hit.getdata() if v) / total


def edge_report(img):
    """Warn when the painting reaches the canvas's left or right edge (a hard cut on screen)."""
    alpha = img.getchannel('A')
    w, h = img.size
    report = []
    for side, x0 in (('left', 0), ('right', w - 6)):
        strip = alpha.crop((x0, 0, x0 + 6, h))
        painted = sum(1 for v in strip.getdata() if v > 40)
        if painted > h * 6 * 0.02:
            report.append('WARNING: paint reaches the %s edge of the canvas; finish the bar end inside it' % side)
    return report


def join_halves(img, m, cut):
    """Cut away everything within cut px of the centre and slide both halves in to meet as one bar.
    The painting is mirror-symmetric, so the two edges that meet match; they are blended over a few
    pixels so the seam does not show."""
    centre = m.w / 2
    feather = 6
    out = Image.new('RGBA', img.size, (0, 0, 0, 0))
    lx = int(round(centre - cut))
    left = img.crop((0, 0, lx, m.h))
    out.alpha_composite(left, (int(round(centre)) - lx, 0))
    rx = int(round(centre + cut))
    right = img.crop((rx - feather, 0, m.w, m.h))
    ramp = Image.new('L', right.size, 255)
    draw = ImageDraw.Draw(ramp)
    for i in range(feather):
        draw.line([(i, 0), (i, m.h)], fill=int(255 * (i + 1) / (feather + 1)))
    right.putalpha(ImageChops.multiply(right.getchannel('A'), ramp))
    out.alpha_composite(right, (int(round(centre)) - feather, 0))
    return out


def narrow_centre(img, m):
    """Shrink the closed bar's centre panel and slide both halves in (layout narrowCentre).

    The panel's edge pieces move with the halves; only a slice of its plain middle is kept, and it
    is blended in over a few pixels so the seams do not show."""
    nc = layout()['narrowCentre']
    if nc['keep'] == 0:
        return join_halves(img, m, nc['plaque'] * m.s)
    shift = (nc['plaque'] - nc['keep']) * m.s
    cut = (nc['plaque'] - nc['edge']) * m.s  # where the halves are cut, from the centre
    middle = (nc['keep'] - nc['edge']) * m.s  # half width of the kept middle slice
    centre = m.w / 2
    feather = 4
    out = Image.new('RGBA', img.size, (0, 0, 0, 0))
    left = img.crop((0, 0, int(round(centre - cut)) + feather, m.h))
    out.alpha_composite(left, (int(round(shift)), 0))
    right_x = int(round(centre + cut)) - feather
    right = img.crop((right_x, 0, m.w, m.h))
    out.alpha_composite(right, (int(round(right_x - shift)), 0))
    x1, x2 = int(round(centre - middle)), int(round(centre + middle))
    mid = img.crop((x1, 0, x2, m.h))
    ramp = Image.new('L', mid.size, 255)
    draw = ImageDraw.Draw(ramp)
    for i in range(feather):
        v = int(255 * (i + 1) / (feather + 1))
        draw.line([(i, 0), (i, m.h)], fill=v)
        draw.line([(mid.width - 1 - i, 0), (mid.width - 1 - i, m.h)], fill=v)
    mid.putalpha(ImageChops.multiply(mid.getchannel('A'), ramp))
    out.alpha_composite(mid, (x1, 0))
    return out


def enforce_bottom(src, out_dir, bed, closed=False, narrow=False):
    lay = layout()
    m = FullMap()
    img = Image.open(src).convert('RGBA').resize((m.w, m.h), Image.LANCZOS)
    mm = lay['minimap']
    report = []

    beds = mask_from(img.size, lambda d: [d.rectangle(m.rect(b['x1'], b['y1'], b['x2'], b['y2']), fill=255) for b in lay['beds']], blur=1.5)
    report.append('beds painted: %.0f%%' % (coverage(img, beds) * 100))
    img = darken(img, beds, bed, 0.55)

    report += edge_report(img)
    if not closed:
        ring = mask_from(img.size, lambda d: d.ellipse(m.circle(mm['x'], mm['y'], ring_outer()), fill=255), blur=0)
        hole = mask_from(img.size, lambda d: d.ellipse(m.circle(mm['x'], mm['y'], mm['hole'] - 0.5), fill=255), blur=1.0)
        ring_only = ImageChops.subtract(ring, hole)
        report.append('minimap ring painted: %.0f%%' % (coverage(img, ring_only) * 100))

    # Everything the bar may cover: the body, a margin above it, and the dome (or plaque) at the centre
    def envelope(d):
        for x in range(-m.half, m.half, 2):
            d.rectangle(m.rect(x, 0, x + 2, body_top(x) + 70), fill=255)
        if closed:
            d.ellipse(m.circle(mm['x'], mm['y'] - 30, CENTER_PLAQUE + 30), fill=255)
        else:
            d.ellipse(m.circle(mm['x'], mm['y'], ring_outer() + 40), fill=255)

    allowed = mask_from(img.size, envelope, blur=6)
    outside = ImageChops.invert(allowed)
    stray = coverage(img, outside.point(lambda v: 255 if v > 200 else 0))
    if stray > 0.01:
        report.append('WARNING: %.1f%% of the clear area was painted; cleared' % (stray * 100))
    img = cut(img, outside)
    if not closed:
        img = cut(img, hole)

    if closed and narrow:
        img = narrow_centre(img, m)
        report.append('centre narrowed for the top right minimap')
    half = m.w // 2
    suffix = '-Closed' if closed else ''
    img.crop((0, 0, half, m.h)).save(os.path.join(out_dir, 'Bottom-Left%s.png' % suffix))
    img.crop((half, 0, m.w, m.h)).save(os.path.join(out_dir, 'Bottom-Right%s.png' % suffix))
    # A full-width copy for checking, kept beside the paintings rather than in the game folder
    img.save(os.path.join(os.path.dirname(os.path.abspath(src)), 'bottom%s_enforced.png' % suffix.lower().replace('-', '_')))
    return report


NARROW = False


def enforce_bottom_closed(src, out_dir, bed):
    return enforce_bottom(src, out_dir, bed, closed=True, narrow=NARROW)


def enforce_minimap(src, out_dir, bed):
    lay = layout()
    bm = BezelMap()
    img = Image.open(src).convert('RGBA').resize((bm.w, bm.h), Image.LANCZOS)
    hole = mask_from(img.size, lambda d: d.ellipse(bm.circle(lay['minimap']['hole'] - 0.5), fill=255), blur=1.0)
    ring = mask_from(img.size, lambda d: d.ellipse(bm.circle(ring_outer()), fill=255), blur=0)
    report = ['bezel ring painted: %.0f%%' % (coverage(img, ImageChops.subtract(ring, hole)) * 100)]
    outside = ImageChops.invert(mask_from(img.size, lambda d: d.ellipse(bm.circle(ring_outer() + 12), fill=255), blur=3))
    img = cut(cut(img, outside), hole)
    img.save(os.path.join(out_dir, 'Minimap.png'))
    return report


def enforce_unitframe(src, out_dir, bed, portrait=True):
    lay = layout()
    pm = PlateMap()
    img = Image.open(src).convert('RGBA').resize((pm.w, pm.h), Image.LANCZOS)
    width, height = lay['frames']['width'], lay['frameHeight']
    spot = lay['plate']['portrait']
    report = []

    def window(d):
        x1, y1 = pm.px(0, 0)
        x2, y2 = pm.px(width, height)
        d.rectangle([x1, y1, x2, y2], fill=255)

    win = mask_from(img.size, window, blur=1.0)
    report.append('plate behind bars painted: %.0f%%' % (coverage(img, win) * 100))
    img = darken(img, win, bed, 0.8)

    if not portrait:
        x, _ = pm.px(NOPORTRAIT_LEFT, 0)
        left = mask_from(img.size, lambda d: d.rectangle([0, 0, x, pm.h], fill=255), blur=1.0)
        img = cut(img, left)
        img.save(os.path.join(out_dir, 'UnitFrame-NoPortrait.png'))
        return report
    cx, cy = pm.px(spot['x'], height / 2)
    r = spot['size'] / 2 * pm.s - 0.5
    ringr = (spot['size'] / 2 + 8) * pm.s
    ring = mask_from(img.size, lambda d: d.ellipse([cx - ringr, cy - ringr, cx + ringr, cy + ringr], fill=255), blur=0)
    hole = mask_from(img.size, lambda d: d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=255), blur=1.0)
    report.append('portrait ring painted: %.0f%%' % (coverage(img, ImageChops.subtract(ring, hole)) * 100))
    img = cut(img, hole)
    img.save(os.path.join(out_dir, 'UnitFrame.png'))
    return report


RING_FILE = 256  # the ring picture's size; drawn at plate scale, centred on the portrait
RING_REACH = 70  # how far from the portrait centre the ring piece keeps paint (px)


def enforce_mount(src, out_dir, bed):
    from mount import FILE

    lay = layout()
    img = Image.open(src).convert('RGBA').resize((FILE, FILE), Image.LANCZOS)
    scale = lay['plate']['file']['width'] / lay['plate']['width']
    r = lay['mount']['size'] / 2 * scale - 0.5
    c = FILE / 2
    hole = mask_from(img.size, lambda d: d.ellipse([c - r, c - r, c + r, c + r], fill=255), blur=1.0)
    report = []
    alpha = img.getchannel('A')
    edge = sum(1 for v in list(alpha.crop((0, 0, FILE, 2)).getdata()) + list(alpha.crop((0, FILE - 2, FILE, FILE)).getdata()) if v > 40)
    edge += sum(1 for v in list(alpha.crop((0, 0, 2, FILE)).getdata()) + list(alpha.crop((FILE - 2, 0, FILE, FILE)).getdata()) if v > 40)
    if edge:
        report.append('WARNING: the mount reaches the canvas edge (%d px)' % edge)
    # The joining piece must reach under the plate's end at the frame's middle
    from mount import MountMap

    mm = MountMap()
    jx, jy = mm.px(2, lay['frameHeight'] / 2)
    if alpha.getpixel((int(jx), int(jy))) < 128:
        report.append('WARNING: the joining piece does not reach under the plate at the middle')
    img = cut(img, hole)
    img.save(os.path.join(out_dir, 'UnitFrame-Mount.png'))
    return report


def ring_piece(out_dir):
    """The portrait ring alone, from the two enforced plates: whatever the portrait plate has that the
    plate without a portrait does not (the ring and its ornaments), near the portrait. Pixels the
    two share are plate body and stay with the plate, which stretches."""
    lay = layout()
    pm = PlateMap()
    spot = lay['plate']['portrait']
    cx, cy = pm.px(spot['x'], lay['frameHeight'] / 2)
    plate = Image.open(os.path.join(out_dir, 'UnitFrame.png')).convert('RGBA')
    bare = Image.open(os.path.join(out_dir, 'UnitFrame-NoPortrait.png')).convert('RGBA')
    diff = ImageChops.difference(plate, bare)
    changed = diff.convert('RGB').convert('L').point(lambda v: 255 if v > 10 else 0)
    changed = ImageChops.lighter(changed, diff.getchannel('A').point(lambda v: 255 if v > 10 else 0))
    near = Image.new('L', plate.size, 0)
    d = ImageDraw.Draw(near)
    d.rectangle([0, 0, cx, plate.height], fill=255)
    d.ellipse([cx - RING_REACH, cy - RING_REACH, cx + RING_REACH, cy + RING_REACH], fill=255)
    keep = ImageChops.multiply(changed, near).filter(ImageFilter.MaxFilter(3)).filter(ImageFilter.GaussianBlur(0.6))
    piece = plate.copy()
    piece.putalpha(ImageChops.multiply(plate.getchannel('A'), keep))
    out = Image.new('RGBA', (RING_FILE, RING_FILE), (0, 0, 0, 0))
    out.alpha_composite(piece, (int(round(RING_FILE / 2 - cx)), int(round(RING_FILE / 2 - cy))))
    return out


def enforce_unitframe_noportrait(src, out_dir, bed):
    return enforce_unitframe(src, out_dir, bed, portrait=False)


def enforce_statusbar(src, out_dir, bed):
    img = Image.open(src).convert('RGBA').resize((512, 32), Image.LANCZOS)
    groove = mask_from(img.size, lambda d: d.rectangle([8, 8, 503, 23], fill=255), blur=1.0)
    img = darken(img, groove, bed, 0.6)
    img.save(os.path.join(out_dir, 'StatusBar.png'))
    # The same groove with its middle cut out, drawn over the fill so the fill shows through
    window = mask_from(img.size, lambda d: d.rectangle([8, 8, 503, 23], fill=255), blur=0.6)
    cut(img, window).save(os.path.join(out_dir, 'StatusBar-Frame.png'))
    return []


def enforce_button(src, out_dir, bed):
    from templates import button_window

    img = Image.open(src).convert('RGBA').resize((128, 128), Image.LANCZOS)
    x1, y1, x2, y2 = button_window()
    window = mask_from(img.size, lambda d: d.rectangle([x1 + 3, y1 + 3, x2 - 3, y2 - 3], fill=255), blur=0.8)
    frame = ImageChops.invert(mask_from(img.size, lambda d: d.rectangle([x1 + 3, y1 + 3, x2 - 3, y2 - 3], fill=255), blur=0))
    report = ['frame painted: %.0f%%' % (coverage(img, frame) * 100)]
    img = cut(img, window)
    img.save(os.path.join(out_dir, 'Button.png'))
    return report


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('painted')
    parser.add_argument('out')
    parser.add_argument('--bed', default='14,14,16', help='dark colour of the button beds and bar window')
    parser.add_argument('--narrow', action='store_true', help='close up the centre of the top right minimap bar (game folders decide from the look)')
    args = parser.parse_args()
    global NARROW
    # A game folder (Themes/<look>/Images) decides from the look itself, so a look that keeps its
    # full centre can never be narrowed by mistake; --narrow is for folders outside the addon
    from layout import ROOT, theme_from_images

    theme = theme_from_images(args.out)
    if theme:
        style = open(os.path.join(ROOT, 'Themes', theme, 'Style.lua'), encoding='utf-8').read()
        NARROW = 'narrowCentre = true' in style
    else:
        NARROW = args.narrow
    bed = tuple(int(v) for v in args.bed.split(','))
    os.makedirs(args.out, exist_ok=True)
    report = []
    pieces = (
        ('bottom.png', enforce_bottom),
        ('bottom_closed.png', enforce_bottom_closed),
        ('minimap.png', enforce_minimap),
        ('unitframe.png', enforce_unitframe),
        ('unitframe_noportrait.png', enforce_unitframe_noportrait),
        ('statusbar.png', enforce_statusbar),
        ('button.png', enforce_button),
        ('portrait_mount.png', enforce_mount),
    )
    for name, fn in pieces:
        path = os.path.join(args.painted, name)
        if os.path.exists(path):
            report += ['%s: %s' % (name, line) for line in fn(path, args.out, bed)]
        else:
            report.append('%s: MISSING' % name)
    if os.path.exists(os.path.join(args.out, 'UnitFrame.png')) and os.path.exists(os.path.join(args.out, 'UnitFrame-NoPortrait.png')):
        ring_piece(args.out).save(os.path.join(args.painted, 'ring_reference.png'))
    print('\n'.join(report))


if __name__ == '__main__':
    main()
