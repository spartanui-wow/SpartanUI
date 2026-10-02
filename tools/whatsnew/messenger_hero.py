"""The What's new picture for Messenger: a sample conversation window.

python tools/whatsnew/messenger_hero.py

What's new shows a hero picture as a wide band cut from the lower part of a 2:1 image (the lower
44% at full width), so the window is drawn there and the top fades into the window's dark. Drawn at
2x and shrunk. Colors follow Modules/Messenger/UI/Theme.lua and the game's default chat colors.
"""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'images' / 'setup' / 'Hero_Messenger.tga'
FONT = ROOT / 'fonts' / 'Roboto-Medium.ttf'
FONT_BOLD = ROOT / 'fonts' / 'Roboto-Bold.ttf'

S = 2
W, H = 1024 * S, 512 * S


def rgb(c, a=1.0):
    return tuple(int(v * 255) for v in c[:3]) + (int(a * 255),)


WINDOW = (0.047, 0.051, 0.059)
LIST = (0.066, 0.070, 0.082)
HEADER = (0.058, 0.062, 0.072)
TEXT = (0.91, 0.90, 0.88)
MUTED = (0.61, 0.61, 0.64)
WHISPER = (1, 0.5, 1)
BNET = (0, 1, 0.965)
GUILD = (0.25, 1, 0.25)
PARTY = (0.667, 0.667, 1)
ONLINE = (0.30, 0.82, 0.40)


def font(size, bold=False):
    return ImageFont.truetype(str(FONT_BOLD if bold else FONT), size * S)


