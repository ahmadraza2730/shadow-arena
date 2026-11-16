#!/usr/bin/env python3
"""Generates every texture in Game/assets/textures/ procedurally (no
downloads, no licences to worry about): colour, normal and roughness maps
for brick, concrete, plaster, ground, container metal, painted metal,
wood, roofing, tread plate and camouflage, plus a cloud layer for the sky
and a few sign boards. All surface textures tile seamlessly.

Run:  python3 MapSource/gen_textures.py      (needs numpy and Pillow)
"""
import os
import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "Game", "assets", "textures")
os.makedirs(OUT, exist_ok=True)
rng = np.random.default_rng(7)


# ------------------------------------------------------------ helpers
def fbm(n, beta=2.0, seed=None, aspect=1.0):
    """Tileable fractal noise in 0..1 made by filtering white noise in
    frequency space (anything built from an FFT wraps around perfectly)."""
    r = np.random.default_rng(seed) if seed is not None else rng
    white = r.standard_normal((n, n))
    fx = np.fft.fftfreq(n)[None, :] * aspect
    fy = np.fft.fftfreq(n)[:, None]
    f = np.sqrt(fx * fx + fy * fy)
    f[0, 0] = 1.0
    spectrum = np.fft.fft2(white) / (f ** (beta / 2.0))
    spectrum[0, 0] = 0.0
    out = np.real(np.fft.ifft2(spectrum))
    out -= out.min()
    return out / out.max()


def blur(a, sigma):
    """Wrap-around Gaussian blur via FFT."""
    n = a.shape[0]
    fx = np.fft.fftfreq(n)[None, :]
    fy = np.fft.fftfreq(a.shape[0])[:, None]
    kernel = np.exp(-2.0 * (np.pi ** 2) * (sigma ** 2) * (fx * fx + fy * fy))
    return np.real(np.fft.ifft2(np.fft.fft2(a) * kernel))


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def normal_from_height(h, strength):
    dx = (np.roll(h, -1, axis=1) - np.roll(h, 1, axis=1)) * strength
    dy = (np.roll(h, -1, axis=0) - np.roll(h, 1, axis=0)) * strength
    nz = np.ones_like(h)
    length = np.sqrt(dx * dx + dy * dy + nz * nz)
    return np.stack([(-dx / length) * 0.5 + 0.5, (dy / length) * 0.5 + 0.5, (nz / length) * 0.5 + 0.5], axis=-1)


def mix(a, b, t):
    if t.ndim == 2 and np.ndim(a) >= 1 and (np.ndim(a) == 1 or a.ndim == 3):
        t = t[..., None]
    return a * (1.0 - t) + b * t


def color(r, g, b):
    return np.array([r, g, b], dtype=np.float64)


def save_set(name, albedo, height, rough, normal_strength):
    Image.fromarray((np.clip(albedo, 0, 1) * 255).astype(np.uint8)).save(
        os.path.join(OUT, name + "_albedo.jpg"), quality=90)
    Image.fromarray((np.clip(normal_from_height(height, normal_strength), 0, 1) * 255).astype(np.uint8)).save(
        os.path.join(OUT, name + "_normal.jpg"), quality=93)
    Image.fromarray((np.clip(rough, 0, 1) * 255).astype(np.uint8)).save(
        os.path.join(OUT, name + "_rough.jpg"), quality=88)
    print("wrote", name)


def cracks(n, count, seed):
    """Thin wandering dark lines (wrap around the edges)."""
    r = np.random.default_rng(seed)
    img = Image.new("L", (n, n), 0)
    draw = ImageDraw.Draw(img)
    for _ in range(count):
        x, y = r.uniform(0, n, 2)
        angle = r.uniform(0, 2 * np.pi)
        for _ in range(int(r.uniform(60, 220))):
            angle += r.normal(0, 0.35)
            nx, ny = x + np.cos(angle) * 4, y + np.sin(angle) * 4
            for ox in (-n, 0, n):
                for oy in (-n, 0, n):
                    draw.line((x + ox, y + oy, nx + ox, ny + oy), fill=255, width=1)
            x, y = nx % n, ny % n
    return np.asarray(img.filter(ImageFilter.GaussianBlur(0.6)), dtype=np.float64) / 255.0


