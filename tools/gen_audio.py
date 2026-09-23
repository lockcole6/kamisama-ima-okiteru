"""プロトタイプ用の音（BGM・環境音・効果音）を合成するスクリプト。外部素材なし。

使い方:  python tools/gen_audio.py
出力先:  assets/audio/*.wav（22050Hz / 16bit / モノラル）
  bgm_day.wav / bgm_night.wav / amb_rain.wav はループ用（smpl チャンクにループ位置を書く）

後で本番のサウンドに差し替える前提。ファイル名を変えなければ差し替えるだけで鳴る。
"""
import math
import os
import random
import struct

SR = 22050
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
OUT = os.path.join(ROOT, "assets", "audio")
os.makedirs(OUT, exist_ok=True)
rng = random.Random(3)

NOTE = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}


def freq(name):
    """'C5' 'A4' → Hz"""
    n = NOTE[name[0]]
    octave = int(name[-1])
    if "#" in name:
        n += 1
    midi = 12 * (octave + 1) + n
    return 440.0 * 2 ** ((midi - 69) / 12)


# ------------------------------------------------------------
# 音色
# ------------------------------------------------------------

def env(t, dur, a=0.005, d=0.1, s=0.6, r=0.1):
    if t < a:
        return t / a
    if t < a + d:
        return 1.0 - (1.0 - s) * (t - a) / d
    if t < dur:
        return s
    if t < dur + r:
        return s * (1.0 - (t - dur) / r)
    return 0.0


def bell(f, t):
    """オルゴール／鈴っぽい音（倍音が速く減衰）"""
    return (math.sin(2 * math.pi * f * t) * math.exp(-t * 3.0)
            + 0.45 * math.sin(2 * math.pi * f * 2.0 * t) * math.exp(-t * 6.0)
            + 0.2 * math.sin(2 * math.pi * f * 3.01 * t) * math.exp(-t * 9.0))


def tri(f, t):
    p = (f * t) % 1.0
    return 4 * p - 1 if p < 0.5 else 3 - 4 * p


def soft_square(f, t):
    return math.tanh(3.0 * math.sin(2 * math.pi * f * t)) * 0.7


# ------------------------------------------------------------
# 書き出し
# ------------------------------------------------------------

def write_wav(name, samples, loop=False, gain=1.0):
    samples = list(samples)
    if not loop:
        # 終わりの段差でプツッと鳴らないように短くフェードアウト
        fade = min(len(samples), int(SR * 0.015))
        for k in range(fade):
            samples[-1 - k] *= k / fade
    peak = max(1e-6, max(abs(s) for s in samples))
    scale = min(1.0, 0.95 / peak) * gain
    data = b"".join(struct.pack("<h", int(max(-1, min(1, s * scale)) * 32767)) for s in samples)
    fmt = struct.pack("<HHIIHH", 1, 1, SR, SR * 2, 2, 16)
    chunks = b"fmt " + struct.pack("<I", len(fmt)) + fmt
    if loop:
        # smpl チャンク：Godot の取り込みは「WAVから検出」でループ位置を読む
        smpl = struct.pack("<IIIIIIIII", 0, 0, int(1e9 / SR), 60, 0, 0, 0, 1, 0)
        smpl += struct.pack("<IIIIII", 0, 0, 0, len(samples) - 1, 0, 0)
        chunks += b"smpl" + struct.pack("<I", len(smpl)) + smpl
    chunks += b"data" + struct.pack("<I", len(data)) + data
    with open(os.path.join(OUT, name), "wb") as f:
        f.write(b"RIFF" + struct.pack("<I", 4 + len(chunks)) + b"WAVE" + chunks)


def buf(sec):
    return [0.0] * int(SR * sec)


def add(b, start_sec, dur_sec, fn, wrap=False):
    """fn(t) を b に足す。wrap=True ならループの頭に回り込ませる（継ぎ目なしのBGM用）"""
    i0 = int(start_sec * SR)
    n = int(dur_sec * SR)
    L = len(b)
    for k in range(n):
        i = i0 + k
        if i >= L:
            if not wrap:
                break
            i %= L
        b[i] += fn(k / SR)


def lowpass(samples, a):
    out, y = [], 0.0
    for s in samples:
        y += a * (s - y)
        out.append(y)
    return out


# ------------------------------------------------------------
# BGM
# ------------------------------------------------------------

CHORDS = {
    "C": ["C4", "E4", "G4"], "Am": ["A3", "C4", "E4"], "F": ["F3", "A3", "C4"], "G": ["G3", "B3", "D4"],
}


def up(n, octs=1):
    return n[:-1] + str(int(n[-1]) + octs)


