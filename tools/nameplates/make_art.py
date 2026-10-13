"""Deterministic white-on-alpha nameplate art. Python 3, Pillow and numpy.

Run from any directory: python tools/nameplates/make_art.py
Catalog sizes, draw modes and source-pixel slice margins are in art.json.
TGA type 2, BGRA32, top-left origin, eight alpha bits, no RLE or timestamps.
"""
from pathlib import Path
import json
import struct
import numpy as np
from PIL import Image

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
MEDIA = ROOT / "Modules/Nameplates/Media"
CATALOG = json.loads((HERE / "art.json").read_text(encoding="utf-8"))


def grid(w, h):
    y, x = np.mgrid[:h, :w]
    return x + 0.5, y + 0.5


def rounded(x, y, w, h, inset=0, radius=0):
    qx = np.abs(x - w / 2) - (w / 2 - inset - radius)
    qy = np.abs(y - h / 2) - (h / 2 - inset - radius)
    return np.hypot(np.maximum(qx, 0), np.maximum(qy, 0)) + np.minimum(np.maximum(qx, qy), 0) - radius


def cover(distance):
    return np.clip(0.5 - distance, 0, 1)


def polygon(x, y, points):
    inside = np.zeros(x.shape, dtype=bool)
    distance = np.full(x.shape, 1e6)
    for i, (ax, ay) in enumerate(points):
        bx, by = points[(i + 1) % len(points)]
        dx, dy = bx - ax, by - ay
        t = np.clip(((x - ax) * dx + (y - ay) * dy) / (dx * dx + dy * dy), 0, 1)
        distance = np.minimum(distance, np.hypot(x - ax - t * dx, y - ay - t * dy))
        if by != ay:
            inside ^= ((ay > y) != (by > y)) & (x < (bx - ax) * (y - ay) / (by - ay) + ax)
    return cover(np.where(inside, -distance, distance))


