#!/usr/bin/env python3
"""Renders the table music: audio/music/tavern_theme.ogg (needs numpy, scipy and ffmpeg).

A warm fantasy-tavern piece in D dorian at 112 BPM, 64 bars (~2:17), looping seamlessly: fingerpicked lute,
low plucked bass, tin-whistle lead, fiddle, string pad, bodhran, rim clicks and a soft tambourine, with a
room reverb. Everything is synthesised here, so there are no samples or licences involved.

    python tools/make_music.py
"""
import subprocess, sys, os
import numpy as np
from scipy import signal

SR = 44100
BPM = 112.0
BEAT = 60.0 / BPM
EIGHTH = BEAT / 2
BAR = BEAT * 4
BARS = 64
LEN = int(round(BARS * BAR * SR))
TAIL = int(4.0 * SR)
rng = np.random.default_rng(7)


def midi(n):
    return 440.0 * 2 ** ((np.asarray(n, dtype=float) - 69.0) / 12.0)


def buf():
    return np.zeros((LEN + TAIL, 2))


def put(b, mono, t, pan=0.0, gain=1.0):
    """Mix a mono note into stereo buffer b at time t (seconds); pan -1..1."""
    i = int(t * SR)
    if i >= LEN:
        return
    n = min(len(mono), b.shape[0] - i)
    if n <= 0:
        return
    l = np.cos((pan + 1) * np.pi / 4)
    r = np.sin((pan + 1) * np.pi / 4)
    b[i:i + n, 0] += mono[:n] * gain * l * 1.4142
    b[i:i + n, 1] += mono[:n] * gain * r * 1.4142


def lowpass(x, fc, order=2):
    sos = signal.butter(order, fc / (SR / 2), "low", output="sos")
    return signal.sosfilt(sos, x)


def highpass(x, fc, order=2):
    sos = signal.butter(order, fc / (SR / 2), "high", output="sos")
    return signal.sosfilt(sos, x)


def bandpass(x, lo, hi, order=2):
    sos = signal.butter(order, [lo / (SR / 2), hi / (SR / 2)], "band", output="sos")
    return signal.sosfilt(sos, x)


# --- instruments --------------------------------------------------------------------------------

def pluck(f, dur=2.6, bright=1.0, partials=14, decay=2.0):
    """Lute / acoustic guitar: decaying harmonics (upper ones die faster), slight stretch, a soft pick click."""
    t = np.arange(int(dur * SR)) / SR
    out = np.zeros_like(t)
    for n in range(1, partials + 1):
        fn = f * n * (1 + 0.00035 * n * n)
        if fn > 9000:
            break
        amp = (1.0 / n ** 1.15) * (bright ** (n - 1) if n > 1 else 1.0)
        d = decay + 0.75 * n
        out += amp * np.sin(2 * np.pi * fn * t + rng.uniform(0, 6.28)) * np.exp(-d * t)
    click = bandpass(rng.standard_normal(int(0.012 * SR)), 1200, 5000)
    out[:len(click)] += click * 0.25
    out *= np.minimum(t / 0.002, 1.0)
    return out / 1.6


def bass_note(f, dur=1.4):
    t = np.arange(int(dur * SR)) / SR
    out = np.sin(2 * np.pi * f * t) * np.exp(-1.8 * t) + 0.45 * np.sin(2 * np.pi * 2 * f * t) * np.exp(-3.2 * t)
    out += 0.15 * np.sin(2 * np.pi * 3 * f * t) * np.exp(-5 * t)
    out *= np.minimum(t / 0.004, 1.0)
    return out


def flute(f, dur, vib=1.0):
    n = int((dur + 0.35) * SR)
    t = np.arange(n) / SR
    vfreq = 5.2
    v = 1 + 0.0045 * vib * np.sin(2 * np.pi * vfreq * t) * np.clip((t - 0.12) / 0.3, 0, 1)
    ph = 2 * np.pi * np.cumsum(f * v) / SR
    tone = np.sin(ph) + 0.22 * np.sin(2 * ph) + 0.06 * np.sin(3 * ph)
    breath = bandpass(rng.standard_normal(n), 2500, 6500) * 0.06
    env = np.clip(t / 0.07, 0, 1)
    rel = np.where(t > dur, np.exp(-(t - dur) * 14), 1.0)
    swell = 1 + 0.12 * np.sin(2 * np.pi * 0.9 * t)
    return (tone + breath) * env * rel * swell * 0.55


