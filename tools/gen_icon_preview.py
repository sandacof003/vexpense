import sys

from PIL import Image, ImageDraw
import os
import pathlib

os.chdir(pathlib.Path(__file__).resolve().parents[1])
res = 'android/app/src/main/res'
BG = (0x4C, 0xAF, 0x50)
DENS = {48: 'mdpi', 72: 'hdpi', 96: 'xhdpi', 144: 'xxhdpi', 192: 'xxxhdpi'}


def legacy(sz):
    return Image.open(f'{res}/mipmap-{DENS[sz]}/ic_launcher.png').convert('RGB')


fg = Image.open(f'{res}/drawable-nodpi/ic_launcher_foreground.png')


def circle_mask(im, box):
    m = Image.new('L', im.size, 0)
    ImageDraw.Draw(m).ellipse(box, fill=255)
    return m


def adaptive_icon(px, mask):
    d = int(round(px * 108 / 48))
    c = Image.new('RGB', (d, d), BG)
    f = fg.resize((d, d), Image.Resampling.LANCZOS)
    c.paste(f, (0, 0), f)
    inset = int(round(px * 18 / 48))
    m = Image.new('L', (d, d), 0)
    dr = ImageDraw.Draw(m)
    box = (inset, inset, d - inset, d - inset)
    if mask == 'circle':
        dr.ellipse(box, fill=255)
    else:
        dr.rounded_rectangle(box, radius=int(px * 0.30), fill=255)
    out = Image.new('RGB', (d, d), (0x2B, 0x2B, 0x2B))
    out.paste(c, (0, 0), m)
    return out.resize((px, px), Image.Resampling.LANCZOS)


def legacy_circle(px):
    im = legacy(192).resize((px, px), Image.Resampling.LANCZOS) if px not in DENS else legacy(px)
    m = circle_mask(im, (0, 0, px - 1, px - 1))
    o = Image.new('RGB', (px, px), (0x2B, 0x2B, 0x2B))
    o.paste(im, (0, 0), m)
    return o


S, PAD = 200, 20
WALL = (0x22, 0x26, 0x2A)
LABEL = (0xDD, 0xDD, 0xDD)
SUB = (0x99, 0x99, 0x99)
W = PAD * 4 + S * 3
H = PAD * 2 + 22 + S + 40 + 200 + 34 + 200 + 30
cv = Image.new('RGB', (W, H), WALL)
d = ImageDraw.Draw(cv)

cells = [('Legacy (API<26)', legacy_circle(S)),
         ('Adaptive bulat (Android 8+)', adaptive_icon(S, 'circle')),
         ('Adaptive squircle', adaptive_icon(S, 'squircle'))]
for i, (lab, img) in enumerate(cells):
    x = PAD + i * (S + PAD)
    cv.paste(img, (x, PAD + 20))
    d.text((x, PAD + 4), lab, fill=LABEL)

y2 = PAD + 20 + S + 40
d.text((PAD, y2 - 18), 'Ukuran asli 1:1 (legacy, mask bulat):', fill=LABEL)
x = PAD
for s in (48, 72, 96, 144, 192):
    cv.paste(legacy_circle(s), (x, y2))
    d.text((x, y2 + s + 6), f'{s}px', fill=SUB)
    x += s + 20

y3 = y2 + 200
d.text((PAD, y3 - 18), 'Adaptive icon di wallpaper terang vs gelap:', fill=LABEL)
for i, (wall, col) in enumerate((('terang', (0xEC, 0xEF, 0xEA)), ('gelap', (0x0F, 0x14, 0x0F)))):
    tile = Image.new('RGB', (S, S), col)
    tile.paste(adaptive_icon(S, 'circle'), (0, 0))
    cv.paste(tile, (PAD + i * (S + PAD), y3))
    d.text((PAD + i * (S + PAD), y3 + S + 6), wall, fill=SUB)

OUT = pathlib.Path(sys.argv[1] if len(sys.argv)>1 else '/tmp/icon_preview.png')
cv.save(OUT)
print('OK preview', cv.size, '->', OUT)
