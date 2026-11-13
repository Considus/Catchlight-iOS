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
LEAD = 1.9            # seconds before the first press: 1.5 s of still screen, then the dot's 0.4 s lead
FADE = 0.25           # seconds the last frames cross-fade into the first, so the loop doesn't snap
STILL_THRESHOLD = 0.06  # mean 0-255 difference between frames that counts as movement (a still screen reads 0.03 or less)

# Tap dot (Art Director, 13 Nov 2026). Sizes in points; the screen is 402 pt wide.
DOT = {"daylight": ("0B0E2A", 0.32), "night": ("F6F7FF", 0.38)}
# Slow pace (13 Nov): the dot appears 0.4 s before the press, shrinks in over 0.18 s, holds, and
# at touch-down the ring starts and the dot fades over 0.25 s.
DOT_PT, DOT_FROM_PT, IN_S, LEAD_S, FADE_S = 36.0, 44.0, 0.18, 0.40, 0.25
RING_FROM_PT, RING_TO_PT, RING_S, RING_STROKE_PT, RING_OPACITY = 36.0, 72.0, 0.50, 2.0, 0.5


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


def dot_source(cx, cy, k, colour, fill, start, hold=0.0):
    """An ffmpeg filter chain drawing one tap dot centred on a 180 px square, then placed.
    Its clock T starts when the dot appears; the press lands at T = LEAD_S."""
    r, g, b = (int(colour[i:i + 2], 16) for i in (0, 2, 4))
    c = 90.0
    u = f"clip(T/{IN_S},0,1)"
    eo = f"(1-pow(1-{u},2))"
    dot_r = f"({DOT_PT / 2}*({DOT_FROM_PT / DOT_PT}-({DOT_FROM_PT / DOT_PT}-1)*{eo})*{k})"
    t2 = f"(T-{LEAD_S}-{hold:.3f})"      # a drag holds the dot until its release
    fade = f"(1-clip({t2}/{FADE_S},0,1))"
    dist = f"hypot(X-{c},Y-{c})"
    dot_a = f"{fill}*{eo}*{fade}*clip({dot_r}+0.5-{dist},0,1)"
    v = f"clip({t2}/{RING_S},0,1)"
    ring_r = f"(({RING_FROM_PT / 2}+({RING_TO_PT - RING_FROM_PT}/2)*(1-pow(1-{v},2)))*{k})"
    ring_a = (f"if(gte({t2},0),{RING_OPACITY}*(1-{v})*clip({RING_STROKE_PT * k / 2}+0.5-abs({dist}-{ring_r}),0,1),0)")
    alpha = f"255*max({dot_a},{ring_a})"
    total = LEAD_S + hold + RING_S + 0.05
    return (f"color=c=black:s=180x180:r={FPS}:d={total},format=gbrap,"
            f"geq=r={r}:g={g}:b={b}:a='{alpha}',setpts=PTS+{start:.3f}/TB")


