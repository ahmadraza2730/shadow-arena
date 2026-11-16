#!/usr/bin/env python3
"""Composes and renders the game's two original music loops:

  menu_theme.ogg   "Dust Over the Godowns"  80 BPM, 16 bars, calm
  match_theme.ogg  "Lalkaar"                128 BPM, 32 bars, driving

Everything is synthesised here (drums, dhol, sitar-like plucks, pads,
bass), so the music is original and free to ship. Both loops wrap their
reverb tail back to the start, so they repeat without a gap.

Run:  python3 MapSource/gen_music.py      (needs numpy and ffmpeg)
"""
import os, subprocess, wave
import numpy as np

SR = 44100
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "Game", "assets", "music")
os.makedirs(OUT, exist_ok=True)
rng = np.random.default_rng(2026)

# D phrygian dominant (Hijaz / Bhairav colour): D Eb F# G A Bb C
SCALE = [0, 1, 4, 5, 7, 8, 10]
D3 = 146.83


def hz(degree, octave=0):
    """Frequency of a scale degree (0 = D3) with octave shifts."""
    o, d = divmod(degree, 7)
    return D3 * 2 ** ((SCALE[d] + 12 * (o + octave)) / 12.0)


def env(n, attack, decay, sustain=0.0, release=None):
    t = np.arange(n) / SR
    a = np.clip(t / max(attack, 1e-4), 0, 1)
    d = sustain + (1 - sustain) * np.exp(-np.maximum(t - attack, 0) / max(decay, 1e-4))
    e = a * d
    if release:
        r = int(release * SR)
        if r < n:
            e[-r:] *= np.linspace(1, 0, r)
    return e


def lowpass(x, cutoff):
    """One-pole low-pass (cheap, vectorised via cumulative filtering)."""
    a = np.exp(-2 * np.pi * cutoff / SR)
    y = np.empty_like(x)
    acc = 0.0
    # chunked python loop is fine for a few seconds of audio per voice
    for i in range(len(x)):
        acc = (1 - a) * x[i] + a * acc
        y[i] = acc
    return y


def lp_fast(x, cutoff):
    """FFT brick-ish low-pass for long signals."""
    f = np.fft.rfft(x)
    freqs = np.fft.rfftfreq(len(x), 1 / SR)
    f *= 1 / np.sqrt(1 + (freqs / cutoff) ** 4)
    return np.fft.irfft(f, len(x))


def hp_fast(x, cutoff):
    f = np.fft.rfft(x)
    freqs = np.fft.rfftfreq(len(x), 1 / SR)
    f *= 1 - 1 / np.sqrt(1 + (freqs / cutoff) ** 4)
    return np.fft.irfft(f, len(x))


# ------------------------------------------------------------ instruments
def kick(length=0.45):
    n = int(length * SR); t = np.arange(n) / SR
    freq = 45 + 85 * np.exp(-t * 28)
    phase = 2 * np.pi * np.cumsum(freq) / SR
    return np.sin(phase) * np.exp(-t * 7) * 1.0 + rng.uniform(-1, 1, n) * np.exp(-t * 300) * 0.15


def snare(length=0.3):
    n = int(length * SR); t = np.arange(n) / SR
    noise = hp_fast(rng.uniform(-1, 1, n), 1200) * np.exp(-t * 18)
    tone = np.sin(2 * np.pi * 190 * t) * np.exp(-t * 25)
    return noise * 0.7 + tone * 0.4


def hat(length=0.08, open_=False):
    n = int((0.3 if open_ else length) * SR); t = np.arange(n) / SR
    return hp_fast(rng.uniform(-1, 1, n), 7000) * np.exp(-t * (12 if open_ else 60)) * 0.35


def dhol_low(length=0.5):
    """'Dagga': the deep side of the dhol."""
    n = int(length * SR); t = np.arange(n) / SR
    freq = 70 + 60 * np.exp(-t * 18)
    body = np.sin(2 * np.pi * np.cumsum(freq) / SR) * np.exp(-t * 6)
    slap = lp_fast(rng.uniform(-1, 1, n), 900) * np.exp(-t * 60)
    return body * 0.9 + slap * 0.5


def dhol_high(length=0.18):
    """'Tilli': the sharp stick side."""
    n = int(length * SR); t = np.arange(n) / SR
    tone = np.sin(2 * np.pi * 420 * t) * np.exp(-t * 35) + np.sin(2 * np.pi * 690 * t) * np.exp(-t * 50) * 0.5
    click = hp_fast(rng.uniform(-1, 1, n), 2500) * np.exp(-t * 120)
    return tone * 0.55 + click * 0.45


