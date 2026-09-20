#!/usr/bin/env python3
"""Generate Android launcher icons (legacy + adaptive) dari satu master artwork.

Pakai: python3 tools/gen_app_icons.py <master.png|jpg>

Kenapa script, bukan flutter_launcher_icons: nol dependency baru di repo, dan kita
butuh 2 penyesuaian yang tool itu tidak lakukan otomatis:
  1. Background dinormalisasi ke brand green yang exact (artwork AI bergeser).
  2. Foreground adaptive di-scale supaya muat safe-zone 66dp (mask bulat Android 8+).

ponytail: alpha diambil dari "whiteness" (min channel), jadi cuma jalan untuk mark
putih di atas background solid. Butuh mark berwarna -> threshold per-channel.
"""
import sys
from pathlib import Path

from PIL import Image, ImageChops

BRAND_GREEN = (0x4C, 0xAF, 0x50)  # == AppTheme.seed
LEGACY = {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192}
ADAPTIVE_CANVAS = 1024
SAFE_ZONE_RATIO = 33 / 108  # Android jamin visible dalam lingkaran 66dp dari 108dp
BG_MIN_CHANNEL = 66  # min-channel dari background hijau #4CAF50 (terukur dari artwork)
ALPHA_FLOOR = 100  # di bawah ini = noise JPEG / edge, bukan mark
WHITE_CUTOFF = 200  # min-channel dianggap "mark putih solid"

ROOT = Path(__file__).resolve().parents[1]
RES = ROOT / 'android/app/src/main/res'

ADAPTIVE_XML = '''<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background" />
    <foreground android:drawable="@drawable/ic_launcher_foreground" />
    <monochrome android:drawable="@drawable/ic_launcher_foreground" />
</adaptive-icon>
'''

COLORS_XML = '''<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="ic_launcher_background">#%s</color>
</resources>
'''


