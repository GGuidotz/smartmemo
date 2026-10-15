#!/usr/bin/env python3
"""Disegna l'icona classica di SmartMemo: Resources/Icon/AppIcon-1024.png (serve Pillow).
Un foglio chiaro nella forma delle icone macOS; tre righe di appunti: la prima con la capsula di un progetto, la
seconda con la sottolineatura a puntini di una persona, la terza con quella di una data; in alto la scintilla
dell'accensione.
    python3 -I tools/render-icon.py
"""
import math, os
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
S = 4  # disegno a 4x e riduco: bordi lisci
W = 1024 * S

def px(v): return int(v * S)

img = Image.new("RGBA", (W, W), (0, 0, 0, 0))

# Ombra
shadow = Image.new("RGBA", (W, W), (0, 0, 0, 0))
ImageDraw.Draw(shadow).rounded_rectangle([px(100), px(112), px(924), px(936)], radius=px(185), fill=(0, 0, 0, 90))
shadow = shadow.filter(ImageFilter.GaussianBlur(px(18)))
img.alpha_composite(shadow)

# Foglio con una sfumatura leggera dall'alto
sheet = Image.new("RGBA", (W, W), (0, 0, 0, 0))
grad = Image.new("RGBA", (W, W))
gd = ImageDraw.Draw(grad)
top, bottom = (255, 255, 255), (232, 236, 246)
for y in range(W):
    t = y / W
    gd.line([(0, y), (W, y)], fill=tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3)) + (255,))
mask = Image.new("L", (W, W), 0)
ImageDraw.Draw(mask).rounded_rectangle([px(100), px(100), px(924), px(924)], radius=px(185), fill=255)
sheet.paste(grad, (0, 0), mask)
img.alpha_composite(sheet)

d = ImageDraw.Draw(img)
gray = (196, 201, 214, 255)
blue = (10, 132, 255)
indigo = (94, 92, 230)
orange = (255, 159, 10)
x0 = px(215)
h = px(46)

# Riga 1: capsula progetto + testo
y = px(330)
d.rounded_rectangle([x0, y - px(12), x0 + px(190), y + h + px(12)], radius=px(35), fill=blue + (60,), outline=blue + (190,), width=px(6))
d.rounded_rectangle([x0 + px(32), y + px(4), x0 + px(158), y + h - px(4)], radius=px(19), fill=blue + (255,))
d.rounded_rectangle([x0 + px(230), y, px(800), y + h], radius=px(23), fill=gray)

# Riga 2: persona, a puntini
y = px(480)
d.rounded_rectangle([x0, y, x0 + px(250), y + h], radius=px(23), fill=gray)
d.rounded_rectangle([x0 + px(285), y, px(760), y + h], radius=px(23), fill=indigo + (255,))
for cx in range(x0 + px(295), px(760), px(34)):
    d.ellipse([cx, y + h + px(16), cx + px(14), y + h + px(30)], fill=indigo + (255,))

# Riga 3: data, sottolineatura spessa
y = px(630)
d.rounded_rectangle([x0, y, x0 + px(300), y + h], radius=px(23), fill=gray)
d.rounded_rectangle([x0 + px(335), y, px(690), y + h], radius=px(23), fill=gray)
d.rounded_rectangle([x0 + px(335), y + h + px(14), px(690), y + h + px(30)], radius=px(8), fill=orange + (255,))

# Scintilla
def sparkle(cx, cy, r, color):
    pts = []
    for i in range(8):
        a = math.pi / 4 * i - math.pi / 2
        rr = r if i % 2 == 0 else r * 0.22
        pts.append((cx + rr * math.cos(a), cy + rr * math.sin(a)))
    d.polygon(pts, fill=color)

glow = Image.new("RGBA", (W, W), (0, 0, 0, 0))
ImageDraw.Draw(glow).ellipse([px(700), px(130), px(900), px(330)], fill=(255, 214, 10, 120))
glow = glow.filter(ImageFilter.GaussianBlur(px(30)))
img.alpha_composite(glow)
d = ImageDraw.Draw(img)
sparkle(px(800), px(230), px(92), (255, 196, 0, 255))
sparkle(px(675), px(165), px(36), (255, 196, 0, 255))

out = os.path.join(ROOT, "Resources", "Icon", "AppIcon-1024.png")
img.resize((1024, 1024), Image.LANCZOS).save(out)
print(out)