def _unused_raw_window_timing(raw, first_reaction_s, second_reaction_s):
    """For the recording as the simulator wrote it (variable frame rate): the real timestamp of
    the first and the last frame that changed between two moments, and how many frames changed."""
    pts = [float(x.strip(b",")) for x in run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries",
                                  "frame=pts_time", "-of", "csv=p=0", raw]).stdout.split()]
    gw, gh = 48, 104
    out = run(["ffmpeg", "-i", raw, "-vf", f"scale={gw}:{gh},format=gray", "-fps_mode", "passthrough",
               "-f", "rawvideo", "-"]).stdout
    size = gw * gh
    n = min(len(pts), len(out) // size)
    changed = []
    for i in range(1, n):
        d = sum(abs(x - y) for x, y in zip(out[(i - 1) * size:i * size], out[i * size:(i + 1) * size])) / size
        if d > STILL_THRESHOLD:
            changed.append(pts[i])
    return pts, changed


def gray_frames(path):
    """Every frame of a video as it is (no resampling), small and grey, with its own time."""
    pts = [float(x.strip(b",")) for x in run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries",
                                              "frame=pts_time", "-of", "csv=p=0", path]).stdout.split()]
    gw, gh = 48, 104
    out = run(["ffmpeg", "-i", path, "-vf", f"scale={gw}:{gh},format=gray", "-fps_mode", "passthrough",
               "-f", "rawvideo", "-"]).stdout
    size = gw * gh
    n = min(len(pts), len(out) // size)
    return [(pts[i], out[i * size:(i + 1) * size]) for i in range(n)]


def distance(a, b):
    return sum(abs(x - y) for x, y in zip(a, b)) / len(a)


def settle_timing(frames, a, b, eps=0.35):
    """How long a screen change takes, independent of the frame rate. Between times a and b (a
    tap, and the next tap): the change starts at the first frame that differs from the frame at a,
    and is settled from the first frame after which every frame is within eps of the frame at b."""
    inside = [(t, f) for t, f in frames if a <= t <= b]
    if len(inside) < 3:
        return None
    first, last = inside[0][1], inside[-1][1]
    began = next((t for t, f in inside if distance(f, first) > eps), None)
    settled = next((inside[i][0] for i in range(len(inside))
                    if all(distance(f, last) <= eps for _, f in inside[i:])), None)
    if began is None or settled is None:
        return None
    return {"starts_s": round(began, 3), "settled_s": round(settled, 3), "ms": round((settled - began) * 1000),
            "frames_between": sum(1 for t, _ in inside if began <= t <= settled)}


def encode(raw, taps_json, out_dir, stem, appearance, fixed_crf=None, focus_tap=0):
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
        base = os.path.join(out_dir, stem)
        chains, last = [], "[bg]"
        fade_at = length - FADE
        p = f"clip((T-{fade_at:.3f})/{FADE},0,1)"
        chains.append(f"[0:v]scale={W}:{H}:flags=lanczos,setsar=1,split[a][b]")
        chains.append("[b]select=eq(n\\,0),loop=loop=-1:size=1:start=0,setpts=N/FRAME_RATE/TB[first]")
        chains.append(f"[a][first]blend=all_expr='A*(1-{p})+B*{p}':shortest=1,setsar=1[bg]")
        plain = ";".join(chains)          # the same picture without the dots, for measuring
        for i, tap in enumerate(taps["taps"]):
            at = (times[i] - start) - LEAD_S
            src = dot_source(tap["x"], tap["y"], k, colour, fill, max(at, 0), tap.get("total", 0.0))
            chains.append(f"{src}[d{i}]")
            x, y = round(tap["x"] * k - 90), round(tap["y"] * k - 90)
            if "x1" in tap:
                # The dot follows the finger: linear from the drag's start to its end.
                down = max(at, 0) + LEAD_S
                m0, m1 = down + tap["moveStart"], down + tap["moveEnd"]
                f = f"clip((t-{m0:.3f})/{m1 - m0:.3f},0,1)"
                ox = f"{x}+{round((tap['x1'] - tap['x']) * k)}*{f}"
                oy = f"{y}+{round((tap['y1'] - tap['y']) * k)}*{f}"
                chains.append(f"{last}[d{i}]overlay=x='{ox}':y='{oy}':eof_action=pass:format=auto[o{i}]")
            else:
                chains.append(f"{last}[d{i}]overlay=x={x}:y={y}:eof_action=pass:format=auto[o{i}]")
            last = f"[o{i}]"
        graph = ";".join(chains)

        def make(path, g, out_label, crf):
            run(["ffmpeg", "-y", "-ss", f"{start:.3f}", "-t", f"{length:.3f}", "-i", cfr,
                 "-filter_complex", g, "-map", out_label, "-r", str(FPS), "-an",
                 "-c:v", "libx264", "-preset", "veryslow", "-crf", str(crf), "-pix_fmt", "yuv420p",
                 "-movflags", "+faststart", path])
            return os.path.getsize(path)

        mp4 = base + ".mp4"
        fit_crf = None
        if fixed_crf is None:
            for crf in range(20, 40):
                size = make(mp4, graph, last, crf)
                if size <= MAX_MP4:
                    break
            else:
                raise SystemExit(f"{mp4}: still {size} bytes at crf 39")
        else:
            crf = fixed_crf
            size = make(mp4, graph, last, crf)
            # What it would take to fit 200 KB, for the report only.
            probe = os.path.join(tmp, "probe.mp4")
            for c in range(crf, 45):
                if make(probe, graph, last, c) <= MAX_MP4:
                    fit_crf = c
                    break
        # Poster: the final held frame, without a dot.
        png = os.path.join(tmp, "poster.png")
        run(["ffmpeg", "-y", "-ss", f"{start + length - 0.15 - FADE:.3f}", "-i", cfr, "-frames:v", "1",
             "-vf", f"scale={W}:{H}:flags=lanczos", png])
        webp = base + ".webp"
        for q in range(90, 10, -5):
            run(["cwebp", "-quiet", "-q", str(q), "-m", "6", png, "-o", webp])
            if os.path.getsize(webp) <= MAX_WEBP:
                break
        else:
            raise SystemExit(f"{webp}: over {MAX_WEBP} bytes at q 15")
        sheet = base + "-contact.png"
        run(["ffmpeg", "-y", "-i", mp4, "-vf", f"fps=8/{length:.3f},scale=250:-1,tile=8x1", "-frames:v", "1", sheet])
        # The first tap's reaction (the Focus row opening, in Shaping a Take) on the raw
        # recording, as the simulator wrote it, and on the encoded picture (without dots).
        res = {"file": os.path.basename(mp4), "seconds": round(duration(mp4), 2), "bytes": size, "crf": crf,
               "poster": os.path.basename(webp), "poster_bytes": os.path.getsize(webp), "poster_q": q,
               "tap_times_s": [round(t - start, 2) for t in times], "taps": len(taps["taps"])}
        if fit_crf:
            res["crf_to_fit_200KB"] = fit_crf
        if len(times) > focus_tap + 1:
            a, b = times[focus_tap] - 0.05, times[focus_tap + 1] - 0.05
            res["focus_row_raw"] = settle_timing(gray_frames(raw), a, b)
            plain_mp4 = os.path.join(tmp, "plain.mp4")
            make(plain_mp4, plain, "[bg]", crf)
            res["focus_row_encoded"] = settle_timing(gray_frames(plain_mp4), a - start, b - start)
        return res


if __name__ == "__main__":
    args = sys.argv[1:]
    crf = None
    if "--crf" in args:
        i = args.index("--crf")
        crf = int(args[i + 1]); del args[i:i + 2]
    focus = 0
    if "--focus-tap" in args:
        i = args.index("--focus-tap")
        focus = int(args[i + 1]); del args[i:i + 2]
    raw, taps_json, out_dir, stem, appearance = args
    print(json.dumps(encode(raw, taps_json, out_dir, stem, appearance, crf, focus)))