def pluck(freq, length=1.2, bright=0.5, buzz=0.35):
    """Karplus-Strong string with a 'jawari' buzz for a sitar/rubab feel."""
    n = int(length * SR)
    period = max(2, int(SR / freq))
    buf = rng.uniform(-1, 1, period)
    out = np.empty(n)
    idx = 0
    damp = 0.996 - (1 - bright) * 0.006
    for i in range(n):
        v = buf[idx]
        nxt = buf[(idx + 1) % period]
        buf[idx] = damp * 0.5 * (v + nxt)
        out[i] = v
        idx = (idx + 1) % period
    out = np.tanh(out * (1 + buzz * 4)) / np.tanh(1 + buzz * 4)    # bridge buzz
    return out * env(n, 0.002, length * 0.45)


def saw(freq, n, detune=0.0):
    t = np.arange(n) / SR
    f = freq * (1 + detune)
    return 2 * ((t * f) % 1.0) - 1


def pad(freqs, length, cutoff=1200):
    n = int(length * SR)
    s = np.zeros(n)
    for f in freqs:
        for d in (-0.006, 0.0, 0.007):
            s += saw(f, n, d)
    s = lp_fast(s / (len(freqs) * 3), cutoff)
    return s * env(n, length * 0.3, 9e9, 1.0, release=length * 0.35)


def bass(freq, length):
    n = int(length * SR)
    s = saw(freq, n) * 0.6 + np.sign(np.sin(2 * np.pi * freq / 2 * np.arange(n) / SR)) * 0.4
    s = lp_fast(s, 380)
    return s * env(n, 0.005, length * 0.6, 0.5, release=0.04)


def riser(length):
    n = int(length * SR); t = np.arange(n) / SR
    noise = rng.uniform(-1, 1, n)
    out = np.zeros(n)
    steps = 16
    for k in range(steps):
        a, b = k * n // steps, (k + 1) * n // steps
        out[a:b] = hp_fast(noise[a:b], 400 + 6000 * k / steps)
    return out * (t / length) ** 2 * 0.4


# --------------------------------------------------------------- mixing
class Track:
    def __init__(self, bpm, bars, tail=4.0):
        self.beat = 60.0 / bpm
        self.length = bars * 4 * self.beat
        self.n = int(self.length * SR)
        self.buf = np.zeros((int((self.length + tail) * SR), 2))

    def add(self, sound, beat_pos, gain=1.0, pan=0.0):
        start = int(beat_pos * self.beat * SR)
        end = min(start + len(sound), len(self.buf))
        if start >= len(self.buf):
            return
        seg = sound[: end - start] * gain
        self.buf[start:end, 0] += seg * np.sqrt(0.5 * (1 - pan))
        self.buf[start:end, 1] += seg * np.sqrt(0.5 * (1 + pan))

    def reverb(self, amount=0.25, decay=1.8):
        """Cheap stereo reverb: noise-burst impulse convolved via FFT."""
        ir_n = int(decay * SR)
        t = np.arange(ir_n) / SR
        out = np.copy(self.buf)
        for ch in range(2):
            ir = rng.uniform(-1, 1, ir_n) * np.exp(-t * 6.9 / decay)
            ir = lp_fast(ir, 5000)
            ir /= np.sqrt(np.sum(ir ** 2))
            size = len(self.buf) + ir_n
            wet = np.fft.irfft(np.fft.rfft(self.buf[:, ch], size) * np.fft.rfft(ir, size), size)
            out[:, ch] += wet[: len(self.buf)] * amount
        self.buf = out

    def render(self, name, title):
        loop = self.buf[: self.n].copy()
        tail = self.buf[self.n:]
        loop[: len(tail)] += tail[: self.n]            # wrap the tail for a seamless loop
        loop = np.tanh(loop / np.max(np.abs(loop)) * 1.4) * 0.89
        path_wav = f"/tmp/{name}.wav"
        with wave.open(path_wav, "wb") as w:
            w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR)
            w.writeframes((loop * 32767).astype(np.int16).tobytes())
        out = os.path.join(OUT, name + ".ogg")
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", path_wav, "-c:a", "libvorbis", "-q:a", "4",
                        "-metadata", f"title={title}", "-metadata", "artist=Shadow Arena", out], check=True)
        print(f"wrote {out}  {self.length:.1f}s  {os.path.getsize(out) // 1024} KB")


