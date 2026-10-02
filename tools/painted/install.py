"""Install a painted look's colours: its window kit in Core/Handlers/WindowKits.lua and its accent
and frame colours in Themes/<theme>/Style.lua. Running it again replaces the earlier install.

python install.py <colors.json> <theme_id> <kit_id> <display name>
"""

import io
import os
import re
import subprocess
import sys
from contextlib import redirect_stdout

import register

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
KITS = os.path.join(ROOT, 'Core', 'Handlers', 'WindowKits.lua')

HELPER = """---A painted look's kit: the shared frame pieces plus the crest mounted on the frame's top edge
---@param folder string
---@param crest? { width: number, height: number, overlap: number } a crest of another shape
local function LookAssets(folder, crest)
	local assets = PaintedAssets(folder)
	crest = crest or { width = 128, height = 64, overlap = 20 }
	assets.crest = { texture = ROOT .. folder .. '\\\\crest.png', width = crest.width, height = crest.height, overlap = crest.overlap }
	return assets
end

"""
ANCHOR = '\t-- Digital has no painted art: 1px light lines over deep blue'


def main():
    path, theme, kit, name = sys.argv[1:5]
    buf = io.StringIO()
    sys.argv = ['register.py', path, theme, kit, name]
    with redirect_stdout(buf):
        register.main()
    out = buf.getvalue()
    block, style = out.split('\n\n-- Themes/')
    block = block.rstrip() + '\n'

    src = open(KITS, encoding='utf-8').read()
    if 'local function LookAssets' not in src:
        marker = '-- Painted kits keep their title and footer bars inside the frame\'s beam'
        assert src.count(marker) == 1
        src = src.replace(marker, HELPER + marker)
    start = "\t-- Painted look: %s\n" % kit
    pattern = re.compile(re.escape(start) + r".*?\n\t\}\)\n\n", re.S)
    src = pattern.sub('', src)
    assert src.count(ANCHOR) == 1
    src = src.replace(ANCHOR, start + block + '\n' + ANCHOR)
    open(KITS, 'w', encoding='utf-8', newline='\n').write(src)

    values = dict(re.findall(r'\t(\w+) = (\{[^}]+\})', style))
    theme_file = os.path.join(ROOT, 'Themes', theme, 'Style.lua')
    t = open(theme_file, encoding='utf-8').read()
    t = re.sub(r'accent = \{[^}]+\}', 'accent = ' + values['accent'], t, count=1)
    t = re.sub(r'frameBg = \{[^}]+\}', 'frameBg = ' + values['frameBg'], t, count=1)
    t = re.sub(r'frameBorder = \{[^}]+\}', 'frameBorder = ' + values['frameBorder'], t, count=1)
    open(theme_file, 'w', encoding='utf-8', newline='\n').write(t)
    subprocess.run(['stylua', KITS, theme_file], check=True)
    print('installed', kit, 'and', theme)


if __name__ == '__main__':
    main()
