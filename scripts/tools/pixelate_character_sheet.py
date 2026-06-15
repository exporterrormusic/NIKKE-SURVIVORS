# Pixel-art conversion tool for character sprite sheets (HoloCure-style).
#
# Converts a high-res 3x4 character sheet (cols = walk frames, rows = facing
# down/left/right/up) into a small pixel-art sheet with outline + grading.
# The 'rimlit_gold' recipe is what shipped for Snow White (option 6).
#
# Usage:
#   python pixelate_character_sheet.py <src_sheet.png> <out_sheet.png> [recipe]
#
# Note: outline/rim passes run PER FRAME (not whole-sheet) so outlines can
# never spill across frame-cell boundaries (caused a dangling-pixel artifact
# on Snow White's left-facing walk frames the first time around).
import sys
import colorsys
import numpy as np
from PIL import Image, ImageEnhance

COLS, ROWS = 3, 4


def alpha_weighted_downscale(img, th, tw=None):
    """Downscale RGBA without transparent-pixel color bleeding.
    Pass tw to override target width (non-uniform squeeze)."""
    if tw is None:
        tw = round(img.width * th / img.height)
    arr = np.asarray(img).astype(np.float64)
    a = arr[..., 3:4] / 255.0
    pre = arr[..., :3] * a
    pre_im = Image.fromarray(np.concatenate([pre, arr[..., 3:4]], axis=2).astype(np.uint8))
    small = np.asarray(pre_im.resize((tw, th), Image.LANCZOS)).astype(np.float64)
    sa = small[..., 3:4] / 255.0
    rgb = np.where(sa > 0.01, small[..., :3] / np.maximum(sa, 1e-6), 255.0)
    out = np.concatenate([np.clip(rgb, 0, 255), small[..., 3:4]], axis=2).astype(np.uint8)
    return Image.fromarray(out, 'RGBA')


def hard_alpha(img, cutoff=110):
    a = img.getchannel('A').point(lambda v: 255 if v > cutoff else 0)
    img.putalpha(a)
    return img


def quantize_global(img, n_colors, white_lock=True, remap_rule=None):
    """Quantize RGB with one global palette; optionally remap palette entries."""
    rgb = img.convert('RGB')
    q = rgb.quantize(colors=n_colors, method=Image.MEDIANCUT, dither=Image.Dither.NONE)
    pal = q.getpalette()[:n_colors * 3]
    for i in range(n_colors):
        r, g, b = [c / 255.0 for c in pal[i*3:i*3+3]]
        h, s, v = colorsys.rgb_to_hsv(r, g, b)
        if remap_rule:
            h, s, v = remap_rule(h, s, v)
        elif white_lock and s < 0.11 and v > 0.84:
            s, v = s * 0.5, min(1.0, v * 1.08)
        r, g, b = colorsys.hsv_to_rgb(h % 1.0, min(1, max(0, s)), min(1, max(0, v)))
        pal[i*3:i*3+3] = [int(r*255), int(g*255), int(b*255)]
    q.putpalette(pal + [0] * (768 - len(pal)))
    out = q.convert('RGBA')
    out.putalpha(img.getchannel('A'))
    return out


def add_outline(frame, mode='dark', color=(48, 48, 60, 255)):
    """Per-frame outline: transparent pixels adjacent to opaque ones."""
    arr = np.asarray(frame).copy()
    op = arr[..., 3] == 255
    pad = np.pad(op, 1)
    nb = pad[:-2, 1:-1] | pad[2:, 1:-1] | pad[1:-1, :-2] | pad[1:-1, 2:]
    edge = (~op) & nb
    if mode == 'dark':
        arr[edge] = color
    elif mode == 'local':
        rgb = arr[..., :3].astype(np.float64)
        acc = np.zeros_like(rgb); cnt = np.zeros(op.shape)
        for sh in ((-1, 0), (1, 0), (0, -1), (0, 1)):
            sr = np.roll(op, sh, axis=(0, 1))
            srgb = np.roll(rgb, sh, axis=(0, 1))
            m = edge & sr
            acc[m] += srgb[m]; cnt[m] += 1
        m = cnt > 0
        arr[..., :3][m] = ((acc[m] / cnt[m][:, None]) * 0.42).astype(np.uint8)
        arr[..., 3][m] = 255
    return Image.fromarray(arr, 'RGBA')


