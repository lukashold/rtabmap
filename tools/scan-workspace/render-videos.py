"""Create original animated tutorials. No real scan or product footage is used.

python render-videos.py --languages en fr es it zh-Hans --audio-dir /path/to/narration
Optional speech sends only the public narration text to Microsoft's Edge TTS.
Generated MP4, VTT and SRT files are self-hosted assets; playback needs no TTS.
"""
import argparse, asyncio, hashlib, json, math, subprocess, wave, importlib.util, sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import imageio_ffmpeg

ROOT=Path(__file__).resolve().parent
OUT=ROOT/'public/videos'
CACHE=ROOT/'.video-cache'
_spec=importlib.util.spec_from_file_location('kantura_shaped_text',ROOT/'shaped-text.py')
_shaped=importlib.util.module_from_spec(_spec);sys.modules[_spec.name]=_shaped;_spec.loader.exec_module(_shaped)
Draw=_shaped.Draw;ShapedFont=_shaped.ShapedFont
W,H,FPS=1280,720,24
INK='#251a40'; MINT='#70edc5'; PAPER='#faf9f6'; MUTED='#746980'
VOICES={'de':'de-DE-KatjaNeural','en':'en-US-JennyNeural','fr':'fr-FR-DeniseNeural','es':'es-ES-ElviraNeural','it':'it-IT-ElsaNeural','zh-Hans':'zh-CN-XiaoxiaoNeural'}
LABELS={'de':['Beispiel','Haus','Etage','Raum','Referenz','Notiz'], 'en':['Example','Building','Floor','Room','Reference','Note'], 'fr':['Exemple','Bâtiment','Étage','Pièce','Référence','Note'], 'es':['Ejemplo','Edificio','Planta','Habitación','Referencia','Nota'], 'it':['Esempio','Edificio','Piano','Stanza','Riferimento','Nota'], 'zh-Hans':['示例','建筑','楼层','房间','参考尺寸','备注']}

LABELS.update({
'pt':['Exemplo','Edifício','Piso','Divisão','Referência','Nota'],
'ar':['مثال','مبنى','طابق','غرفة','مرجع','ملاحظة'],
'hi':['उदाहरण','भवन','मंज़िल','कमरा','संदर्भ','टिप्पणी'],
'bn':['উদাহরণ','ভবন','তলা','ঘর','রেফারেন্স','নোট'],
'ru':['Пример','Здание','Этаж','Комната','Эталон','Заметка'],
'ja':['例','建物','階','部屋','基準','メモ'],
'ko':['예시','건물','층','방','기준','메모'],
'id':['Contoh','Gedung','Lantai','Ruangan','Acuan','Catatan'],
'tr':['Örnek','Bina','Kat','Oda','Referans','Not']})
CJK={'zh-Hans','ja','ko'}
COMPLEX={'ar','hi','bn'}

def font_path(chinese=False):
    choices=['C:/Windows/Fonts/msyh.ttc','/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc','/System/Library/Fonts/PingFang.ttc'] if chinese else ['C:/Windows/Fonts/segoeui.ttf','/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf','/System/Library/Fonts/Supplemental/Arial.ttf']
    for value in choices:
        if Path(value).is_file(): return value
    raise RuntimeError('Install a Latin/CJK font, or pass --font-latin/--font-cjk.')

def wrap(draw,text,font,width,chinese=False):
    pieces=list(text) if chinese else text.split();lines=[];line=''
    for piece in pieces:
        candidate=line+('' if chinese or not line else ' ')+piece
        if draw.textlength(candidate,font=font)>width and line:lines.append(line);line=piece
        else:line=candidate
    if line:lines.append(line)
    return lines

def center_text(draw,xy,text,font,fill=INK):
    x,y=xy;draw.text((x-draw.textlength(text,font=font)/2,y),text,font=font,fill=fill)

def rounded(draw,box,fill,r=20,outline=None,width=2):
    draw.rounded_rectangle(box,radius=r,fill=fill,outline=outline,width=width)