def recipe(key):
    if key.startswith("bar") or key in ("absorb", "healAbsorb", "roundedBackground", "roundedMask", "roundedFrame"):
        w, h = 256, 32
    elif key in ("arrows", "doubleArrows"):
        w, h = (32 if key == "doubleArrows" else 16), 32
    elif key == "sideBars":
        w, h = 8, 32
    elif key == "underline":
        w, h = 256, 8
    elif key.startswith("spark"):
        w, h = 16, 64
    elif key.startswith("glow") or key == "glow" or key == "highlightGlow":
        w, h = 128, 64
    elif key == "brackets" or key.startswith("border") or key == "roundedFrame" or key == "highlightGlow":
        w, h = 64, 32
    else:
        w, h = 64, 64
    x, y = grid(w, h)
    u, v = x / w, y / h
    a = np.zeros((h, w))
    if key.startswith("bar"):
        name = key[3:]
        a[:] = 1
        if name == "SoftGradient":
            a = 0.65 + 0.35 * (1 - v)
        elif name == "Glossy":
            a = np.where(v < 0.45, 0.82 + 0.18 * (1 - v / 0.45), 0.64 + 0.12 * (1 - v))
        elif name == "Striped":
            a = 0.8 + 0.13 * (np.mod(x + y, 24) < 10)
        elif name == "TopLine":
            a = np.where(y < 4, 1, 0.62)
        elif name == "Matte":
            a = 0.84 + 0.04 * np.cos((v - 0.5) * np.pi)
        elif name == "Inset":
            a = 0.62 + 0.32 * np.clip(np.minimum(y, h - y) / 7, 0, 1)
        elif name == "Smooth":
            a = 0.74 + 0.24 * np.sin(np.pi * v)
        elif name == "Rounded":
            a = cover(rounded(x, y, w, h, radius=8)) * (0.78 + 0.2 * (1 - v))
    elif key == "absorb":
        a = np.where(np.mod(x + y, 20) < 7, 0.85, 0.16)
    elif key == "healAbsorb":
        a = np.where(np.mod(x - y, 20) < 4, 0.9, 0.38) * (0.8 + 0.2 * (1 - v))
    elif key in ("arrows", "doubleArrows"):
        offsets = [0, 16] if key == "doubleArrows" else [0]
        for i, off in enumerate(offsets):
            shape = polygon(x, y, [(off+1,2),(off+15,16),(off+1,30),(off+1,23),(off+8,16),(off+1,9)])
            a = np.maximum(a, shape * (0.55 if len(offsets) == 2 and i == 0 else 1))
    elif key == "sideBars":
        a = ((x >= 2) & (x < 6)).astype(float)
    elif key == "underline":
        a = np.clip(np.minimum(u, 1-u) / 0.16, 0, 1) * np.where(y < 4, 1, 0.25)
    elif key == "brackets":
        a = (((x < 2) | (x >= w-2)) | (((y < 2) | (y >= h-2)) & ((x < 8) | (x >= w-8)))).astype(float)
    elif key.startswith("border"):
        thickness = 4 if key == "borderThick" else 2
        edge = np.minimum.reduce([x, w-x, y, h-y])
        a = (edge < thickness).astype(float)
        if key == "borderShadow":
            a = np.where(edge < 2, 0.8, 0.35 * np.exp(-np.maximum(edge-2, 0) / 2)) * (edge < 8)
        elif key == "borderBeveled":
            a = np.where(edge < 2, np.where((y < 2) | (x < 2), 1, 0.38), np.where(edge < 4, 0.3, 0))
    elif key.startswith("glow") or key == "highlightGlow":
        name = "soft" if key in ("glow", "highlightGlow") else key[4:]
        inset = 6 if name == "pandemic" or key == "highlightGlow" else 12
        d = rounded(x, y, w, h, inset=inset, radius=4)
        sigma = {"soft": 4.0, "important": 3.0, "purge": 2.0, "pandemic": 1.3, "threat": 2.5}[name]
        if key == "highlightGlow":
            sigma = 2.0
        margin = 8 if name == "pandemic" or key == "highlightGlow" else 16
        fade = np.clip(1 + d / (margin - inset), 0, 1)
        fade = fade * fade * (3 - 2 * fade)
        a = fade * np.exp(-0.5 * (d / sigma) ** 2) * np.clip((np.minimum.reduce([x,w-x,y,h-y])-0.5)/2,0,1)
        # The stretchable center is completely empty, including under text.
        margin = 8 if name == "pandemic" or key == "highlightGlow" else 16
        a = np.where((x >= margin) & (x <= w-margin) & (y >= margin) & (y <= h-margin), 0, a)
    elif key.startswith("aura") or key == "roundedFrame":
        radius = 8 if key in ("auraRounded", "roundedFrame") else 0
        thickness = 4 if key == "auraThick" else 2
        a = cover(rounded(x,y,w,h,radius=radius)) - cover(rounded(x,y,w,h,inset=thickness,radius=max(0,radius-thickness)))
    elif key in ("roundedBackground", "roundedMask"):
        a = cover(rounded(x,y,w,h,radius=8))
    elif key.startswith("spark"):
        a = np.exp(-0.5 * ((x-w/2)/(0.85 if key == "sparkFine" else 2.2))**2) * np.sin(np.pi*v)**0.4
    elif key == "pip":
        a = cover(np.hypot(x-w/2,y-h/2)-w*0.42)
    elif key == "focus":
        a = polygon(x,y,[(10,14),(54,14),(32,42)])
        a = np.maximum(a, ((x>=28)&(x<36)&(y>=46)&(y<54)).astype(float))
    elif key == "star":
        angles = np.arange(10)*np.pi/5 - np.pi/2
        radii = np.where(np.arange(10)%2==0,28,12)
        a = polygon(x,y,list(zip(32+np.cos(angles)*radii,32+np.sin(angles)*radii)))
    elif key == "shield":
        a = polygon(x,y,[(8,8),(32,3),(56,8),(53,39),(43,52),(32,61),(21,52),(11,39)])
        inner = polygon(x,y,[(15,14),(32,10),(49,14),(46,36),(39,46),(32,52),(25,46),(18,36)])
        a = np.maximum(a-inner, ((x>=29)&(x<35)&(y>=17)&(y<39)).astype(float))
    elif key == "quest":
        a = polygon(x,y,[(25,5),(39,5),(37,40),(27,40)])
        a = np.maximum(a,cover(np.hypot(x-32,y-52)-6))
    elif key == "boss":
        a = cover(rounded(x,y,w,h,inset=9,radius=20))
        eyes = np.maximum(cover(np.hypot(x-23,y-28)-6),cover(np.hypot(x-41,y-28)-6))
        a *= 1-eyes
        a *= 1-(((x>27)&(x<37)&(y>39)&(y<54)).astype(float))
    elif key.startswith("faction"):
        points = ([(32,4),(55,20),(49,49),(32,60),(15,49),(9,20)] if key == "factionAlliance" else [(32,4),(57,29),(45,29),(50,57),(32,47),(14,57),(19,29),(7,29)])
        a = polygon(x,y,points)
        a *= 1-polygon(x,y,[(32,19),(41,31),(32,43),(23,31)])
    else:
        raise ValueError(key)
    alpha = np.floor(np.clip(a, 0, 1)*255 + 0.5).astype(np.uint8)
    pixels = np.full((h, w, 4), 255, dtype=np.uint8)
    pixels[:,:,3] = alpha
    return Image.fromarray(pixels)


def save_tga(image, path):
    w, h = image.size
    assert w & (w-1) == 0 and h & (h-1) == 0
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, w, h, 32, 0x28)
    path.write_bytes(header + image.tobytes("raw", "BGRA"))


def main():
    MEDIA.mkdir(parents=True, exist_ok=True)
    seen = set()
    for item in CATALOG:
        if item["file"] not in seen:
            save_tga(recipe(item["recipe"]), MEDIA / item["file"])
            seen.add(item["file"])
    return len(seen)


if __name__ == "__main__":
    main()
