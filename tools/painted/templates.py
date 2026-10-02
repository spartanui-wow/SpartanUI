"""Guide pictures for painting a painted look, drawn from the layout in Themes/Painted.lua.

python templates.py <out_dir>

Writes:
- template_bottom.png  2048 x 512  the whole bottom bar (split into the two 1024 x 512 halves later)
- template_unitframe.png 512 x 128 the plate behind the player frame (the target uses it mirrored)
- template_statusbar.png 512 x 32  the experience / reputation bar groove
- template_button.png  128 x 128   the frame drawn around every action button (the action bars scale it)
- template_bottom_closed.png 2048 x 512 the bar for the "Minimap top right" variant: no minimap opening
- template_minimap.png 512 x 512   the minimap bezel for the "Minimap top right" variant
- template_unitframe_noportrait.png 512 x 128 the plate for frames with the portrait turned off
- template_legend.txt  what each colour means
"""

import os
import sys

from PIL import Image, ImageDraw

from layout import layout, PlateMap

BED = (40, 110, 230, 170)
BUTTON = (120, 170, 255, 200)
HOLE = (230, 40, 40, 220)
RING = (255, 150, 30, 120)
STATUS = (250, 220, 40, 200)
BODY = (200, 200, 200, 70)
WINDOW = (40, 110, 230, 170)
NAME = (250, 220, 40, 150)
CLEAR = (255, 255, 255, 0)


class FullMap:
    """Art units <-> pixels of the whole bottom bar picture (both halves, 2048 x 512)."""

    def __init__(self):
        art = layout()['art']
        self.w = art['file']['width'] * 2
        self.h = art['file']['height']
        self.s = art['file']['width'] / art['halfWidth']
        self.half = art['halfWidth']

    def px(self, x, y):
        return (x + self.half) * self.s, self.h - y * self.s

    def rect(self, x1, y1, x2, y2):
        ax, ay = self.px(x1, y2)
        bx, by = self.px(x2, y1)
        return [ax, ay, bx, by]

    def circle(self, x, y, r):
        cx, cy = self.px(x, y)
        r = r * self.s
        return [cx - r, cy - r, cx + r, cy + r]


def ring_outer():
    """How far the minimap ring may reach, in art units."""
    return layout()['minimap']['hole'] + 32


def body_top(x):
    """Suggested top edge of the bar body at art x (the painting may vary, keep it near this)."""
    ax = abs(x)
    if ax >= 554:
        return 140
    return 128


def bottom_template(path):
    lay = layout()
    m = FullMap()
    img = Image.new('RGBA', (m.w, m.h), CLEAR)
    d = ImageDraw.Draw(img)
    # Suggested body: the bar across the bottom and the dome around the minimap
    for x in range(-m.half, m.half, 4):
        d.rectangle(m.rect(x, 0, x + 4, body_top(x)), fill=BODY)
    mm = lay['minimap']
    d.ellipse(m.circle(mm['x'], mm['y'], ring_outer() + 10), fill=BODY)
    d.ellipse(m.circle(mm['x'], mm['y'], ring_outer()), fill=RING)
    d.ellipse(m.circle(mm['x'], mm['y'], mm['hole']), fill=HOLE)
    # Bar areas only: players resize their buttons, so the art never draws single button sockets
    for bed in lay['beds']:
        d.rectangle(m.rect(bed['x1'], bed['y1'], bed['x2'], bed['y2']), fill=BED)
    for bar in lay['statusBars'].values():
        d.rectangle(
            m.rect(bar['x'] - bar['width'] / 2, bar['y'] - bar['height'] / 2, bar['x'] + bar['width'] / 2, bar['y'] + bar['height'] / 2),
            fill=STATUS,
        )
    img.save(path)


CENTER_PLAQUE = 104  # how far the closed bar's centre piece may reach (art units from the centre spot)


def bottom_closed_template(path):
    lay = layout()
    m = FullMap()
    img = Image.new('RGBA', (m.w, m.h), CLEAR)
    d = ImageDraw.Draw(img)
    for x in range(-m.half, m.half, 4):
        d.rectangle(m.rect(x, 0, x + 4, body_top(x)), fill=BODY)
    mm = lay['minimap']
    # The centre is closed: a low plaque or emblem may rise here, but no opening
    d.ellipse(m.circle(mm['x'], mm['y'] - 30, CENTER_PLAQUE), fill=BODY)
    for bed in lay['beds']:
        d.rectangle(m.rect(bed['x1'], bed['y1'], bed['x2'], bed['y2']), fill=BED)
    for bar in lay['statusBars'].values():
        d.rectangle(
            m.rect(bar['x'] - bar['width'] / 2, bar['y'] - bar['height'] / 2, bar['x'] + bar['width'] / 2, bar['y'] + bar['height'] / 2),
            fill=STATUS,
        )
    img.save(path)


class BezelMap:
    """Art units (centre origin, y up) <-> pixels of the corner minimap bezel picture."""

    def __init__(self):
        corner = layout()['cornerMinimap']
        self.w = self.h = corner['file']
        self.s = corner['file'] / corner['bezel']

    def circle(self, r):
        c = self.w / 2
        r = r * self.s
        return [c - r, c - r, c + r, c + r]


