using System;
using System.IO;
using System.Linq;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;

public class Cards {
    static string root, output;
    static Dictionary<string,Bitmap> cache = new Dictionary<string,Bitmap>();
    static HashSet<string> sources = new HashSet<string>();
    static List<string> report = new List<string>();
    static Color C(int r,int g,int b,int a=255) { return Color.FromArgb(a,r,g,b); }
    static uint U(byte[] b,int p) { return BitConverter.ToUInt32(b,p); }
    static Color RGB565(int n) { return C(((n>>11)&31)*255/31,((n>>5)&63)*255/63,(n&31)*255/31); }
    static Bitmap Pixels(int w,int h,byte[] bytes) {
        var b = new Bitmap(w,h,PixelFormat.Format32bppArgb);
        var d=b.LockBits(new Rectangle(0,0,w,h),ImageLockMode.WriteOnly,b.PixelFormat);
        Marshal.Copy(bytes,0,d.Scan0,bytes.Length); b.UnlockBits(d); return b;
    }
    static Bitmap Blp(byte[] b) {
        if(System.Text.Encoding.ASCII.GetString(b,0,4)!="BLP2" || b[8]!=2) throw new Exception("Expected DXT BLP2");
        int w=(int)U(b,12),h=(int)U(b,16),p=(int)U(b,20),enc=b[10];
        byte[] pixels=new byte[w*h*4];
        for(int y=0;y<h;y+=4) for(int x=0;x<w;x+=4) {
            int cp=p+(enc==0?0:8); int c0=BitConverter.ToUInt16(b,cp),c1=BitConverter.ToUInt16(b,cp+2);
            Color[] cs={RGB565(c0),RGB565(c1),Color.Empty,Color.Empty};
            for(int i=0;i<3;i++) {
                int a=i==0?cs[0].R:i==1?cs[0].G:cs[0].B, z=i==0?cs[1].R:i==1?cs[1].G:cs[1].B;
                int v2=c0>c1||enc!=0?(2*a+z)/3:(a+z)/2, v3=c0>c1||enc!=0?(a+2*z)/3:0;
                if(i==0) {cs[2]=C(v2,0,0);cs[3]=C(v3,0,0);} else if(i==1) {cs[2]=C(cs[2].R,v2,0);cs[3]=C(cs[3].R,v3,0);} else {cs[2]=C(cs[2].R,cs[2].G,v2);cs[3]=C(cs[3].R,cs[3].G,v3);}
            }
            uint bits=U(b,cp+4); ulong abits=0; int[] alpha=new int[8];
            if(enc==7) {
                alpha[0]=b[p];alpha[1]=b[p+1];
                if(alpha[0]>alpha[1]) for(int i=2;i<8;i++) alpha[i]=((8-i)*alpha[0]+(i-1)*alpha[1])/7;
                else {for(int i=2;i<6;i++) alpha[i]=((6-i)*alpha[0]+(i-1)*alpha[1])/5;alpha[6]=0;alpha[7]=255;}
                for(int i=0;i<6;i++) abits|=(ulong)b[p+2+i]<<(8*i);
            } else if(enc==1) abits=BitConverter.ToUInt64(b,p);
            for(int j=0;j<16;j++) {
                int xx=x+j%4,yy=y+j/4;if(xx>=w||yy>=h) continue;
                int ci=(int)((bits>>(j*2))&3),a=enc==7?alpha[(int)((abits>>(j*3))&7)]:enc==1?(int)((abits>>(j*4))&15)*17:ci==3&&c0<=c1?0:255;
                int o=(yy*w+xx)*4;pixels[o]=cs[ci].B;pixels[o+1]=cs[ci].G;pixels[o+2]=cs[ci].R;pixels[o+3]=(byte)a;
            } p+=enc==0?8:16;
        } return Pixels(w,h,pixels);
    }
    static Bitmap Tga(byte[] b) {
        int w=BitConverter.ToUInt16(b,12),h=BitConverter.ToUInt16(b,14),n=b[16]/8,p=18+b[0],i=0;
        if((b[2]!=2&&b[2]!=10)||n<3) throw new Exception("Expected true-color TGA");
        byte[] raw=new byte[w*h*4];
        while(i<w*h) {
            int run=1; bool repeat=false;
            if(b[2]==10) {int head=b[p++];run=(head&127)+1;repeat=(head&128)!=0;}
            for(int j=0;j<run;j++) {
                int xx=i%w,yy=i/w;if((b[17]&32)==0) yy=h-1-yy;if((b[17]&16)!=0) xx=w-1-xx;
                int o=(yy*w+xx)*4;raw[o]=b[p];raw[o+1]=b[p+1];raw[o+2]=b[p+2];raw[o+3]=n==4?b[p+3]:(byte)255;i++;
                if(!repeat||j==run-1) p+=n;
            }
        } return Pixels(w,h,raw);
    }
    static Bitmap Load(string rel) {
        sources.Add(rel.Replace('\\','/'));
        if(!cache.ContainsKey(rel)) {
            string path=Path.Combine(root,rel);byte[] b=File.ReadAllBytes(path);
            cache[rel]=rel.EndsWith(".blp",StringComparison.OrdinalIgnoreCase)?Blp(b):rel.EndsWith(".tga",StringComparison.OrdinalIgnoreCase)?Tga(b):new Bitmap(path);
        } return cache[rel];
    }
    static string Asset(string theme,string name) {
        string dir=Path.Combine(root,"Themes",theme,"Images");
        return Path.GetRelativePath(root,Directory.GetFiles(dir).First(p=>Path.GetFileNameWithoutExtension(p).Equals(name,StringComparison.OrdinalIgnoreCase)));
    }
    static Graphics G(Bitmap b) {var g=Graphics.FromImage(b);g.InterpolationMode=InterpolationMode.HighQualityBicubic;g.SmoothingMode=SmoothingMode.AntiAlias;g.PixelOffsetMode=PixelOffsetMode.HighQuality;return g;}
    static void Fill(Graphics g,Color c,float x,float y,float w,float h) {using(var b=new SolidBrush(c))g.FillRectangle(b,x,y,w,h);}
    static void Text(Graphics g,string t,float x,float y,float size,Color? color=null) {
        using(var f=new Font("Arial",size,FontStyle.Bold,GraphicsUnit.Pixel)) {
            using(var b=new SolidBrush(Color.Black))g.DrawString(t,f,b,x+1,y+1);
            using(var b=new SolidBrush(color??C(248,238,210)))g.DrawString(t,f,b,x,y);
        }
    }
    static void Art(Graphics g,string path,float x,float y,float w,float h,float l=0,float r=1,float t=0,float b=1,float opacity=1,Color? tint=null) {
        var img=Load(path); bool fx=l>r,fy=t>b;
        using(var part=img.Clone(new Rectangle((int)(Math.Min(l,r)*img.Width),(int)(Math.Min(t,b)*img.Height),Math.Max(1,(int)(Math.Abs(r-l)*img.Width)),Math.Max(1,(int)(Math.Abs(b-t)*img.Height))),PixelFormat.Format32bppArgb)) {
            if(fx)part.RotateFlip(RotateFlipType.RotateNoneFlipX);if(fy)part.RotateFlip(RotateFlipType.RotateNoneFlipY);
            using(var attrs=new ImageAttributes()) {var m=new ColorMatrix();m.Matrix33=opacity;if(tint.HasValue){m.Matrix00=tint.Value.R/255f;m.Matrix11=tint.Value.G/255f;m.Matrix22=tint.Value.B/255f;}attrs.SetColorMatrix(m);g.DrawImage(part,new Rectangle((int)x,(int)y,(int)w,(int)h),0,0,part.Width,part.Height,GraphicsUnit.Pixel,attrs);}
        }
    }
    static Bitmap Scene(string theme,bool frame=false) {
        string bg="images/setup/backdrops/"+theme+".png";
        if(!File.Exists(Path.Combine(root,bg))) bg="openspec/setup-mockup/img/cards/Style_"+theme+".png";
        var b=new Bitmap(1024,512,PixelFormat.Format32bppArgb);using(var g=G(b)) {
            g.Clear(Color.Black);
            if(bg.StartsWith("openspec")) Art(g,bg,0,0,1024,512,0,1,0,.50f);
            else Art(g,bg,0,0,1024,512);
            Fill(g,C(0,0,0,frame?165:135),0,0,1024,512);
        }return b;
    }
    static void Portrait(Graphics g,float cx,float cy,float size) {
        using(var b=new SolidBrush(C(46,42,38)))g.FillEllipse(b,cx-size/2,cy-size/2,size,size);
        using(var b=new SolidBrush(C(120,100,88)))g.FillEllipse(b,cx-size*.16f,cy-size*.3f,size*.32f,size*.32f);
        using(var b=new SolidBrush(C(92,78,70)))g.FillEllipse(b,cx-size*.32f,cy+size*.06f,size*.64f,size*.42f);
    }
    static void Map(Graphics g,float cx,float cy,float size,bool square=false) {
        var state=g.Save();using(var clip=new GraphicsPath()) {
            if(square)clip.AddRectangle(new RectangleF(cx-size/2,cy-size/2,size,size));else clip.AddEllipse(cx-size/2,cy-size/2,size,size);g.SetClip(clip);
            var rng=new Random(3);using(var tiny=new Bitmap(12,12)) {
                for(int x=0;x<12;x++)for(int y=0;y<12;y++){double v=rng.NextDouble();tiny.SetPixel(x,y,v<.3?C(60,110,160):v<.8?C(90,130,60):C(150,140,100));}
                g.DrawImage(tiny,cx-size/2,cy-size/2,size,size);
            }
        } g.Restore(state);
    }
    static void FelMapArt(Graphics g,float cx,float cy) {
        var img=Load(Asset("Fel","Minimap-Engulfed"));
        int left=img.Width,top=img.Height,right=0,bottom=0;
        for(int y=0;y<img.Height;y++)for(int x=0;x<img.Width;x++)if(img.GetPixel(x,y).A>16){left=Math.Min(left,x);top=Math.Min(top,y);right=Math.Max(right,x);bottom=Math.Max(bottom,y);}
        Art(g,Asset("Fel","Minimap-Engulfed"),cx-122,cy-142,244,244,left/(float)img.Width,(right+1f)/img.Width,top/(float)img.Height,(bottom+1f)/img.Height);
    }
    static void Buttons(Graphics g,float x,float y,int cols,int rows,float size,float gap=2) {
        for(int r=0;r<rows;r++)for(int c=0;c<cols;c++) {
            float xx=x+c*(size+gap),yy=y+r*(size+gap);int v=60+(c*13+r*29)%50;
            Fill(g,C(12,12,12),xx,yy,size,size);Fill(g,C(v,v-5,v-12),xx+1,yy+1,size-2,size-2);
            using(var p=new Pen(C(v+35,v+25,v+10),1))g.DrawRectangle(p,xx+3,yy+3,size-6,size-6);
        }
    }
    static void Bars(Graphics g,float x,float y,float w,float health,float power,Color color,float fraction=.84f,bool voidMode=false,bool dark=false) {
        Fill(g,dark?C(10,10,10,178):C(12,15,15),x,y,w,health+power);
        Fill(g,voidMode?color:C(20,28,25),x,y,w,health);
        if(dark) {using(var brush=new LinearGradientBrush(new RectangleF(x,y,w,health),Color.FromArgb(215,color),Color.FromArgb(120,color),90))g.FillRectangle(brush,x,y,w*fraction,health);}
        else Fill(g,voidMode?Color.Black:color,x,y,w*fraction,health);
        Fill(g,voidMode?C(25,25,25):C(35,56,95),x,y+health,w,power);
        Fill(g,voidMode?Color.Black:C(220,175,45),x,y+health,w*.62f,power);
    }
    static string BaseTheme(string theme) {return theme.StartsWith("Midnight")?"Midnight":theme=="Arcane_Red"?"Arcane":theme=="War_Alliance"?"War":theme;}
    static bool Flat(string t) {return new[]{"ModernFlat","HealerGrid","ClassicDark","Digital","Minimal","Transparent","Grid"}.Contains(t)||t.StartsWith("Midnight");}
    static void Frame(Graphics g,string theme,float x,float y,float scale,bool target=false,bool party=false,int index=0,bool raid=false) {
        string bt=BaseTheme(theme);sources.Add("Themes/"+bt+"/Style.lua");
        string label=party?"Party "+(index+1):target?"Target Name":"60 Player Name";
        bool painted=new[]{"Atlas","Boughs","Meridian"}.Contains(theme);
        if(painted) {
            sources.Add("Themes/Painted.lua");float w=230*scale,h=36*scale;
            if(!party) {
                float mx=target?x+w+62*scale:x-62*scale;
                Art(g,Asset(bt,"UnitFrame-Mount"),mx-78*scale,y+h/2-78*scale,156*scale,156*scale,target?1:0,target?0:1);
                Portrait(g,mx,y+h/2,60*scale);
            }
            // Nine-slice preserves the painted caps when making party plates smaller.
            Nine(g,Asset(bt,"UnitFrame-NoPortrait"),x-8*scale,y-18*scale,w+20*scale,78*scale,40,40,36,26);
            Bars(g,x+4*scale,y+2*scale,w-8*scale,24*scale,8*scale,C(40,170,60));
            Text(g,label,x+6*scale,y-14*scale,12*scale);
            return;
        }
        if(Flat(theme)) {
            if(new[]{"ModernFlat","HealerGrid","ClassicDark"}.Contains(theme))sources.Add("Themes/Flat.lua");
            float w=220,hh=40,ph=10;bool md=theme.StartsWith("Midnight"),inside=false;
            if(theme=="ModernFlat"){w=party?150:180;hh=party?38:46;ph=party?4:6;inside=true;}
            if(theme=="HealerGrid"){w=party?(raid?110:125):200;hh=party?(raid?52:60):36;ph=party?4:5;inside=true;}
            if(theme=="ClassicDark"){w=party?180:220;hh=party?34:36;ph=party?6:8;inside=true;}
            if(md){w=party?95:250;hh=party?36:50;ph=party?4:10;inside=true;}
            if(theme=="Grid"){w=party?90:72;hh=party?34:28;ph=party?3:2;inside=true;}
            w*=scale;hh*=scale;ph*=scale;
            Color color=inside?index%3==0?C(105,170,235):index%3==1?C(235,150,75):C(115,195,130):C(40,170,60);
            if(theme=="Midnight")color=C(40,170,60);
            if(target&&inside&&theme!="Midnight")color=C(235,150,75);
            if(target&&!inside)color=C(40,170,60);
            Fill(g,md&&theme!="Midnight"?color:Color.Black,x-2*scale,y-2*scale,w+4*scale,hh+ph+4*scale);
            Bars(g,x,y,w,hh,ph,color,target?.66f:.84f,theme=="Midnight_Void",theme=="ClassicDark");
            if(theme=="Midnight_Shadow")Fill(g,color,x,y+hh,w*.62f,ph);
            Text(g,label,x+4*scale,inside?y+3*scale:y-15*scale,Math.Min(24,Math.Min((party?10:theme=="Grid"?9:12)*scale,w/(label.Length*.68f))));
            if(theme=="Grid"||theme=="HealerGrid") {
                Fill(g,C(65,195,130),x+w-7*scale,y+2*scale,5*scale,5*scale);
                Fill(g,C(230,190,60),x+w-14*scale,y+2*scale,5*scale,5*scale);
            }
            return;
        }
        float fw=(theme=="Classic"?153:220)*scale,fh=(theme=="Classic"?32:50)*scale;
        if(theme=="Classic") {
            if(!party) {
                Art(g,Asset(bt,"base_plate1"),x-(target?126:58)*scale,y-31*scale,fw*2.2f,80*scale,target?.810546875f:.19140625f,target?.19140625f:.810546875f,.1796875f,.8203125f);
                float cx=target?x-41*scale:x+fw+41*scale;
                Portrait(g,cx,y+fh/2-7*scale,62*scale);Art(g,Asset(bt,"ring1"),cx-40*scale,y+fh/2-41*scale,80*scale,68*scale,target?1:0,target?0:1);
            }
            Bars(g,x,y,fw,16*scale,16*scale,C(40,170,60));Text(g,label,x,y-14*scale,12*scale);return;
        }
        sources.Add("Themes/ArtFrames.lua");
        string img=Asset(bt,"UnitFrames");float l=0,r=1,t=0,b=1,tl=0,tr=1,tt=0,tb=.2f,bl=0,br=1,btp=.37f,bb=.42f,topH=.225f,bottomH=.08f;
        if(bt=="War") {l=.572265625f;r=.96875f;t=.74609375f;b=1;tl=theme=="War_Alliance"?.03125f:.541015625f;tr=theme=="War_Alliance"?.458984375f:1;tb=.1796875f;bl=tl;br=tr;btp=.37109375f;bb=.421875f;}
        if(bt=="Fel"){l=.02f;r=.385f;t=.45f;b=.575f;tl=.1796875f;tr=.736328125f;tb=.099609375f;bl=tl;br=tr;btp=.197265625f;bb=.244140625f;topH=.25f;bottomH=.115f;}
        if(bt=="Arcane"){l=theme=="Arcane_Red"?.533203125f:0;r=theme=="Arcane_Red"?1:.458984375f;t=.46484375f;b=.75f;tl=l;tr=r;tb=.19921875f;bl=l;br=r;btp=.374f;bb=.403f;}
        if(bt=="Tribal"){l=.126953125f;r=.734375f;t=.171875f;b=.291015625f;tl=.25390625f;tr=.580078125f;tt=.583984375f;tb=.712890625f;bl=.869140625f;br=1;btp=.3203125f;bb=.359375f;topH=.38f;bottomH=.15f;}
        Art(g,img,x-6*scale,y-4*scale,fw+12*scale,fh+8*scale,l,r,t,b);
        Bars(g,x,y,fw,40*scale,10*scale,C(40,170,60),target?.66f:.84f);
        if(!party) {
            float tw=bt=="Tribal"?fw*.6f:fw;
            Art(g,img,x+(fw-tw)/2,y-fw*topH+8*scale,tw,fw*topH,tl,tr,tt,tb);
            float bw=bt=="Tribal"?fw*.25f:fw;
            Art(g,img,x+(fw-bw)/2,y+fh-2*scale,bw,fw*bottomH,bl,br,btp,bb);
            float cx=target?x+fw+35*scale:x-35*scale;Portrait(g,cx,y+fh/2,58*scale);
        }
        Text(g,label,x+3*scale,y+fh+7*scale,12*scale);
    }
    static void Nine(Graphics g,string path,float x,float y,float w,float h,int left,int right,int top,int bottom) {
        var img=Load(path);float factor=h/img.Height;
        float[] sx={0,left,img.Width-right,img.Width},sy={0,top,img.Height-bottom,img.Height};
        float[] dx={x,x+left*factor,x+w-right*factor,x+w},dy={y,y+top*factor,y+h-bottom*factor,y+h};
        for(int r=0;r<3;r++)for(int c=0;c<3;c++)g.DrawImage(img,new RectangleF(dx[c],dy[r],dx[c+1]-dx[c],dy[r+1]-dy[r]),new RectangleF(sx[c],sy[r],sx[c+1]-sx[c],sy[r+1]-sy[r]),GraphicsUnit.Pixel);
    }
    public static void AssetSheet(string repo) {
        root=repo;output=Path.Combine(root,"openspec/setup-cards");Directory.CreateDirectory(output);
        var paths=Directory.GetFiles(Path.Combine(root,"Themes"),"*",SearchOption.AllDirectories).Where(p=>new[]{".png",".tga",".blp"}.Contains(Path.GetExtension(p).ToLower())&&!p.Contains("World")&&!p.Contains("Icon")).ToArray();
        using(var sheet=new Bitmap(1200,((paths.Length+5)/6)*150))using(var g=G(sheet)) {
            g.Clear(C(50,55,60));for(int i=0;i<paths.Length;i++) {string rel=Path.GetRelativePath(root,paths[i]);var b=Load(rel);int x=i%6*200,y=i/6*150;float s=Math.Min(190f/b.Width,110f/b.Height);g.DrawImage(b,x+(190-b.Width*s)/2,y,b.Width*s,b.Height*s);Text(g,rel.Replace("Themes\\",""),x,y+112,10);Text(g,b.Width+" x "+b.Height,x,y+128,10);}
            sheet.Save(Path.Combine(output,"sources.png"),ImageFormat.Png);
        }
    }
    static void Save(Bitmap b,string group,string name,string note) {
        string dir=Path.Combine(output,group);Directory.CreateDirectory(dir);
        using(var card=new Bitmap(512,256,PixelFormat.Format32bppArgb)) {
            using(var g=G(card)) {g.Clear(Color.Black);g.DrawImage(b,0,0,512,256);}card.Save(Path.Combine(dir,name+".png"),ImageFormat.Png);
            using(var stream=new BinaryWriter(File.Create(Path.Combine(dir,name+".tga")))) {
                byte[] header=new byte[18];header[2]=2;header[12]=0;header[13]=2;header[14]=0;header[15]=1;header[16]=32;header[17]=40;stream.Write(header);
                for(int y=0;y<256;y++)for(int x=0;x<512;x++){Color c=card.GetPixel(x,y);if(c.A!=255)throw new Exception("Nonopaque card");stream.Write(c.B);stream.Write(c.G);stream.Write(c.R);stream.Write((byte)255);}
            }
        }
        report.Add("- `"+group+"/"+name+"` - Sources: "+string.Join(", ",sources.OrderBy(x=>x).Select(x=>"`"+x+"`"))+". "+note);
    }
    public static void Build(string repo) {
        report.Clear();
        root=repo;output=Path.Combine(root,"openspec/setup-cards");Directory.CreateDirectory(output);
        string[] looks={"Classic","War","War_Alliance","Fel","Digital","Midnight","Arcane","Arcane_Red","Tribal","Minimal","Transparent","ModernFlat","HealerGrid","ClassicDark"};
        foreach(string t in looks) {sources.Clear();using(var b=Look(t))Save(b,"looks","Style_"+t,LookNote(t));}
        string[] frames={"Atlas","Boughs","Meridian","War","Classic","Midnight","Midnight_Void","Midnight_Shadow","ModernFlat","HealerGrid","ClassicDark","Fel","Digital","Arcane","Arcane_Red","Tribal","Transparent","Grid"};
        foreach(string t in frames) {
            sources.Clear();using(var b=Scene(t=="Grid"?"HealerGrid":BaseTheme(t),true)) {
                using(var g=G(b)) {
                    bool painted=new[]{"Atlas","Boughs","Meridian"}.Contains(t);
                    if(painted){Frame(g,t,154,220,1.3f);Frame(g,t,572,220,1.3f,true);}
                    else if(t=="Classic") {Frame(g,t,82,220,1.65f);Frame(g,t,690,220,1.65f,true);}
                    else {
                        float width=t=="Grid"?72:t=="ModernFlat"?180:t=="HealerGrid"?200:t.StartsWith("Midnight")?250:220;
                        float scale=Flat(t)?400/width:1.6f;
                        Frame(g,t,Flat(t)?86:100,220,scale,false);
                        Frame(g,t,Flat(t)?538:572,220,scale,true);
                    }
                }
                Save(b,"frames","Style_Frames_"+t,FrameNote(t));
            }
        }
        Contact("looks");Contact("frames");
        File.WriteAllText(Path.Combine(output,"ROUND2-SOURCES.md"),"# Round 2 sources and approximations\n\n"+string.Join("\n",report)+"\n");
        Console.WriteLine("Built 32 cards (64 files), both contact sheets and ROUND2-SOURCES.md.");
    }
    static string FrameNote(string t) {
        if(t=="Grid")return "Grid only defines party/raid styles: the two enlarged center cells demonstrate its raid settings rather than inventing a player/target preset. HealerGrid backdrop reused because Grid has none; corner indicators shown with sample states. Party column omitted.";
        if(new[]{"Atlas","Boughs","Meridian"}.Contains(t))return "Painted plate nine-slice and separate portrait mount, enlarged with space around the outer portraits. Upper scene-only half of existing look card used as mood backdrop because images/setup/backdrops has no painted backdrop. Sample fills/portraits; inactive casts and aura rows omitted. Party column omitted.";
        if(t.StartsWith("Midnight"))return "250-wide, 50-health portrait-free layout; Void shows black current health and class-colored missing health, Shadow shows class-colored current health and power. Base Midnight uses inherited green health. Class borders drawn for variant styles; inactive casts/aura rows omitted. Party column omitted.";
        if(t=="Classic")return "153-wide plate cropped and mirrored from per-unit texcoords, 16-health and 14-player/16-target power approximated by equal strips; real portrait rings placed on inward ends as UnitFrameCallback specifies, with clear space between rings. Casts/auras and party column omitted.";
        return "Frame proportions, portrait policy and colors follow theme data; sample bars/portraits. Player/target enlarged to lead the composition. Inherited element defaults approximated where the theme only overrides art. Inactive cast/aura rows and party column omitted.";
    }
    static string LookNote(string t) {return "Bottom-screen review composition with sample map, portrait, empty slots and status fills. "+(t=="Arcane_Red"?"Red unit-frame regions are native to the atlas; bottom artwork has no separate red variant, so shared neutral bottom art is retained. Arcane references missing Barbg; no substitute ornament was invented. ":t=="Arcane"?"Arcane references missing Barbg; empty slots drawn on the native bottom art. ":t=="Midnight"?"Void wide 855x185 overlay rebuilt from its cropped background and edge regions; map moved into the crop at top right. Blizzard atlas status borders unavailable locally, so shown as plain dark strips. ":t=="HealerGrid"?"Centered 5x5 raid25 cells use 110x52 health plus 4 power proportions; corner healing indicators use sample states. ":t=="ModernFlat"||t=="ClassicDark"?"Flat health/power proportions and class colors preserved; corner minimap brought into the bottom crop. Inactive casts omitted. ":t=="Minimal"?"Minimal defines no frame preset: inherited plain frames shown. Native panels retain their proportions and default red vertex color; top-right map included in crop. ":"Art sizes use source dimensions and declared .75 scales where applicable; anchor positions approximated for readable bottom-screen crop. ")+"Status art is reduced to a review strip with sample fills; inherited element defaults and inactive cast/aura rows are approximated or omitted. No live-client rendering is claimed.";}
    static void Contact(string group) {
        var files=Directory.GetFiles(Path.Combine(output,group),"*.png").OrderBy(x=>x).ToArray();
        using(var b=new Bitmap(1088,((files.Length+3)/4)*166))using(var g=G(b)) {
            g.Clear(C(18,21,25));for(int i=0;i<files.Length;i++){int x=16+i%4*272,y=12+i/4*166;using(var c=new Bitmap(files[i]))g.DrawImage(c,x,y,256,128);Text(g,Path.GetFileName(files[i]),x,y+134,12);}
            b.Save(Path.Combine(output,"contact_"+group+".png"),ImageFormat.Png);
        }
    }
    public static void Verify(string repo) {
        string dir=Path.Combine(repo,"openspec/setup-cards");int count=0;
        foreach(string group in new[]{"looks","frames"}) {
            var files=Directory.GetFiles(Path.Combine(dir,group),"*.png");
            if(files.Length!=(group=="looks"?14:18))throw new Exception("Incorrect card count: "+group);
            foreach(string file in files) using(var png=new Bitmap(file)) using(var tga=Tga(File.ReadAllBytes(Path.ChangeExtension(file,".tga")))) {
                byte[] header=File.ReadAllBytes(Path.ChangeExtension(file,".tga"));
                if(png.Width!=512||png.Height!=256||tga.Width!=512||tga.Height!=256||header[16]!=32)throw new Exception("Incorrect export size or depth: "+file);
                for(int y=0;y<256;y++)for(int x=0;x<512;x++) {
                    var c=png.GetPixel(x,y);if(c.A!=255||c.ToArgb()!=tga.GetPixel(x,y).ToArgb())throw new Exception("Alpha or PNG/TGA pixel mismatch: "+file);
                }count++;
            }
        }
        Console.WriteLine("Verified "+count+" PNG/TGA pairs: 512x256, 32-bit TGA, alpha 255, pixel-identical.");
    }
    static Bitmap Look(string theme) {
        string bt=BaseTheme(theme);sources.Add("Themes/"+bt+"/Style.lua");if(File.Exists(Path.Combine(root,"Themes",bt,"Style.xml")))sources.Add("Themes/"+bt+"/Style.xml");
        var b=Scene(bt);using(var g=G(b)) {
            bool flat=new[]{"ModernFlat","HealerGrid","ClassicDark"}.Contains(theme);
            if(flat) {
                sources.Add("Themes/Flat.lua");
                Buttons(g,300,422,12,3,30,3);Buttons(g,24,450,8,2,29,3);Buttons(g,748,450,8,2,29,3);
                Map(g,924,100,168,true);
                float scale=theme=="ModernFlat"?1.4f:theme=="HealerGrid"?1.25f:1.15f;
                float y=theme=="ModernFlat"?222:330;
                Frame(g,theme,100,y,scale);Frame(g,theme,670,y,scale,true);
                if(theme=="HealerGrid")for(int r=0;r<5;r++)for(int c=0;c<5;c++)Frame(g,theme,290+c*89,35+r*46,.78f,false,true,r*5+c,true);
            } else if(theme=="Midnight") {
                var state=g.Save();g.TranslateTransform(512,512);g.ScaleTransform(2.1f,2.1f);g.TranslateTransform(-512,-512);
                MidnightOverlay(g);g.Restore(state);
                Buttons(g,65,398,12,2,31,3);Buttons(g,550,398,12,2,31,3);
                Map(g,918,98,166);Art(g,Asset(bt,"Minimap"),820,0,196,196);
                Frame(g,"Midnight_Void",80,257,1);Frame(g,"Midnight_Void",690,257,1,true);
            } else if(theme=="Minimal") {
                Art(g,Asset(bt,"base-center"),290,284,444,222,0,1,0,1,.9f,C(157,31,31));
                Art(g,Asset(bt,"base-sides"),0,284,444,222,0,1,0,1,.9f,C(157,31,31));Art(g,Asset(bt,"base-sides"),580,284,444,222,1,0,0,1,.9f,C(157,31,31));
                Buttons(g,300,422,12,3,30,3);Buttons(g,24,450,8,2,29,3);Buttons(g,748,450,8,2,29,3);Map(g,922,100,168,true);
                Frame(g,theme,80,304,1.15f);Frame(g,theme,690,304,1.15f,true);
            } else {
                var state=g.Save();g.TranslateTransform(512,512);g.ScaleTransform(2.1f,2.1f);g.TranslateTransform(-512,-512);
                float unit=.52f,artScale=bt=="Fel"||bt=="Digital"?unit:unit*.75f;
                if(bt=="Classic"||bt=="Transparent") {
                    var center=Load(Asset(bt,"base-center"));float cw=center.Width*unit,ch=center.Height*unit;
                    Art(g,Asset(bt,"base-center"),512-cw/2,512-ch,cw,ch);
                    if(bt=="Classic") {Art(g,Asset(bt,"base-left1"),512-cw/2-512*unit,512-256*unit,512*unit,256*unit);Art(g,Asset(bt,"base-right1"),512+cw/2,512-256*unit,512*unit,256*unit);}
                    else {Art(g,Asset(bt,"base-sides"),0,512-256*unit,512-cw/2,256*unit);Art(g,Asset(bt,"base-sides"),512+cw/2,512-256*unit,512-cw/2,256*unit);}
                    for(int s=0;s<2;s++)for(int r=0;r<2;r++)Art(g,Asset(bt,"bar-backdrop1"),s==0?295:574,437+r*30,155,28,.107421875f,.896484375f,.25f,.765625f,bt=="Transparent"?.1f:1);
                } else {
                    string left=bt=="Arcane"?"Art_Left":bt=="Tribal"?"Art-Left":"Base_Bar_Left";
                    string right=bt=="Arcane"?"Art_Right":bt=="Tribal"?"Art-Right":"Base_Bar_Right";
                    var img=Load(Asset(bt,left));float aw=img.Width*artScale,ah=img.Height*artScale;
                    Art(g,Asset(bt,left),512-aw,512-ah,aw,ah);Art(g,Asset(bt,right),512,512-ah,aw,ah);
                    if(bt=="War") {
                        string faction=theme=="War_Alliance"?"Alliance":"Horde";
                        for(int s=0;s<2;s++)for(int r=0;r<2;r++)Art(g,Asset(bt,"Barbg-"+faction),s==0?295:574,435+r*30,155,28,.07421875f,.92578125f,.359375f,.6796875f);
                        Art(g,Asset(bt,"Trays-"+faction),292,405,161,25);Art(g,Asset(bt,"Trays-"+faction),572,405,161,25,1,0);
                    }
                    if(bt=="Fel"||bt=="Digital"||bt=="Tribal") {
                        string bed=bt=="Fel"?"Fel-Box":bt=="Digital"?"BarBG":"Barbg";
                        for(int s=0;s<2;s++)for(int r=0;r<2;r++)Art(g,Asset(bt,bed),s==0?295:574,435+r*30,155,28,.07421875f,.92578125f,.359375f,.6796875f,.5f);
                    }
                }
                Buttons(g,300,440,9,2,14,3);Buttons(g,578,440,9,2,14,3);
                g.Restore(state);
                float mapSize=168;float cy=405;
                if(bt=="War"||bt=="Fel"||bt=="Digital"||bt=="Tribal"||bt=="Arcane") {
                    string mm=bt=="Fel"?"Minimap-Engulfed":"Minimap";
                    if(bt=="Fel")FelMapArt(g,512,cy);
                    else Art(g,Asset(bt,mm),512-112,cy-112,224,224);
                    Map(g,512,cy,mapSize);
                } else Map(g,512,cy,mapSize,bt=="Transparent");
                if(theme=="Classic") {Frame(g,theme,75,245,1.6f);Frame(g,theme,704,245,1.6f,true);}
                else {Frame(g,theme,100,245,1.15f);Frame(g,theme,670,245,1.15f,true);}
            }
            Status(g,theme);
        }return b;
    }
    static void Status(Graphics g,string theme) {
        string bt=BaseTheme(theme);bool flat=new[]{"ModernFlat","HealerGrid","ClassicDark","Minimal","Midnight"}.Contains(theme);
        for(int s=0;s<2;s++) {
            float x=s==0?24:614,y=flat?502:360,w=386;
            if(!flat) {
                string path=bt=="War"?Asset(bt,"StatusBar-"+(theme=="War_Alliance"?"Alliance":"Horde")):bt=="Classic"?Asset(bt,"status-plate-exp"):bt=="Transparent"?Asset(bt,"status-plate-rep"):bt=="Digital"?null:Asset(bt,"StatusBar");
                if(path!=null)Art(g,path,x-3,y-3,w+6,15);
            }
            Fill(g,C(10,15,15,215),x,y,w,6);Fill(g,C(67,140,150),x,y,w*(s==0?.62f:.35f),6);
        }
    }
    static void MidnightOverlay(Graphics g) {
        string a=Asset("Midnight","BottomArt");float x=290,y=416,w=445,h=96;
        // Natural-size background is center-clipped by the 855x185 wide window.
        Art(g,a,x,y,w,h,(1754-855)/2f/1754,(1754+855)/2f/1754,(162+(438-185)/2f)/600,(162+(438+185)/2f)/600);
        Art(g,a,x-3,y-3,52,52,0,158f/1754,0,159f/600);Art(g,a,x+w-49,y-3,52,52,1596f/1754,1,0,159f/600);
        Art(g,a,x+49,y-3,w-98,52,400f/1754,420f/1754,0,159f/600);
        Art(g,a,x-3,y+46,52,50,160f/1754,318f/1754,1f/600,159f/600);Art(g,a,x+w-49,y+46,52,50,1596f/1754,1,148f/600,159f/600);
    }
}