def logo(draw,x,y,size):
    scale=size/100;pts=lambda v:[(x+a*scale,y+b*scale) for a,b in v]
    draw.line(pts([(12,64),(12,27),(50,6),(88,27),(88,64),(50,42),(12,64)]),fill='white',width=max(2,round(5*scale)),joint='curve')
    draw.line(pts([(50,6),(50,42)]),fill='white',width=max(2,round(5*scale)))
    draw.line(pts([(12,77),(50,98),(88,77)]),fill=MINT,width=max(2,round(5*scale)),joint='curve')

def room(draw,cx,cy,s=1,progress=1):
    p=lambda a,b:(cx+a*s,cy+b*s)
    floor=[p(-170,10),p(15,-90),p(200,18),p(20,120)]
    draw.polygon(floor,fill='#e1f3e9',outline='#a4cdb8',width=3)
    draw.polygon([p(-170,10),p(-170,-135),p(15,-235),p(15,-90)],fill='#efe9f5',outline='#d0c3dc',width=3)
    draw.polygon([p(15,-90),p(15,-235),p(200,-127),p(200,18)],fill='#faf6fe',outline='#d0c3dc',width=3)
    draw.polygon([p(42,-94),p(42,-175),p(94,-145),p(94,-65)],fill='#d6eff8',outline='#78a6b7',width=3)
    draw.polygon([p(-131,-13),p(-131,-111),p(-75,-145),p(-75,-47)],fill='#b7ead4',outline='#4e9d7a',width=3)
    if progress>0:
        a,b=p(-170,10),p(20,120);end=(a[0]+(b[0]-a[0])*progress,a[1]+(b[1]-a[1])*progress)
        draw.line([a,end],fill='#2e906b',width=5)
        for q in [a,end]:draw.ellipse((q[0]-6,q[1]-6,q[0]+6,q[1]+6),fill='#208665')
    return floor

def base_frame(scene,index,language,fonts):
    image=Image.new('RGB',(W,H),PAPER);draw=Draw(image)
    rounded(draw,(58,34,103,79),INK,12);logo(draw,65,39,30)
    draw.text((119,36),'Kantura',font=fonts['brand'],fill=INK)
    draw.text((119,67),'SCAN · MEASURE',font=fonts['small'],fill=MUTED)
    rounded(draw,(970,39,1222,79),'#e6f4ed',18)
    center_text(draw,(1096,47),f'{LABELS[language][0]} · {language.upper()}',fonts['small'],'#285f4b')
    draw.text((62,110),f'{index+1:02d} / 08',font=fonts['small'],fill=MUTED)
    title_lines=wrap(draw,scene['title'],fonts['title'],1130,language in CJK)
    for j,line in enumerate(title_lines[:2]):draw.text((W-62-draw.textlength(line,font=fonts['title']) if language=='ar' else 62,139+j*48),line,font=fonts['title'],fill=INK)
    rounded(draw,(42,544,1238,673),INK,24)
    lines=wrap(draw,scene['caption'],fonts['caption'],1098,language in CJK)
    caption_font=fonts['caption'];advance=33
    if len(lines)>3:
        caption_font=fonts['captionSmall'];advance=27
        lines=wrap(draw,scene['caption'],caption_font,1098,language in CJK)
    if len(lines)>4:raise RuntimeError(f'Caption too long: {language}/{scene["id"]}')
    top=553+(4-len(lines))*13
    for j,line in enumerate(lines):draw.text((W-86-draw.textlength(line,font=caption_font) if language=='ar' else 86,top+j*advance),line,font=caption_font,fill='#fffaf2')
    for i in range(8):rounded(draw,(62+i*147,691,194+i*147,696),MINT if i<=index else '#e0d9e5',2)
    return image