def main():
    image = Image.new('RGBA', (W, H), rgb((0.02, 0.022, 0.028)))
    draw = ImageDraw.Draw(image, 'RGBA')

    # Soft glow behind the window so it lifts off the background
    glow = Image.new('L', (W, H), 0)
    ImageDraw.Draw(glow).rounded_rectangle((60 * S, 300 * S, 964 * S, 520 * S), radius=30 * S, fill=110)
    glow = glow.filter(ImageFilter.GaussianBlur(40 * S))
    image.alpha_composite(Image.merge('RGBA', (Image.new('L', (W, H), 120), Image.new('L', (W, H), 60), Image.new('L', (W, H), 140), glow)))
    # Pillow blends translucent fills only into an RGB image
    image = image.convert('RGB')
    draw = ImageDraw.Draw(image, 'RGBA')

    # The window, inside the band What's new shows (lower 44%: y 287 to 512)
    left, top, right, bottom = 40 * S, 296 * S, 984 * S, 508 * S
    draw.rounded_rectangle((left, top, right, bottom), radius=8 * S, fill=rgb(WINDOW), outline=rgb((1, 1, 1), 0.14), width=S)
    # Title bar
    draw.rectangle((left + S, top + S, right - S, top + 26 * S), fill=rgb(HEADER))
    draw.text((left + 14 * S, top + 6 * S), 'Messenger', font=font(13, True), fill=rgb(TEXT))
    for i, color in enumerate((MUTED, MUTED, MUTED)):
        x = right - (20 + i * 16) * S
        draw.ellipse((x - 4 * S, top + 9 * S, x + 4 * S, top + 17 * S), fill=rgb(color, 0.55))
    draw.line((left, top + 26 * S, right, top + 26 * S), fill=rgb((1, 1, 1), 0.08), width=S)

    # Conversation list
    listRight = left + 262 * S
    draw.rectangle((left + S, top + 27 * S, listRight, bottom - S), fill=rgb(LIST))
    draw.line((listRight, top + 27 * S, listRight, bottom), fill=rgb((1, 1, 1), 0.08), width=S)
    rows = [
        ('Aelyra', 'sending it now', WHISPER, (0.25, 0.78, 0.92), True, 0),
        ('Brannoc', 'see you at the summoning stone', BNET, (0.78, 0.61, 0.43), False, 2),
        ('Guild', 'Thessa: anyone need a crafter?', GUILD, None, False, 0),
        ('Party', 'Korvin: ready when you are', PARTY, None, False, 5),
    ]
    y = top + 34 * S
    for name, preview, kindColor, classColor, selected, unread in rows:
        rowTop, rowBottom = y, y + 40 * S
        if selected:
            draw.rectangle((left + S, rowTop, listRight - S, rowBottom), fill=rgb((1, 1, 1), 0.08))
            draw.rectangle((left + S, rowTop, left + 3 * S, rowBottom), fill=rgb(kindColor))
        cx, cy = left + 26 * S, rowTop + 20 * S
        if classColor:
            draw.ellipse((cx - 14 * S, cy - 14 * S, cx + 14 * S, cy + 14 * S), fill=rgb(classColor, 0.9))
            draw.text((cx, cy), name[0], font=font(14, True), fill=rgb((0.05, 0.05, 0.06)), anchor='mm')
            draw.ellipse((cx + 7 * S, cy + 7 * S, cx + 14 * S, cy + 14 * S), fill=rgb(ONLINE), outline=rgb(LIST), width=2 * S)
        else:
            draw.rounded_rectangle((cx - 14 * S, cy - 14 * S, cx + 14 * S, cy + 14 * S), radius=7 * S, fill=rgb(kindColor, 0.22))
            draw.text((cx, cy), '#', font=font(15, True), fill=rgb(kindColor), anchor='mm')
        draw.text((left + 48 * S, rowTop + 5 * S), name, font=font(13, True), fill=rgb(kindColor if not classColor else TEXT))
        draw.text((left + 48 * S, rowTop + 22 * S), preview, font=font(11), fill=rgb(MUTED))
        draw.text((listRight - 12 * S, rowTop + 6 * S), '9:4' + str(len(name) % 10), font=font(10), fill=rgb(MUTED, 0.8), anchor='ra')
        if unread:
            pill = (listRight - 30 * S, rowTop + 22 * S, listRight - 12 * S, rowTop + 36 * S)
            draw.rounded_rectangle(pill, radius=7 * S, fill=rgb((1, 1, 1), 0.92))
            draw.text(((pill[0] + pill[2]) / 2, (pill[1] + pill[3]) / 2), str(unread), font=font(10, True), fill=rgb((0.04, 0.04, 0.05)), anchor='mm')
        y = rowBottom + 4 * S

    # The open conversation
    chatLeft = listRight + 18 * S
    draw.text((chatLeft, top + 34 * S), 'Aelyra', font=font(15, True), fill=rgb(WHISPER))
    draw.text((chatLeft + 62 * S, top + 37 * S), 'Level 80 Mage - Dornogal', font=font(11), fill=rgb(MUTED))
    draw.line((listRight, top + 58 * S, right, top + 58 * S), fill=rgb((1, 1, 1), 0.08), width=S)

    def bubble(text, y, mine):
        f = font(12)
        width = draw.textlength(text, font=f) + 24 * S
        if mine:
            box = (right - 20 * S - width, y, right - 20 * S, y + 24 * S)
            draw.rounded_rectangle(box, radius=10 * S, fill=rgb(WHISPER, 0.22))
        else:
            box = (chatLeft, y, chatLeft + width, y + 24 * S)
            draw.rounded_rectangle(box, radius=10 * S, fill=rgb((1, 1, 1), 0.07))
        draw.text((box[0] + 12 * S, y + 12 * S), text, font=f, fill=rgb(TEXT), anchor='lm')

    bubble('are you still up for the dungeon tonight?', top + 68 * S, False)
    bubble('yes! invite me when you are ready', top + 98 * S, True)
    bubble('sending it now', top + 128 * S, False)

    # Composer
    composer = (chatLeft, bottom - 34 * S, right - 14 * S, bottom - 10 * S)
    draw.rounded_rectangle(composer, radius=6 * S, fill=rgb((0, 0, 0), 0.35), outline=rgb(WHISPER, 0.5), width=S)
    draw.text((composer[0] + 12 * S, (composer[1] + composer[3]) / 2), 'Whisper Aelyra', font=font(12), fill=rgb(WHISPER, 0.75), anchor='lm')

    out = image.resize((1024, 512), Image.LANCZOS).convert('RGBA')
    out.save(OUT)
    print('written', OUT)


if __name__ == '__main__':
    main()