# ------------------------------------------------------------ surfaces
def make_brick(n=1024):
    cols, rows = 8, 24                     # 2 m tile: bricks 25 x 8.3 cm
    y, x = np.mgrid[0:n, 0:n] / n
    gy = y * rows
    row = np.floor(gy)
    gx = x * cols + (row % 2) * 0.5
    col = np.floor(gx) % cols
    fx, fy = gx - np.floor(gx), gy - row
    mortar_x, mortar_y = 0.035, 0.11
    edge = np.minimum(np.minimum(fx, 1 - fx) / mortar_x, np.minimum(fy, 1 - fy) / mortar_y)
    is_brick = smoothstep(0.7, 1.5, edge)
    ids = (row * cols + col).astype(int)
    r = np.random.default_rng(11)
    tone = r.uniform(0.0, 1.0, rows * cols)[ids]
    dark = (r.uniform(0, 1, rows * cols) < 0.08)[ids]
    grain = fbm(n, 1.6, 12)
    dirt = fbm(n, 2.6, 13)
    base = mix(color(0.52, 0.22, 0.15), color(0.66, 0.33, 0.2), tone)
    base = mix(base, color(0.3, 0.16, 0.13), dark.astype(float) * 0.8)
    base = base * (0.82 + 0.36 * grain[..., None])
    mortar = color(0.62, 0.58, 0.52) * (0.8 + 0.3 * fbm(n, 1.2, 14)[..., None])
    albedo = mix(mortar, base, is_brick)
    albedo = albedo * (1.0 - 0.35 * smoothstep(0.55, 0.9, dirt)[..., None])     # soot / damp
    height = is_brick * (0.75 + 0.25 * tone) + 0.12 * grain
    rough = mix(np.full((n, n), 0.95), 0.8 + 0.12 * grain, is_brick)
    save_set("brick", albedo, height, rough, 3.2)


def make_concrete(n=1024):
    base = fbm(n, 2.2, 21)
    fine = fbm(n, 0.9, 22)
    stains = smoothstep(0.52, 0.85, fbm(n, 3.0, 23, aspect=3.0))     # vertical streaks
    pores = smoothstep(0.86, 0.95, fbm(n, 0.4, 24))
    crack = cracks(n, 5, 25)
    shade = 0.74 + 0.2 * base + 0.08 * fine
    albedo = color(0.64, 0.62, 0.58)[None, None, :] * shade[..., None]
    albedo = mix(albedo, albedo * color(0.62, 0.58, 0.5), stains * 0.75)
    albedo = albedo * (1.0 - 0.5 * pores[..., None]) * (1.0 - 0.7 * crack[..., None])
    height = 0.5 + 0.2 * base + 0.1 * fine - 0.5 * pores - 0.8 * crack
    rough = 0.85 + 0.1 * fine - 0.1 * stains
    save_set("concrete", albedo, height, rough, 2.0)


def make_plaster(n=1024):
    big = fbm(n, 2.8, 31)
    fine = fbm(n, 1.0, 32)
    flake = smoothstep(0.6, 0.66, fbm(n, 2.3, 33))                  # paint flaked off
    damp = smoothstep(0.5, 0.9, fbm(n, 3.2, 34, aspect=2.5))
    paint = color(0.83, 0.75, 0.55)[None, None, :] * (0.86 + 0.16 * big[..., None])
    under = color(0.55, 0.53, 0.5)[None, None, :] * (0.75 + 0.3 * fine[..., None])
    albedo = mix(paint, under, flake)
    albedo = mix(albedo, albedo * color(0.6, 0.62, 0.5), damp * 0.6)
    albedo = albedo * (1.0 - 0.6 * cracks(n, 4, 35)[..., None])
    height = 0.6 + 0.08 * fine - 0.25 * flake
    rough = 0.82 + 0.12 * flake + 0.05 * fine
    save_set("plaster", albedo, height, rough, 2.2)


