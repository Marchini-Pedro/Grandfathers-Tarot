"""Draws the Deck (the editor's home screen) into a PNG from the real tile widgets, so the layout can be looked at without the
game. Step 1: run the editor test with the dump switched on, step 2: draw it.

    set DECK_DUMP=deck.json  (PowerShell: $env:DECK_DUMP = "deck.json")
    python tools/editor_test.py
    python tools/deck_preview.py deck.json deck.png

NOT a replacement for the game: text is drawn with a Windows font of a similar kind (not the game's), the glow texture is a soft
frame guess, there is no engine layering. It shows positions, sizes, wrapping, colours and what is visible. Needs Pillow.
"""
import sys, json, re
from PIL import Image, ImageDraw, ImageFont

src = sys.argv[1] if len(sys.argv) > 1 else "deck.json"
out = sys.argv[2] if len(sys.argv) > 2 else "deck.png"
data = json.load(open(src, encoding="utf-8"))

W, H = 1920, 1080
img = Image.new("RGBA", (W, H), (10, 12, 7, 255))
SERIF_BOLD = ["C:/Windows/Fonts/georgiab.ttf", "C:/Windows/Fonts/timesbd.ttf"]
SANS_BOLD = ["C:/Windows/Fonts/arialbd.ttf", "C:/Windows/Fonts/segoeuib.ttf"]
fonts = {}

def font(kind, size):
    key = (kind, round(size))
    if key not in fonts:
        paths = SERIF_BOLD if kind == "serif" else SANS_BOLD
        for p in paths:
            try:
                fonts[key] = ImageFont.truetype(p, round(size))
                break
            except OSError:
                continue
        else:
            fonts[key] = ImageFont.load_default()
    return fonts[key]

def rgba(c, alpha_mul=1.0):
    return (int(c[1]), int(c[2]), int(c[3]), int(c[0] * alpha_mul))

def layer():
    return Image.new("RGBA", (W, H), (0, 0, 0, 0))

TAG = re.compile(r"\{#color\((\d+),(\d+),(\d+)\)\}|\{#reset\(\)\}")

def runs(text, base):
    out_runs, pos, col = [], 0, base
    for m in TAG.finditer(text):
        if m.start() > pos:
            out_runs.append((text[pos:m.start()], col))
        col = (int(m.group(1)), int(m.group(2)), int(m.group(3))) if m.group(1) else base
        pos = m.end()
    if pos < len(text):
        out_runs.append((text[pos:], col))
    return out_runs

def draw_text(d, x, y, w, h, text, st, alpha_mul):
    size = st["font_size"]
    f = font("serif" if "novarese" in st["font_type"] else "sans", size)
    tc = st["text_color"]
    base = (int(tc[1]), int(tc[2]), int(tc[3]))
    a = int(tc[0] * alpha_mul)
    lines = []
    for raw in text.split("\n"):
        # word wrap by visible width, keeping colours: rebuild per word
        words = []
        for run_text, col in runs(raw, base):
            for i, word in enumerate(re.split(r"(\s+)", run_text)):
                if word:
                    words.append((word, col))
        line, width = [], 0
        for word, col in words:
            ww = d.textlength(word, font=f)
            if line and width + ww > w and word.strip():
                lines.append(line)
                line, width = [], 0
            if not line and not word.strip():
                continue
            line.append((word, col))
            width += ww
        lines.append(line)
    line_h = size * 1.2
    total = len(lines) * line_h
    va = st.get("text_vertical_alignment", "top")
    ty = y + ((h - total) / 2 if va == "center" else 0)
    for ln in lines:
        lw = sum(d.textlength(wd, font=f) for wd, _ in ln)
        ha = st.get("text_horizontal_alignment", "left")
        tx = x + ((w - lw) / 2 if ha == "center" else (w - lw) if ha == "right" else 0)
        for wd, col in ln:
            d.text((tx, ty), wd, font=f, fill=(col[0], col[1], col[2], a))
            tx += d.textlength(wd, font=f)
        ty += line_h
    if total > h + 1:
        d.rectangle([x, y, x + w, y + h], outline=(255, 0, 255, 160))  # overflow marker

def draw_widget(wd):
    ox, oy, alpha_mul = wd["x"], wd["y"], wd["alpha"]
    passes = sorted(wd["passes"], key=lambda p: (p["style"].get("offset") or [0, 0, 0])[2])
    for p in passes:
        st, t = p["style"], p["type"]
        off = st.get("offset") or [0, 0, 0]
        x, y = ox + off[0], oy + off[1]
        lay = layer()
        d = ImageDraw.Draw(lay)
        if t == "rect":
            sz = st["size"]
            d.rectangle([x, y, x + sz[0] - 1, y + sz[1] - 1], fill=rgba(st["color"], alpha_mul))
        elif t == "circle":
            sz = st["size"]
            d.ellipse([x, y, x + sz[0], y + sz[1]], fill=rgba(st["color"], alpha_mul))
        elif t == "triangle":
            c = st["triangle_corners"]
            d.polygon([(x + c[i][0], y + c[i][1]) for i in range(3)], fill=rgba(st["color"], alpha_mul))
        elif t == "rotated_rect":
            sz = st["size"][0]
            cx, cy, r = x + sz / 2, y + sz / 2, sz / 2 * 1.4142
            d.polygon([(cx, cy - r), (cx + r, cy), (cx, cy + r), (cx - r, cy)], fill=rgba(st["color"], alpha_mul))
        elif t == "texture":
            sz = st["size"]
            c = st["color"]
            for k in range(12):
                a = int(c[0] * alpha_mul * (1 - k / 12) * 0.5)
                d.rectangle([x + k, y + k, x + sz[0] - k, y + sz[1] - k], outline=(int(c[1]), int(c[2]), int(c[3]), a))
        elif t == "text":
            sz = st["size"]
            draw_text(d, x, y, sz[0], sz[1], p.get("text") or "", st, alpha_mul)
        img.alpha_composite(lay)

# the strip, then the tiles
draw_widget(data["strip"])
for tile in data["tiles"]:
    draw_widget(tile)
d = ImageDraw.Draw(img)
d.text((105, 40), "THE GRANDFATHER'S TAROT", font=font("serif", 30), fill=(183, 194, 58, 255))
d.text((900, 46), data["count"], font=font("sans", 20), fill=(152, 147, 111, 255))
d.text((105, 178), data["caption"], font=font("sans", 15), fill=(152, 147, 111, 255))
img.convert("RGB").save(out)
print("wrote", out)
