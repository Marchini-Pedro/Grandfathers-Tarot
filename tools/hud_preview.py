"""Draws the Spread's shapes offline into a PNG, from the same arithmetic the HUD uses (ui/spread.lua), so the geometry can
be looked at without starting the game. NOT a replacement for the game (no anti-aliasing quirks, no fonts, no layering by
the engine), only a sanity check of shapes: the six suit marks, the eye shut / opening / open, the card face and the rot.
Run:  python tools/hud_preview.py [out.png]   (needs `lupa` and Pillow, see CLAUDE.md)
"""
import sys, os, json
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.environ.get("PYLIBS", r"C:\Users\ayko4\AppData\Local\Temp\claude\c--XboxGames-Warhammer-40-000--Darktide-Content\9da40c72-f459-4d9d-ab4b-3023fa21e2f5\scratchpad\pylibs"))
from lupa import LuaRuntime
from PIL import Image, ImageDraw

MODROOT = os.path.abspath(os.path.join(HERE, "..")).replace("\\", "/")
OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "hud_preview.png")
lua = LuaRuntime(unpack_returned_tuples=True)

# Lua side: returns JSON with everything to draw (so the drawing code here knows nothing about the HUD's maths)
harness = r'''
local MODROOT = ...
local BASE = MODROOT .. "/scripts/mods/RealmsWaves"
function math.clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
local Spread = dofile(BASE .. "/ui/spread.lua")
local Cards = dofile(BASE .. "/catalog/cards.lua")

local function shape_json(shape, ox, oy, cols)
  local out = {}
  for i, t in ipairs(shape.tri) do
    if t.on then out[#out + 1] = string.format('{"k":"t","i":%d,"c":%d,"z":%d,"p":[%f,%f,%f,%f,%f,%f]}', i, t.col, t.z, ox + t.x1, oy + t.y1, ox + t.x2, oy + t.y2, ox + t.x3, oy + t.y3) end
  end
  for i, c in ipairs(shape.circ) do
    if c.on then out[#out + 1] = string.format('{"k":"c","i":%d,"c":%d,"z":%d,"p":[%f,%f,%f]}', i, c.col, c.z, ox + c.cx, oy + c.cy, c.r) end
  end
  return out
end

local items = {}
local function add(s) for _, v in ipairs(s) do items[#items + 1] = v end end

-- suit icons at 18 px, each in a 40 px cell
local icon = Spread.new_shape(Spread.ICON_TRIS, Spread.ICON_CIRCS)
local icons = {}
for i, suit in ipairs(Cards.SUIT_ORDER) do
  Spread.icon(Cards.SUITS[suit].icon, 18, icon)
  icons[#icons + 1] = { suit = suit, shapes = shape_json(icon, 0, 0) }
end

-- the eye at a few openings (28 px) and a big one (80 px)
local eye = Spread.new_shape(Spread.EYE_TRIS, Spread.EYE_CIRCS)
local eyes = {}
for _, spec in ipairs({ { 28, 0 }, { 28, 0.25 }, { 28, 0.5 }, { 28, 0.75 }, { 28, 1 }, { 80, 0 }, { 80, 1 } }) do
  local a, b, c = Spread.eye(spec[1], spec[2], eye)
  eyes[#eyes + 1] = { size = spec[1], open = spec[2], lens = a, lid = b, pupil = c, shapes = shape_json(eye, 0, 0) }
end

-- the rot on a 152 x 76 card at a few moments, for the weakest and the strongest rot
local fx = Spread.new_rot()
local rots = {}
for _, k in ipairs({ 0.2, 1 }) do
  for _, r in ipairs({ 0.2, 0.5, 0.8, 1 }) do
    Spread.rot_fx(fx, r, k, 152, 76, 0.7)
    local blot = {}
    for i = 1, Spread.BLOTCHES do blot[#blot + 1] = { on = fx.blotch[i].on, cx = fx.blotch[i].cx, cy = fx.blotch[i].cy, r = fx.blotch[i].r } end
    local flies = {}
    for i = 1, Spread.MAX_FLIES do if fx.flies[i].on then flies[#flies + 1] = { fx.flies[i].x, fx.flies[i].y } end end
    local drips = {}
    for i = 1, Spread.DRIPS do if fx.drips[i].on then drips[#drips + 1] = { fx.drips[i].x, fx.drips[i].y, fx.drips[i].h, fx.drips[i].alpha } end end
    rots[#rots + 1] = { k = k, r = r, fade = fx.fade, bright = fx.bright, wash = fx.wash, blot = blot, flies = flies, drips = drips }
  end
end

-- dots and diamonds layout for the three card widths
local rows = {}
for _, cw in ipairs({ 176, 152, 132 }) do
  local row = { cw = cw, fits = {} }
  for count = 1, 6 do
    local d, p, n = Spread.dots_fit(cw, count)
    row.fits[#row.fits + 1] = { count = count, d = d, p = p, n = n }
  end
  rows[#rows + 1] = row
end

local suits = {}
for _, s in ipairs(Cards.SUIT_ORDER) do suits[s] = Cards.SUITS[s] end
return { icons = icons, eyes = eyes, rots = rots, rows = rows, suits = suits, thr = Cards.THREAT_COLORS, base = Cards.BASE, ds = Spread.DIAMONDS_END }
'''

