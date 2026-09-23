"""プロトタイプ用ピクセルアートの生成スクリプト。

使い方:  python tools/gen_art.py
出力先:  assets/sprites/
  chara_<id>.png  キャラのスプライトシート（16x16 × 4列 × 8行）
  town_bg.png     町の背景（360x400）
  town_glow.png   夜の窓明かり（360x400、町の背景に重ねる）
  grave.png       墓石（12x14）

後で本番アートに差し替える前提。レイアウトは scripts/town.gd と Sim.PLACES に合わせてある。
"""
import os
import random
from PIL import Image, ImageDraw

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
OUT = os.path.join(ROOT, "assets", "sprites")
os.makedirs(OUT, exist_ok=True)


def hexc(h, a=255):
    h = h.lstrip("#")
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), a)


# ============================================================
# キャラクター
# ============================================================
# 頭 12x10 / 体 12x5。16x16 のキャンバスに (2, 1) と (2, 11) で置く。
# o=輪郭 s=肌 S=肌影 h=髪 H=髪影 c=服 C=服影 e=目 w=目のハイライト
# b=頬 l=脚 a/A=小物 p=エプロン g=メガネ

HEAD_TOP = [
    "...oooooo...",
    "..ohhhhhho..",
    ".ohhhhhhhho.",
    "ohhhhhhhhhho",
    "ohhHhhhhHhho",
]
FACE_FRONT = {
    "open":   ["ohssssssssho", "ohswesswesho", "ohseesseesho"],
    "closed": ["ohssssssssho", "ohssssssssho", "ohseesseesho"],
    "wide":   ["ohssssssssho", "ohseesseesho", "ohswesswesho"],
    "sleepy": ["ohssssssssho", "ohsoossoosho", "ohseesseesho"],
}
CHIN_FRONT = {
    "normal": ["osbssssssbso", ".osssssssso."],
    "wide":   ["osbsseessbso", ".osssssssso."],
}
HEAD_SIDE = {
    "open": [
        "...oooooo...",
        "..ohhhhhho..",
        ".ohhhhhhhho.",
        "ohhhhhhhhhho",
        "ohhhhhhhhHho",
        "ohhhhsssssso",
        "ohhhhssswe" + "so",
        "ohhhhsssee" + "so",
        ".ohhhsssbso.",
        "..ohhsssso..",
    ],
}
HEAD_SIDE["closed"] = HEAD_SIDE["open"][:6] + ["ohhhhsssssso", "ohhhhssseeso"] + HEAD_SIDE["open"][8:]
HEAD_SIDE["sleepy"] = HEAD_SIDE["open"][:6] + ["ohhhhsssooso", "ohhhhssseeso"] + HEAD_SIDE["open"][8:]
HEAD_SIDE["wide"] = HEAD_SIDE["open"]
HEAD_BACK = HEAD_TOP + [
    "ohhhhhhhhhho",
    "ohhhhhhhhhho",
    "ohHhhhhhhhHo",
    ".ohHhhhhHho.",
    "..oHHHHHHo..",
]

BODY = {
    "front": ["..occcccco..", ".osccccccso.", "..oCCCCCCo.."],
    "side":  ["...occcco...", "...occcso...", "...oCCCCo..."],
    "pray":  ["..occsscco..", "..occcccco..", "..oCCCCCCo.."],
    "armup": ["..occccccos.", ".osccccccoo.", "..oCCCCCCo.."],
    "cheer": [".soccccccos.", "..occcccco..", "..oCCCCCCo.."],
}
LEGS = {
    "stand":  ["...ol..lo...", "...oo..oo..."],
    "stepA":  ["..ol...lo...", "..oo...oo..."],
    "stepB":  ["...ol...lo..", "...oo...oo.."],
    "sstand": ["....olo.....", "....ooo....."],
    "sstepA": ["...ol.lo....", "...oo.oo...."],
    "sstepB": [".....olo....", ".....ooo...."],
}

BASE_PAL = {
    "o": "#2a1e36", "e": "#2a1e36", "w": "#ffffff",
    "s": "#ffe0c4", "S": "#f2b999", "b": "#ff9aa8", "l": "#4a3b52",
}

