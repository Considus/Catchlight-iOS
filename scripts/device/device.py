#!/usr/bin/env python3
"""Build Catchlight onto the owner's iPhone, and read its diagnostics back off it.

    python3 scripts/device/device.py status
    python3 scripts/device/device.py install [--ref origin/main] [--launch]
    python3 scripts/device/device.py logs [--crashes] [--out DIR]

`install` builds a clean Debug copy of one git ref in a throwaway worktree, so the
shared checkout is never touched and the git-SHA build stamp is always applied (an
incremental build leaves it at "1"). It installs that build and then reads the
version back off the phone: the run fails unless the phone reports the commit that
was built.

`logs` copies the diagnostics log out of the app's container and writes it as the
same readable text the in-app Export produces. `--crashes` adds any Catchlight
crash reports. Other apps' crash reports are copied to a temporary folder only to
be filtered out, and are deleted before the command returns.

Needs Xcode 26+ (xcodebuild, devicectl), xcodegen and git. Standard library only.
Every device and build call has a hard deadline, and each leg prints its exit code.
"""

import argparse
import datetime as dt
import fcntl
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

BUNDLE_ID = "com.considus.catchlight"
SCHEME = "Catchlight"
# The log's own path inside the app container (CatchlightCore DiagnosticsLog).
DIAG_PATH = "Library/Application Support/catchlight-diagnostics.json"
BUILD_ROOT = os.path.expanduser("~/CatchlightBuild")
# Foundation's JSONEncoder writes a Date as seconds since this reference date.
APPLE_EPOCH = dt.datetime(2001, 1, 1, tzinfo=dt.timezone.utc)

# Deadlines, in seconds. A device call that hangs is a dropped connection, not slow
# work; a clean device build of the app and its packages takes several minutes.
DEVICE_TIMEOUT = 120
CRASH_COPY_TIMEOUT = 300
BUILD_TIMEOUT = 1800
GIT_TIMEOUT = 120


class Failure(Exception):
    """A step that failed, with a message that says what to do about it."""


def run(cmd, timeout, cwd=None, label=None):
    """Run a command, print its exit code, and return its stdout. Raise on failure."""
    name = label or os.path.basename(cmd[0])
    try:
        proc = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, timeout=timeout)
    except FileNotFoundError:
        raise Failure(f"{cmd[0]} is not installed or not on PATH")
    except subprocess.TimeoutExpired:
        print(f"[{name}] exit=timeout after {timeout}s")
        raise Failure(f"{name} did not finish within {timeout}s")
    print(f"[{name}] exit={proc.returncode}")
    if proc.returncode != 0:
        # xcodebuild writes compile errors to stdout, so show the end of both streams.
        tail = []
        for stream in (proc.stdout, proc.stderr):
            lines = (stream or "").strip().splitlines()[-15:]
            if lines:
                tail.append("\n".join(lines))
        raise Failure(f"{name} failed (exit {proc.returncode}):\n" + "\n---\n".join(tail))
    return proc.stdout


def devicectl_json(args, timeout=DEVICE_TIMEOUT, label=None):
    """Run a devicectl command with --json-output and return the parsed result."""
    with tempfile.TemporaryDirectory() as tmp:
        out = os.path.join(tmp, "out.json")
        run(["xcrun", "devicectl", *args, "--json-output", out], timeout, label=label)
        with open(out) as f:
            return json.load(f)["result"]


# ---- pure helpers (unit-tested in test_device.py) -------------------------

def choose_device(devices, wanted=None):
    """Pick the iPhone to use from `devicectl list devices` results.

    `wanted` matches a device's identifier or UDID, or part of its name. Without it, the single
    paired iPhone is used, and anything else is an error rather than a guess.
    """
    phones = [d for d in devices
              if d.get("hardwareProperties", {}).get("platform") == "iOS"
              and d.get("connectionProperties", {}).get("pairingState") == "paired"]
    if wanted:
        w = wanted.lower()
        # An identifier or UDID must match whole; a name may match in part ("iPhone 17").
        hits = [d for d in phones
                if w in (d.get("identifier", "").lower(),
                         d.get("hardwareProperties", {}).get("udid", "").lower())
                or w in d.get("deviceProperties", {}).get("name", "").lower()]
        if len(hits) != 1:
            raise Failure(f"no single paired iOS device matches {wanted!r}")
        return hits[0]
    if not phones:
        raise Failure("no paired iPhone found: connect it by cable or put it on the same Wi-Fi, unlocked")
    if len(phones) > 1:
        names = ", ".join(d["deviceProperties"]["name"] for d in phones)
        raise Failure(f"more than one paired iPhone ({names}): pass --device")
    return phones[0]


def entry_line(entry):
    """One diagnostics entry as the in-app Export writes it, in local time."""
    when = (APPLE_EPOCH + dt.timedelta(seconds=float(entry["timestamp"]))).astimezone()
    return f"{when:%Y-%m-%d %H:%M:%S}  [{entry['category']}]  {entry['message']}"