def whiteness_mask(src: Image.Image) -> Image.Image:
    """Mask 'putih' dari min(R,G,B) — bukan luminance.

    Luminance hijau #4CAF50 = 134 (dianggap setengah putih), min-channel = 66.
    ALPHA_FLOOR mematikan noise JPEG di background (min-channel bg = 63..67);
    tanpa itu 62% kanvas dapat alpha 1-9 alias haze.

    ponytail: cuma valid untuk mark putih di atas background solid. Mark berwarna
    butuh threshold per-channel.
    """
    r, g, b = src.split()
    low = ImageChops.darker(ImageChops.darker(r, g), b)
    span = 255 - ALPHA_FLOOR
    return low.point(lambda v: max(0, min(255, (v - ALPHA_FLOOR) * 255 // span)))


def build_artwork(master: Path) -> Image.Image:
    """Mark putih di atas brand green exact — buang geseran warna + noise JPEG."""
    src = Image.open(master).convert('RGB')
    art = Image.new('RGB', src.size, BRAND_GREEN)
    art.paste(Image.new('RGB', src.size, (255, 255, 255)), (0, 0), whiteness_mask(src))
    return art


def mark_reach(fg: Image.Image) -> float:
    """Jarak radial terluar piksel mark dari tengah kanvas."""
    alpha = fg.getchannel('A')
    cx = cy = ADAPTIVE_CANVAS / 2
    reach = 0.0
    for y in range(0, ADAPTIVE_CANVAS, 4):
        for x in range(0, ADAPTIVE_CANVAS, 4):
            if alpha.getpixel((x, y)) > WHITE_CUTOFF:
                reach = max(reach, ((x - cx) ** 2 + (y - cy) ** 2) ** 0.5)
    return reach


def build_foreground(art: Image.Image) -> tuple[Image.Image, float, float, Image.Image]:
    """Foreground transparan, di-scale supaya ujung mark pas menyentuh safe-zone."""
    mask = whiteness_mask(art)
    fg = Image.new('RGBA', art.size, (255, 255, 255, 255))
    fg.putalpha(mask)

    reach = mark_reach(fg)
    limit = SAFE_ZONE_RATIO * ADAPTIVE_CANVAS
    scale = min(1.0, limit / reach) if reach else 1.0
    if scale < 1.0:
        side = round(ADAPTIVE_CANVAS * scale)
        inner = fg.resize((side, side), Image.Resampling.LANCZOS)
        canvas = Image.new('RGBA', (ADAPTIVE_CANVAS, ADAPTIVE_CANVAS), (0, 0, 0, 0))
        off = (ADAPTIVE_CANVAS - side) // 2
        canvas.paste(inner, (off, off), inner)
        fg = canvas
    return fg, scale, reach, mask


def verify(raw_mask: Image.Image) -> None:
    """Self-check: jalan tiap kali script dipakai, gagal = icon rusak.

    Cek haze dilakukan pada mask MENTAH (sebelum resize) — foreground final
    memang punya alpha 1-59 dari antialiasing LANCZOS, itu yang bikin tepi halus.
    """
    import numpy as np
    res = RES
    for density, size in LEGACY.items():
        im = Image.open(res / f'mipmap-{density}/ic_launcher.png').convert('RGB')
        a = np.asarray(im).astype(int)
        assert im.size == (size, size), f'{density}: ukuran {im.size} != {size}'
        assert np.array_equal(a[0, 0], BRAND_GREEN), f'{density}: pojok bukan brand green: {a[0, 0]}'
        # mark harus ada telak, bukan nyaris putih
        assert a.max() == 255 and (a.max(axis=2) > 250).sum() > 20, f'{density}: mark putih hilang'

    raw = np.asarray(raw_mask).astype(int)
    # Background harus MATI total — ini yang menangkap noise JPEG (bg min-channel 63-67).
    corner = raw[:120, :120]
    assert corner.max() == 0, f'mask mentah: pojok background alpha {corner.max()} (harus 0)'
    # Sisa px parsial = antialiasing tepi asli. Batasi supaya haze global nggak lolos.
    partial = int(((raw > 0) & (raw < 255)).sum())
    frac = partial / raw.size
    assert frac < 0.05, f'mask mentah: {frac:.1%} px parsial — kelebihan haze'
    assert (raw == 255).sum() > 80000, f'mask mentah: mark putih cuma {int((raw == 255).sum())}px'
    assert (raw > 0).sum() > 110000, 'mask mentah: mark kepotong'

    fgv = Image.open(res / 'drawable-nodpi/ic_launcher_foreground.png')
    alpha = np.asarray(fgv.getchannel('A')).astype(int)
    assert alpha.max() == 255, 'foreground: nggak ada piksel solid'

    reach = mark_reach(fgv)
    limit = SAFE_ZONE_RATIO * ADAPTIVE_CANVAS
    assert reach <= limit + 1, f'safe-zone bocor: reach {reach:.0f} > {limit:.0f}'

    assert (res / 'values/ic_launcher_colors.xml').exists(), 'ic_launcher_colors.xml hilang'
    print(f'verify   : OK (bg mati, mark {int((raw == 255).sum())}px solid, '
          f'edge {frac:.1%}, reach {reach:.0f}/{limit:.0f})')


def main() -> None:
    master = Path(sys.argv[1])
    art = build_artwork(master)

    for density, size in LEGACY.items():
        art.resize((size, size), Image.Resampling.LANCZOS).save(
            RES / f'mipmap-{density}/ic_launcher.png', optimize=True)

    fg, scale, reach, mask = build_foreground(art)
    (RES / 'drawable-nodpi').mkdir(parents=True, exist_ok=True)
    fg.save(RES / 'drawable-nodpi/ic_launcher_foreground.png', optimize=True)

    (RES / 'mipmap-anydpi-v26').mkdir(parents=True, exist_ok=True)
    (RES / 'mipmap-anydpi-v26/ic_launcher.xml').write_text(ADAPTIVE_XML)
    (RES / 'values').mkdir(parents=True, exist_ok=True)
    (RES / 'values/ic_launcher_colors.xml').write_text(COLORS_XML % '%02X%02X%02X' % BRAND_GREEN)

    print(f'artwork  : {master}')
    print(f'legacy   : {", ".join(f"{d} {s}px" for d, s in LEGACY.items())}')
    print(f'adaptive : foreground {ADAPTIVE_CANVAS}px, scale {scale:.3f} '
          f'(reach {reach:.0f} -> {reach * scale:.0f}, safe limit {SAFE_ZONE_RATIO * ADAPTIVE_CANVAS:.0f})')
    verify(mask)


if __name__ == '__main__':
    main()