def render_bgm(name, bpm, prog, melody, arp_step, melody_voice, pad=False, bass=True, gain=0.7):
    beat = 60.0 / bpm
    bars = len(prog)
    b = buf(bars * 4 * beat)
    for bi, ch in enumerate(prog):
        t0 = bi * 4 * beat
        tones = CHORDS[ch]
        # ベース（1拍目と3拍目）
        if bass:
            root = tones[0][:-1] + str(int(tones[0][-1]) - 1)
            for k in (0, 2):
                f = freq(root)
                add(b, t0 + k * beat, beat * 1.8,
                    lambda t, f=f: 0.28 * tri(f, t) * env(t, beat * 1.2, 0.01, 0.2, 0.5, 0.3), wrap=True)
        # オルゴールのアルペジオ
        arp = [up(tones[0]), up(tones[1]), up(tones[2]), up(tones[1])]
        steps = int(4 / arp_step)
        for s in range(steps):
            f = freq(arp[s % 4])
            add(b, t0 + s * arp_step * beat, 1.6, lambda t, f=f: 0.13 * bell(f, t), wrap=True)
        # パッド（夜）
        if pad:
            for n in tones:
                f = freq(n)
                add(b, t0, 4 * beat + 0.8,
                    lambda t, f=f: 0.07 * math.sin(2 * math.pi * f * t) * env(t, 4 * beat, 0.8, 0.5, 0.8, 0.8), wrap=True)
    # メロディ
    t = 0.0
    for bar in melody:
        for note, length in bar:
            if note != "-":
                f = freq(note)
                dur = length * beat
                add(b, t, dur + 0.6, lambda tt, f=f, dur=dur: melody_voice(f, tt, dur), wrap=True)
            t += length * beat
    write_wav(name, lowpass(b, 0.55), loop=True, gain=gain)


def day_voice(f, t, dur):
    vib = 1.0 + 0.004 * math.sin(2 * math.pi * 5.5 * t)
    return 0.2 * (0.6 * tri(f * vib, t) + 0.4 * math.sin(2 * math.pi * f * t)) * env(t, dur * 0.85, 0.01, 0.15, 0.55, 0.25)


def night_voice(f, t, dur):
    return 0.22 * bell(f, t) + 0.05 * math.sin(2 * math.pi * f * 0.5 * t) * env(t, dur, 0.2, 0.3, 0.6, 0.5)


DAY_MELODY = [
    [("E5", 1), ("G5", 1), ("A5", 0.5), ("G5", 0.5), ("E5", 1)],
    [("C5", 1), ("D5", 1), ("E5", 2)],
    [("A4", 1), ("C5", 1), ("D5", 1), ("C5", 1)],
    [("D5", 2), ("G4", 1), ("-", 1)],
    [("E5", 1), ("G5", 1), ("C6", 1), ("A5", 1)],
    [("G5", 1), ("E5", 1), ("D5", 1), ("C5", 1)],
    [("D5", 1), ("E5", 1), ("A4", 1), ("C5", 1)],
    [("D5", 2), ("C5", 2)],
]
NIGHT_MELODY = [
    [("E5", 2), ("C5", 2)],
    [("A4", 3), ("-", 1)],
    [("G4", 1), ("C5", 1), ("E5", 2)],
    [("D5", 4)],
    [("E5", 1), ("G5", 1), ("E5", 2)],
    [("C5", 2), ("A4", 2)],
    [("G4", 2), ("E5", 2)],
    [("D5", 3), ("-", 1)],
]


# ------------------------------------------------------------
# 環境音・効果音
# ------------------------------------------------------------

def rain_loop():
    n = int(SR * 4.0)
    noise = [rng.uniform(-1, 1) for _ in range(n)]
    b = lowpass(noise, 0.25)
    b = [s * 0.35 for s in b]
    # 雨粒
    for _ in range(90):
        i = rng.randrange(n)
        f = rng.uniform(1800, 4200)
        for k in range(int(SR * 0.03)):
            t = k / SR
            b[(i + k) % n] += 0.12 * math.sin(2 * math.pi * f * t) * math.exp(-t * 180)
    # 頭と尻をクロスフェードして継ぎ目をなくす
    xf = int(SR * 0.3)
    head = b[:xf]
    b = b[xf:]
    for k in range(xf):
        w = k / xf
        b[-xf + k] = b[-xf + k] * (1 - w) + head[k] * w
    write_wav("amb_rain.wav", b, loop=True, gain=0.8)


def sweep(f0, f1, dur, shape=math.sin, decay=20.0):
    out, ph = [], 0.0
    for k in range(int(SR * dur)):
        t = k / SR
        f = f0 + (f1 - f0) * (t / dur)
        ph += 2 * math.pi * f / SR
        out.append(shape(ph) * math.exp(-t * decay))
    return out


def seq(notes, step, voice, tail=1.0):
    b = buf(step * len(notes) + tail)
    for i, n in enumerate(notes):
        if n:
            f = freq(n)
            add(b, i * step, tail + step, lambda t, f=f: voice(f, t))
    return b