def fiddle(f, dur, vib=1.0):
    n = int((dur + 0.4) * SR)
    t = np.arange(n) / SR
    v = 1 + 0.006 * vib * np.sin(2 * np.pi * 5.8 * t) * np.clip((t - 0.15) / 0.35, 0, 1)
    ph = 2 * np.pi * np.cumsum(f * v) / SR
    tone = np.zeros(n)
    for k in range(1, 11):
        if f * k > 9000:
            break
        tone += np.sin(k * ph + k) / k ** 0.9
    bow = bandpass(rng.standard_normal(n), 800, 4000) * 0.05
    sig = tone + bow
    # body resonances give it wood instead of buzz
    sig = lowpass(sig, 3800) + 0.6 * bandpass(sig, 1000, 1500) + 0.4 * bandpass(sig, 2400, 3000)
    env = np.clip(t / 0.11, 0, 1) * np.where(t > dur, np.exp(-(t - dur) * 9), 1.0)
    return sig * env * 0.3


def pad(freqs, dur):
    n = int((dur + 1.4) * SR)
    t = np.arange(n) / SR
    out = np.zeros(n)
    for f in freqs:
        for cents in (-7, 0, 6):
            ff = f * 2 ** (cents / 1200)
            saw = signal.sawtooth(2 * np.pi * ff * t + rng.uniform(0, 6.28), 0.5)
            out += saw
    out = lowpass(out, 1100, 3)
    env = np.clip(t / 0.9, 0, 1) * np.where(t > dur, np.exp(-(t - dur) * 3.2), 1.0)
    return out * env / (len(freqs) * 3) * 0.9


def bodhran(strength=1.0, dur=0.45):
    t = np.arange(int(dur * SR)) / SR
    f = 62 + 70 * np.exp(-t * 30)
    ph = 2 * np.pi * np.cumsum(f) / SR
    body = np.sin(ph) * np.exp(-t * 9.5)
    skin = lowpass(rng.standard_normal(len(t)), 1400) * np.exp(-t * 40) * 0.7
    return (body + skin) * strength


def rim(dur=0.12):
    t = np.arange(int(dur * SR)) / SR
    click = bandpass(rng.standard_normal(len(t)), 1500, 6000) * np.exp(-t * 55)
    tone = np.sin(2 * np.pi * 620 * t) * np.exp(-t * 45) * 0.6
    return click * 0.8 + tone


def tambourine(dur=0.16, accent=1.0):
    t = np.arange(int(dur * SR)) / SR
    hiss = highpass(rng.standard_normal(len(t)), 6000) * np.exp(-t * 28)
    ring = (np.sin(2 * np.pi * 7400 * t) + np.sin(2 * np.pi * 9100 * t)) * np.exp(-t * 36) * 0.15
    return (hiss + ring) * accent


def clap(dur=0.14):
    t = np.arange(int(dur * SR)) / SR
    return bandpass(rng.standard_normal(len(t)), 900, 3200) * np.exp(-t * 38)


def reverb_ir(seconds=2.4):
    n = int(seconds * SR)
    t = np.arange(n) / SR
    ir = []
    for _ in range(2):
        noise = rng.standard_normal(n) * np.exp(-t * 2.6)
        noise = lowpass(noise, 5500)
        noise[:int(0.012 * SR)] *= np.linspace(0, 1, int(0.012 * SR))
        ir.append(noise)
    ir = np.stack(ir, axis=1)
    return ir / np.sqrt((ir ** 2).sum(axis=0, keepdims=True)).max()


# --- the score ----------------------------------------------------------------------------------

# chord: (guitar root MIDI, bass MIDI, minor?)
CH = {"Dm": (50, 38, True), "C": (48, 36, False), "Gm": (55, 43, True), "F": (53, 41, False), "Am": (57, 45, True)}

A8 = ["Dm", "Dm", "C", "C", "Gm", "Gm", "Dm", "Dm"]
SEC_A = A8 + A8
SEC_B = ["F", "F", "C", "C", "Gm", "Gm", "Am", "Am", "F", "C", "Gm", "Gm", "Am", "Am", "Dm", "Dm"]
SEC_C = ["Dm", "Dm", "Gm", "Gm", "C", "C", "Am", "Am", "Dm", "Dm", "Gm", "Gm", "Am", "Am", "Dm", "Dm"]
PROG = SEC_A + SEC_B + SEC_A + SEC_C

