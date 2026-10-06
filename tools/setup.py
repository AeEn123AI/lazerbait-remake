#!/usr/bin/env python3
"""
One-step project setup for the Lazerbait Godot remake.

    python3 tools/setup.py /path/to/Lazerbait

1. extracts the original game's assets into ./assets   (tools/extract_assets.py)
2. downloads the Godot OpenXR Vendors plugin into ./addons (Meta/HTC/Pico passthrough, Quest support)
3. runs `godot --headless --import` if a Godot 4.6 executable is found (GODOT env var or `godot` on PATH)

Options: --skip-assets, --skip-addons, --skip-import, --godot PATH
"""
import argparse
import io
import os
import shutil
import subprocess
import sys
import urllib.request
import zipfile

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
VENDORS_VERSION = "5.1.0-stable"
VENDORS_URL = f"https://github.com/GodotVR/godot_openxr_vendors/releases/download/{VENDORS_VERSION}/godotopenxrvendorsaddon.zip"


def fetch_vendors():
    dest = os.path.join(ROOT, "addons", "godotopenxrvendors")
    if os.path.isfile(os.path.join(dest, "plugin.gdextension")):
        print(f"[setup] OpenXR vendors plugin already present ({dest})")
        return
    print(f"[setup] downloading Godot OpenXR Vendors {VENDORS_VERSION} ...")
    with urllib.request.urlopen(VENDORS_URL) as r:
        data = r.read()
    with zipfile.ZipFile(io.BytesIO(data)) as z:
        prefix = "asset/addons/godotopenxrvendors/"
        for name in z.namelist():
            if not name.startswith(prefix) or name.endswith("/"):
                continue
            target = os.path.join(dest, name[len(prefix):])
            os.makedirs(os.path.dirname(target), exist_ok=True)
            with z.open(name) as src, open(target, "wb") as dst:
                shutil.copyfileobj(src, dst)
    print(f"[setup] installed -> {dest}")


def find_godot(explicit):
    for c in [explicit, os.environ.get("GODOT"), "godot", "godot4"]:
        if c and (os.path.isfile(c) or shutil.which(c)):
            return c
    return None


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("game_dir", nargs="?", help="original Lazerbait install folder")
    ap.add_argument("--skip-assets", action="store_true")
    ap.add_argument("--skip-addons", action="store_true")
    ap.add_argument("--skip-import", action="store_true")
    ap.add_argument("--godot", help="path to the Godot 4.6 executable")
    a = ap.parse_args()

    if not a.skip_assets:
        if not a.game_dir:
            ap.error("game_dir is required (or pass --skip-assets)")
        subprocess.run([sys.executable, os.path.join(ROOT, "tools", "extract_assets.py"), a.game_dir], check=True)
    if not a.skip_addons:
        fetch_vendors()
    if not a.skip_import:
        godot = find_godot(a.godot)
        if godot:
            print(f"[setup] importing project with {godot} ...")
            subprocess.run([godot, "--headless", "--path", ROOT, "--import"], check=False)
        else:
            print("[setup] Godot not found; open the project in the Godot 4.6 editor once to import it.")
    print("[setup] done")


if __name__ == "__main__":
    main()
