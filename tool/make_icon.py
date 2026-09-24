"""Draws the Pitbeat app icon: a red heartbeat line on carbon black,
with white speed streaks. Original artwork, no Formula 1 marks.

Run it from the project folder to (re)make every icon size:
    pip3 install pillow
    python3 tool/make_icon.py
"""
import os
from PIL import Image, ImageDraw, ImageFilter

S = 1024
RED = (225, 6, 0)
CARBON = (21, 21, 30)

def make(size=S):
    k = 4  # draw big then shrink, for smooth edges
    W = size * k
    img = Image.new("RGB", (W, W), CARBON)
    d = ImageDraw.Draw(img)
    # soft diagonal lighter band for depth
    band = Image.new("L", (W, W), 0)
    bd = ImageDraw.Draw(band)
    bd.polygon([(0, int(W*0.55)), (int(W*0.55), 0), (int(W*0.85), 0), (0, int(W*0.85))], fill=40)
    band = band.filter(ImageFilter.GaussianBlur(W * 0.06))
    light = Image.new("RGB", (W, W), (48, 48, 62))
    img = Image.composite(light, img, band)
    d = ImageDraw.Draw(img)

    u = W / 100.0
    # speed streaks (left), white, fading
    for y, x0, x1, a in [(38, 8, 30, 90), (50, 4, 24, 150), (62, 10, 28, 90)]:
        streak = Image.new("RGBA", (W, W), (0, 0, 0, 0))
        sd = ImageDraw.Draw(streak)
        sd.line([(x0*u, y*u), (x1*u, y*u)], fill=(255, 255, 255, a), width=int(3.2*u))
        img = Image.alpha_composite(img.convert("RGBA"), streak).convert("RGB")
    d = ImageDraw.Draw(img)

    # heartbeat / pulse line
    pts = [(24, 50), (40, 50), (47, 34), (56, 72), (64, 22), (71, 50), (92, 50)]
    pts = [(x*u, y*u) for x, y in pts]
    width = int(7*u)
    d.line(pts, fill=RED, width=width, joint="curve")
    r = width / 2
    for (x, y) in (pts[0], pts[-1]):
        d.ellipse([x-r, y-r, x+r, y+r], fill=RED)
    return img.resize((size, size), Image.LANCZOS)

IOS_ICONS = {  # file name -> size in pixels (points x scale)
    "Icon-App-20x20@1x.png": 20, "Icon-App-20x20@2x.png": 40,
    "Icon-App-20x20@3x.png": 60, "Icon-App-29x29@1x.png": 29,
    "Icon-App-29x29@2x.png": 58, "Icon-App-29x29@3x.png": 87,
    "Icon-App-40x40@1x.png": 40, "Icon-App-40x40@2x.png": 80,
    "Icon-App-40x40@3x.png": 120, "Icon-App-60x60@2x.png": 120,
    "Icon-App-60x60@3x.png": 180, "Icon-App-76x76@1x.png": 76,
    "Icon-App-76x76@2x.png": 152, "Icon-App-83.5x83.5@2x.png": 167,
    "Icon-App-1024x1024@1x.png": 1024,
}
WEB_ICONS = {
    "web/icons/Icon-192.png": 192, "web/icons/Icon-512.png": 512,
    "web/icons/Icon-maskable-192.png": 192,
    "web/icons/Icon-maskable-512.png": 512, "web/favicon.png": 32,
}

if __name__ == "__main__":
    big = make(1024)
    ios_dir = "ios/Runner/Assets.xcassets/AppIcon.appiconset"
    for name, px in IOS_ICONS.items():
        big.resize((px, px), Image.LANCZOS).save(os.path.join(ios_dir, name))
    for path, px in WEB_ICONS.items():
        big.resize((px, px), Image.LANCZOS).save(path)
    print("Icons written. Rebuild the app to see them.")
