from pathlib import Path
from PIL import Image, ImageDraw
root=Path(__file__).resolve().parents[2]/'openspec/databar-art/sources'
paths=sorted(root.glob('*-raw.png'))
sheet=Image.new('RGB',(1024,((len(paths)+1)//2)*360),'#16191f')
for i,p in enumerate(paths):
    x,y=i%2*512,i//2*360
    ImageDraw.Draw(sheet).text((x+5,y+5),p.stem,fill='white')
    im=Image.open(p).convert('RGB'); im.thumbnail((512,340))
    sheet.paste(im,(x,y+20))
sheet.save(root/'raw-contact.png')
print(len(paths),'paintings')