CHARAS = {
    "tome": {"h": "#7a4a32", "H": "#5c3422", "c": "#e98a4f", "C": "#c96a36",
             "a": "#fff3dc", "A": "#e6cfa8", "p": "#fffaf0"},
    "kaz":  {"h": "#6b3fa0", "H": "#4f2c7a", "c": "#7d4fc0", "C": "#5d3796",
             "a": "#ffd45a", "A": "#e0a82a"},
    "nob":  {"h": "#2f3450", "H": "#1f2238", "c": "#eef3f8", "C": "#c9d3df",
             "a": "#4a78d8", "A": "#3a5ab0", "g": "#7a9ad8"},
    "sen":  {"h": "#b8bcc8", "H": "#9096a4", "c": "#5a6070", "C": "#434857",
             "a": "#4b4f5e", "A": "#353844", "s": "#f3dccb", "S": "#dcbfae"},
    "mimi": {"h": "#ff8fc4", "H": "#e0619f", "c": "#ffd84d", "C": "#f0b429",
             "a": "#ff5a7a", "A": "#d93a5a"},
}


class Canvas:
    def __init__(self):
        self.px = {}

    def put(self, x, y, k):
        if 0 <= x < 16 and 0 <= y < 16:
            self.px[(x, y)] = k

    def blit(self, rows, ox, oy):
        for y, row in enumerate(rows):
            for x, k in enumerate(row):
                if k != ".":
                    self.put(ox + x, oy + y, k)

    def recolor(self, ox, oy, x0, y0, x1, y1, frm, to):
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                if self.px.get((ox + x, oy + y), ".") in frm:
                    self.px[(ox + x, oy + y)] = to


def default_eyes(cid):
    return "sleepy" if cid == "sen" else "open"


def make_frame(cid, view, eyes=None, body="front", legs="stand", head_dy=0, dy=0):
    """view: front/side/back。dy は全体、head_dy は頭だけのずらし"""
    eyes = eyes or default_eyes(cid)
    c = Canvas()
    hx, hy = 2, 1 + dy + head_dy
    bx, by = 2, 11 + dy
    # 体（頭より先に描いて、頭が重なるようにする）
    body_rows = BODY["side"] if view == "side" and body == "front" else BODY[body]
    c.blit(body_rows, bx, by)
    c.blit(LEGS[legs], bx, by + 3)
    # 頭
    if view == "front":
        chin = CHIN_FRONT["wide" if eyes == "wide" else "normal"]
        c.blit(HEAD_TOP + FACE_FRONT[eyes] + chin, hx, hy)
    elif view == "side":
        c.blit(HEAD_SIDE[eyes if eyes in HEAD_SIDE else "open"], hx, hy)
    else:
        c.blit(HEAD_BACK, hx, hy)
    decorate(c, cid, view, body, hx, hy, bx, by)
    return c