def add_rim_light(frame):
    """Per-frame top rim light on opaque pixels with transparent above."""
    arr = np.asarray(frame).copy()
    op = arr[..., 3] == 255
    above = np.zeros_like(op)
    above[1:, :] = ~op[:-1, :]
    rim = op & above
    rgb = arr[..., :3].astype(np.int32)
    rgb[rim] = np.clip(rgb[rim] + 48, 0, 255)
    arr[..., :3] = rgb.astype(np.uint8)
    return Image.fromarray(arr, 'RGBA')


def add_drop_shadow(frame):
    arr = np.asarray(frame).copy()
    op = arr[..., 3] == 255
    shifted = np.zeros_like(op)
    shifted[1:, 1:] = op[:-1, :-1]
    arr[shifted & ~op] = (24, 24, 32, 140)
    return Image.fromarray(arr, 'RGBA')


# ---------------- grading / palette rules ----------------

def grade_vibrant(rgb):
    return ImageEnhance.Brightness(ImageEnhance.Color(rgb).enhance(1.35)).enhance(1.06)

def grade_mild(rgb):
    return ImageEnhance.Brightness(ImageEnhance.Color(rgb).enhance(1.15)).enhance(1.03)

def _is_gold(deg, s, v):
    # gold accents (eyes/trim) ~38-55deg high-sat; skin incl. shadows is 22-32deg
    return 34 <= deg <= 65 and s > 0.5 and v > 0.30

def rule_gold_accent(h, s, v):
    deg = h * 360
    if _is_gold(deg, s, v):
        return (45/360, min(1, s * 1.4 + 0.08), min(1, v * 1.18 + 0.04))
    if s < 0.13 and v >= 0.85:
        return (h, s * 0.5, min(1, v * 1.08))
    return (h, s, v)

def rule_bright_retro(h, s, v):
    deg = h * 360
    if _is_gold(deg, s, v):
        return (45/360, min(1, s * 1.4 + 0.08), min(1, v * 1.18 + 0.04))
    if s < 0.13 and v >= 0.80:
        return (h, s * 0.3, min(1, v * 1.12 + 0.02))
    if s < 0.15 and 0.30 < v < 0.80:
        return (h, s * 0.5, min(1, v * 1.08))
    return (h, s, min(1, v * 1.04))


RECIPES = {
    'crisp64':     dict(target_h=64, grade=None,          n_colors=32, outline_mode='dark'),
    'vibrant64':   dict(target_h=64, grade=grade_vibrant, n_colors=28, outline_mode='local'),
    'detail96':    dict(target_h=96, grade=grade_mild,    n_colors=40, outline_mode='local'),
    'gold64':      dict(target_h=64, grade=grade_mild,    n_colors=28, outline_mode='dark',
                        remap_rule=rule_gold_accent),
    'retro48':     dict(target_h=48, grade=None,          n_colors=18, outline_mode='dark',
                        remap_rule=rule_bright_retro, shadow=True),
    # shipped for Snow White:
    'rimlit_gold': dict(target_h=64, grade=grade_vibrant, n_colors=28, outline_mode='dark',
                        remap_rule=rule_gold_accent, rim=True),
    # enemies (rapture-basic renders 96px tall in-game = 48 x integer 2x):
    'rimlit_gold48': dict(target_h=48, grade=grade_vibrant, n_colors=28, outline_mode='dark',
                          remap_rule=rule_gold_accent, rim=True),
}


