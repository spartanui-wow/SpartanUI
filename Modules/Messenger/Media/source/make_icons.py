"""Messenger icon atlas: 16 white glyphs, 32px cells, 2px strokes, 8x supersampled.

Output: Modules/Messenger/Media/Icons.tga (256x64, RGBA, uncompressed) and
images/chatbox/messenger.png for the SpartanUI chat header.
Glyphs are pure white with alpha so the addon tints them with SetVertexColor.
"""
import math
from PIL import Image, ImageDraw

SS = 8
CELL = 32
S = CELL * SS
W = 2.0 * SS  # stroke width in supersampled px

ORDER = ['close', 'plus', 'gear', 'search', 'pin', 'popout', 'dock', 'more',
         'send', 'chevron', 'mute', 'invite', 'bubble', 'info', 'dot', 'check']


def p(x, y):
    return (x * SS, y * SS)


def line(d, pts, w=W):
    pts = [p(*q) for q in pts]
    d.line(pts, fill=255, width=int(w), joint='curve')
    r = w / 2
    for (x, y) in (pts[0], pts[-1]):
        d.ellipse((x - r, y - r, x + r, y + r), fill=255)


def ring(d, cx, cy, rad, w=W):
    r = rad * SS
    cx, cy = cx * SS, cy * SS
    d.ellipse((cx - r - w / 2, cy - r - w / 2, cx + r + w / 2, cy + r + w / 2), fill=255)
    d.ellipse((cx - r + w / 2, cy - r + w / 2, cx + r - w / 2, cy + r - w / 2), fill=0)


def disc(d, cx, cy, rad):
    r = rad * SS
    d.ellipse((cx * SS - r, cy * SS - r, cx * SS + r, cy * SS + r), fill=255)


def rect(d, x0, y0, x1, y1):
    line(d, [(x0, y0), (x1, y0), (x1, y1), (x0, y1), (x0, y0)])


def draw(name, d):
    if name == 'close':
        line(d, [(10, 10), (22, 22)]); line(d, [(22, 10), (10, 22)])
    elif name == 'plus':
        line(d, [(16, 9), (16, 23)]); line(d, [(9, 16), (23, 16)])
    elif name == 'gear':
        ring(d, 16, 16, 3.2)
        for i in range(8):
            a = i * math.pi / 4
            line(d, [(16 + math.cos(a) * 6.5, 16 + math.sin(a) * 6.5), (16 + math.cos(a) * 9.5, 16 + math.sin(a) * 9.5)], w=2.6 * SS)
        ring(d, 16, 16, 7)
    elif name == 'search':
        ring(d, 14, 14, 5.5); line(d, [(18.2, 18.2), (23, 23)])
    elif name == 'pin':
        line(d, [(12, 8), (20, 8)]); line(d, [(13, 8), (13, 15), (10, 18), (22, 18), (19, 15), (19, 8)]); line(d, [(16, 18), (16, 24)])
    elif name == 'popout':
        line(d, [(15, 9), (9, 9), (9, 23), (23, 23), (23, 17)]); line(d, [(18, 9), (23, 9), (23, 14)]); line(d, [(23, 9), (15, 17)])
    elif name == 'dock':
        line(d, [(15, 9), (9, 9), (9, 23), (23, 23), (23, 17)]); line(d, [(16, 11), (16, 16), (21, 16)]); line(d, [(16, 16), (23, 9)])
    elif name == 'more':
        for x in (10, 16, 22):
            disc(d, x, 16, 1.7)
    elif name == 'send':
        line(d, [(9, 9), (23, 16), (9, 23), (12, 16), (9, 9)]); line(d, [(12, 16), (17, 16)])
    elif name == 'chevron':
        line(d, [(11, 13), (16, 18), (21, 13)])
    elif name == 'mute':
        line(d, [(9, 13), (12, 13), (16, 9), (16, 23), (12, 19), (9, 19), (9, 13)]); line(d, [(19, 13), (24, 19)]); line(d, [(24, 13), (19, 19)])
    elif name == 'invite':
        ring(d, 13, 12, 3.5); line(d, [(7, 23), (7, 21), (9, 18), (13, 17), (17, 18), (19, 21), (19, 23)]); line(d, [(23, 11), (23, 17)]); line(d, [(20, 14), (26, 14)])
    elif name == 'bubble':
        line(d, [(9, 9), (23, 9), (23, 19), (15, 19), (11, 23), (11, 19), (9, 19), (9, 9)])
        for x in (13, 16, 19):
            disc(d, x, 14, 1.2)
    elif name == 'info':
        ring(d, 16, 16, 8); disc(d, 16, 11.8, 1.3); line(d, [(16, 15), (16, 21)])
    elif name == 'dot':
        disc(d, 16, 16, 14)
    elif name == 'check':
        line(d, [(9, 16), (14, 21), (23, 11)])


def render(name):
    mask = Image.new('L', (S, S), 0)
    draw(name, ImageDraw.Draw(mask))
    mask = mask.resize((CELL, CELL), Image.LANCZOS)
    img = Image.new('RGBA', (CELL, CELL), (255, 255, 255, 0))
    img.putalpha(mask)
    return img


atlas = Image.new('RGBA', (CELL * 8, CELL * 2), (255, 255, 255, 0))
for i, n in enumerate(ORDER):
    atlas.paste(render(n), ((i % 8) * CELL, (i // 8) * CELL))
atlas.save(r'C:\code\SpartanUI\Modules\Messenger\Media\Icons.tga')
render('bubble').save(r'C:\code\SpartanUI\images\chatbox\messenger.png')

# Round avatar mask (white disc, soft edge) and ring
for fname, fn in (('Circle', lambda d: disc(d, 32, 32, 31)),):
    m = Image.new('L', (64 * SS, 64 * SS), 0)
    fn(ImageDraw.Draw(m))
    m = m.resize((64, 64), Image.LANCZOS)
    im = Image.new('RGBA', (64, 64), (255, 255, 255, 0))
    im.putalpha(m)
    im.save(rf'C:\code\SpartanUI\Modules\Messenger\Media\{fname}.tga')
print('ok', ORDER)
