"""Draws a screen of the wave editor into a PNG from the real widgets, so a layout can be looked at without the game.
Step 1: run the editor test with the dump switched on, step 2: draw it.

    set UI_DUMP_DIR=ui_dump        (PowerShell: $env:UI_DUMP_DIR = "ui_dump"; the folder must exist)
    python tools/editor_test.py
    python tools/ui_preview.py ui_dump/detail.json detail.png        (add --scale 2 for a sharper picture)

Every widget the view shows is drawn at its scenegraph position, passes in z order: rect, circle, triangle, rotated rect and
text (with the game's colour tags). NOT the game: the text is a Windows font of a similar kind (not the game's), textures
(the frame glow of a tile, the terminal background) are skipped, there is no engine layering and no snapping. It shows
positions, sizes, wrapping, colours and what is visible. HOTSPOTS=1 outlines the click areas that were dumped as hotspots (they
are not dumped by default). Needs Pillow.
"""
import sys, json, re, math
from PIL import Image, ImageDraw, ImageFont

args = [a for a in sys.argv[1:] if not a.startswith("--")]
SCALE = 2
for i, a in enumerate(sys.argv):
    if a == "--scale" and i + 1 < len(sys.argv):
        SCALE = max(1, int(sys.argv[i + 1]))
src = args[0] if args else "ui_dump/detail.json"
out = args[1] if len(args) > 1 else "ui.png"
data = json.load(open(src, encoding="utf-8"))

W, H = 1920, 1080
img = Image.new("RGBA", (W * SCALE, H * SCALE), (10, 12, 7, 255))
SERIF_BOLD = ["C:/Windows/Fonts/georgiab.ttf", "C:/Windows/Fonts/timesbd.ttf"]
SANS_BOLD = ["C:/Windows/Fonts/segoeuib.ttf", "C:/Windows/Fonts/arialbd.ttf"]
fonts = {}


def font(kind, size):
    key = (kind, round(size * SCALE))
    if key not in fonts:
        for p in (SERIF_BOLD if kind == "serif" else SANS_BOLD):
            try:
                fonts[key] = ImageFont.truetype(p, round(size * SCALE))
                break
            except OSError:
                continue
        else:
            fonts[key] = ImageFont.load_default()
    return fonts[key]


def rgba(c, alpha_mul=1.0):
    return (int(c[1]), int(c[2]), int(c[3]), int(c[0] * alpha_mul))


TAG = re.compile(r"\{#color\((\d+),(\d+),(\d+)\)\}|\{#reset\(\)\}")


def runs(text, base):
    result, pos, col = [], 0, base
    for m in TAG.finditer(text):
        if m.start() > pos:
            result.append((text[pos:m.start()], col))
        col = (int(m.group(1)), int(m.group(2)), int(m.group(3))) if m.group(1) else base
        pos = m.end()
    if pos < len(text):
        result.append((text[pos:], col))
    return result


def S(v):
    return v * SCALE


def draw_text(d, x, y, w, h, text, st, alpha_mul):
    size = st.get("font_size", 20)
    f = font("serif" if "novarese" in st.get("font_type", "") or "rexlia" in st.get("font_type", "") else "sans", size)
    tc = st.get("text_color") or [255, 255, 255, 255]
    base = (int(tc[1]), int(tc[2]), int(tc[3]))
    a = int(tc[0] * alpha_mul)
    wrap = st.get("word_wrap", False)
    lines = []
    for raw in str(text).split("\n"):
        words = []
        for run_text, col in runs(raw, base):
            for word in re.split(r"(\s+)", run_text):
                if word:
                    words.append((word, col))
        line, width = [], 0
        for word, col in words:
            ww = d.textlength(word, font=f)
            if wrap and line and width + ww > S(w) and word.strip():
                lines.append(line)
                line, width = [], 0
            if not line and not word.strip():
                continue
            line.append((word, col))
            width += ww
        lines.append(line)
    line_h = S(size * 1.2)
    total = len(lines) * line_h
    va = st.get("text_vertical_alignment", "top")
    ty = S(y) + ((S(h) - total) / 2 if va == "center" else 0)
    for ln in lines:
        lw = sum(d.textlength(wd, font=f) for wd, _ in ln)
        ha = st.get("text_horizontal_alignment", "left")
        tx = S(x) + ((S(w) - lw) / 2 if ha == "center" else (S(w) - lw) if ha == "right" else 0)
        for wd, col in ln:
            d.text((tx, ty), wd, font=f, fill=(col[0], col[1], col[2], a))
            tx += d.textlength(wd, font=f)
        ty += line_h
    if wrap and total > S(h) + 1:
        d.rectangle([S(x), S(y), S(x + w), S(y + h)], outline=(255, 0, 255, 160))  # overflow marker


def rot(points, angle, cx, cy):
    c, s = math.cos(angle), math.sin(angle)
    return [(cx + (px - cx) * c - (py - cy) * s, cy + (px - cx) * s + (py - cy) * c) for px, py in points]


items = []
for wd in data["widgets"]:
    for order, p in enumerate(wd["passes"]):
        if not isinstance(p["style"], dict):
            continue
        off = p["style"].get("offset") or [0, 0, 0]
        items.append((wd["z"] + (off[2] if len(off) > 2 else 0), len(items), wd, p))
items.sort(key=lambda t: (t[0], t[1]))

for z, _, wd, p in items:
    st, t = p["style"], p.get("type")
    if not isinstance(st, dict) or t is None:
        continue
    off = st.get("offset") or [0, 0, 0]
    x, y = wd["x"] + off[0], wd["y"] + off[1]
    alpha_mul = wd["alpha"]
    color = st.get("color")
    lay = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(lay)
    if t == "rect" and color:
        sz = st["size"]
        d.rectangle([S(x), S(y), S(x + sz[0]) - 1, S(y + sz[1]) - 1], fill=rgba(color, alpha_mul))
    elif t == "circle" and color:
        sz = st["size"]
        d.ellipse([S(x), S(y), S(x + sz[0]), S(y + sz[1])], fill=rgba(color, alpha_mul))
    elif t == "triangle" and color:
        c = st["triangle_corners"]
        d.polygon([(S(x + c[i][0]), S(y + c[i][1])) for i in range(3)], fill=rgba(color, alpha_mul))
    elif t == "rotated_rect" and color:
        sz = st["size"]
        pv = st.get("pivot") or [sz[0] / 2, sz[1] / 2]
        pts = [(x, y), (x + sz[0], y), (x + sz[0], y + sz[1]), (x, y + sz[1])]
        pts = rot(pts, st.get("angle", 0), x + pv[0], y + pv[1])
        d.polygon([(S(px), S(py)) for px, py in pts], fill=rgba(color, alpha_mul))
    elif t == "text":
        sz = st["size"]
        draw_text(d, x, y, sz[0], sz[1], p.get("text") or "", st, alpha_mul)
    img.alpha_composite(lay)

result = img.convert("RGB")
if SCALE > 1:
    result = result.resize((W, H), Image.LANCZOS)
result.save(out)
print("wrote", out)