MEL_A = [
    [[0, 74, 2], [2, 77, 1], [3, 76, 1], [4, 74, 2], [6, 69, 2]],
    [[0, 74, 3], [3, 76, 1], [4, 77, 4]],
    [[0, 76, 2], [2, 72, 1], [3, 74, 1], [4, 76, 2], [6, 79, 2]],
    [[0, 77, 3], [3, 76, 1], [4, 72, 4]],
    [[0, 74, 2], [2, 70, 1], [3, 74, 1], [4, 79, 2], [6, 77, 2]],
    [[0, 74, 3], [3, 70, 1], [4, 67, 4]],
    [[0, 69, 2], [2, 74, 1], [3, 77, 1], [4, 81, 2], [6, 77, 2]],
    [[0, 74, 6]],
]
MEL_A2 = MEL_A[:7] + [[[0, 74, 2], [2, 76, 2], [4, 77, 2], [6, 81, 2]]]
MEL_B = [
    [[0, 77, 2], [2, 81, 2], [4, 84, 3], [7, 81, 1]], [[0, 81, 4], [4, 77, 4]],
    [[0, 79, 2], [2, 76, 2], [4, 72, 2], [6, 76, 2]], [[0, 79, 4], [4, 76, 4]],
    [[0, 74, 2], [2, 79, 2], [4, 82, 3], [7, 79, 1]], [[0, 79, 4], [4, 74, 4]],
    [[0, 76, 2], [2, 81, 2], [4, 84, 2], [6, 81, 2]], [[0, 81, 6]],
    [[0, 77, 2], [2, 81, 2], [4, 84, 2], [6, 81, 2]], [[0, 79, 2], [2, 84, 2], [4, 79, 2], [6, 76, 2]],
    [[0, 82, 2], [2, 79, 2], [4, 74, 2], [6, 79, 2]], [[0, 82, 4], [4, 74, 4]],
    [[0, 81, 2], [2, 76, 2], [4, 72, 2], [6, 76, 2]], [[0, 81, 4], [4, 69, 4]],
    [[0, 74, 2], [2, 77, 2], [4, 81, 2], [6, 86, 2]], [[0, 74, 8]],
]
MEL_C = [[74, 77], [76, 74], [74, 70], [67, 70], [72, 76], [79, 76], [69, 72], [76, 72],
         [74, 77], [81, 77], [74, 70], [79, 74], [72, 76], [81, 76], [77, 74], [74, 74]]
PICK_A = [0, 2, 3, 4, 2, 3, 4, 5]
PICK_B = [0, 3, 2, 4, 3, 5, 4, 2]


def voicing(chord):
    r, _, minor = CH[chord]
    return [r, r + 7, r + 12, r + 12 + (3 if minor else 4), r + 19, r + 24]


def triad(chord, octave_shift=0):
    r, _, minor = CH[chord]
    return [r + octave_shift, r + 7 + octave_shift, r + 12 + (3 if minor else 4) + octave_shift]


