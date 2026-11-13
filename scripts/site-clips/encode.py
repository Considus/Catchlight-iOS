#!/usr/bin/env python3
"""Turn one raw simulator recording and its tap log into the site's clip files.

    encode.py RAW.mov TAPS.json OUT_DIR NAME APPEARANCE [--draft]

Writes OUT_DIR/NAME-APPEARANCE.mp4 (H.264, 600x1304, 30 fps, at most 200 KB), a WebP still of the
final held frame without the tap dots (at most 30 KB) and a contact sheet. The tap dots are drawn
here, from the flow's logged coordinates and times: the app and the recording stay untouched.
"""
import json, subprocess, sys, os, tempfile, math

W, H, FPS = 600, 1304, 30
MAX_MP4, MAX_WEBP = 200_000, 30_000
LEAD = 0.8            # seconds of still Dailies before the first tap
STILL_THRESHOLD = 0.06  # mean 0-255 difference between frames that counts as movement (a still screen reads 0.03 or less)

# Tap dot (Art Director, 13 Nov 2026). Sizes in points; the screen is 402 pt wide.
DOT = {"daylight": ("0B0E2A", 0.32), "night": ("F6F7FF", 0.38)}
DOT_PT, DOT_FROM_PT, PRESS_S, HOLD_S, FADE_S = 36.0, 44.0, 0.12, 0.15, 0.20
RING_FROM_PT, RING_TO_PT, RING_S, RING_STROKE_PT, RING_OPACITY = 36.0, 72.0, 0.40, 2.0, 0.5


def run(cmd, **kw):
    return subprocess.run(cmd, check=True, capture_output=True, **kw)


def duration(path):
    out = run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", path])
    return float(out.stdout)


