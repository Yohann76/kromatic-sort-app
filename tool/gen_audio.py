"""Génère tous les sons du jeu (SFX + musique d'ambiance en boucle) de façon procédurale.

Usage : python3 tool/gen_audio.py   (depuis la racine du projet)
Dépendances : numpy (+ ffmpeg pour compresser la musique en .ogg).
"""
import subprocess
import wave
from pathlib import Path

import numpy as np

OUT = Path(__file__).resolve().parent.parent / "assets" / "audio"
SR = 44100
RNG = np.random.default_rng(7)


def t_axis(duration, sr=SR):
    return np.arange(int(duration * sr)) / sr


def env_ad(n, attack=0.005, decay=6.0, sr=SR):
    """Enveloppe attaque courte + décroissance exponentielle."""
    t = np.arange(n) / sr
    a = np.minimum(1.0, t / attack)
    return a * np.exp(-decay * t)


def save_wav(name, data, sr=SR):
    data = data / max(1e-9, np.max(np.abs(data))) * 0.85
    pcm = (data * 32767).astype(np.int16)
    with wave.open(str(OUT / name), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes(pcm.tobytes())


def bell(freq, duration, decay=5.0):
    """Note de type cloche/glockenspiel (partiels harmoniques)."""
    t = t_axis(duration)
    sig = (np.sin(2 * np.pi * freq * t)
           + 0.35 * np.sin(2 * np.pi * freq * 2.76 * t) * np.exp(-8 * t)
           + 0.2 * np.sin(2 * np.pi * freq * 5.4 * t) * np.exp(-14 * t))
    return sig * env_ad(len(t), 0.003, decay)


def place(buf, sig, start):
    i = int(start * SR)
    buf[i:i + len(sig)] += sig[: len(buf) - i]


def sweep(f0, f1, duration, decay=7.0):
    t = t_axis(duration)
    freq = np.linspace(f0, f1, len(t))
    phase = 2 * np.pi * np.cumsum(freq) / SR
    return np.sin(phase) * env_ad(len(t), 0.004, decay)


def sfx():
    save_wav("select.wav", sweep(620, 900, 0.14, 14))
    save_wav("deselect.wav", sweep(820, 560, 0.12, 16))
    save_wav("click.wav", sweep(1300, 1000, 0.05, 50))
    # erreur : petit "toc" grave et doux
    save_wav("error.wav", sweep(210, 120, 0.2, 18) * 0.9)

    # versement : série de bulles qui montent en fréquence + souffle filtré
    n = int(0.62 * SR)
    pour = np.zeros(n)
    for i in range(14):
        start = i * 0.038 + RNG.uniform(0, 0.012)
        f0 = 280 + i * 28 + RNG.uniform(-20, 20)
        place(pour, sweep(f0, f0 * 1.9, 0.07, 30) * RNG.uniform(0.5, 1.0), start)
    noise = RNG.normal(0, 1, n)
    k = np.ones(40) / 40
    noise = np.convolve(noise, k, mode="same")
    noise *= np.sin(np.linspace(0, np.pi, n)) * 0.25
    save_wav("pour.wav", pour + noise)

    # tube terminé : arpège de cloches aigu
    buf = np.zeros(int(1.0 * SR))
    for i, f in enumerate([1046.5, 1318.5, 1568.0]):
        place(buf, bell(f, 0.8, 5.0) * 0.8, i * 0.08)
    save_wav("tube_done.wav", buf)

    # victoire : arpège ascendant + accord final scintillant
    buf = np.zeros(int(2.2 * SR))
    for i, f in enumerate([523.3, 659.3, 784.0, 1046.5, 1318.5]):
        place(buf, bell(f, 1.2, 3.5), i * 0.11)
    for f in (1046.5, 1318.5, 1568.0, 2093.0):
        place(buf, bell(f, 1.5, 2.8) * 0.6, 0.62)
    save_wav("win.wav", buf)


def music():
    """Boucle ambiante de 32 s : nappes douces + notes pentatoniques avec écho."""
    sr = 22050
    dur = 32.0
    n = int(dur * sr)
    t = np.arange(n) / sr
    mix = np.zeros(n)

    chords = [  # Cmaj7, Am7, Fmaj7, G6 (fréquences en Hz)
        [130.8, 196.0, 246.9, 329.6],
        [110.0, 164.8, 196.0, 261.6],
        [87.3, 130.8, 220.0, 261.6],
        [98.0, 146.8, 196.0, 247.0],
    ]
    seg = dur / len(chords)
    for ci, chord in enumerate(chords):
        centre = (ci + 0.5) * seg
        # fenêtre en cloche circulaire -> boucle sans couture
        d = (t - centre + dur / 2) % dur - dur / 2
        win = np.exp(-0.5 * (d / (seg * 0.42)) ** 2)
        pad = np.zeros(n)
        for f in chord:
            for detune in (-0.6, 0.0, 0.7):
                pad += np.sin(2 * np.pi * (f + detune) * t) * 0.12
        mix += pad * win

    # petites notes (pentatonique de Do) répétées en motif avec écho
    scale = [523.3, 587.3, 659.3, 784.0, 880.0, 1046.5]
    notes = np.zeros(n)
    step = 1.0
    for i in range(int(dur / step)):
        if RNG.random() < 0.62:
            f = scale[RNG.integers(len(scale))]
            nt = np.sin(2 * np.pi * f * t[: int(2.5 * sr)]) * env_ad(int(2.5 * sr), 0.01, 2.6, sr)
            start = int(i * step * sr)
            idx = (np.arange(len(nt)) + start) % n  # écriture circulaire
            np.add.at(notes, idx, nt * 0.22)
    for delay, gain in ((0.375, 0.5), (0.75, 0.28), (1.125, 0.14)):
        notes += np.roll(notes, int(delay * sr)) * gain
    mix += notes

    mix = mix / np.max(np.abs(mix)) * 0.8
    pcm = (mix * 32767).astype(np.int16)
    tmp = OUT / "_music.wav"
    with wave.open(str(tmp), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes(pcm.tobytes())
    try:
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(tmp),
                        "-c:a", "libvorbis", "-q:a", "3", str(OUT / "music.ogg")], check=True)
        tmp.unlink()
    except Exception:
        tmp.rename(OUT / "music.wav")


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    sfx()
    music()
    print("OK ->", OUT)