def diagnostics_text(entries):
    """The whole log as text, oldest first, the same order as the in-app Export."""
    ordered = sorted(entries, key=lambda e: float(e["timestamp"]))
    return "\n".join(entry_line(e) for e in ordered) + ("\n" if ordered else "")


CRASH_NAME = re.compile(r"(^|[_-])catchlight", re.IGNORECASE)


def catchlight_crashes(paths):
    """The crash reports (relative paths) that belong to the app or its extensions.

    A report is named after its process, sometimes with a prefix such as
    ExcUserFault_, and older ones sit in a Retired/ subfolder.
    """
    return sorted(p for p in paths
                  if p.endswith(".ips") and CRASH_NAME.search(os.path.basename(p)))


# ---- commands -------------------------------------------------------------

def find_device(wanted):
    result = devicectl_json(["list", "devices"], label="devicectl list devices")
    device = choose_device(result.get("devices", []), wanted)
    name = device["deviceProperties"]["name"]
    tunnel = device.get("connectionProperties", {}).get("tunnelState")
    print(f"device: {name} ({device['identifier']}), connection {tunnel}")
    return device


def installed_build(device):
    """The app's (version, build stamp) on the phone, or None when it is not installed."""
    result = devicectl_json(["device", "info", "apps", "--device", device["identifier"],
                             "--bundle-id", BUNDLE_ID], label="devicectl info apps")
    apps = [a for a in result.get("apps", []) if a.get("bundleIdentifier") == BUNDLE_ID]
    if not apps:
        return None
    return apps[0].get("version"), apps[0].get("bundleVersion")


def repo_root():
    here = os.path.dirname(os.path.abspath(__file__))
    out = run(["git", "-C", here, "rev-parse", "--show-toplevel"], GIT_TIMEOUT, label="git toplevel")
    return out.strip()


def cmd_status(args):
    device = find_device(args.device)
    build = installed_build(device)
    root = repo_root()
    run(["git", "-C", root, "fetch", "--quiet", "origin", "main"], GIT_TIMEOUT, label="git fetch")
    main = run(["git", "-C", root, "rev-parse", "--short", "origin/main"], GIT_TIMEOUT,
               label="git rev-parse").strip()
    if build is None:
        print(f"Catchlight is not installed on {device['deviceProperties']['name']}.")
        return 1
    version, stamp = build
    print(f"on the phone: {version} ({stamp})  ·  origin/main: {main}")
    if stamp == main:
        print("The phone has the latest main.")
    else:
        try:
            behind = run(["git", "-C", root, "rev-list", "--count", f"{stamp}..origin/main"],
                         GIT_TIMEOUT, label="git rev-list")
            if behind.strip() == "0":
                print("The phone has everything on origin/main: it is a branch build ahead of it.")
            else:
                print(f"The phone is {behind.strip()} commits behind origin/main.")
        except Failure:
            print(f"The phone's build stamp {stamp!r} is not a commit this repo knows "
                  "(an incremental, dirty or archive build): install a fresh one.")
    return 0


def cmd_install(args):
    os.makedirs(BUILD_ROOT, exist_ok=True)
    # One install at a time: sessions run side by side, and a second build would
    # race the first for the phone and for Xcode's package cache.
    lock = open(os.path.join(BUILD_ROOT, "device-install.lock"), "w")
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        raise Failure("another device install is running; wait for it to finish and run this again")
    try:
        return install_locked(args)
    finally:
        fcntl.flock(lock, fcntl.LOCK_UN)
        lock.close()


def install_locked(args):
    device = find_device(args.device)
    udid = device["hardwareProperties"]["udid"]
    root = repo_root()
    run(["git", "-C", root, "fetch", "--quiet", "origin"], GIT_TIMEOUT, label="git fetch")
    # ^{commit} so an annotated tag resolves to the commit the stamp script will see.
    sha = run(["git", "-C", root, "rev-parse", "--short", f"{args.ref}^{{commit}}"], GIT_TIMEOUT,
              label="git rev-parse").strip()
    print(f"building {args.ref} at {sha}")

    run(["git", "-C", root, "worktree", "prune"], GIT_TIMEOUT, label="git worktree prune")
    work = tempfile.mkdtemp(prefix=f"device-{sha}-", dir=BUILD_ROOT)
    src = os.path.join(work, "src")
    # A fresh derived-data folder per run is what applies the git-SHA stamp
    # (an incremental build leaves it at "1").
    derived = os.path.join(work, "dd")
    try:
        run(["git", "-C", root, "worktree", "add", "--detach", src, sha], GIT_TIMEOUT,
            label="git worktree add")
        run(["xcodegen", "generate"], DEVICE_TIMEOUT, cwd=src, label="xcodegen")
        # The stamp adds "+dirty" when the tree has changes, and xcodegen rewrites
        # tracked plists: stop here, with the reason, rather than fail the stamp
        # check after a full build.
        changed = run(["git", "-C", src, "status", "--porcelain"], GIT_TIMEOUT, label="git status")
        if changed.strip():
            raise Failure("xcodegen changed tracked files, so the build would be stamped "
                          "+dirty; commit the regenerated files on the branch first:\n" + changed.strip())
        run(["xcodebuild", "-scheme", SCHEME, "-configuration", "Debug",
             "-destination", f"platform=iOS,id={udid}", "-derivedDataPath", derived,
             "-allowProvisioningUpdates", "build"], BUILD_TIMEOUT, cwd=src, label="xcodebuild")
        app = os.path.join(derived, "Build", "Products", "Debug-iphoneos", "Catchlight.app")
        if not os.path.isdir(app):
            raise Failure(f"the build reported success but {app} is missing")
        run(["xcrun", "devicectl", "device", "install", "app", "--device", device["identifier"], app],
            DEVICE_TIMEOUT, label="devicectl install")
    finally:
        cleanup_worktree(root, src, work)

    build = installed_build(device)
    if build is None or build[1] != sha:
        raise Failure(f"the phone reports build {build[1] if build else 'none'}, not {sha}: "
                      "the install did not take")
    print(f"Build {sha} ({args.ref}) is on {device['deviceProperties']['name']}.")
    if args.launch:
        run(["xcrun", "devicectl", "device", "process", "launch", "--device", device["identifier"],
             "--terminate-existing", BUNDLE_ID], DEVICE_TIMEOUT, label="devicectl launch")
        print("Relaunched, so the new build is the one running.")
    else:
        print("If Catchlight was open, swipe it away and reopen it to run the new build.")
    return 0