def make_ground(n=1024):
    big = fbm(n, 2.6, 41)
    mid = fbm(n, 1.8, 42)
    fine = fbm(n, 0.7, 43)
    pebbles = smoothstep(0.8, 0.9, fbm(n, 0.9, 44))
    asphalt = smoothstep(0.66, 0.74, fbm(n, 2.9, 45))                # broken tarmac patches
    dirt = mix(color(0.47, 0.38, 0.27), color(0.62, 0.53, 0.38), big)
    dirt = dirt * (0.8 + 0.3 * mid[..., None])
    tar = color(0.2, 0.2, 0.21)[None, None, :] * (0.8 + 0.5 * fine[..., None])
    albedo = mix(dirt, tar, asphalt * 0.6)
    albedo = mix(albedo, color(0.68, 0.64, 0.58)[None, None, :] * (0.8 + 0.3 * fine[..., None]), pebbles * 0.8)
    albedo = albedo * (1.0 - 0.6 * cracks(n, 7, 46)[..., None] * asphalt[..., None])
    height = 0.4 * mid + 0.15 * fine + 0.5 * pebbles + 0.12 * asphalt
    rough = 0.95 - 0.12 * asphalt + 0.03 * fine
    save_set("ground", albedo, height, rough, 2.4)


def make_container(n=1024):
    """Corrugated steel, light grey so the material colour tints it."""
    y, x = np.mgrid[0:n, 0:n] / n
    ribs = 12                                                       # 2.4 m tile: a rib every 20 cm
    phase = (x * ribs) % 1.0
    profile = smoothstep(0.0, 0.18, phase) * (1.0 - smoothstep(0.5, 0.68, phase))
    grime = fbm(n, 2.4, 51, aspect=4.0)
    rust_mask = smoothstep(0.62, 0.74, fbm(n, 2.2, 52, aspect=2.0) + 0.1 * (1 - profile))
    scratch = smoothstep(0.9, 0.97, fbm(n, 0.6, 53, aspect=0.15))
    paint = color(0.86, 0.86, 0.86)[None, None, :] * (0.8 + 0.2 * profile[..., None]) \
        * (0.85 + 0.2 * grime[..., None])
    rust = mix(color(0.36, 0.17, 0.08), color(0.55, 0.3, 0.14), fbm(n, 1.2, 54))
    albedo = mix(paint, rust, rust_mask)
    albedo = mix(albedo, np.full(3, 0.75), scratch * 0.5)
    height = profile + 0.05 * fbm(n, 1.0, 55) - 0.08 * rust_mask
    rough = 0.45 + 0.45 * rust_mask + 0.1 * grime
    save_set("container", albedo, height, rough, 2.6)


def make_painted_metal(n=512):
    grime = fbm(n, 2.4, 61)
    rust_mask = smoothstep(0.66, 0.78, fbm(n, 2.0, 62))
    scratch = smoothstep(0.9, 0.97, fbm(n, 0.6, 63, aspect=0.2))
    paint = np.full((n, n, 3), 0.86) * (0.82 + 0.2 * grime[..., None])
    rust = mix(color(0.36, 0.17, 0.08), color(0.55, 0.3, 0.14), fbm(n, 1.2, 64))
    albedo = mix(paint, rust, rust_mask)
    albedo = mix(albedo, np.full(3, 0.7), scratch * 0.6)
    height = 0.5 - 0.15 * rust_mask + 0.05 * grime - 0.1 * scratch
    rough = 0.4 + 0.5 * rust_mask + 0.1 * grime
    save_set("painted_metal", albedo, height, rough, 1.6)


def make_wood(n=512):
    planks = 8                                                      # 1.2 m tile: 15 cm planks
    y, x = np.mgrid[0:n, 0:n] / n
    row = np.floor(y * planks)
    fy = y * planks - row
    gap = 1.0 - smoothstep(0.0, 0.06, np.minimum(fy, 1 - fy))
    r = np.random.default_rng(71)
    tone = r.uniform(0, 1, planks)[row.astype(int)]
    grain = fbm(n, 1.8, 72, aspect=0.06)                            # long streaks along the plank
    knots = smoothstep(0.9, 0.97, fbm(n, 1.4, 73))
    base = mix(color(0.5, 0.36, 0.2), color(0.68, 0.52, 0.32), tone)
    albedo = base * (0.72 + 0.45 * grain[..., None])
    albedo = albedo * (1.0 - 0.5 * knots[..., None]) * (1.0 - 0.75 * gap[..., None])
    # nail heads near the plank ends
    nails = np.zeros((n, n))
    for p in range(planks):
        cy = int((p + 0.5) / planks * n)
        for cx in (int(0.04 * n), int(0.54 * n)):
            nails[cy - 2:cy + 3, cx - 2:cx + 3] = 1.0
    albedo = mix(albedo, np.full(3, 0.2), nails)
    height = 0.6 + 0.25 * grain - 0.7 * gap - 0.2 * knots
    rough = 0.8 + 0.1 * grain
    save_set("wood", albedo, height, rough, 2.2)