def frame_diffs(raw, tmp):
    """The recording at a steady 30 fps, and the mean 0-255 change from each frame to the last."""
    cfr = os.path.join(tmp, "cfr.mov")
    run(["ffmpeg", "-y", "-i", raw, "-vf", f"fps={FPS}", "-an", "-c:v", "libx264", "-crf", "12", cfr])
    gw, gh = 48, 104
    out = run(["ffmpeg", "-i", cfr, "-vf", f"scale={gw}:{gh},format=gray", "-f", "rawvideo", "-"]).stdout
    size = gw * gh
    diffs = [0.0]
    for i in range(1, len(out) // size):
        a, b = out[(i - 1) * size:i * size], out[i * size:(i + 1) * size]
        diffs.append(sum(abs(x - y) for x, y in zip(a, b)) / size)
    return cfr, diffs


def reactions(diffs, taps):
    """The video time of each tap, found where the screen first reacts to it.

    The flow's log gives the order and a rough time (it is written a little before the touch is
    delivered); the screen gives the exact one. The first tap is the first movement in the
    recording, which opens on a still Dailies. Each later tap is the first movement after its
    logged time, the flow having waited for the last animation to settle.
    """
    first = next((i for i, d in enumerate(diffs) if d > STILL_THRESHOLD), None)
    if first is None:
        raise SystemExit("no movement found in the recording: the flow did not run on screen")
    times = [first / FPS]
    for tap in taps[1:]:
        est = times[0] + (tap["t"] - taps[0]["t"]) - 0.1
        i = next((j for j in range(max(int(est * FPS), 0), len(diffs)) if diffs[j] > STILL_THRESHOLD), None)
        if i is None:
            raise SystemExit("a tap left no movement in the recording")
        times.append(i / FPS)
    return times


def dot_source(cx, cy, k, colour, fill, start):
    """An ffmpeg filter chain drawing one tap dot centred on a 180 px square, then placed."""
    r, g, b = (int(colour[i:i + 2], 16) for i in (0, 2, 4))
    c = 90.0
    u = f"clip(T/{PRESS_S},0,1)"
    eo = f"(1-pow(1-{u},2))"
    dot_r = f"({DOT_PT / 2}*({DOT_FROM_PT / DOT_PT}-({DOT_FROM_PT / DOT_PT}-1)*{eo})*{k})"
    t2 = f"(T-{PRESS_S})"
    fade = f"(1-clip(({t2}-{HOLD_S})/{FADE_S},0,1))"
    dist = f"hypot(X-{c},Y-{c})"
    dot_a = f"{fill}*{eo}*{fade}*clip({dot_r}+0.5-{dist},0,1)"
    v = f"clip({t2}/{RING_S},0,1)"
    ring_r = f"(({RING_FROM_PT / 2}+({RING_TO_PT - RING_FROM_PT}/2)*(1-pow(1-{v},2)))*{k})"
    ring_a = (f"if(gte({t2},0),{RING_OPACITY}*(1-{v})*clip({RING_STROKE_PT * k / 2}+0.5-abs({dist}-{ring_r}),0,1),0)")
    alpha = f"255*max({dot_a},{ring_a})"
    total = PRESS_S + RING_S + 0.05
    return (f"color=c=black:s=180x180:r={FPS}:d={total},format=gbrap,"
            f"geq=r={r}:g={g}:b={b}:a='{alpha}',setpts=PTS+{start:.3f}/TB")


def encode(raw, taps_json, out_dir, name, appearance, draft):
    taps = json.load(open(taps_json))
    colour, fill = DOT[appearance]
    with tempfile.TemporaryDirectory() as tmp:
        cfr, diffs = frame_diffs(raw, tmp)
        times = reactions(diffs, taps["taps"])
        v1 = times[0]
        start = max(0.0, v1 - LEAD)
        length = (times[-1] - start) + (taps["end"] - taps["taps"][-1]["t"])
        total = duration(cfr)
        length = min(length, total - start)
        k = W / taps["screenWidth"]
        label = "-DRAFT" if draft else ""
        base = os.path.join(out_dir, f"{name}-{appearance}{label}")
        chains, inputs, last = [], [], "[bg]"
        chains.append(f"[0:v]scale={W}:{H}:flags=lanczos,setsar=1[bg]")
        for i, tap in enumerate(taps["taps"]):
            at = (times[i] - start) - PRESS_S
            src = dot_source(tap["x"], tap["y"], k, colour, fill, max(at, 0))
            chains.append(f"{src}[d{i}]")
            x, y = round(tap["x"] * k - 90), round(tap["y"] * k - 90)
            chains.append(f"{last}[d{i}]overlay=x={x}:y={y}:eof_action=pass:format=auto[o{i}]")
            last = f"[o{i}]"
        graph = ";".join(chains)
        mp4 = base + ".mp4"
        size = None
        for crf in range(20, 40):
            run(["ffmpeg", "-y", "-ss", f"{start:.3f}", "-t", f"{length:.3f}", "-i", cfr,
                 "-filter_complex", graph, "-map", last, "-r", str(FPS), "-an",
                 "-c:v", "libx264", "-preset", "veryslow", "-crf", str(crf), "-pix_fmt", "yuv420p",
                 "-movflags", "+faststart", mp4])
            size = os.path.getsize(mp4)
            if size <= MAX_MP4:
                break
        else:
            raise SystemExit(f"{mp4}: still {size} bytes at crf 39")
        # Poster: the final held frame, without a dot.
        png = os.path.join(tmp, "poster.png")
        run(["ffmpeg", "-y", "-ss", f"{start + length - 0.15:.3f}", "-i", cfr, "-frames:v", "1",
             "-vf", f"scale={W}:{H}:flags=lanczos", png])
        webp = base + ".webp"
        for q in range(90, 10, -5):
            run(["cwebp", "-quiet", "-q", str(q), "-m", "6", png, "-o", webp])
            if os.path.getsize(webp) <= MAX_WEBP:
                break
        else:
            raise SystemExit(f"{webp}: over {MAX_WEBP} bytes at q 15")
        # Contact sheet: eight frames, for judging pacing and the dot.
        sheet = base + "-contact.png"
        run(["ffmpeg", "-y", "-i", mp4, "-vf", f"fps=8/{length:.3f},scale=250:-1,tile=8x1", "-frames:v", "1", sheet])
        return {"file": os.path.basename(mp4), "seconds": round(duration(mp4), 2), "bytes": size, "crf": crf,
                "poster": os.path.basename(webp), "poster_bytes": os.path.getsize(webp), "poster_q": q,
                "tap_times_s": [round(t - start, 2) for t in times], "taps": len(taps["taps"])}


if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if a != "--draft"]
    raw, taps_json, out_dir, name, appearance = args
    print(json.dumps(encode(raw, taps_json, out_dir, name, appearance, "--draft" in sys.argv)))
