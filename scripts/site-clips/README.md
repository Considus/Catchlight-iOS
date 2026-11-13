# Site clips

Records the three phone clips on catchlight.app from the real app, so they stay identical to it:
**Shaping a Take**, **Setting a reminder** and **Sequence**, in the Cobalt Scene, in Daylight and
Night. Nothing is redrawn.

```bash
scripts/site-clips/record.sh --draft          # six clips, labelled DRAFT
scripts/site-clips/record.sh                  # the final six
scripts/site-clips/record.sh --clip sequence --appearance night   # one clip
```

Files go to `~/Library/Caches/considus/handover/<date>_site-clips[-draft]/`: per clip and look an
MP4 (H.264, 600x1304, 30 fps, at most 200 KB), a WebP still of the final held frame without the
dot (at most 30 KB) and a contact sheet, with `RECORDED.txt` naming the app commit. Needs
`xcodegen`, `ffmpeg` with libx264, and `cwebp`.

## How it works

- **Demo Takes:** `--uitesting-demo` (with `--uitesting`) seeds the site's drawn-phone Takes,
  `Catchlight/App/DemoTakes.swift`. Debug only: the file and the hook are inside `#if DEBUG`, so a
  Release binary holds neither (checked with `strings`).
- **Flows:** `Tests/CatchlightSiteClips/SiteClipFlows.swift`, run from the `CatchlightSiteClips`
  scheme. It is not in the `Catchlight` scheme, so CI and the merge queue never run it. Each flow runs
  twice: a scouting pass finds where each tap lands (and fails if a step can't be reached), then a
  recorded pass relaunches and taps those points on a schedule, so the pacing is the flow's, not the
  runner's lookups.
- **Recording:** `simctl io recordVideo` on "Claude iPhone 17" (created if missing, never deleted,
  shut down at the end) with the status bar fixed at 9:41. The flow says when the app is up, the
  script starts the recorder, then the flow starts.
- **Tap dot:** drawn by `encode.py` at encode time from the logged tap places. Each tap's time is
  where the screen first reacts to it. Size, colour and pulse are the constants at the top of
  `encode.py` (the Art Director owns them). The app and the recording are untouched.
- **Loop and timing:** the last 250 ms cross-fade into the first frame. Shaping a Take waits for a minute that is a multiple of five, so its reminder reads like 07:40. A final run (no `--draft`) refuses uncommitted changes, so `RECORDED.txt` names a clean commit.
- **Size:** `encode.py` raises the CRF until the MP4 is within 200 KB, and lowers the WebP quality
  until it is within 30 KB.

## Changing a flow

Edit the `Step` lists in `SiteClipFlows.swift`: each step is where to tap and the beat (seconds
from the last tap). A sheet or menu makes the runner wait before the next tap, so a clip can run
longer than its beats add up to.

## Not shown

The date on screen is the day of recording, and a reminder's words ("Tomorrow", a date) follow it:
the app reads the system clock, which a simulator cannot change. No notification is shown arriving.