def make_roof(n=512):
    big = fbm(n, 2.4, 81)
    fine = fbm(n, 0.6, 82)
    patches = smoothstep(0.58, 0.63, fbm(n, 2.8, 83))
    gravel = smoothstep(0.82, 0.9, fine)
    albedo = color(0.27, 0.27, 0.28)[None, None, :] * (0.75 + 0.4 * big[..., None])
    albedo = mix(albedo, albedo * 0.6, patches)
    albedo = mix(albedo, np.full(3, 0.5), gravel * 0.6)
    height = 0.3 * big + 0.5 * gravel + 0.1 * patches
    rough = 0.9 - 0.25 * patches
    save_set("roof", albedo, height, rough, 2.0)


def make_tread_plate(n=512):
    """Steel floor plate with raised diamond lugs (ramps and landings)."""
    y, x = np.mgrid[0:n, 0:n] / n
    cells = 16
    u, v = (x + y) * cells, (x - y) * cells
    fu, fv = u % 1.0, v % 1.0
    cu, cv = np.floor(u), np.floor(v)
    flip = ((cu + cv) % 2) < 1
    a = np.where(flip, np.abs(fu - 0.5) / 0.42 + np.abs(fv - 0.5) / 0.12, np.abs(fu - 0.5) / 0.12 + np.abs(fv - 0.5) / 0.42)
    lug = 1.0 - smoothstep(0.7, 1.0, a)
    wear = fbm(n, 2.2, 91)
    albedo = np.full((n, n, 3), 0.42) * (0.75 + 0.3 * wear[..., None]) + 0.18 * lug[..., None]
    rust = smoothstep(0.7, 0.8, fbm(n, 2.0, 92))
    albedo = mix(albedo, mix(color(0.36, 0.17, 0.08), color(0.5, 0.28, 0.14), wear), rust * 0.7)
    height = lug + 0.05 * wear
    rough = 0.55 - 0.2 * lug + 0.35 * rust
    save_set("tread_plate", albedo, height, rough, 2.4)


def make_camo(n=512):
    """Desert camouflage cloth; light enough that team colour can tint it."""
    a, b, c = fbm(n, 3.0, 101), fbm(n, 3.0, 102), fbm(n, 3.0, 103)
    albedo = np.empty((n, n, 3))
    albedo[:] = color(0.62, 0.56, 0.42)
    albedo = mix(albedo, color(0.4, 0.36, 0.26), smoothstep(0.52, 0.55, a))
    albedo = mix(albedo, color(0.3, 0.33, 0.22), smoothstep(0.6, 0.63, b))
    albedo = mix(albedo, color(0.75, 0.7, 0.58), smoothstep(0.66, 0.69, c))
    y, x = np.mgrid[0:n, 0:n]
    weave = 0.5 + 0.25 * np.sin(x * 2 * np.pi / 4) * np.sin(y * 2 * np.pi / 4)
    albedo = albedo * (0.9 + 0.2 * weave[..., None])
    save_set("camo", albedo, weave + 0.3 * fbm(n, 2.0, 104), np.full((n, n), 0.92), 1.2)


# ----------------------------------------------------------------- sky
def make_clouds(w=2048, h=1024):
    """A cloud layer as an equirectangular panorama with transparency.
    Clouds thin out straight overhead and stop below the horizon."""
    n = 2048
    noise = blur(fbm(n, 3.4, 111), 3.0)[:h, :] * 0.8 + blur(fbm(n, 2.4, 112), 1.5)[:h, :] * 0.2
    noise = (noise - noise.min()) / (noise.max() - noise.min())
    v = np.linspace(0.0, 1.0, h)[:, None]              # 0 = straight up, 0.5 = horizon
    band = smoothstep(0.08, 0.3, v) * (1.0 - smoothstep(0.47, 0.5, v))
    cover = smoothstep(0.5, 0.68, noise) * band
    shade = 0.82 + 0.18 * smoothstep(0.5, 0.9, noise)   # brighter tops, greyer bases
    rgba = np.zeros((h, w, 4))
    rgba[..., 0:3] = shade[..., None]
    rgba[..., 3] = cover * 0.9
    Image.fromarray((np.clip(rgba, 0, 1) * 255).astype(np.uint8), "RGBA").save(os.path.join(OUT, "clouds.png"))
    print("wrote clouds")


