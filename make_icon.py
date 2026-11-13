import math, os
from PIL import Image, ImageDraw

SIZES = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
BASE = 1024

def drop_mask(size):
    m = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(m)
    # gota: circulo + triangulo superior
    r = size * 0.30
    cx, cy = size * 0.5, size * 0.63
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=255)
    tip = (cx, size * 0.10)
    d.polygon([tip, (cx - r * 0.99, cy - r * 0.30), (cx + r * 0.99, cy - r * 0.30)], fill=255)
    return m

def render(size):
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    # fondo con degradado
    bg = Image.new("RGBA", (size, size))
    px = bg.load()
    for y in range(size):
        for x in range(size):
            t = (x / size * 0.45 + y / size * 0.55)
            r = int(4 + 10 * t)
            g = int(30 + 90 * t)
            b = int(48 + 130 * t)
            px[x, y] = (r, g, b, 255)
    mask_bg = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask_bg).rounded_rectangle([0, 0, size - 1, size - 1], radius=int(size * 0.22), fill=255)
    img.paste(bg, (0, 0), mask_bg)

    # halo
    glow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse(
        [size * 0.18, size * 0.28, size * 0.82, size * 0.92],
        fill=(0, 209, 255, 90),
    )
    img.alpha_composite(glow.filter(__import__("PIL.ImageFilter", fromlist=["ImageFilter"]).GaussianBlur(size * 0.06)))

    # gota con degradado vertical
    dm = drop_mask(size)
    grad = Image.new("RGBA", (size, size))
    gp = grad.load()
    for y in range(size):
        t = y / size
        gp_row = (
            int(180 + 75 * (1 - t)),
            int(250 - 30 * t),
            int(255 - 20 * t),
            255,
        )
        for x in range(size):
            gp[x, y] = gp_row
    img.paste(grad, (0, 0), dm)

    # brillo interior
    sh = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(sh)
    d.ellipse([size * 0.40, size * 0.42, size * 0.47, size * 0.55], fill=(255, 255, 255, 200))
    img.alpha_composite(sh)
    return img

master = render(BASE)
res = os.path.join("android", "app", "src", "main", "res")
for dpi, s in SIZES.items():
    out = os.path.join(res, f"mipmap-{dpi}")
    os.makedirs(out, exist_ok=True)
    master.resize((s, s), Image.LANCZOS).save(os.path.join(out, "ic_launcher.png"), "PNG")
print("iconos generados:", ", ".join(SIZES))
master.resize((512, 512), Image.LANCZOS).save("logo-512.png", "PNG")
