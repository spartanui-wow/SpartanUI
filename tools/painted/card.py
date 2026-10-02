"""Setup card (512 x 256) for a painted look, cut from a preview render.

python card.py <theme_images_dir> <out.tga> [--background kit_backdrop.png] [--accent R,G,B]

The card shows the bottom of the screen: the bar, minimap and both unit frames, over the
look's own window backdrop so it carries the look's mood.
"""

import argparse
import os
import tempfile

from PIL import Image

from preview import render


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('images')
    parser.add_argument('out')
    parser.add_argument('--background')
    parser.add_argument('--accent', default='150,110,230')
    args = parser.parse_args()
    accent = tuple(int(v) for v in args.accent.split(','))
    with tempfile.TemporaryDirectory() as tmp:
        shot = os.path.join(tmp, 'shot.png')
        render(args.images, shot, (2560, 1440), args.background, accent)
        img = Image.open(shot)
        # The interesting part: the bar and the frames above it, as a 2:1 crop
        width = 1900
        height = width // 2
        left = (img.width - width) // 2
        top = img.height - height
        card = img.crop((left, top, left + width, img.height)).resize((512, 256), Image.LANCZOS)
        # Setup cards load without a file extension, which the game only fills in for TGA and BLP
        card.convert('RGBA').save(args.out, format='TGA' if args.out.lower().endswith('.tga') else None)
    print(args.out)


if __name__ == '__main__':
    main()