# --------------------------------------------------------------- signs
def font(size):
    for path in ("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
                 "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf"):
        if os.path.exists(path):
            return ImageFont.truetype(path, size)
    return ImageFont.load_default()


def make_sign(name, text, sub, bg, fg):
    w, h = 512, 256
    img = Image.new("RGB", (w, h), bg)
    draw = ImageDraw.Draw(img)
    draw.rectangle((8, 8, w - 9, h - 9), outline=fg, width=6)
    f1, f2 = font(74 if len(text) < 9 else 54), font(30)
    tw = draw.textlength(text, font=f1)
    draw.text(((w - tw) / 2, 52), text, font=f1, fill=fg)
    sw = draw.textlength(sub, font=f2)
    draw.text(((w - sw) / 2, 168), sub, font=f2, fill=fg)
    arr = np.asarray(img, dtype=np.float64) / 255.0
    wear = fbm(512, 2.2, sum(map(ord, name)) % 1000)[:h, :]
    rust = smoothstep(0.68, 0.8, fbm(512, 2.0, sum(map(ord, name)) % 977 + 3)[:h, :])
    arr = arr * (0.75 + 0.3 * wear[..., None])
    arr = arr * (1 - rust[..., None]) + np.array([0.42, 0.22, 0.1]) * rust[..., None]
    Image.fromarray((np.clip(arr, 0, 1) * 255).astype(np.uint8)).save(os.path.join(OUT, name + ".jpg"), quality=88)
    print("wrote", name)


def make_truck_art():
    """Bright striped panel in the spirit of Pakistani truck art."""
    w, h = 512, 256
    img = Image.new("RGB", (w, h), (150, 20, 30))
    d = ImageDraw.Draw(img)
    palette = [(250, 200, 30), (20, 120, 70), (30, 80, 170), (240, 240, 230), (230, 90, 30)]
    for i in range(0, w, 32):
        d.polygon([(i, 0), (i + 16, 0), (i + 32, 40), (i + 16, 40)], fill=palette[(i // 32) % 5])
        d.polygon([(i, h), (i + 16, h), (i + 32, h - 40), (i + 16, h - 40)], fill=palette[(i // 32 + 2) % 5])
    for k, cx in enumerate(range(64, w, 128)):
        for r, c in ((58, palette[0]), (46, palette[1]), (34, palette[3]), (20, palette[4]), (9, palette[2])):
            d.regular_polygon((cx, h // 2, r), 8, rotation=22.5 * (r % 2), fill=c)
    d.rectangle((0, 40, w - 1, 46), fill=palette[0])
    d.rectangle((0, h - 47, w - 1, h - 41), fill=palette[0])
    arr = np.asarray(img, dtype=np.float64) / 255.0
    arr = arr * (0.72 + 0.3 * fbm(512, 2.2, 131)[:h, :, None])
    Image.fromarray((np.clip(arr, 0, 1) * 255).astype(np.uint8)).save(os.path.join(OUT, "truck_art.jpg"), quality=88)
    print("wrote truck_art")


if __name__ == "__main__":
    make_brick(); make_concrete(); make_plaster(); make_ground(); make_container()
    make_painted_metal(); make_wood(); make_roof(); make_tread_plate(); make_camo()
    make_clouds()
    make_sign("sign_godown", "GODOWN 4", "TEXTILE MILLS (PVT) LTD", (26, 70, 120), (235, 230, 215))
    make_sign("sign_danger", "DANGER", "NO ENTRY  -  KEEP OUT", (200, 170, 20), (20, 20, 20))
    make_sign("sign_workshop", "WORKSHOP", "TRUCK & TRACTOR REPAIR", (120, 30, 25), (240, 235, 220))
    make_truck_art()