def sfx():
    # UI
    write_wav("sfx_tap.wav", sweep(900, 650, 0.06, decay=60), gain=0.35)
    write_wav("sfx_open.wav", seq(["E6", "B6"], 0.05, lambda f, t: 0.5 * math.sin(2 * math.pi * f * t) * math.exp(-t * 25), 0.15), gain=0.4)
    write_wav("sfx_close.wav", seq(["B5", "E5"], 0.05, lambda f, t: 0.5 * math.sin(2 * math.pi * f * t) * math.exp(-t * 25), 0.15), gain=0.35)
    write_wav("sfx_toast.wav", seq(["G5"], 0.05, lambda f, t: 0.5 * math.sin(2 * math.pi * f * t) * math.exp(-t * 18), 0.25), gain=0.3)
    # つつく
    pop = sweep(350, 1000, 0.09, decay=35)
    write_wav("sfx_poke.wav", pop, gain=0.6)
    write_wav("sfx_heal.wav", seq(["C6", "E6", "G6", "C7"], 0.07, lambda f, t: 0.4 * bell(f, t), 0.9), gain=0.55)
    boing = [math.sin(2 * math.pi * (300 + 180 * math.sin(k / SR * 38)) * k / SR) * math.exp(-k / SR * 7) for k in range(int(SR * 0.35))]
    write_wav("sfx_scare.wav", boing, gain=0.5)
    shimmer = buf(1.2)
    for i, n in enumerate(["E6", "G#6", "B6", "E7", "B6"]):
        f = freq(n)
        add(shimmer, i * 0.06, 1.0, lambda t, f=f: 0.3 * math.sin(2 * math.pi * f * t * (1 + 0.003 * math.sin(40 * t))) * math.exp(-t * 3.5))
    write_wav("sfx_revelation.wav", shimmer, gain=0.5)
    thud = [0.9 * math.sin(2 * math.pi * 70 * k / SR * (1 - 0.3 * k / SR)) * math.exp(-k / SR * 9) for k in range(int(SR * 0.6))]
    noise = lowpass([rng.uniform(-1, 1) * math.exp(-k / SR * 14) for k in range(int(SR * 0.6))], 0.08)
    write_wav("sfx_disaster.wav", [a + 0.8 * b for a, b in zip(thud, noise)], gain=0.7)
    # 風：ふくらんでしぼむノイズ（カットオフも動かす）
    n = int(SR * 1.8)
    out, y = [], 0.0
    for k in range(n):
        t = k / SR
        a = 0.02 + 0.10 * math.sin(math.pi * t / 1.8) ** 2
        y += a * (rng.uniform(-1, 1) - y)
        out.append(y * math.sin(math.pi * t / 1.8))
    write_wav("sfx_wind.wav", out, gain=0.6)
    # 雨のはじまり
    n = int(SR * 1.2)
    rs = lowpass([rng.uniform(-1, 1) * min(1.0, k / (SR * 0.8)) for k in range(n)], 0.3)
    write_wav("sfx_rain.wav", rs, gain=0.45)
    # 夢・祈り・教え
    dream = seq(["E5", "G5", "B5", "E6", "B5"], 0.13, lambda f, t: 0.35 * bell(f, t), 1.2)
    echo = [s + 0.35 * (dream[i - int(SR * 0.18)] if i >= int(SR * 0.18) else 0) for i, s in enumerate(dream)]
    write_wav("sfx_dream.wav", echo, gain=0.55)
    write_wav("sfx_bell.wav", seq(["A5"], 0.1, lambda f, t: 0.5 * bell(f, t), 1.2), gain=0.35)
    write_wav("sfx_yes.wav", seq(["C6", "G6"], 0.12, lambda f, t: 0.45 * bell(f, t), 1.0), gain=0.5)
    fan = seq(["C5", "E5", "G5", "C6", None, "E6"], 0.09, lambda f, t: 0.3 * bell(f, t) + 0.15 * tri(f, t) * math.exp(-t * 6), 1.4)
    add(fan, 0.54, 1.3, lambda t: sum(0.08 * math.sin(2 * math.pi * freq(n) * t) for n in ["C5", "E5", "G5", "C6"]) * math.exp(-t * 2.2))
    write_wav("sfx_doctrine.wav", fan, gain=0.6)
    write_wav("sfx_guide.wav", seq(["G5", "C6"], 0.08, lambda f, t: 0.4 * bell(f, t), 0.6), gain=0.4)


if __name__ == "__main__":
    render_bgm("bgm_day.wav", 96, ["C", "Am", "F", "G", "C", "Am", "F", "G"], DAY_MELODY, 0.5, day_voice)
    render_bgm("bgm_night.wav", 72, ["Am", "F", "C", "G", "Am", "F", "C", "G"], NIGHT_MELODY, 1.0, night_voice, pad=True, bass=False)
    rain_loop()
    sfx()
    print("generated:", sorted(os.listdir(OUT)))