# ----------------------------------------------------------------- menu
def make_menu():
    tr = Track(80, 16, tail=4)
    # Chords (scale degrees): i - bII - i - VII, two bars each.
    chords = [[0, 2, 4], [1, 3, 5], [0, 2, 4], [6, 1, 3]] * 2
    for i, ch in enumerate(chords):
        tr.add(pad([hz(d, -1) for d in ch] + [hz(ch[0], -2)], 8 * tr.beat + 1.0, cutoff=900), i * 8, 0.32)
    # Low drone on D.
    tr.add(pad([hz(0, -2)], tr.length, cutoff=300), 0, 0.25)
    # Sparse frame-drum pulse.
    for bar in range(16):
        tr.add(dhol_low(0.8), bar * 4, 0.35)
        if bar % 2 == 1:
            tr.add(dhol_low(0.6), bar * 4 + 2.5, 0.22)
        tr.add(hat(open_=True), bar * 4 + 2, 0.08, pan=0.3)
    # Plucked melody (degree, beat, length), enters on bar 4 and answers itself.
    motif = [(4, 0, 1), (5, 1, 0.5), (4, 1.5, 0.5), (2, 2, 1.5), (1, 3.5, 0.5), (0, 4, 2), (2, 6, 1), (1, 7, 1)]
    answer = [(7, 0, 1), (6, 1, 0.5), (5, 1.5, 0.5), (4, 2, 1), (5, 3, 0.5), (4, 3.5, 0.5), (2, 4, 2.5), (1, 7, 1)]
    for start_bar, phrase in ((4, motif), (6, answer), (10, motif), (12, answer)):
        for deg, beat_pos, ln in phrase:
            tr.add(pluck(hz(deg, 1), 1.6, bright=0.6), start_bar * 4 + beat_pos, 0.42, pan=-0.2)
    tr.reverb(0.45, 2.6)
    tr.render("menu_theme", "Dust Over the Godowns")


# ---------------------------------------------------------------- match
def make_match():
    tr = Track(128, 32, tail=2.5)
    K, S, DL, DH = kick(), snare(), dhol_low(), dhol_high()
    H, HO = hat(), hat(open_=True)
    # Song shape (8-bar sections): intro, drop A, break, drop B.
    for bar in range(32):
        section = bar // 8
        b0 = bar * 4
        full = section in (1, 3)
        # Kick: four on the floor except in the break's first half.
        if not (section == 2 and bar % 8 < 4):
            for q in range(4):
                tr.add(K, b0 + q, 0.9)
        if full or section == 2:
            tr.add(S, b0 + 1, 0.5, pan=0.05)
            tr.add(S, b0 + 3, 0.5, pan=0.05)
        # Hats on the off-beats, open hat on the "and" of 4.
        if section > 0:
            for q in range(4):
                tr.add(H, b0 + q + 0.5, 0.32, pan=0.35)
            tr.add(HO, b0 + 3.5, 0.22, pan=-0.3)
        # Dhol "chaal" groove: dha . ge na . dha ge na.
        chaal = [(0, DL, 0.55), (0.75, DH, 0.4), (1.0, DH, 0.35), (1.5, DL, 0.45),
                 (2.0, DL, 0.55), (2.75, DH, 0.4), (3.0, DH, 0.35), (3.5, DH, 0.3)]
        for pos, snd, g in chaal:
            tr.add(snd, b0 + pos, g * (1.0 if section != 0 or bar % 8 >= 4 else 0.6), pan=-0.25)
    # Bass ostinato on D with a push to Eb and C.
    bass_line = [0, 0, 0, 1, 0, 0, 6 - 7, 0]          # degrees per half bar
    for bar in range(32):
        if bar // 8 == 2 and bar % 8 < 4:
            continue
        for half in range(2):
            deg = bass_line[(bar * 2 + half) % len(bass_line)]
            for eighth in range(4):
                tr.add(bass(hz(deg, -2), tr.beat * 0.45), bar * 4 + half * 2 + eighth * 0.5,
                       0.55 if eighth % 2 == 0 else 0.4)
    # Pads under the drops and the break.
    prog = [[0, 2, 4], [1, 3, 5], [6, 1, 3], [0, 2, 4]]
    for bar in range(8, 32, 2):
        ch = prog[(bar // 2) % 4]
        tr.add(pad([hz(d, -1) for d in ch], 8 * tr.beat, cutoff=1400), bar * 4, 0.18)
    # Lead: sitar-like hook in the drops, answered an octave up.
    hook = [(4, 0), (5, 0.5), (4, 1), (2, 1.5), (1, 2), (2, 2.75), (0, 3.5),
            (4, 4), (5, 4.5), (7, 5), (5, 5.5), (4, 6), (2, 6.75), (1, 7.25)]
    for start in (8, 12, 24, 28):
        octave = 1 if start in (8, 24) else 2
        for deg, pos in hook:
            tr.add(pluck(hz(deg, octave), 0.7, bright=0.75), start * 4 + pos, 0.38, pan=0.25)
    # Break: slow plucked arpeggio, then a riser into drop B.
    for i in range(16):
        tr.add(pluck(hz([0, 2, 4, 7][i % 4], 1), 1.0, bright=0.5), 16 * 4 + i * 2, 0.35, pan=-0.3)
    tr.add(riser(4 * 4 * tr.beat), 20 * 4, 0.18)
    tr.add(riser(2 * 4 * tr.beat), 6 * 4, 0.12)
    tr.reverb(0.2, 1.4)
    tr.render("match_theme", "Lalkaar")


if __name__ == "__main__":
    make_menu()
    make_match()