def decorate(c, cid, view, body, hx, hy, bx, by):
    """キャラごとの髪型・小物"""
    if cid == "tome":
        # 三角巾とエプロン
        c.recolor(hx, hy, 0, 0, 11, 2, "hH", "a")
        c.recolor(hx, hy, 0, 3, 11, 3, "H", "A")
        if view == "side":
            c.put(hx - 1, hy + 3, "o"); c.put(hx, hy + 3, "a"); c.put(hx - 1, hy + 4, "o")
        if view == "front" and body != "pray":
            c.recolor(bx, by, 4, 1, 7, 2, "cC", "p")
    elif cid == "kaz":
        # フード（髪色＝フード色）と胸の金の紋
        if view == "front" and body in ("front", "armup", "cheer"):
            c.put(bx + 5, by + 1, "a"); c.put(bx + 6, by + 1, "a")
    elif cid == "nob":
        # メガネ・ネクタイ・アホ毛
        if view == "front":
            for x in (2, 5, 6, 9):
                c.put(hx + x, hy + 6, "g")
            if body in ("front", "armup", "cheer"):
                c.put(bx + 5, by + 1, "a"); c.put(bx + 6, by + 1, "a"); c.put(bx + 5, by + 2, "A")
        elif view == "side":
            c.put(hx + 7, hy + 6, "g"); c.put(hx + 7, hy + 7, "g")
            c.put(hx + 10, hy + 6, "g"); c.put(hx + 10, hy + 7, "g")
        c.put(hx + 6, hy - 1, "o"); c.put(hx + 7, hy - 1, "o")
    elif cid == "sen":
        # つば広の帽子
        c.recolor(hx, hy, 0, 0, 11, 2, "hH", "a")
        for x in range(-1, 13):
            c.put(hx + x, hy + 3, "A")
        c.put(hx - 2, hy + 3, "o"); c.put(hx + 13, hy + 3, "o")
        for x in range(-1, 13):
            if c.px.get((hx + x, hy + 4)) in (None,):
                c.put(hx + x, hy + 4, "o")
    elif cid == "mimi":
        # ツインテールとリボン
        # (内側の列, 外側への向き)
        sides = [(-1, -1), (12, 1)] if view in ("front", "back") else [(-1, -1)]
        for base, d in sides:
            x0 = hx + base
            c.put(x0, hy + 2, "a"); c.put(x0 + d, hy + 2, "A")
            for yy in range(3, 8):
                c.put(x0, hy + yy, "h" if yy < 6 else "H")
                c.put(x0 + d, hy + yy, "o")
            c.put(x0, hy + 8, "o")


# アニメーション定義（行ごと）。各要素 = make_frame の引数
ANIMS = [
    ("idle",       [dict(view="front"), dict(view="front", head_dy=1)]),
    ("walk_down",  [dict(view="front"), dict(view="front", legs="stepA", dy=-1),
                    dict(view="front"), dict(view="front", legs="stepB", dy=-1)]),
    ("walk_up",    [dict(view="back"), dict(view="back", legs="stepA", dy=-1),
                    dict(view="back"), dict(view="back", legs="stepB", dy=-1)]),
    ("walk_side",  [dict(view="side", legs="sstand"), dict(view="side", legs="sstepA", dy=-1),
                    dict(view="side", legs="sstand"), dict(view="side", legs="sstepB", dy=-1)]),
    ("pray",       [dict(view="front", eyes="closed", body="pray"),
                    dict(view="front", eyes="closed", body="pray", head_dy=1)]),
    ("sleep",      [dict(view="front", eyes="closed", head_dy=1),
                    dict(view="front", eyes="closed", head_dy=2)]),
    ("work",       [dict(view="front"), dict(view="front", body="armup", dy=-1)]),
    ("surprise",   [dict(view="front", eyes="wide", body="cheer", dy=-1),
                    dict(view="front", eyes="wide", body="cheer")]),
]


def render_chara(cid):
    pal = dict(BASE_PAL)
    pal.update(CHARAS[cid])
    img = Image.new("RGBA", (64, 16 * len(ANIMS)), (0, 0, 0, 0))
    for row, (_name, frames) in enumerate(ANIMS):
        for col, args in enumerate(frames):
            c = make_frame(cid, **args)
            for (x, y), k in c.px.items():
                if k in pal:
                    img.putpixel((col * 16 + x, row * 16 + y), hexc(pal[k]))
    img.save(os.path.join(OUT, f"chara_{cid}.png"))


# ============================================================
# 町の背景
# ============================================================
W, H = 360, 400
TILE = 16
OX = 4
rng = random.Random(7)

OUTLINE = hexc("#3b2a3a")
GRASS = [hexc("#8fd16a"), hexc("#84c95f"), hexc("#9bd875")]
GRASS_DARK = hexc("#6fb455")
GRASS_LIGHT = hexc("#b5e68a")
DIRT = hexc("#ecd09a")
DIRT_EDGE = hexc("#d2b07a")
DIRT_DOT = hexc("#c9a46e")


def tile_rect(tx, ty, tw, th):
    return OX + tx * TILE, ty * TILE, tw * TILE, th * TILE


def rect(d, x, y, w, h, col):
    if w > 0 and h > 0:
        d.rectangle([x, y, x + w - 1, y + h - 1], fill=col)


