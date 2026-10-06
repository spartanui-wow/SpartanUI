from pathlib import Path
from PIL import Image, ImageOps, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'openspec/databar-art/sources'
OUT.mkdir(parents=True, exist_ok=True)
names = ['Arcane','ArcaneRed','Classic','Digital','Fel','Tribal','War_Alliance','War','Midnight','Atlas','Boughs','Meridian']
sheet = Image.new('RGB', (1200, 1800), '#16191f')
d = ImageDraw.Draw(sheet)
for i, name in enumerate(names):
    folder = {'ArcaneRed':'Arcane','War_Alliance':'War'}.get(name,name)
    paths = list((ROOT/'images/setup').glob('Style_'+name+'.tga'))
    paths += list((ROOT/'images/setup').glob('Style_Frames_'+name+'.tga'))
    candidates = list((ROOT/'Themes'/folder/'Images').glob('*'))
    candidates = [p for p in candidates if any(s in p.stem.lower() for s in ['bottom-left','base_bar_left','art_left','art-left','base-left2','bottomart','artwork'])]
    paths += candidates[:1]
    x, y = (i%2)*600, (i//2)*300
    d.text((x+12,y+8),name,fill='white')
    for j,p in enumerate(paths[:3]):
        im=Image.open(p).convert('RGBA')
        im=ImageOps.contain(im,(570,82))
        sheet.paste(im,(x+15,y+30+j*88),im)
sheet.save(OUT/'references.png')
print(OUT/'references.png')