def to_py(v):
    # lupa tables -> python (dict/list)
    if hasattr(v, "items"):
        keys = list(v.keys())
        if keys and all(isinstance(k, int) for k in keys):
            return [to_py(v[k]) for k in sorted(keys)]
        return {k: to_py(x) for k, x in v.items()}
    return v

# the shape lists come back as lua strings of JSON: decode
data = lua.execute(harness, MODROOT)
data = to_py(data)

def dec(shapes):
    return [json.loads(s) for s in shapes]

S = 8  # pixels per unit in the preview
W, H = 1800, 1000
img = Image.new("RGB", (W, H), (10, 12, 7))
d = ImageDraw.Draw(img)

def rgb(c):
    return tuple(int(x) for x in c)

def draw_shape(shapes, ox, oy, scale, accent, card, alpha=1.0, over=None):
    ordered = sorted(shapes, key=lambda s: s["z"])
    for sh in ordered:
        col = accent if sh["c"] == 1 else card
        if sh["c"] == 1 and alpha < 1:
            col = tuple(int(card[i] * (1 - alpha) + accent[i] * alpha) for i in range(3))
        if sh["k"] == "t":
            p = sh["p"]
            d.polygon([(ox + p[0] * scale, oy + p[1] * scale), (ox + p[2] * scale, oy + p[3] * scale), (ox + p[4] * scale, oy + p[5] * scale)], fill=col)
        else:
            cx, cy, r = sh["p"]
            d.ellipse([ox + (cx - r) * scale, oy + (cy - r) * scale, ox + (cx + r) * scale, oy + (cy + r) * scale], fill=col)

suits = data["suits"]
d.text((10, 6), "suit marks (18 px, shown at 8x)", fill=(200, 200, 160))
for i, icon in enumerate(data["icons"]):
    s = suits[icon["suit"]]
    ox, oy = 20 + i * 150, 30
    d.rectangle([ox - 6, oy - 6, ox + 18 * S + 6, oy + 18 * S + 6], fill=rgb(s["card"]))
    draw_shape(dec(icon["shapes"]), ox, oy, S, rgb(s["accent"]), rgb(s["card"]))
    d.text((ox, oy + 18 * S + 10), icon["suit"], fill=(200, 200, 160))

d.text((10, 230), "the eye, shut -> open (28 px at 6x, 80 px at 3x) on the Plague card colour at the winner's strength", fill=(200, 200, 160))
s = suits["plague"]
x = 20
for e in data["eyes"]:
    sc = 6 if e["size"] == 28 else 3
    w = e["size"] * sc
    d.rectangle([x - 4, 255, x + w + 4, 255 + w + 8], fill=rgb(s["card"]))
    shapes = dec(e["shapes"])
    # lens/lid fade: draw lens and lid separately with their own opacity
    lens = [t for t in shapes if (t["k"] == "t" and t["i"] <= 4) or t["k"] == "c"]
    lid = [t for t in shapes if not ((t["k"] == "t" and t["i"] <= 4) or t["k"] == "c")]
    base = 0.5 if e["open"] >= 0.99 else 0.9  # brighter than the in-game 16 percent so it can be seen
    draw_shape(lid, x, 259, sc, rgb(s["accent"]), rgb(s["card"]), alpha=base * e["lid"])
    draw_shape(lens, x, 259, sc, rgb(s["accent"]), rgb(s["card"]), alpha=base * max(e["lens"], 0.0001))
    d.text((x, 259 + w + 12), "open %.2f" % e["open"], fill=(200, 200, 160))
    x += w + 30

