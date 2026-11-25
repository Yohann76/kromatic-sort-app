"""Génère l'icône de l'app (plein cadre + premier plan adaptatif) avec Pillow."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter

OUT = Path(__file__).resolve().parent.parent / "assets" / "icon"
S = 1024
COLORS = [("#FF5C7A", "#FFB547", "#3DDC97"), ("#4DA3FF", "#B36BFF", "#FF5C7A"), ("#FFB547", "#3DDC97", "#4DA3FF")]


def tubes(scale):
    """Dessine 3 éprouvettes remplies de couleurs sur un calque transparent."""
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    tw, th, gap = 190 * scale, 560 * scale, 70 * scale
    total = 3 * tw + 2 * gap
    x0 = (S - total) / 2
    y0 = (S - th) / 2
    for i, cols in enumerate(COLORS):
        x = x0 + i * (tw + gap)
        d.rounded_rectangle([x, y0, x + tw, y0 + th], radius=tw / 2, fill=(255, 255, 255, 40),
                            outline=(255, 255, 255, 220), width=int(10 * scale))
        layer_h = (th - 40 * scale) / 4
        for j, c in enumerate(cols):
            ly1 = y0 + th - 20 * scale - j * layer_h
            ly0 = ly1 - layer_h
            mask = Image.new("L", (S, S), 0)
            md = ImageDraw.Draw(mask)
            md.rounded_rectangle([x + 16 * scale, y0 + 16 * scale, x + tw - 16 * scale, y0 + th - 16 * scale],
                                 radius=(tw - 32 * scale) / 2, fill=255)
            band = Image.new("RGBA", (S, S), (0, 0, 0, 0))
            ImageDraw.Draw(band).rectangle([x, ly0, x + tw, ly1], fill=c)
            band.putalpha(Image.composite(band.getchannel("A"), Image.new("L", (S, S), 0), mask))
            img = Image.alpha_composite(img, band)
        d = ImageDraw.Draw(img)
    return img


def background():
    bg = Image.new("RGBA", (S, S))
    px = bg.load()
    top, bot = (38, 30, 84), (14, 12, 36)
    for y in range(S):
        r = y / (S - 1)
        c = tuple(int(top[k] * (1 - r) + bot[k] * r) for k in range(3)) + (255,)
        for x in range(S):
            px[x, y] = c
    return bg


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    full = Image.alpha_composite(background(), tubes(1.0))
    full.convert("RGB").save(OUT / "icon.png")
    # premier plan adaptatif : contenu réduit pour rester dans la zone sûre (66 %)
    fg = tubes(0.62)
    fg.save(OUT / "icon_fg.png")
    print("OK")