def compose():
    guitar, bass, lead, fid, pads, perc = buf(), buf(), buf(), buf(), buf(), buf()
    for bar, chord in enumerate(PROG):
        sec = bar // 16          # 0 A, 1 B, 2 A', 3 C
        within = bar % 16
        t0 = bar * BAR
        v = voicing(chord)
        rb = CH[chord][1]
        # pad: held through the bar (two bars where the chord repeats)
        if bar == 0 or PROG[bar - 1] != chord or within in (0,):
            span = 1
            while bar + span < len(PROG) and PROG[bar + span] == chord and span < 2:
                span += 1
            put(pads, pad(triad(chord, 0) + [rb + 12], span * BAR), t0, 0.0, [0.5, 0.7, 0.55, 0.9][sec])
        # guitar: arpeggio on eighths, a strum to open every four bars (not in the bridge)
        pat = PICK_A if bar % 2 == 0 else PICK_B
        for e in range(8):
            t = t0 + e * EIGHTH
            if sec == 3:
                if e % 4 == 0:
                    put(guitar, pluck(midi(v[pat[e]]), 3.0, 0.85), t, -0.35, 0.55)
                continue
            if e == 0 and within % 4 == 0:
                for k, nn in enumerate(v):
                    put(guitar, pluck(midi(nn), 2.8, 1.0), t + k * 0.017, -0.35, 0.5 - 0.03 * k)
            else:
                put(guitar, pluck(midi(v[pat[e]]), 2.4, 0.95), t + rng.normal(0, 0.003), -0.35, 0.48 if e % 2 == 0 else 0.38)
        # bass: root on 1 and 3, a passing fifth before bar changes
        if sec != 3:
            put(bass, bass_note(midi(rb)), t0, 0.0, 0.8)
            put(bass, bass_note(midi(rb)), t0 + 2 * BEAT, 0.0, 0.62)
            if sec in (1, 2):
                put(bass, bass_note(midi(rb + 7)), t0 + 3 * BEAT, 0.0, 0.45)
        else:
            put(bass, bass_note(midi(rb), 2.4), t0, 0.0, 0.6)
        # lead and fiddle
        if sec == 0:
            mel = (MEL_A if within < 8 else MEL_A2)[within % 8]
            for s, m, d in mel:
                put(lead, flute(midi(m), d * EIGHTH * 0.96), t0 + s * EIGHTH, 0.25, 0.9 if within < 8 else 1.0)
        elif sec == 1:
            for s, m, d in MEL_B[within]:
                put(lead, flute(midi(m), d * EIGHTH * 0.97), t0 + s * EIGHTH, 0.25, 1.0)
            put(fid, fiddle(midi(v[1] + 12), BAR * 0.98, 0.8), t0, -0.25, 0.55)
        elif sec == 2:
            mel = (MEL_A if within < 8 else MEL_A2)[within % 8]
            for s, m, d in mel:
                put(lead, flute(midi(m + 12 if m < 76 else m), d * EIGHTH * 0.96), t0 + s * EIGHTH, 0.3, 0.7)
                put(fid, fiddle(midi(m - 12 if m > 70 else m), d * EIGHTH * 0.98, 1.0), t0 + s * EIGHTH + 0.01, -0.3, 0.8)
        else:
            for k, m in enumerate(MEL_C[within]):
                put(lead, flute(midi(m), BEAT * 2 * 0.98, 1.2), t0 + k * 2 * BEAT, 0.2, 0.85)
        # percussion
        if sec == 3:
            put(perc, bodhran(0.5, 0.6), t0, 0.0, 0.5)
            continue
        loud = [0.8, 1.0, 1.0][sec]
        put(perc, bodhran(1.0), t0, -0.1, 0.9 * loud)
        put(perc, bodhran(0.8), t0 + 2 * BEAT, -0.1, 0.8 * loud)
        put(perc, bodhran(0.6), t0 + 2.5 * BEAT, -0.1, 0.55 * loud)
        for k in (1, 3):
            put(perc, rim(), t0 + k * BEAT, 0.3, 0.35 * loud)
        for e in range(8):
            acc = 1.0 if e % 2 == 1 else 0.45
            if sec == 0 and e % 2 == 0:
                continue
            put(perc, tambourine(0.16, acc), t0 + e * EIGHTH, 0.35, 0.16 * loud)
        if sec == 2:
            for k in (1, 3):
                put(perc, clap(), t0 + k * BEAT, 0.0, 0.3)
        # fill into the next section
        if within == 15:
            for e in range(4, 8):
                put(perc, bodhran(0.7, 0.25), t0 + e * EIGHTH, -0.1, 0.6)
    return guitar, bass, lead, fid, pads, perc


def fold(b):
    """Wrap the part that rings past the end back onto the start, so the loop has no seam."""
    out = b[:LEN].copy()
    over = b[LEN:LEN + TAIL]
    out[:len(over)] += over
    return out


def master(stems):
    guitar, bass, lead, fid, pads, perc = [fold(s) for s in stems]
    # warm wooden body on the guitar bus
    for fc, q, g in ((210, 1.4, 1.6), (520, 1.2, 1.2)):
        sos = signal.iirpeak(fc / (SR / 2), q)
        pk = signal.sosfilt(signal.tf2sos(*sos), guitar, axis=0)
        guitar = guitar + pk * (g - 1)
    dry = guitar * 1.35 + bass * 0.5 + lead * 0.42 + fid * 0.7 + pads * 0.85 + perc * 0.6
    dry = dry + 0.45 * highpass(dry, 3200, 1)  # a little air on top
    ir = reverb_ir()
    wet = np.zeros_like(dry)
    for c in range(2):
        full = signal.fftconvolve(dry[:, c], ir[:, c])
        w = full[:LEN].copy()
        over = full[LEN:]
        w[:len(over)] += over[:LEN]
        wet[:, c] = w
    mix = dry * 0.8 + wet * 0.22
    # Level it before the soft clip so the clip only rounds off rare peaks: the 99.7th percentile sits at 0.7.
    mix *= 0.7 / np.percentile(np.abs(mix), 99.7)
    mix = np.tanh(mix)
    mix = highpass(mix, 28, 2)
    mix *= 10 ** (-2 / 20) / np.abs(mix).max()
    return mix


def main():
    out_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "audio", "music")
    os.makedirs(out_dir, exist_ok=True)
    stems = compose()
    mix = master(stems)
    pcm = (mix * 32767).astype("<i2")
    wav = os.path.join(out_dir, "tavern_theme.wav")
    import wave
    with wave.open(wav, "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    ogg = os.path.join(out_dir, "tavern_theme.ogg")
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", wav, "-c:a", "libvorbis", "-q:a", "4", ogg], check=True)
    os.remove(wav)
    print("wrote", ogg, "%.1f s" % (LEN / SR), "rms %.3f" % float(np.sqrt((mix ** 2).mean())))


if __name__ == "__main__":
    sys.exit(main())
