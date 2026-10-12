"""Explicit artifact-format test doubles; never reconstruction evidence."""
import io
import json
import struct
import zipfile
from pathlib import Path
from PIL import Image
from contract import sha256


def input_image(alpha=True):
    image = Image.new('RGBA' if alpha else 'RGB', (64,64), (80,120,180,255) if alpha else (80,120,180))
    if alpha:
        image.putpixel((0,0), (0,0,0,0))
    stream = io.BytesIO()
    image.save(stream, 'PNG')
    return stream.getvalue()


def generated_glb(nonfinite=False):
    binary = struct.pack('<9f3H', 0,0,0, 1,0,0, 0,float('nan') if nonfinite else 1,0, 0,1,2)+b'\0\0'
    provenance = {'source':'generated','metricMeasurementsAllowed':False,'scaleStatus':'unverified'}
    document = {'asset':{'version':'2.0'},'buffers':[{'byteLength':42}],
                'bufferViews':[{'buffer':0,'byteOffset':0,'byteLength':36},{'buffer':0,'byteOffset':36,'byteLength':6}],
                'accessors':[{'bufferView':0,'componentType':5126,'count':3,'type':'VEC3'},
                             {'bufferView':1,'componentType':5123,'count':3,'type':'SCALAR'}],
                'meshes':[{'primitives':[{'attributes':{'POSITION':0},'indices':1}], 'extras':provenance}],
                'nodes':[{'mesh':0}],'scenes':[{'nodes':[0]}],'scene':0}
    encoded = json.dumps(document,separators=(',',':')).encode()
    encoded += b' ' * (-len(encoded)%4)
    return struct.pack('<4sII',b'glTF',2,28+len(encoded)+len(binary))+struct.pack('<II',len(encoded),0x4e4f534a)+encoded+struct.pack('<II',len(binary),0x004e4942)+binary


def artifacts(folder, mode, original=None, nonfinite=False):
    folder = Path(folder)
    folder.mkdir(parents=True, exist_ok=True)
    if mode == 'panorama':
        mask = Image.new('L',(512,256),0)
        mask.paste(255,(0,0,256,256))
        image = Image.new('RGBA',(512,256),(40,80,120,0)); image.putalpha(mask)
        image.save(folder/'panorama.png'); mask.save(folder/'coverage.png')
        if original is None:
            stream=io.BytesIO()
            with zipfile.ZipFile(stream,'w') as archive:
                archive.writestr('a.png',input_image());archive.writestr('b.png',input_image())
            original=stream.getvalue()
        (folder/'originals.zip').write_bytes(original)
        manifest={'format':'kantura-panorama','version':1,'status':'complete','scaleStatus':'unverified',
                  'projection':'equirectangular','width':512,'height':256,'coverageFraction':.5,'hasDepth':False,'canMeasure':False,
                  'testDouble':True,'artifacts':[{'name':p.name,'bytes':p.stat().st_size,'sha256':sha256(p)} for p in folder.iterdir()]}
        (folder/'result.json').write_text(json.dumps(manifest),'utf-8')
    else:
        glb=generated_glb(nonfinite)
        (folder/'generated-model.glb').write_bytes(glb)
        (folder/'generated-model.obj').write_text('# TEST DOUBLE generated metricMeasurementsAllowed=false\nv 0 0 0\nv 1 0 0\nv 0 1 0\nf 1 2 3\n','ascii')
        (folder/'generated-model.ply').write_text('ply\nformat ascii 1.0\nelement vertex 3\nproperty float x\nproperty float y\nproperty float z\nelement face 1\nproperty list uchar int vertex_indices\nend_header\n0 0 0\n1 0 0\n0 1 0\n3 0 1 2\n','ascii')
        with zipfile.ZipFile(folder/'model.zip','w') as archive:
            archive.writestr('model.glb',glb)
            archive.writestr('rtab-measure.json',json.dumps({'version':1,'source':'generated','metricMeasurementsAllowed':False,'calibrated':False,'measurements':[]}))
        manifest={'format':'kantura-generation','version':1,'status':'complete','source':'generated','scaleStatus':'unverified',
                  'metricMeasurementsAllowed':False,'units':'arbitrary','testDouble':True,'statistics':{'vertices':3,'faces':1},
                  'outputs':{p.name:{'bytes':p.stat().st_size,'sha256':sha256(p)} for p in folder.iterdir()}}
        (folder/'generation.json').write_text(json.dumps(manifest),'utf-8')
