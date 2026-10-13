"""Tinted art contact sheet at native game size (1x) and authored size (2x).
Run: python tools/nameplates/preview_art.py
Nine-slice margins are source pixels at 2x; corners are preserved in previews.
"""
from pathlib import Path
import json
import math
from PIL import Image, ImageDraw, ImageFont

HERE = Path(__file__).resolve().parent
MEDIA = HERE.parents[1] / "Modules/Nameplates/Media"
CATALOG = json.loads((HERE / "art.json").read_text(encoding="utf-8"))
OUTPUT = HERE / "out/contact.png"


def sliced(image, size, margins, scale):
    w, h = image.size
    dw, dh = size
    l, t, r, b = margins
    factor = min(scale/2, dw/(l+r), dh/(t+b))
    dl, dt, dr, db = [round(n*factor) for n in margins]
    sx, sy = [0,l,w-r,w], [0,t,h-b,h]
    dx, dy = [0,dl,dw-dr,dw], [0,dt,dh-db,dh]
    out = Image.new("RGBA", size)
    for i in range(3):
        for j in range(3):
            tw, th = dx[i+1]-dx[i], dy[j+1]-dy[j]
            if tw > 0 and th > 0:
                tile = image.crop((sx[i],sy[j],sx[i+1],sy[j+1]))
                tile = tile.resize((tw,th), Image.Resampling.LANCZOS)
                out.paste(tile,(dx[i],dy[j]))
    return out


def picture(entry, scale):
    image = Image.open(MEDIA / entry["file"]).convert("RGBA")
    size = tuple(n*scale for n in entry["preview"])
    if entry["draw"] in ("sliced","glow") and entry.get("margins"):
        image = sliced(image,size,entry["margins"],scale)
    else:
        image = image.resize(size, Image.Resampling.LANCZOS)
    tint = tuple(round(c*255) for c in entry["tint"][:3])
    colored = Image.new("RGBA", image.size, tint+(255,))
    colored.putalpha(image.getchannel("A"))
    return colored


def main():
    columns, cw, ch, header = 3, 584, 178, 92
    sheet = Image.new("RGB", (columns*cw+32, math.ceil(len(CATALOG)/columns)*ch+header+16), (14,19,27))
    draw = ImageDraw.Draw(sheet)
    font_path = Path("C:/Windows/Fonts/segoeui.ttf")
    font = ImageFont.truetype(str(font_path),14) if font_path.exists() else ImageFont.load_default()
    title = ImageFont.truetype(str(font_path),24) if font_path.exists() else font
    draw.text((24,16),"NAMEPLATE ART / 42 TEXTURES",font=title,fill=(224,235,245))
    draw.text((24,51),"42 aliases | White + alpha | Left: dark / Right: light | Upper: 1x / Lower: 2x",font=font,fill=(150,172,192))
    for index, entry in enumerate(CATALOG):
        x, y = 16+index%columns*cw, header+index//columns*ch
        draw.rounded_rectangle((x,y,x+cw-12,y+ch-10),radius=8,fill=(27,35,47))
        draw.text((x+12,y+8),entry["alias"]+"  /  "+entry["name"].replace("Nameplates ",""),font=font,fill=(225,235,245))
        for scale in (1,2):
            pic = picture(entry,scale)
            for light in (False,True):
                tx, ty = x+10+int(light)*278, y+34+(scale-1)*64
                bg = (225,230,237,255) if light else (9,14,22,255)
                tile = Image.new("RGBA", (274,60), bg)
                tile.alpha_composite(pic,((274-pic.width)//2,(60-pic.height)//2))
                sheet.paste(tile.convert("RGB"),(tx,ty))
        dimensions = Image.open(MEDIA/entry["file"]).size
        detail = "%dx%d | %s" % (*dimensions,entry["draw"])
        if entry.get("margins"):
            detail += " | slice " + "/".join(map(str,entry["margins"]))
        draw.text((x+12,y+158),detail,font=font,fill=(145,167,190))
    OUTPUT.parent.mkdir(parents=True,exist_ok=True)
    sheet.save(OUTPUT, optimize=False)


if __name__ == "__main__":
    main()
