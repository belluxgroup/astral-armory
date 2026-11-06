"""Procedural VFX textures for Astral Armory.

Writes white/greyscale RGBA PNGs into assets/textures so Roblox can tint them
through Color. Run from the repo root:

    python tools/gen_textures.py

Every texture is deterministic (fixed seeds), so re-running produces the same
files byte for byte.
"""

from __future__ import annotations

import math
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

SIZE = 512
OUT_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets", "textures")


# ---------------------------------------------------------------- helpers


def grid(size: int = SIZE) -> tuple[np.ndarray, np.ndarray]:
    """Pixel-centre coordinates in [-1, 1], y pointing down like the image."""
    c = (np.arange(size, dtype=np.float64) + 0.5) / size * 2.0 - 1.0
    x, y = np.meshgrid(c, c)
    return x, y


def smoothstep(e0: float, e1: float, v: np.ndarray) -> np.ndarray:
    t = np.clip((v - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def value_noise(size: int, cells: int, seed: int) -> np.ndarray:
    """Tileable value noise in [0, 1] with smooth (quintic) interpolation."""
    rng = np.random.default_rng(seed)
    lattice = rng.random((cells, cells))
    coords = np.arange(size, dtype=np.float64) / size * cells
    i0 = np.floor(coords).astype(int)
    f = coords - i0
    f = f * f * f * (f * (f * 6.0 - 15.0) + 10.0)
    i1 = (i0 + 1) % cells
    i0 = i0 % cells
    # rows (y) then columns (x)
    a = lattice[np.ix_(i0, i0)]
    b = lattice[np.ix_(i0, i1)]
    c = lattice[np.ix_(i1, i0)]
    d = lattice[np.ix_(i1, i1)]
    fx = f[np.newaxis, :]
    fy = f[:, np.newaxis]
    top = a + (b - a) * fx
    bottom = c + (d - c) * fx
    return top + (bottom - top) * fy


def fbm(size: int, base_cells: int, octaves: int, seed: int, gain: float = 0.5) -> np.ndarray:
    total = np.zeros((size, size))
    amp, norm = 1.0, 0.0
    for o in range(octaves):
        total += value_noise(size, base_cells * (2**o), seed + o * 101) * amp
        norm += amp
        amp *= gain
    return total / norm


def noise_1d_periodic(n: int, cells: int, seed: int) -> np.ndarray:
    """Smooth periodic 1D noise in [0, 1] sampled at n points over one period."""
    rng = np.random.default_rng(seed)
    lattice = rng.random(cells)
    coords = np.arange(n, dtype=np.float64) / n * cells
    i0 = np.floor(coords).astype(int)
    f = coords - i0
    f = f * f * (3.0 - 2.0 * f)
    return lattice[i0 % cells] + (lattice[(i0 + 1) % cells] - lattice[i0 % cells]) * f


def to_image(lum: np.ndarray, alpha: np.ndarray) -> Image.Image:
    rgb = np.clip(lum, 0.0, 1.0)
    a = np.clip(alpha, 0.0, 1.0)
    data = np.dstack([rgb, rgb, rgb, a])
    return Image.fromarray((data * 255.0 + 0.5).astype(np.uint8), "RGBA")


def white(alpha: np.ndarray) -> Image.Image:
    return to_image(np.ones_like(alpha), alpha)


def save(img: Image.Image, name: str) -> None:
    path = os.path.join(OUT_DIR, name + ".png")
    img.save(path, optimize=True)
    print(f"wrote {path} {img.size} {img.mode}")


def supersampled_mask(draw_fn, size: int = SIZE, ss: int = 4) -> np.ndarray:
    """Draw with ImageDraw at ss x resolution, return an anti-aliased [0,1] mask."""
    big = Image.new("L", (size * ss, size * ss), 0)
    draw_fn(ImageDraw.Draw(big), size * ss)
    small = big.resize((size, size), Image.Resampling.LANCZOS)
    return np.asarray(small, dtype=np.float64) / 255.0


def blur(mask: np.ndarray, radius: float) -> np.ndarray:
    img = Image.fromarray((np.clip(mask, 0, 1) * 255).astype(np.uint8), "L")
    out = img.filter(ImageFilter.GaussianBlur(radius))
    return np.asarray(out, dtype=np.float64) / 255.0


# ---------------------------------------------------------------- textures


def glow_soft() -> Image.Image:
    x, y = grid()
    r = np.sqrt(x * x + y * y)
    # Gaussian core with a long soft tail, forced to 0 at the edge.
    core = np.exp(-(r * r) / 0.06)
    tail = np.exp(-(r * r) / 0.35) * 0.55
    alpha = (core * 0.6 + tail) * (1.0 - smoothstep(0.75, 1.0, r))
    return white(alpha / alpha.max())


def glow_star() -> Image.Image:
    x, y = grid()
    r = np.sqrt(x * x + y * y)
    edge = 1.0 - smoothstep(0.8, 1.0, r)

    def spike(along: np.ndarray, across: np.ndarray, length: float, width: float) -> np.ndarray:
        fall = np.clip(1.0 - np.abs(along) / length, 0.0, 1.0) ** 2.2
        return np.exp(-((across / (width * (0.25 + fall))) ** 2)) * fall

    main = np.maximum(spike(x, y, 1.0, 0.035), spike(y, x, 1.0, 0.035))
    d1 = (x + y) / math.sqrt(2.0)
    d2 = (x - y) / math.sqrt(2.0)
    diag = np.maximum(spike(d1, d2, 0.45, 0.025), spike(d2, d1, 0.45, 0.025)) * 0.45
    core = np.exp(-(r * r) / 0.012) + np.exp(-(r * r) / 0.08) * 0.35
    alpha = np.clip(np.maximum(np.maximum(main, diag), core), 0.0, 1.0) * edge
    return white(alpha)


def spark() -> Image.Image:
    # Vertical streak (texture up axis), suited to Orientation = VelocityParallel.
    x, y = grid()
    length = np.clip(1.0 - np.abs(y) / 0.95, 0.0, 1.0)
    # Slightly heavier head toward the top so motion reads clearly.
    head = np.clip(1.0 - (y + 0.35) ** 2 / 0.9, 0.0, 1.0)
    width = 0.018 + 0.03 * length
    streak = np.exp(-((x / width) ** 2)) * length**1.4 * (0.55 + 0.45 * head)
    halo = np.exp(-((x / (width * 4.0)) ** 2)) * length**2.0 * 0.25
    alpha = np.clip(streak + halo, 0.0, 1.0)
    return white(alpha / alpha.max())


def smoke_soft() -> Image.Image:
    x, y = grid()
    r = np.sqrt(x * x + y * y)
    n = fbm(SIZE, 4, 5, seed=1337, gain=0.55)
    n = blur(n, 3.0)
    n = (n - n.min()) / (n.max() - n.min())
    # Warp the radial mask by low-frequency noise so the puff is not a perfect disc.
    warp = blur(fbm(SIZE, 3, 2, seed=77), 6.0)
    rr = r + (warp - 0.5) * 0.35
    mask = 1.0 - smoothstep(0.35, 0.95, rr)
    density = smoothstep(0.25, 0.85, n * 0.75 + mask * 0.45) * mask
    density *= 1.0 - smoothstep(0.88, 1.0, r)
    # Lighter top, darker bottom: cheap self-shadowing that survives tinting.
    lum = 0.78 + 0.22 * (1.0 - (y + 1.0) * 0.5) + (n - 0.5) * 0.15
    return to_image(lum, density)


GLYPH_STROKES = 24


def _glyph_segments(rng: np.random.Generator) -> list[tuple[tuple[float, float], tuple[float, float]]]:
    """An original glyph: 3-5 strokes snapped to a 3x4 lattice in unit space."""
    pts = [(gx / 2.0, gy / 3.0) for gx in range(3) for gy in range(4)]
    segs: list[tuple[tuple[float, float], tuple[float, float]]] = []
    spine_x = rng.integers(0, 3) / 2.0
    segs.append(((spine_x, 0.0), (spine_x, 1.0)))  # every glyph has a vertical spine
    for _ in range(int(rng.integers(2, 5))):
        a = pts[int(rng.integers(0, len(pts)))]
        b = pts[int(rng.integers(0, len(pts)))]
        if a != b:
            segs.append((a, b))
    return segs


def ring_runes() -> Image.Image:
    rng = np.random.default_rng(2406)
    glyphs = [_glyph_segments(rng) for _ in range(GLYPH_STROKES)]

    def draw(d: ImageDraw.ImageDraw, s: int) -> None:
        c = s / 2.0
        def ring(radius: float, w: float) -> None:
            r = radius * c
            d.ellipse((c - r, c - r, c + r, c + r), outline=255, width=max(1, int(w * c)))
        ring(0.97, 0.018)
        ring(0.92, 0.008)
        ring(0.66, 0.008)
        ring(0.61, 0.016)
        # Tick marks between the outer rings.
        for i in range(96):
            a = i / 96.0 * math.tau
            r0, r1 = (0.92, 0.95) if i % 4 else (0.90, 0.97)
            d.line(
                (c + math.cos(a) * r0 * c, c + math.sin(a) * r0 * c, c + math.cos(a) * r1 * c, c + math.sin(a) * r1 * c),
                fill=255,
                width=max(1, int(0.006 * c)),
            )
        # 24 glyphs in the band between radius 0.66 and 0.92, upright relative to the ring.
        gh, gw = 0.17, 0.085
        mid = 0.79
        stroke = max(1, int(0.012 * c))
        for i, segs in enumerate(glyphs):
            a = i / len(glyphs) * math.tau
            ux, uy = math.cos(a), math.sin(a)  # radial (glyph up = outward)
            tx, ty = -uy, ux  # tangent
            def place(p: tuple[float, float]) -> tuple[float, float]:
                gx = (p[0] - 0.5) * gw
                gy = (p[1] - 0.5) * gh
                px = mid * ux + gx * tx - gy * ux
                py = mid * uy + gx * ty - gy * uy
                return (c + px * c, c + py * c)
            for p0, p1 in segs:
                d.line((*place(p0), *place(p1)), fill=255, width=stroke)
            # A dot accent between glyphs.
            a2 = (i + 0.5) / len(glyphs) * math.tau
            dr = 0.008 * c
            dx, dy = c + math.cos(a2) * mid * c, c + math.sin(a2) * mid * c
            d.ellipse((dx - dr, dy - dr, dx + dr, dy + dr), fill=255)
        # Inner hexagram for a focal centre.
        for k in range(2):
            poly = []
            for j in range(3):
                a = j / 3.0 * math.tau + k * math.pi / 3.0 - math.pi / 2.0
                poly.append((c + math.cos(a) * 0.58 * c, c + math.sin(a) * 0.58 * c))
            d.polygon(poly, outline=255, width=max(1, int(0.007 * c)))

    lines = supersampled_mask(draw)
    glow = blur(lines, 6.0)
    alpha = np.clip(lines + glow * 0.6, 0.0, 1.0)
    return white(alpha)


def hex_cell() -> Image.Image:
    x, y = grid()
    # Flat-top hexagon signed distance, apothem 0.86 (edge to edge fills the width).
    ax, ay = np.abs(x), np.abs(y)
    k = math.sqrt(3.0) / 2.0
    dist = np.maximum(ax * k + ay * 0.5, ay)  # 'hex radius' in apothem units
    apothem = 0.86
    edge_d = np.abs(dist - apothem)
    outline = np.exp(-((edge_d / 0.022) ** 2))
    inside = (dist < apothem).astype(np.float64)
    inner_glow = np.clip(dist / apothem, 0.0, 1.0) ** 3.0 * inside * 0.55
    fill = inside * 0.08
    halo = np.exp(-((np.maximum(dist - apothem, 0.0) / 0.05) ** 2)) * (1.0 - inside) * 0.35
    alpha = np.clip(outline + inner_glow + fill + halo, 0.0, 1.0)
    return white(alpha)


def slash_arc() -> Image.Image:
    x, y = grid()
    # Crescent: outer circle minus offset inner circle, opening downward.
    r_out = np.sqrt(x * x + (y - 0.35) ** 2)
    r_in = np.sqrt(x * x + (y - 0.55) ** 2)
    outer = 1.0 - smoothstep(0.86, 0.9, r_out)
    inner = smoothstep(0.86, 0.95, r_in)
    body = outer * inner
    # Only the upper part of the crescent, with ends tapering toward the sides.
    angle = np.arctan2(-(y - 0.35), x)  # 0 right, pi/2 up
    taper = np.clip(np.sin(np.clip(angle, 0.0, math.pi)), 0.0, 1.0) ** 1.6
    body *= taper * (angle > 0.0)
    # Bright leading edge on the outer rim.
    rim = np.exp(-(((r_out - 0.86) / 0.02) ** 2)) * taper * (angle > 0.0)
    soft = blur(body, 4.0)
    alpha = np.clip(body * 0.85 + rim * 0.9 + soft * 0.4, 0.0, 1.0)
    lum = 0.85 + 0.15 * rim
    return to_image(lum, alpha)


def beam_core() -> Image.Image:
    # Beam textures map U along the beam (image x) and V across the width (image y).
    # Bright centre line across the width; x stays tileable so TextureSpeed can scroll it.
    _, y = grid()
    ay = np.abs(y)
    core = np.exp(-((ay / 0.12) ** 2))
    body = np.exp(-((ay / 0.45) ** 2)) * 0.55
    streak_x = noise_1d_periodic(SIZE, 8, seed=909) * 0.6 + noise_1d_periodic(SIZE, 23, seed=910) * 0.4
    streak_x = (streak_x - streak_x.min()) / (streak_x.max() - streak_x.min() + 1e-9)
    mod = 0.75 + 0.25 * streak_x[np.newaxis, :]
    alpha = np.clip(core + body * mod, 0.0, 1.0) * (1.0 - smoothstep(0.85, 1.0, ay))
    lum = 0.8 + 0.2 * core
    return to_image(lum, alpha)


def explosion_flipbook() -> Image.Image:
    frames = 16
    fs = 512
    sheet = np.zeros((fs * 4, fs * 4, 4))
    x, y = grid(fs)
    r = np.sqrt(x * x + y * y)
    theta = np.arctan2(y, x)
    turb = fbm(fs, 4, 5, seed=4242, gain=0.55)
    turb2 = fbm(fs, 6, 4, seed=999, gain=0.5)
    boundary = noise_1d_periodic(720, 12, seed=31)
    ti = ((theta + math.pi) / math.tau * 719).astype(int)
    edge_noise = boundary[ti]
    for f in range(frames):
        t = f / (frames - 1)
        grow = 1.0 - (1.0 - t) ** 2.4
        radius = 0.18 + 0.72 * grow
        wobble = (edge_noise - 0.5) * (0.12 + 0.18 * t)
        # Fade the angular wobble out toward the centre so it cannot pinch into a star.
        rr = r / radius + wobble * smoothstep(0.0, 0.7, r / radius)
        # Noise scrolls outward over time for billowing motion.
        n = np.roll(turb, int(t * 40), axis=0) * 0.6 + np.roll(turb2, -int(t * 25), axis=1) * 0.4
        body = 1.0 - smoothstep(0.75, 1.0, rr + (n - 0.5) * 0.5)
        # Holes open up in the later half as the fireball burns out.
        erosion = smoothstep(0.35 + 0.5 * (1.0 - t), 0.9, n + t * 0.45 - (1.0 - rr) * 0.25)
        density = body * (1.0 - erosion * smoothstep(0.3, 1.0, t))
        fade = 1.0 - smoothstep(0.55, 1.0, t)
        alpha = np.clip(density * (0.35 + 0.65 * fade) * (0.75 + 0.5 * n), 0.0, 1.0)
        alpha *= 1.0 - smoothstep(0.92, 1.0, r)
        # Heat: white-hot core early, cooling to grey smoke at the edges and later frames.
        heat = np.clip((1.0 - rr) * 1.6 + n * 0.4 - t * 0.9, 0.0, 1.0)
        lum = 0.45 + 0.55 * heat
        row, col = divmod(f, 4)
        sheet[row * fs : (row + 1) * fs, col * fs : (col + 1) * fs, 0:3] = lum[..., np.newaxis]
        sheet[row * fs : (row + 1) * fs, col * fs : (col + 1) * fs, 3] = alpha
    return Image.fromarray((np.clip(sheet, 0, 1) * 255 + 0.5).astype(np.uint8), "RGBA")


TEXTURES = {
    "glow_soft": glow_soft,
    "glow_star": glow_star,
    "spark": spark,
    "smoke_soft": smoke_soft,
    "ring_runes": ring_runes,
    "hex_cell": hex_cell,
    "slash_arc": slash_arc,
    "beam_core": beam_core,
    "explosion_flipbook_4x4": explosion_flipbook,
}


def main() -> None:
    os.makedirs(OUT_DIR, exist_ok=True)
    for name, fn in TEXTURES.items():
        img = fn()
        expected = (2048, 2048) if name == "explosion_flipbook_4x4" else (SIZE, SIZE)
        assert img.size == expected and img.mode == "RGBA", (name, img.size, img.mode)
        save(img, name)


if __name__ == "__main__":
    main()