def outline_rect(d, x, y, w, h, col):
    d.rectangle([x, y, x + w - 1, y + h - 1], outline=col)


def draw_grass(img, d):
    rect(d, 0, 0, W, H, GRASS[0])
    for y in range(0, H, 4):
        for x in range(0, W, 4):
            if rng.random() < 0.35:
                rect(d, x, y, 4, 4, rng.choice(GRASS))
    for _ in range(420):
        x, y = rng.randrange(W), rng.randrange(H)
        img.putpixel((x, y), GRASS_DARK)
        if y > 0:
            img.putpixel((x, y - 1), GRASS_DARK if rng.random() < 0.5 else GRASS_LIGHT)
    # 花
    flowers = [hexc("#ffffff"), hexc("#ffe066"), hexc("#ff9ec7"), hexc("#b9a6ff")]
    for _ in range(90):
        x, y = rng.randrange(2, W - 2), rng.randrange(2, H - 2)
        col = rng.choice(flowers)
        img.putpixel((x, y), col)
        img.putpixel((x + 1, y), col)
        img.putpixel((x, y + 1), col)
        img.putpixel((x + 1, y + 1), hexc("#f6a33b"))


def draw_path(img, d, tx, ty, tw, th):
    x, y, w, h = tile_rect(tx, ty, tw, th)
    x, y, w, h = x + 2, y + 2, w - 4, h - 4
    rect(d, x - 1, y - 1, w + 2, h + 2, DIRT_EDGE)
    rect(d, x, y, w, h, DIRT)
    for _ in range(w * h // 40):
        px, py = x + rng.randrange(w), y + rng.randrange(h)
        img.putpixel((px, py), DIRT_DOT)


def draw_plaza(img, d):
    x, y, w, h = tile_rect(8, 11, 6, 4)
    rect(d, x - 1, y - 1, w + 2, h + 2, hexc("#a79c88"))
    for ty in range(0, h, 8):
        for tx in range(0, w, 8):
            off = 4 if (ty // 8) % 2 else 0
            col = hexc("#e2dccd") if ((tx + ty) // 8) % 3 else hexc("#d8d0bf")
            rect(d, x + tx + off - 4, y + ty, 8, 8, col)
    # 目地
    for ty in range(0, h, 8):
        d.line([x, y + ty, x + w - 1, y + ty], fill=hexc("#c7bda9"))
        off = 4 if (ty // 8) % 2 else 0
        for tx in range(off, w, 8):
            d.line([x + tx, y + ty, x + tx, y + ty + 7], fill=hexc("#c7bda9"))
    # 四隅の花壇
    for cx, cy in [(x + 2, y + 2), (x + w - 12, y + 2), (x + 2, y + h - 10), (x + w - 12, y + h - 10)]:
        rect(d, cx, cy, 10, 8, hexc("#8b5a3c"))
        rect(d, cx + 1, cy + 1, 8, 6, hexc("#5d9e45"))
        for fx, fy, fc in [(2, 2, "#ff7eb6"), (5, 3, "#ffe066"), (3, 5, "#ffffff"), (7, 2, "#ff7eb6")]:
            img.putpixel((cx + fx, cy + fy), hexc(fc))


def roof_shingles(img, d, x, y, w, h, col, dark):
    rect(d, x, y, w, h, col)
    for ry in range(y + 3, y + h, 4):
        d.line([x, ry, x + w - 1, ry], fill=dark)
        off = 2 if ((ry - y) // 4) % 2 else 0
        for rx in range(x + off, x + w, 6):
            img.putpixel((rx, ry - 1), dark)
    d.line([x, y, x + w - 1, y], fill=tuple(min(255, v + 40) for v in col[:3]) + (255,))


def window(d, glow, x, y, w=6, h=6):
    rect(d, x - 1, y - 1, w + 2, h + 2, OUTLINE)
    rect(d, x, y, w, h, hexc("#9fd8ff"))
    rect(d, x, y, w // 2, h // 2, hexc("#d8f1ff"))
    d.line([x + w // 2, y, x + w // 2, y + h - 1], fill=hexc("#6b4a3a"))
    # 夜の明かり
    gd = ImageDraw.Draw(glow)
    rect(gd, x - 2, y - 2, w + 4, h + 4, hexc("#ffcf6b", 70))
    rect(gd, x, y, w, h, hexc("#ffd97a"))
    rect(gd, x, y, w // 2, h // 2, hexc("#fff0b8"))
    gd.line([x + w // 2, y, x + w // 2, y + h - 1], fill=hexc("#6b4a3a"))


def house(img, d, glow, tx, ty, tw, th, roof, roof_dark, wall="#f5e6cc", wall_dark="#dcc7a4", door="#8b5a3c"):
    x, y, w, h = tile_rect(tx, ty, tw, th)
    roof_h = int(h * 0.55)
    # 影
    rect(d, x + 2, y + h - 1, w, 3, hexc("#000000", 40))
    # 壁
    rect(d, x + 1, y + roof_h - 2, w - 2, h - roof_h + 2, hexc(wall))
    rect(d, x + 1, y + h - 3, w - 2, 2, hexc(wall_dark))
    outline_rect(d, x + 1, y + roof_h - 2, w - 2, h - roof_h + 2, OUTLINE)
    # 屋根（少しはみ出す）
    roof_shingles(img, d, x - 1, y, w + 2, roof_h, hexc(roof), hexc(roof_dark))
    outline_rect(d, x - 1, y, w + 2, roof_h, OUTLINE)
    # ドア
    dw, dh = 8, 10
    dx = x + w // 2 - dw // 2
    dy = y + h - dh - 1
    rect(d, dx - 1, dy - 1, dw + 2, dh + 1, OUTLINE)
    rect(d, dx, dy, dw, dh, hexc(door))
    rect(d, dx + 1, dy + 1, dw - 2, 3, tuple(min(255, v + 30) for v in hexc(door)[:3]) + (255,))
    img.putpixel((dx + dw - 2, dy + dh // 2 + 1), hexc("#ffd45a"))
    # 窓
    wy = y + roof_h + 2
    if w >= 48:
        window(d, glow, x + 6, wy)
        window(d, glow, x + w - 12, wy)
    else:
        window(d, glow, x + 4, wy, 5, 5)
    return x, y, w, h, roof_h


def draw_bakery(img, d, glow):
    x, y, w, h, roof_h = house(img, d, glow, 1, 5, 4, 3, "#e8744a", "#c2553a")
    # 縞のひさし
    ay = y + roof_h - 3
    for i in range(0, w - 2, 4):
        rect(d, x + 1 + i, ay, 4, 4, hexc("#ffffff") if (i // 4) % 2 else hexc("#ff6b6b"))
    outline_rect(d, x + 1, ay, w - 2, 4, OUTLINE)
    # パンの看板
    sx, sy = x + w - 16, y + 4
    rect(d, sx - 1, sy - 1, 14, 10, OUTLINE)
    rect(d, sx, sy, 12, 8, hexc("#fff3dc"))
    d.ellipse([sx + 2, sy + 2, sx + 9, sy + 6], fill=hexc("#d98c3c"), outline=hexc("#8b5a2b"))
    d.line([sx + 4, sy + 3, sx + 4, sy + 5], fill=hexc("#f5c57a"))
    d.line([sx + 7, sy + 3, sx + 7, sy + 5], fill=hexc("#f5c57a"))


def draw_study(img, d, glow):
    x, y, w, h, roof_h = house(img, d, glow, 17, 5, 4, 3, "#5a78c8", "#3f5aa0", wall="#eef0f5", wall_dark="#c9cfdc", door="#5a4a6a")
    # 本の看板
    sx, sy = x + 4, y + 4
    rect(d, sx - 1, sy - 1, 14, 10, OUTLINE)
    rect(d, sx, sy, 12, 8, hexc("#fff8e8"))
    rect(d, sx + 2, sy + 2, 4, 5, hexc("#4a78d8"))
    rect(d, sx + 6, sy + 2, 4, 5, hexc("#e0574f"))
    d.line([sx + 6, sy + 2, sx + 6, sy + 6], fill=OUTLINE)
    # 煙突
    rect(d, x + w - 14, y - 4, 6, 8, hexc("#a05a4a"))
    outline_rect(d, x + w - 14, y - 4, 6, 8, OUTLINE)


def draw_shrine(img, d, glow):
    x, y, w, h = tile_rect(10, 1, 3, 2)
    # 石畳
    rect(d, x + 14, y + 20, 20, 12, hexc("#cfc8b8"))
    # 祠本体
    bx, by = x + 14, y + 6
    rect(d, bx + 2, by + 8, 16, 12, hexc("#b5543c"))
    outline_rect(d, bx + 2, by + 8, 16, 12, OUTLINE)
    rect(d, bx + 7, by + 12, 6, 8, hexc("#3b2a3a"))
    # 屋根
    rect(d, bx - 2, by + 2, 24, 7, hexc("#4f6b5a"))
    d.line([bx - 2, by + 2, bx + 21, by + 2], fill=hexc("#7fa08a"))
    outline_rect(d, bx - 2, by + 2, 24, 7, OUTLINE)
    rect(d, bx + 4, by - 1, 12, 4, hexc("#4f6b5a"))
    outline_rect(d, bx + 4, by - 1, 12, 4, OUTLINE)
    # しめ縄
    d.line([bx + 3, by + 10, bx + 16, by + 10], fill=hexc("#fff3dc"))
    for i in (6, 10, 14):
        img.putpixel((bx + i, by + 11), hexc("#ffffff"))
    # 鳥居
    tx0, ty0 = x + 2, y + 10
    for gx in (tx0, x + w - 6):
        rect(d, gx, ty0 + 4, 3, 18, hexc("#e0453a"))
        outline_rect(d, gx, ty0 + 4, 3, 18, OUTLINE)
    rect(d, tx0 - 3, ty0, (x + w - 3) - tx0 + 6, 4, hexc("#e0453a"))
    outline_rect(d, tx0 - 3, ty0, (x + w - 3) - tx0 + 6, 4, OUTLINE)
    rect(d, tx0 - 1, ty0 + 6, (x + w - 3) - tx0 + 2, 2, hexc("#c23a30"))
    # 灯籠
    for lx in (x - 8, x + w + 2):
        rect(d, lx + 1, y + 16, 6, 12, hexc("#bdb8ad"))
        rect(d, lx, y + 14, 8, 3, hexc("#9e988b"))
        outline_rect(d, lx + 1, y + 16, 6, 12, OUTLINE)
        rect(d, lx + 2, y + 18, 4, 3, hexc("#fff0b8"))
        gd = ImageDraw.Draw(glow)
        rect(gd, lx, y + 16, 8, 7, hexc("#ffcf6b", 90))
        rect(gd, lx + 2, y + 18, 4, 3, hexc("#fff6c8"))


def draw_cemetery(img, d):
    x, y, w, h = tile_rect(15, 18, 6, 5)
    rect(d, x, y, w, h, hexc("#79b060"))
    for _ in range(60):
        img.putpixel((x + rng.randrange(w), y + rng.randrange(h)), hexc("#5f9a4c"))
    # 柵
    fence = hexc("#5a4a5e")
    for fx in range(x, x + w, 4):
        rect(d, fx, y - 3, 2, 5, fence)
        rect(d, fx, y + h - 3, 2, 5, fence)
    for fy in range(y, y + h, 4):
        if fy < y + 22 or fy > y + 34:  # 左側に入口
            rect(d, x - 1, fy, 2, 3, fence)
        rect(d, x + w - 1, fy, 2, 3, fence)
    d.line([x, y - 2, x + w - 1, y - 2], fill=fence)
    d.line([x, y + h - 2, x + w - 1, y + h - 2], fill=fence)
    # 枯れ木
    tx, ty = x + w - 12, y + 2
    rect(d, tx + 4, ty + 4, 2, 12, hexc("#6b4f45"))
    d.line([tx + 5, ty + 7, tx + 1, ty + 3], fill=hexc("#6b4f45"))
    d.line([tx + 5, ty + 6, tx + 9, ty + 2], fill=hexc("#6b4f45"))


def tree(img, d, cx, cy, r=9):
    rect(d, cx - 8, cy + r - 2, 16, 3, hexc("#000000", 40))
    rect(d, cx - 2, cy + 2, 4, r, hexc("#8b5a3c"))
    d.ellipse([cx - r, cy - r, cx + r, cy + r - 2], fill=hexc("#4f9a4a"), outline=OUTLINE)
    d.ellipse([cx - r + 3, cy - r + 2, cx + 1, cy - 1], fill=hexc("#6cbf5a"))
    img.putpixel((cx - 3, cy - r + 4), hexc("#9be07a"))
    # 木の実
    for fx, fy in [(3, -2), (-4, 2), (5, 3)]:
        if rng.random() < 0.6:
            img.putpixel((cx + fx, cy + fy), hexc("#ff6b6b"))


def bush(img, d, cx, cy):
    d.ellipse([cx - 6, cy - 4, cx + 6, cy + 4], fill=hexc("#5aa84e"), outline=OUTLINE)
    d.ellipse([cx - 4, cy - 3, cx, cy], fill=hexc("#7cc868"))


def render_town():
    img = Image.new("RGBA", (W, H), (0, 0, 0, 255))
    glow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    draw_grass(img, d)
    for p in [(11, 3, 1, 21), (2, 8, 18, 1), (2, 16, 18, 1), (2, 8, 1, 14), (20, 8, 1, 8), (14, 16, 1, 5)]:
        draw_path(img, d, *p)
    draw_plaza(img, d)
    draw_cemetery(img, d)
    # 木と茂み（道や建物を避けて外周に）
    for cx, cy in [(10, 20), (100, 24), (130, 60), (250, 22), (340, 30), (230, 60), (112, 166),
                   (250, 168), (8, 250), (350, 246), (100, 200), (258, 206), (150, 300),
                   (60, 380), (220, 384), (340, 384), (120, 370), (300, 180)]:
        tree(img, d, cx, cy)
    for cx, cy in [(64, 60), (300, 60), (150, 110), (210, 110), (70, 176),
                   (130, 250), (230, 244), (60, 280), (300, 272), (40, 360), (160, 360)]:
        bush(img, d, cx, cy)
    draw_shrine(img, d, glow)
    draw_bakery(img, d, glow)
    draw_study(img, d, glow)
    # 家（トメ / ノブ / カズ / ミミ / セン）
    house(img, d, glow, 1, 12, 2, 2, "#e0604a", "#b8463a")
    house(img, d, glow, 19, 12, 2, 2, "#4a5a8a", "#353f66")
    house(img, d, glow, 5, 19, 2, 2, "#8a5ac8", "#6a3fa0")
    house(img, d, glow, 1, 19, 2, 2, "#ff8fc4", "#e0619f")
    house(img, d, glow, 11, 20, 2, 2, "#7a808e", "#5a606c")
    img.save(os.path.join(OUT, "town_bg.png"))
    glow.save(os.path.join(OUT, "town_glow.png"))


def render_grave():
    img = Image.new("RGBA", (12, 14), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    rect(d, 1, 12, 10, 2, hexc("#000000", 50))
    d.rectangle([2, 2, 9, 12], fill=hexc("#b8bcc8"), outline=OUTLINE)
    d.rectangle([3, 1, 8, 2], fill=hexc("#b8bcc8"))
    d.line([3, 0, 8, 0], fill=OUTLINE)
    img.putpixel((2, 1), OUTLINE); img.putpixel((9, 1), OUTLINE)
    d.line([3, 3, 3, 11], fill=hexc("#d8dce6"))
    d.line([5, 4, 5, 8], fill=hexc("#6a6e7a"))
    d.line([4, 5, 7, 5], fill=hexc("#6a6e7a"))
    for x, c in [(1, "#ff7eb6"), (10, "#ffe066"), (0, "#5aa84e"), (11, "#5aa84e")]:
        img.putpixel((x, 11), hexc(c))
    img.save(os.path.join(OUT, "grave.png"))


if __name__ == "__main__":
    for cid in CHARAS:
        render_chara(cid)
    render_town()
    render_grave()
    print("generated:", sorted(os.listdir(OUT)))