def cleanup_worktree(root, src, work):
    """Remove the build's worktree and folder without hiding an earlier failure."""
    try:
        run(["git", "-C", root, "worktree", "remove", "--force", src], GIT_TIMEOUT,
            label="git worktree remove")
    except Failure as exc:
        print(f"[cleanup] {exc}; removing the folder and pruning instead")
    shutil.rmtree(work, ignore_errors=True)
    try:
        run(["git", "-C", root, "worktree", "prune"], GIT_TIMEOUT, label="git worktree prune")
    except Failure as exc:
        print(f"[cleanup] {exc}")


def cmd_logs(args):
    device = find_device(args.device)
    stamp = dt.datetime.now().strftime("%Y-%m-%d-%H%M%S")
    out_dir = args.out or os.path.join(BUILD_ROOT, "device-logs", stamp)
    os.makedirs(out_dir, exist_ok=True)

    raw = os.path.join(out_dir, "catchlight-diagnostics.json")
    run(["xcrun", "devicectl", "device", "copy", "from", "--device", device["identifier"],
         "--domain-type", "appDataContainer", "--domain-identifier", BUNDLE_ID,
         "--source", DIAG_PATH, "--destination", raw], DEVICE_TIMEOUT, label="devicectl copy log")
    with open(raw) as f:
        entries = json.load(f)
    text_path = os.path.join(out_dir, "catchlight-diagnostics.txt")
    with open(text_path, "w") as f:
        f.write(diagnostics_text(entries))
    build = installed_build(device)
    print(f"{len(entries)} log entries from build {build[1] if build else 'unknown'} -> {text_path}")

    if args.crashes:
        # devicectl copies every app's crash reports; keep Catchlight's, delete the rest.
        with tempfile.TemporaryDirectory() as tmp:
            run(["xcrun", "devicectl", "device", "copy", "from", "--device", device["identifier"],
                 "--domain-type", "systemCrashLogs", "--source", "/", "--destination", tmp],
                CRASH_COPY_TIMEOUT, label="devicectl copy crashes")
            found = [os.path.relpath(os.path.join(d, f), tmp)
                     for d, _, files in os.walk(tmp) for f in files]
            mine = catchlight_crashes(found)
            for rel in mine:
                shutil.copy2(os.path.join(tmp, rel), os.path.join(out_dir, os.path.basename(rel)))
        print(f"{len(mine)} Catchlight crash report(s)" + (": " + ", ".join(mine) if mine else ""))

    tail = diagnostics_text(entries).splitlines()[-args.tail:]
    if tail:
        print(f"--- last {len(tail)} entries ---")
        print("\n".join(tail))
    return 0


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    common = argparse.ArgumentParser(add_help=False)
    common.add_argument("--device", help="identifier, UDID or name, when more than one iPhone is paired")
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("status", parents=[common], help="which build is on the phone, against origin/main")
    p_install = sub.add_parser("install", parents=[common], help="clean-build a ref and install it on the phone")
    p_install.add_argument("--ref", default="origin/main", help="git ref to build (default origin/main)")
    p_install.add_argument("--launch", action="store_true", help="relaunch the app on the new build")
    p_logs = sub.add_parser("logs", parents=[common], help="copy the diagnostics log (and crashes) off the phone")
    p_logs.add_argument("--crashes", action="store_true", help="also copy Catchlight crash reports")
    p_logs.add_argument("--out", help="folder to write into (default ~/CatchlightBuild/device-logs/<time>)")
    p_logs.add_argument("--tail", type=int, default=20, help="how many recent entries to print")
    args = parser.parse_args(argv)
    try:
        return {"status": cmd_status, "install": cmd_install, "logs": cmd_logs}[args.command](args)
    except Failure as exc:
        print(f"FAILED: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