def animate(image,scene_id,t,language,fonts):
    draw=Draw(image);ease=(1-math.cos(min(1,t)*math.pi))/2
    if scene_id in ['start','capture']:
        rounded(draw,(192,209,391,524),INK,32);rounded(draw,(205,233,378,505),'#eee8f5',20)
        room(draw,293,418,.4, min(1,t*2))
        rounded(draw,(258,219,325,228),'#5b4c71',4)
        y=263+math.sin(t*math.pi)*150;draw.line((214,y,369,y),fill='#389a73',width=3)
        for i,(name,color) in enumerate([('RoomPlan','#dff6ea'),('LiDAR','#efe8f8')]):
            rounded(draw,(494,263+i*107,1100,340+i*107),color,18)
            draw.text((527,280+i*107),name,font=fonts['medium'],fill=INK)
            draw.ellipse((1033,286+i*107,1064,317+i*107),fill='#65cda4' if (scene_id=='capture' or i==0) else '#b9a6d0')
    elif scene_id=='organize':
        for i,label in enumerate(LABELS[language][1:4]):
            x=111+i*370;lift=12*math.sin(max(0,min(1,t*3-i*.3))*math.pi)
            rounded(draw,(x,271-lift,x+317,456-lift),'white',22,outline='#ddd4e5')
            rounded(draw,(x+20,291-lift,x+64,335-lift),'#d8f4e6',12)
            center_text(draw,(x+42,298-lift),f'{i+1:02}',fonts['small'],'#2a7053')
            draw.text((x+22,362-lift),label,font=fonts['medium'],fill=INK)
            if i<2:draw.line((x+327,369,x+355,369),fill='#9d8bb0',width=3)
    elif scene_id in ['inspect','measure','photos']:
        room(draw,453,407,.72,min(1,t*1.5))
        if scene_id=='inspect':
            rounded(draw,(783,270,1167,475),'white',20,outline='#e0d8e8')
            for i,v in enumerate(['4.80 m','3.60 m','17.28 m²']):draw.text((818,289+i*59),v,font=fonts['medium'],fill=INK if i<2 else '#23795a')
        elif scene_id=='measure':
            rounded(draw,(758,262,1170,492),'white',20,outline='#e0d8e8')
            draw.text((793,285),LABELS[language][4],font=fonts['small'],fill=MUTED)
            draw.text((793,323),'4.80 / 4.81 m',font=fonts['medium'],fill=INK)
            draw.text((793,400),'Δ −0.01 m',font=fonts['medium'],fill='#32845f')
        else:
            px,py=471,344;draw.ellipse((px-9,py-9,px+9,py+9),fill='#21825c');draw.line((px,py,781,330),fill='#7baa91',width=3)
            rounded(draw,(781,264,1166,486),'white',20,outline='#e0d8e8')
            rounded(draw,(804,285,1138,420),'#e8e1f0',12)
            draw.polygon([(822,403),(894,324),(966,392),(1035,336),(1117,403)],fill='#bba8d1')
            draw.ellipse((1090,302,1116,328),fill='#80dcb6')
            draw.text((806,434),LABELS[language][5],font=fonts['small'],fill=INK)
    elif scene_id=='share':
        room(draw,322,420,.55,1)
        for i,name in enumerate(['PDF','DXF','Cloud','Docker']):
            x=615+(i%2)*273;y=251+(i//2)*125
            rounded(draw,(x,y,x+240,y+92),'#e6f6ed' if i>1 else 'white',18,outline='#d5e1d9')
            center_text(draw,(x+120,y+27),name,fonts['medium'],INK)
        if t>.2:draw.line((459,385,585,385),fill='#8c7c9f',width=4)
    elif scene_id=='transport':
        cx,cy=401,377;ratio=190;landing=1.1*ratio
        rounded(draw,(cx-landing/2,cy-landing/2,cx+landing/2,cy+landing/2),'white',8,outline='#9f91ac',width=3)
        angle=ease*math.pi/2;w=.6*ratio;d=.66*ratio
        points=[(cx+x*math.cos(angle)-y*math.sin(angle),cy+x*math.sin(angle)+y*math.cos(angle)) for x,y in [(-w/2,-d/2),(w/2,-d/2),(w/2,d/2),(-w/2,d/2)]]
        draw.polygon(points,fill=MINT,outline='#248965',width=3)
        center_text(draw,(cx,497),f'{round(angle*180/math.pi)}°',fonts['small'],MUTED)
        rounded(draw,(737,249,1139,486),'white',20,outline='#ddd4e7')
        draw.text((777,282),'0.60 × 0.66 m',font=fonts['medium'],fill=INK)
        draw.text((777,346),'2.03 m',font=fonts['medium'],fill=INK)
        draw.line((777,422,1100,422),fill='#ddd4e7',width=2)
        draw.ellipse((779,448,795,464),fill='#79be9c');draw.line((811,456,1060,456),fill='#c6dacf',width=5)
    return image

def stamp(seconds,separator=','):
    millis=round(seconds*1000);h,millis=divmod(millis,3600000);m,millis=divmod(millis,60000);s,ms=divmod(millis,1000)
    return f'{h:02}:{m:02}:{s:02}{separator}{ms:03}'

async def speech(scene,language,cache):
    import edge_tts
    key=hashlib.sha256((VOICES[language]+scene['narration']).encode()).hexdigest()[:18]
    target=cache/f'{key}.mp3'
    if not target.exists() or not target.stat().st_size:
        async with SPEECH_LIMIT:
            await edge_tts.Communicate(scene['narration'],VOICES[language],rate='+0%').save(str(target))
    return target

def audio_pcm(path,ffmpeg):
    result=subprocess.run([ffmpeg,'-v','error','-i',str(path),'-f','s16le','-ar','24000','-ac','1','pipe:1'],stdout=subprocess.PIPE,check=True)
    return result.stdout

async def render_language(language,script,args,ffmpeg):
    cache=CACHE/language;cache.mkdir(parents=True,exist_ok=True)
    scenes=script['scenes'];audio=[];durations=[]
    voice=None;engine=args.narration
    if args.audio_dir:
        source=Path(args.audio_dir)/language
        manifest=json.loads((source/'manifest.json').read_text(encoding='utf-8'))
        voice=manifest['voice'];engine=manifest['engine']
        for scene in scenes:
            pcm=audio_pcm(source/f'{scene["id"]}.wav',ffmpeg)
            if not pcm:raise RuntimeError(f'Empty narration: {language}/{scene["id"]}')
            audio.append(pcm+b'\0'*int(.5*24000*2));durations.append(len(pcm)/48000+.5)
    elif args.narration=='edge':
        voice=VOICES[language]
        paths=await asyncio.gather(*(speech(s,language,cache) for s in scenes))
        for path in paths:
            pcm=audio_pcm(path,ffmpeg);audio.append(pcm+b'\0'*int(.5*24000*2));durations.append(len(pcm)/48000+.5)
    else:
        durations=[max(6,len(s['narration'])/5 if language in CJK else len(s['narration'].split())/2.5) for s in scenes]
    wav=cache/'narration.wav'
    if audio:
        with wave.open(str(wav),'wb') as f:f.setnchannels(1);f.setsampwidth(2);f.setframerate(24000);f.writeframes(b''.join(audio))
    if language in {'hi','bn'}:
        fontfile=args.font_indic or next((p for p in ['C:/Windows/Fonts/Nirmala.ttf','/usr/share/fonts/truetype/noto/NotoSansDevanagari-Regular.ttf' if language=='hi' else '/usr/share/fonts/truetype/noto/NotoSansBengali-Regular.ttf'] if Path(p).is_file()),None)
        if not fontfile:raise RuntimeError('Install an Indic font or pass --font-indic.')
    elif language=='ko':fontfile=args.font_cjk or ('C:/Windows/Fonts/malgun.ttf' if Path('C:/Windows/Fonts/malgun.ttf').is_file() else font_path(True))
    else:fontfile=args.font_cjk or font_path(True) if language in CJK else args.font_latin or font_path()
    factory=ShapedFont if language in COMPLEX else ImageFont.truetype
    fonts={name:factory(fontfile,size) for name,size in [('brand',29),('title',42),('caption',25),('captionSmall',21),('small',19),('medium',30)]}
    captions=[];srt=[];vtt=['WEBVTT\n'];elapsed=0
    for i,(scene,duration) in enumerate(zip(scenes,durations)):
        end=elapsed+duration;captions.append({'id':scene['id'],'start':round(elapsed,3),'end':round(end,3),'title':scene['title']})
        srt.append(f'{i+1}\n{stamp(elapsed)} --> {stamp(end)}\n{scene["caption"]}\n')
        vtt.append(f'{stamp(elapsed,".")} --> {stamp(end,".")}\n{scene["caption"]}\n');elapsed=end
    (OUT/f'kantura-{language}.srt').write_text('\n'.join(srt),encoding='utf-8')
    (OUT/f'kantura-{language}.vtt').write_text('\n'.join(vtt),encoding='utf-8')
    target=OUT/f'kantura-{language}.mp4'
    command=[ffmpeg,'-y','-v','error','-f','rawvideo','-pix_fmt','rgb24','-s',f'{W}x{H}','-r',str(FPS),'-i','pipe:0']
    if audio:command+=['-i',str(wav)]
    command+=['-c:v','libx264','-preset','fast','-crf','23','-pix_fmt','yuv420p','-movflags','+faststart']
    if audio:command+=['-c:a','aac','-b:a','96k','-shortest']
    command+=[str(target)]
    process=subprocess.Popen(command,stdin=subprocess.PIPE,stderr=subprocess.PIPE)
    for i,(scene,duration) in enumerate(zip(scenes,durations)):
        base=base_frame(scene,i,language,fonts);count=round(duration*FPS)
        for frame in range(count):
            image=animate(base.copy(),scene['id'],frame/max(1,count-1),language,fonts)
            process.stdin.write(image.tobytes())
        if i in [0,4,7]:animate(base.copy(),scene['id'],.5,language,fonts).save(cache/f'preview-{i}.png')
    process.stdin.close();error=process.stderr.read();code=process.wait()
    if code:raise RuntimeError(error.decode(errors='replace'))
    # Decode the entire result to verify container, video and audio integrity.
    subprocess.run([ffmpeg,'-v','error','-i',str(target),'-f','null','-'],check=True)
    result={'language':language,'duration':round(elapsed,3),'narration':engine,'voice':voice,'chapters':captions,'bytes':target.stat().st_size,'synthetic':True}
    (OUT/f'kantura-{language}.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
    print(f'{language}: {elapsed:.1f}s, {target.stat().st_size} bytes, decoded successfully.',flush=True)
    return result

async def main():
    parser=argparse.ArgumentParser();parser.add_argument('--languages',nargs='+',default=list(LABELS));parser.add_argument('--narration',choices=['none','edge'],default='none');parser.add_argument('--audio-dir',help='Folder with <language>/<scene>.wav and manifest.json');parser.add_argument('--font-latin');parser.add_argument('--font-cjk');parser.add_argument('--font-indic');args=parser.parse_args()
    scripts=json.loads((OUT/'scripts.json').read_text(encoding='utf-8'));ffmpeg=imageio_ffmpeg.get_ffmpeg_exe()
    global SPEECH_LIMIT;SPEECH_LIMIT=asyncio.Semaphore(2)
    results=[]
    for language in args.languages:
        if language not in scripts['languages']:raise ValueError(language)
        results.append(await render_language(language,scripts['languages'][language],args,ffmpeg))
    print(json.dumps({'videos':results},ensure_ascii=True),flush=True)

if __name__=='__main__':asyncio.run(main())