# card faces with threat and dots on three widths
d.text((10, 520), "card bottom rows: diamonds at the left, dots at the right (cards 176 / 152 / 132 wide, 3 and 6 enemy kinds)", fill=(200, 200, 160))
y = 545
for row in data["rows"]:
    cw = row["cw"]
    for variant, count in enumerate((3, 6)):
        fit = [f for f in row["fits"] if f["count"] == count][0]
        ox = 20 + variant * (cw * 3 + 40)
        d.rectangle([ox, y, ox + cw * 3, y + 40 * 3], fill=rgb(suits["blight"]["card"]))
        cy = y + (76 - 8 - 7) * 3 - 6 * 3 * 0  # row centre like the HUD: ch - 8 - 7
        cy = y + 3 * (40 - 15)
        for j in range(5):
            cxd = ox + 3 * (4 + 12 + 4 + j * 11.2)
            col = rgb(data["thr"][2]) if j < 3 else rgb(data["base"]["muted"])
            r = 3 * 5.66 / 1.0
            pts = [(cxd, cy - r), (cxd + r, cy), (cxd, cy + r), (cxd - r, cy)]
            d.polygon(pts, fill=col)
            if j >= 3:
                r2 = 3 * (8 - 3.6) / 2 * 1.4142
                d.polygon([(cxd, cy - r2), (cxd + r2, cy), (cxd, cy + r2), (cxd - r2, cy)], fill=rgb(suits["blight"]["card"]))
        dd, p, n = fit["d"], fit["p"], fit["n"]
        palette = [(200, 60, 60), (230, 140, 30), (60, 220, 60), (80, 200, 230), (220, 220, 220), (230, 100, 170)]
        for j in range(n):
            dx = ox + 3 * (cw - 12 - dd - (n - 1 - j) * p)
            d.ellipse([dx, cy - 3 * dd / 2, dx + 3 * dd, cy + 3 * dd / 2], fill=palette[j])
        d.text((ox + 4, y + 4), "%d wide, %d kinds -> %d shown (d %.0f)" % (cw, count, n, dd), fill=(230, 230, 200))
    y += 40 * 3 + 12

# rot: the card at several moments
d.text((980, 520), "the rot at 20/50/80/100 percent: weak (top) and strong (bottom) (blotches, flies, drips, wash)", fill=(200, 200, 160))
oy0 = 545
for ri, rot in enumerate(data["rots"]):
    col, rowi = ri % 4, ri // 4
    ox = 990 + col * 190
    oy = oy0 + rowi * 200
    cw, ch = 152, 76
    sc = 1.0
    base = suits["rage"]["card"]
    # card with the rot's darkening and brown wash
    bright = rot["bright"]
    card_col = tuple(int(base[i] * bright) for i in range(3))
    d.rectangle([ox, oy + 20, ox + cw, oy + 20 + ch], fill=card_col)
    # the card's text stands in as a bar
    d.rectangle([ox + 16, oy + 28, ox + 100, oy + 40], fill=(int(236 * bright), int(217 * bright), int(191 * bright)))
    wash = rot["wash"]
    d.rectangle([ox, oy + 20, ox + cw, oy + 20 + ch], outline=None, fill=None)
    ov = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    od = ImageDraw.Draw(ov)
    od.rectangle([ox, oy + 20, ox + cw, oy + 20 + ch], fill=(70, 52, 20, int(wash * 255)))
    cols = [(43, 41, 16), (74, 58, 22), (43, 41, 16), (90, 106, 31), (59, 47, 18)]
    rings = [(1.0, 0.22), (0.8, 0.28), (0.58, 0.34), (0.36, 0.42)]
    for i, b in enumerate(rot["blot"]):
        if b["on"]:
            for rr, a in rings:
                r = b["r"] * rr
                od.ellipse([ox + b["cx"] - r, oy + 20 + b["cy"] - r, ox + b["cx"] + r, oy + 20 + b["cy"] + r], fill=cols[i] + (int(a * 255),))
    for (fx_, fy_) in rot["flies"]:
        od.ellipse([ox + fx_ - 3.5, oy + 20 + fy_ - 3.5, ox + fx_ + 3.5, oy + 20 + fy_ + 3.5], fill=(138, 154, 85, 255))
        od.ellipse([ox + fx_ - 2.5, oy + 20 + fy_ - 2.5, ox + fx_ + 2.5, oy + 20 + fy_ + 2.5], fill=(29, 33, 19, 255))
    for (dx, dy, dh, da) in rot["drips"]:
        od.rectangle([ox + dx, oy + 20 + dy, ox + dx + 3, oy + 20 + dy + dh], fill=(111, 130, 34, int(da * 255)))
    # the whole card fades
    fade = rot["fade"]
    if fade < 1:
        a = ov.split()[3].point(lambda v: int(v * fade))
        ov.putalpha(a)
    img.paste(ov, (0, 0), ov)
    d = ImageDraw.Draw(img)
    d.text((ox, oy + 4), "k %.1f r %.1f fade %.2f" % (rot["k"], rot["r"], fade), fill=(230, 230, 200))

img.save(OUT)
print("wrote", OUT)