def convert_sheet(src_path, out_path, recipe='rimlit_gold', width_squeeze=1.0):
    """width_squeeze < 1.0 narrows the art slightly (uniform per frame, centered
    in its cell) for characters whose art fills the frame edge-to-edge and
    would otherwise have no room for the outline (e.g. Scarlet's hat brim)."""
    cfg = dict(RECIPES[recipe])
    target_h = cfg.pop('target_h')
    grade = cfg.pop('grade')
    n_colors = cfg.pop('n_colors')
    outline_mode = cfg.pop('outline_mode')
    remap_rule = cfg.pop('remap_rule', None)
    shadow = cfg.pop('shadow', False)
    rim = cfg.pop('rim', False)

    src = Image.open(src_path).convert('RGBA')
    fw, fh = src.width // COLS, src.height // ROWS
    tw = round(fw * target_h / fh)

    # 1) downscale all frames, assemble small sheet
    cw = max(1, round(tw * width_squeeze))  # content width after squeeze
    pad_x = (tw - cw) // 2
    sheet = Image.new('RGBA', (tw * COLS, target_h * ROWS), (0, 0, 0, 0))
    for r in range(ROWS):
        for c in range(COLS):
            f = src.crop((c * fw, r * fh, (c + 1) * fw, (r + 1) * fh))
            sheet.paste(alpha_weighted_downscale(f, target_h, cw),
                        (c * tw + pad_x, r * target_h))
    sheet = hard_alpha(sheet)

    # 2) grade + quantize with ONE palette (keeps animation flicker-free)
    if grade:
        rgb = grade(sheet.convert('RGB'))
        g = rgb.convert('RGBA'); g.putalpha(sheet.getchannel('A'))
        sheet = g
    sheet = quantize_global(sheet, n_colors, remap_rule=remap_rule)

    # 3) rim/outline/shadow PER FRAME so nothing spills across cell borders
    out = Image.new('RGBA', sheet.size, (0, 0, 0, 0))
    for r in range(ROWS):
        for c in range(COLS):
            f = sheet.crop((c * tw, r * target_h, (c + 1) * tw, (r + 1) * target_h))
            if rim:
                f = add_rim_light(f)
            f = add_outline(f, outline_mode)
            if shadow:
                f = add_drop_shadow(f)
            out.paste(f, (c * tw, r * target_h))

    out.save(out_path)
    print(f'{recipe}: {src_path} -> {out_path} {out.size}')
    return out


def convert_single(src_path, out_path, factor, n_colors=12, outline=True, alpha_cutoff=110):
    """Convert a single (non-sheet) image, e.g. bullet/projectile textures.
    factor = downscale divisor (consumers must multiply their scale by it).
    Use alpha_cutoff ~170 for textures with soft glow halos (tracer streaks)
    so the halo doesn't survive as detached pale chunks.
    No gold remap / rim light — bullets are tinted via modulate at runtime."""
    src = Image.open(src_path).convert('RGBA')
    th = max(1, round(src.height / factor))
    tw = max(1, round(src.width / factor))
    img = hard_alpha(alpha_weighted_downscale(src, th, tw), alpha_cutoff)
    img = quantize_global(img, n_colors, white_lock=False)
    if outline:
        img = add_outline(img, 'dark')
    img.save(out_path)
    print(f'single /{factor}: {src_path} -> {out_path} {img.size}')
    return img


if __name__ == '__main__':
    if len(sys.argv) < 3:
        print('usage: pixelate_character_sheet.py <src> <out> [recipe] [width_squeeze]')
        print('       pixelate_character_sheet.py <src> <out> single <factor>')
        print('recipes:', ', '.join(RECIPES))
        sys.exit(1)
    if len(sys.argv) > 3 and sys.argv[3] == 'single':
        convert_single(sys.argv[1], sys.argv[2], float(sys.argv[4]) if len(sys.argv) > 4 else 4.0,
                       alpha_cutoff=int(sys.argv[5]) if len(sys.argv) > 5 else 110)
    else:
        convert_sheet(sys.argv[1], sys.argv[2],
                      sys.argv[3] if len(sys.argv) > 3 else 'rimlit_gold',
                      float(sys.argv[4]) if len(sys.argv) > 4 else 1.0)
