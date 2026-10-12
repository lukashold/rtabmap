"""Own transparent single-view object illustration for actual inference CI.

Not a photograph, field benchmark, measured model, or Polycam comparison.
"""
import argparse
from pathlib import Path
from PIL import Image, ImageDraw

parser=argparse.ArgumentParser()
parser.add_argument('--output',type=Path,required=True)
args=parser.parse_args()
image=Image.new('RGBA',(512,512),(0,0,0,0)); draw=ImageDraw.Draw(image)
draw.polygon([(100,170),(270,90),(410,175),(240,255)],fill=(55,158,181,255),outline=(20,50,65,255),width=4)
draw.polygon([(100,170),(240,255),(240,420),(100,335)],fill=(23,92,127,255),outline=(20,50,65,255),width=4)
draw.polygon([(240,255),(410,175),(410,340),(240,420)],fill=(95,199,185,255),outline=(20,50,65,255),width=4)
draw.line([(120,200),(215,257),(215,363),(120,308),(120,200)],fill=(237,245,229,255),width=8)
draw.ellipse((284,234,365,310),fill=(234,182,56,255))
args.output.parent.mkdir(parents=True,exist_ok=True); image.save(args.output)
print('Original synthetic illustration saved: '+str(args.output))
