"""Build deterministic DataBar assets from preserved, original generated paintings."""
import json, math, random
from pathlib import Path
from PIL import Image, ImageOps, ImageDraw, ImageFont, ImageFilter, ImageStat

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'openspec/databar-art'
SRC = OUT / 'sources'
FONT = ROOT / 'fonts/RobotoCondensed-Bold.ttf'
RESAMPLE = Image.Resampling.LANCZOS

def mix(a,b,t):
    return tuple(round(x*(1-t)+y*t) for x,y in zip(a,b))

def luminance(rgb):
    c=[v/12.92 if v<=.04045 else ((v+.055)/1.055)**2.4 for v in rgb]
    return sum(v*w for v,w in zip(c,[.2126,.7152,.0722]))

def contrast(c,bg):
    a,b=sorted([luminance(c),luminance(bg)])
    return (b+.05)/(a+.05)

def backdrop(w,h,accent):
    im=Image.new('RGB',(w,h),'#111820'); d=ImageDraw.Draw(im)
    rng=random.Random(714)
    for layer in range(4):
        color=(14+layer*3,21+layer*2,24+layer*2)
        pts=[(0,h)]+[(x,int(h*(.22+layer*.13)+rng.uniform(-h*.15,h*.15))) for x in range(0,w+70,70)]+[(w,h)]
        d.polygon(pts,fill=color)
    for x in range(30,w,150):
        y=rng.randint(h//4,max(h//4,h//2)); d.rectangle((x,y,x+22,h),fill=(16,22,25))
        d.polygon([(x-18,y),(x+11,y-35),(x+40,y)],fill=(18,25,27))
    return im.filter(ImageFilter.GaussianBlur(max(3,h/35)))

def assemble(tile,cap,w,h):
    cw=round(cap.width*h/64); tw=round(tile.width*h/64)
    tile=tile.resize((tw,h),RESAMPLE); cap=cap.resize((cw,h),RESAMPLE)
    im=Image.new('RGBA',(w,h))
    for x in range(cw,w-cw,tw):
        length=min(tw,w-cw-x); im.paste(tile.crop((0,0,length,h)),(x,0))
    im.paste(cap,(0,0)); im.paste(ImageOps.mirror(cap),(w-cw,0))
    return im

def plugins(im,y,h,colors,card=False):
    d=ImageDraw.Draw(im); scale=h/22
    font=ImageFont.truetype(str(FONT),round(11.5*scale))
    entries=[('Gold ','12,345g'),('Bags ','42/120'),('Durability ','87%'),('FPS ','120'),('MS ','34'),('','12:34')]
    if card:
        entries=[('Gold ','12,345g'),('Bags ','42/120')]
        font=ImageFont.truetype(str(FONT),16)
        xs=[im.width*.19,im.width*.56]
    else:
        xs=[im.width*p for p in [.055,.24,.43,.66,.79,.91]]
    for x,(label,value) in zip(xs,entries):
        yy=y+h*.5
        d.text((x,yy),label,font=font,fill=colors[1],anchor='lm')
        d.text((x+d.textlength(label,font=font),yy),value,font=font,fill=colors[0],anchor='lm')

def process(job):
    name,base,description,accent=job
    raw=Image.open(SRC/(name+'-raw.png')).convert('RGB')
    boxes=json.loads((SRC/'crops.json').read_text())
    strip=raw.crop(tuple(boxes[name])).resize((1024,64),RESAMPLE).convert('RGBA')
    # Only the generated calm middle is sampled; reference/status pictures are never a base.
    tile=strip.crop((420,0,676,64))
    tile=tile.filter(ImageFilter.GaussianBlur(.45))
    calm=tile.resize((16,64),Image.Resampling.BOX).resize((256,64),Image.Resampling.BICUBIC)
    tile=Image.blend(tile,calm,.72)
    for y in range(64):
        if y<13 or y>51:
            row=tuple(round(v) for v in ImageStat.Stat(tile.crop((0,y,256,y+1))).mean)
            for x in range(256):
                tile.putpixel((x,y),mix(tile.getpixel((x,y)),row,.78))
    # Suppress distinctive text-band marks while retaining painted material.
    for y in range(64):
        strength=.28 if 13<=y<=51 else 0
        for x in range(256):
            p=tile.getpixel((x,y)); tile.putpixel((x,y),mix(p,(7,9,12,255),strength))
    # A shared row profile makes every boundary identical without a vertical seam.
    for y in range(64):
        edge=mix(tile.getpixel((0,y)),tile.getpixel((255,y)),.5)
        for x in range(24):
            t=(1-x/24)**2
            for xx in [x,255-x]:
                tile.putpixel((xx,y),mix(tile.getpixel((xx,y)),edge,t))
    cap=strip.crop((0,0,128,64))
    for y in range(64):
        for x in range(72,128):
            t=(x-72)/55
            target=tile.getpixel((0,y))
            cap.putpixel((x,y),mix(cap.getpixel((x,y)),target,t*t*(3-2*t)))
    path=ROOT/base; path.parent.mkdir(parents=True,exist_ok=True)
    tile.save(str(path)+'-Tile.png'); cap.save(str(path)+'-Cap.png')
    assemble(tile,cap,1024,64).save(str(path)+'.png')
    band=ImageStat.Stat(assemble(tile,cap,1024,64).crop((0,13,1024,51))).mean[:3]
    bg=[v/255 for v in band]
    acc=tuple(bytes.fromhex(accent.lstrip('#')))
    text=[.96,.95,.91]; label=[v/255 for v in mix(acc,(255,255,255),.22)]
    ratios=[contrast(c,bg) for c in [text,label]]
    assert min(ratios)>=4.5,(name,ratios)
    colors=[tuple(round(v*255) for v in c)+(255,) for c in [text,label]]
    card=backdrop(512,256,acc).convert('RGBA')
    card.paste(assemble(tile,cap,512,70),(0,137)); plugins(card,137,70,colors,True)
    card.save(str(path)+'-Card.png')
    preview=Image.new('RGBA',(2560,240),(12,17,22,255))
    for w,h,y in [(1920,31,0),(2560,41,120)]:
        scene=backdrop(w,120,acc).convert('RGBA'); scene.paste(assemble(tile,cap,w,h),(0,120-h))
        plugins(scene,120-h,h,colors)
        ImageDraw.Draw(scene).text((12,12),f'{name} | {w} x {h}',fill='white',font=ImageFont.truetype(str(FONT),17))
        preview.paste(scene,(0,y))
    preview.save(OUT/(name+'-preview.png'))
    # 400% nearest-neighbor inspections: cap/tile and tile/tile joints.
    assembled=assemble(tile,cap,1024,64)
    seam=Image.new('RGBA',(512,256))
    for i,x in enumerate([128,384]):
        seam.paste(assembled.crop((x-32,0,x+32,64)).resize((256,256),Image.Resampling.NEAREST),(i*256,0))
    seam.save(OUT/(name+'-joints-400.png'))
    scaled=Image.new('RGBA',(1280,360),(12,17,22,255))
    draw=ImageDraw.Draw(scaled)
    for w,h,y in [(1920,31,25),(2560,41,185)]:
        bar=assemble(tile,cap,w,h)
        cw=round(cap.width*h/64); tw=round(tile.width*h/64)
        joints=list(range(cw,w-cw,tw))+[w-cw]
        draw.text((5,y-20),f'{name}: all {w} px joints at 400% (cap, tiles, right cap)',fill='white')
        for i,x in enumerate(joints):
            scaled.paste(bar.crop((x-8,0,x+8,h)).resize((64,h*4),Image.Resampling.NEAREST),(i*72,y))
    scaled.save(OUT/(name+'-scaled-joints-400.png'))
    return dict(base=base.replace('/','\\'),capWidth=128,textColor=text,labelColor=label,highlight=[v/255 for v in acc]+[.18],contrast=round(min(ratios),3),name=name,description=description,textContrast=round(ratios[0],3),labelContrast=round(ratios[1],3))

def main():
    jobs=json.loads((SRC/'jobs.json').read_text())
    results=[process(j) for j in jobs]
    keys=['base','capWidth','textColor','labelColor','highlight','contrast']
    (ROOT/'tools/databar/looks.json').write_text(json.dumps([{k:r[k] for k in keys} for r in results],indent=2)+'\n')
    contact=Image.new('RGB',(2560,12*264+300),'#10151b')
    comparison=Image.new('RGB',(1024,12*280),'#10151b')
    jointsheet=Image.new('RGB',(1024,6*286),'#10151b')
    scaledpages=[Image.new('RGB',(1280,4*360),'#10151b') for _ in range(3)]
    for i,r in enumerate(results):
        p=ROOT/Path(r['base'].replace('\\','/'))
        preview=Image.open(OUT/(r['name']+'-preview.png'))
        contact.paste(preview,(0,i*264))
        card=Image.open(str(p)+'-Card.png')
        contact.paste(card.resize((210,148),RESAMPLE),(i*213,12*264+25))
        comparison.paste(card,(512,i*280+20))
        look={'Arcane-Blue':'Arcane','Arcane-Red':'Arcane','War-Alliance':'War_Alliance','War-Horde':'War','Voyager':'Atlas','Grove':'Boughs'}.get(r['name'],r['name'])
        ref=Image.open(ROOT/'images/setup'/('Style_'+look+'.tga')).convert('RGBA')
        ref=ImageOps.contain(ref,(512,256)); comparison.paste(ref,(0,i*280+20),ref)
        ImageDraw.Draw(comparison).text((8,i*280),r['name'],fill='white')
        joints=Image.open(OUT/(r['name']+'-joints-400.png'))
        x,y=(i%2)*512,(i//2)*286
        jointsheet.paste(joints,(x,y+25)); ImageDraw.Draw(jointsheet).text((x+5,y+5),r['name'],fill='white')
        scaledpages[i//4].paste(Image.open(OUT/(r['name']+'-scaled-joints-400.png')),(0,(i%4)*360))
    contact.save(OUT/'contact.png'); comparison.save(OUT/'card-comparison.png'); jointsheet.save(OUT/'joints-400.png')
    for i,page in enumerate(scaledpages):
        page.save(OUT/f'scaled-joints-400-page-{i+1}.png')
    expected=[]
    for r in results:
        p=ROOT/Path(r['base'].replace('\\','/'))
        for suffix,size in [('-Tile',(256,64)),('-Cap',(128,64)),('',(1024,64)),('-Card',(512,256))]:
            f=Path(str(p)+suffix+'.png'); im=Image.open(f)
            assert im.mode=='RGBA' and im.size==size,(f,im.mode,im.size)
            assert im.getextrema()[3]==(255,255),f
            expected.append(str(f.relative_to(ROOT)))
        tile=Image.open(str(p)+'-Tile.png'); cap=Image.open(str(p)+'-Cap.png')
        assert tile.crop((0,0,1,64)).tobytes()==tile.crop((255,0,256,64)).tobytes()
        assert cap.crop((127,0,128,64)).tobytes()==tile.crop((0,0,1,64)).tobytes()
    (OUT/'validation.json').write_text(json.dumps(dict(files=expected,results=results,checks='48 RGBA files; exact dimensions; full alpha; identical native tile and cap boundary pixels; both contrast ratios >= 4.5'),indent=2)+'\n')
    print(f'Validated {len(expected)} assets. Lowest contrast: {min(r["contrast"] for r in results):.3f}:1')

if __name__=='__main__':
    main()