def minimap_template(path):
    lay = layout()
    bm = BezelMap()
    img = Image.new('RGBA', (bm.w, bm.h), CLEAR)
    d = ImageDraw.Draw(img)
    d.ellipse(bm.circle(ring_outer() + 8), fill=BODY)
    d.ellipse(bm.circle(ring_outer()), fill=RING)
    d.ellipse(bm.circle(lay['minimap']['hole']), fill=HOLE)
    img.save(path)


def unitframe_template(path, portrait=True):
    lay = layout()
    plate = lay['plate']
    pm = PlateMap()
    img = Image.new('RGBA', (pm.w, pm.h), CLEAR)
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, pm.w - 1, pm.h - 1], fill=BODY)
    width, height = lay['frames']['width'], lay['frameHeight']
    # Name strip above the bars
    x1, y1 = pm.px(0, -16)
    x2, y2 = pm.px(width, -2)
    d.rectangle([x1, y1, x2, y2], fill=NAME)
    # The bar window: the frame draws its own bars here
    x1, y1 = pm.px(0, 0)
    x2, y2 = pm.px(width, height)
    d.rectangle([x1, y1, x2, y2], fill=WINDOW)
    if portrait:
        # Portrait and its ring
        spot = plate['portrait']
        cx, cy = pm.px(spot['x'], height / 2)
        r = spot['size'] / 2 * pm.s
        ring = (spot['size'] / 2 + 8) * pm.s
        d.ellipse([cx - ring, cy - ring, cx + ring, cy + ring], fill=RING)
        d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=HOLE)
    else:
        # No portrait: the plate ends just left of the bars, and left of that stays transparent
        x, _ = pm.px(NOPORTRAIT_LEFT, 0)
        d.rectangle([0, 0, x, pm.h - 1], fill=CLEAR)
    img.save(path)


NOPORTRAIT_LEFT = -14  # where the plate without a portrait ends, in frame units from the bars' left edge


BUTTON_FRAME = layout()['buttonFrame']  # the button frame's size relative to the button


def button_window():
    """The icon window of the 128 x 128 button frame picture, in pixels."""
    inner = 128 / BUTTON_FRAME
    pad = (128 - inner) / 2
    return pad, pad, 128 - pad, 128 - pad


def button_template(path):
    img = Image.new('RGBA', (128, 128), CLEAR)
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, 127, 127], fill=RING)
    x1, y1, x2, y2 = button_window()
    d.rectangle([x1 + 3, y1 + 3, x2 - 3, y2 - 3], fill=HOLE)
    img.save(path)


def statusbar_template(path):
    img = Image.new('RGBA', (512, 32), CLEAR)
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, 511, 31], fill=STATUS)
    d.rectangle([8, 8, 503, 23], fill=WINDOW)
    img.save(path)


LEGEND = """Colours in the templates (all templates are drawn from Themes/Painted.lua):

Bottom bar (2048 x 512, the whole bar; it is cut into two 1024 x 512 halves):
- light grey   suggested bar body; paint the bar's own silhouette near this
- blue         bar areas: dark, flat recessed trays the action bars sit on. Do NOT paint single
               button sockets or dividers: players change button size and count, and every button
               gets its own frame from the button frame picture below.
- orange       the minimap ring: paint the ring/bezel here
- red          the minimap hole: cut to fully transparent by the enforcer
- yellow       experience / reputation bars: keep calm, a groove is fine
- transparent  must stay transparent (the game world shows here)

Unit frame plate (512 x 128, player side, portrait on the left; the target uses it mirrored):
- light grey   plate area
- blue         the frame's bar window (health, power, cast bar draw here): filled dark by the enforcer
- red          portrait hole: cut to transparent by the enforcer
- orange       portrait ring
- yellow       name strip: keep calm so the name reads

Status bar (512 x 32): yellow is the groove frame, blue is where the bar fill draws.

Closed bar (2048 x 512, the "Minimap top right" variant): the same bar, with the centre closed. A low
plaque or emblem may rise in the light grey bump in the middle, but there is no opening and no ring.
It must match bottom.png exactly everywhere else, so build it from the same painting.

Minimap bezel (512 x 512, the "Minimap top right" variant, drawn at the top right of the screen):
- orange       the bezel ring: paint it to match the bar's minimap ring
- red          the map: cut to transparent by the enforcer
- outside the light grey disc stays transparent

Plate without portrait (512 x 128): the same plate as unitframe.png with the portrait and its ring
removed; the plate ends just left of the bars with a finished edge, and the left part stays empty.

Button frame (128 x 128): drawn around every action button and scaled with it.
- orange       the frame: a slim border in the look's material, a few pixels wide
- red          the icon window: cut to transparent by the enforcer (the frame may overlap the
               icon edge by about 3 pixels)
Paint one clean square frame; no number, glow or decoration inside the window.
"""


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else '.'
    os.makedirs(out, exist_ok=True)
    bottom_template(os.path.join(out, 'template_bottom.png'))
    unitframe_template(os.path.join(out, 'template_unitframe.png'))
    statusbar_template(os.path.join(out, 'template_statusbar.png'))
    button_template(os.path.join(out, 'template_button.png'))
    bottom_closed_template(os.path.join(out, 'template_bottom_closed.png'))
    minimap_template(os.path.join(out, 'template_minimap.png'))
    unitframe_template(os.path.join(out, 'template_unitframe_noportrait.png'), portrait=False)
    with open(os.path.join(out, 'template_legend.txt'), 'w', encoding='utf-8') as f:
        f.write(LEGEND)
    print('templates written to', out)


if __name__ == '__main__':
    main()
