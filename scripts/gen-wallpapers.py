#!/usr/bin/env python3
"""Procedural wallpapers: six layered-gradient landscapes, each with a night and a day variant.

One style for all: vertical sky gradient, a soft sun or moon glow, five ridgelines that fade into the
horizon colour (atmospheric perspective), a little grain. 5120x3200 to match the shipped wallpapers.

    python3 scripts/gen-wallpapers.py OUTDIR [name ...]     # needs pillow and numpy
Writes OUTDIR/wall-<name>-<night|day>.png and a 800x500 -thumb.jpg. Convert the PNGs to HEIC with
`heif-enc -q 58` for the app's `App/Mac/Wallpapers/` folder.
"""
import sys, os
import numpy as np
from PIL import Image

W, H = 5120, 3200


def hx(s):
    return np.array([int(s[i : i + 2], 16) for i in (1, 3, 5)], np.float32) / 255


# name -> variant -> (sky top, sky mid, horizon, glow, near ridge, sun x, sun y, moon?)
PALETTES = {
    "dusk": {  # rose and pink
        "night": ("#1c1038", "#5a2a6e", "#d9628f", "#ff9ac0", "#160a26", 0.68, 0.34),
        "day": ("#f6a6c4", "#fbc7d6", "#ffe9e0", "#fff6ea", "#a8467a", 0.68, 0.34),
    },
    "lagoon": {  # mint and teal
        "night": ("#06223a", "#0c5c66", "#3fd1b0", "#a8ffe6", "#04202a", 0.30, 0.30),
        "day": ("#7fd9e6", "#b6f0e0", "#effff4", "#ffffff", "#1c8f86", 0.30, 0.30),
    },
    "ember": {  # orange dawn
        "night": ("#240f10", "#7a2a14", "#ff8a2e", "#ffc27a", "#1a0a08", 0.50, 0.42),
        "day": ("#ffb36b", "#ffd2a0", "#fff0d8", "#fffaf0", "#c4541f", 0.50, 0.42),
    },
    "zenith": {  # sky blue noon
        "night": ("#050c26", "#12307a", "#3d8fe6", "#9fd0ff", "#060f2a", 0.74, 0.26),
        "day": ("#3b96f0", "#8cc8fb", "#e4f3ff", "#ffffff", "#2a64b8", 0.74, 0.26),
    },
    "orchid": {  # violet and indigo haze
        "night": ("#0f0a30", "#3a1f8a", "#9a5cf0", "#d9b8ff", "#0c0724", 0.24, 0.36),
        "day": ("#9b86f2", "#c9b9fa", "#f3ecff", "#ffffff", "#5a3fc0", 0.24, 0.36),
    },
    "crimson": {  # red mesa
        "night": ("#1c0608", "#6a1218", "#e23a3a", "#ff9a8a", "#140405", 0.58, 0.30),
        "day": ("#f07a6a", "#f8a898", "#ffe6dc", "#fff6f0", "#a82a2e", 0.58, 0.30),
    },
}


def fbm(n, seed, octaves=6, base=3.0):
    """1-D value noise summed over octaves, in 0..1, length n."""
    rng = np.random.default_rng(seed)
    x = np.linspace(0, 1, n, dtype=np.float32)
    out = np.zeros(n, np.float32)
    amp, freq, tot = 1.0, base, 0.0
    for _ in range(octaves):
        pts = rng.random(int(freq) + 3).astype(np.float32)
        xi = x * freq
        i = xi.astype(int)
        f = xi - i
        f = f * f * (3 - 2 * f)
        out += amp * (pts[i] * (1 - f) + pts[i + 1] * f)
        tot += amp
        amp *= 0.5
        freq *= 2
    return out / tot


def render(name, night, seed):
    top, mid, hor, glow, near, sx, sy = PALETTES[name]["night" if night else "day"]
    top, mid, hor, glow, near = map(hx, (top, mid, hor, glow, near))
    y = np.linspace(0, 1, H, dtype=np.float32)[:, None]
    x = np.linspace(0, 1, W, dtype=np.float32)[None, :]
    horizon = 0.62
    t = np.clip(y / horizon, 0, 1)[..., None]
    img = np.where(
        t < 0.55,
        top + (mid - top) * (t / 0.55),
        mid + (hor - mid) * ((t - 0.55) / 0.45),
    ).astype(np.float32) * np.ones((1, W, 1), np.float32)
    # sun / moon glow, aspect-corrected so it stays round
    d = np.sqrt(((x - sx) * W / H) ** 2 + (y - sy) ** 2)
    g = np.exp(-(d / 0.20) ** 2)[..., None] * (0.55 if night else 0.8)
    img = img + (glow - img) * g
    core = np.clip((0.045 - d) / 0.003, 0, 1)[..., None]  # crisp disc, 1.5 px edge at 5K
    img = img + (np.minimum(glow + 0.15, 1) - img) * core * (0.95 if night else 0.9)
    if night:  # stars, only in the upper sky
        rng = np.random.default_rng(seed)
        n = 900
        xs, ys = rng.integers(0, W, n), (rng.random(n) ** 1.6 * H * 0.45).astype(int)
        for a, b in zip(xs, ys):
            br = rng.random() * 0.7 + 0.2
            sl = (slice(b, b + 3), slice(a, a + 3))
            img[sl] = img[sl] + (1 - img[sl]) * br * 0.6
    # ridgelines, far to near
    px = np.arange(H, dtype=np.float32)[:, None]
    for i in range(5):
        k = i / 4
        base = H * (horizon - 0.02 + 0.30 * k)
        amp = H * (0.07 + 0.05 * k)
        prof = base - amp * (fbm(W, seed * 10 + i, 6, 2.5 + i * 0.8) - 0.3) * (1.6 - 0.4 * k)
        cov = np.clip(px - prof[None, :] + 0.75, 0, 1)[..., None]  # 1.5 px anti-aliased edge
        fade = 0.80 * (1 - k) ** 1.3
        col = near + (hor - near) * fade
        # a touch of vertical shading inside each ridge: lighter at its crest
        depth = np.clip((px - prof[None, :]) / (H * 0.25), 0, 1)[..., None]
        shade = col * (1 - 0.18 * depth) + (hor * 0.25 + glow * 0.15) * (1 - depth) * 0.25 * (1 - k)
        img = img * (1 - cov) + shade * cov
    rng = np.random.default_rng(seed + 99)
    img = img + (rng.standard_normal((H, W, 1), dtype=np.float32) * 0.012)
    return Image.fromarray((np.clip(img, 0, 1) * 255 + 0.5).astype(np.uint8))


def main():
    out = sys.argv[1]
    names = sys.argv[2:] or list(PALETTES)
    os.makedirs(out, exist_ok=True)
    for seed, name in enumerate(PALETTES, 1):
        if name not in names:
            continue
        for night in (True, False):
            tag = "night" if night else "day"
            im = render(name, night, seed)
            im.save(f"{out}/wall-{name}-{tag}.png")
            im.resize((800, 500), Image.LANCZOS).save(f"{out}/wall-{name}-{tag}-thumb.jpg", quality=82)
            print(name, tag)


if __name__ == "__main__":
    main()
