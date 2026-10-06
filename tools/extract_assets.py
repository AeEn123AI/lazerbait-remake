#!/usr/bin/env python3
"""
Extracts the assets this Godot remake needs from an installed copy of the original
Lazerbait (Steam app 529150, Unity 5.4) into ./assets.

Usage:
    python3 tools/extract_assets.py /path/to/Lazerbait [--out assets]

The path may point at the game folder (containing lazerbait_Data) or at lazerbait_Data.
Requires: UnityPy, Pillow, numpy (see tools/requirements.txt) and ffmpeg on PATH.
"""
import argparse
import json
import os
import re
import shutil
import subprocess
import sys

try:
    import UnityPy
    import numpy as np
    from PIL import Image
except ImportError as e:  # pragma: no cover
    sys.exit(f"Missing Python dependency ({e.name}). Run: pip install -r tools/requirements.txt")

TEXTURES = ["arrow", "greenArrow", "greenSquare", "redX", "one", "Menu", "Controls", "Gameplay",
            "star_red", "glow", "torch_tint", "shape_sphere", "Default-Particle"]
SKYBOX = ["front", "back", "left", "right", "top", "bottom"]
DERIVED = ["terrain01_normal", "Geo pattern normal"]
MESHES = {"Sphere": "sphere", "Cube": "cube", "Cylinder": "cylinder", "Quad": "quad",
          "pCube1 (2)": "ship", "Mesh": "ring", "hyperbit_sphere": "hyperbit_sphere",
          "LowPolySphere": "lowpoly_sphere"}
MUSIC = ["Allies or enemies", "Calm before the storm", "Chosen ones", "Fall back", "For glory",
         "Reflections", "The mission", "Unknown beings", "We all have secrets", "Engage"]
SFX = ["Click_Electronic_01", "Click_Electronic_03", "Click_Electronic_05", "Click_Electronic_14",
       "Click_Electronic_16", "Click_Heavy_00", "Laser_09", "impact5", "shoot1", "Slide_Electronic_01"]
AMBIENT = "SpaceSounds_loop_9"
FONTS = {"alterebro-pixel-font": "alterebro-pixel-font.ttf", "Plain Cred 1978": "plain-cred-1978.ttf"}
MOVIES = ["primarycontrols", "secondarycontrols", "gameplay"]


def log(msg):
    print(f"[extract] {msg}", flush=True)


def find_data_dir(path):
    path = os.path.abspath(os.path.expanduser(path))
    if os.path.isfile(os.path.join(path, "globalgamemanagers")):
        return path
    for name in os.listdir(path) if os.path.isdir(path) else []:
        p = os.path.join(path, name)
        if name.endswith("_Data") and os.path.isfile(os.path.join(p, "globalgamemanagers")):
            return p
    sys.exit(f"Could not find lazerbait_Data in {path}")


def srgb_encode(lin):
    lin = np.clip(lin, 0, 1)
    return np.where(lin <= 0.0031308, lin * 12.92, 1.055 * np.power(lin, 1 / 2.4) - 0.055)


def to_u8(a):
    return (np.clip(a, 0, 1) * 255 + 0.5).astype(np.uint8)


def convert_mesh(obj_text):
    """UnityPy exports with X negated; the remake uses Unity (x, y, -z) => rotate 180 deg about Y."""
    out = []
    has_normals = "\nvn " in obj_text
    for line in obj_text.splitlines():
        p = line.split()
        if not p:
            continue
        if p[0] in ("v", "vn"):
            x, y, z = map(float, p[1:4])
            out.append(f"{p[0]} {-x:.6f} {y:.6f} {-z:.6f}")
        elif p[0] == "f" and not has_normals:
            out.append("f " + " ".join("/".join(t.split("/")[:2]) for t in p[1:]))
        else:
            out.append(line)
    return "\n".join(out) + "\n"


def ffmpeg_ogg(src, dst):
    subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", src, "-c:a", "libvorbis", "-q:a", "6", dst],
                   check=True)


# ---------------------------------------------------------------- explosions

def _decode_rgba(v):
    v = v["rgba"]
    return [round((v >> s & 255) / 255, 4) for s in (0, 8, 16, 24)]


def _minmax(c):
    if not isinstance(c, dict):
        return c
    st = c.get("minMaxState")
    if st == 0:
        return c["scalar"]
    if st == 3:
        return [c["scalar"] * c["minCurve"]["m_Curve"][0]["value"], c["scalar"] * c["maxCurve"]["m_Curve"][0]["value"]]
    return c["scalar"]


def _ps_entry(tt):
    i = tt["InitialModule"]
    g = tt["ColorModule"]["gradient"]["maxGradient"]
    nc, na = g["m_NumColorKeys"], g["m_NumAlphaKeys"]
    gc = [[round(g[f"ctime{k}"] / 65535, 3)] + _decode_rgba(g[f"key{k}"])[:3] for k in range(nc)]
    ga = [[round(g[f"atime{k}"] / 65535, 3), _decode_rgba(g[f"key{k}"])[3]] for k in range(na)]
    sc = i["startColor"]["maxColor"]
    shape = tt.get("ShapeModule", {})
    return {
        "grad_c": gc, "grad_a": ga,
        "start_color": [round(sc[ch], 4) for ch in "rgba"],
        "gravity": round(_minmax(i["gravityModifier"]), 5),
        "size": _minmax(i["startSize"]),
        "speed": _minmax(i["startSpeed"]),
        "lifetime": _minmax(i["startLifetime"]),
        "radius": round(shape.get("radius", 0), 5) if shape.get("enabled") else 0,
    }


def extract_explosions(env):
    by_file = {}
    for o in env.objects:
        if o.type.name == "GameObject":
            by_file.setdefault(o.assets_file, []).append(o)
    out = {}
    for af, gos in by_file.items():
        objs = af.objects
        for go in gos:
            tt = go.read_typetree()
            m = re.fullmatch(r"ClusterExplosion(\w+)", tt["m_Name"])
            if not m:
                continue
            entry = {}

            def comps(gtt):
                res = {}
                for c in gtt["m_Component"]:
                    ptr = c[1] if isinstance(c, (tuple, list)) else c.get("component", c.get("second"))
                    co = objs.get(ptr["m_PathID"])
                    if co is not None:
                        res[co.type.name] = co
                return res

            root_c = comps(tt)
            entry["main"] = _ps_entry(root_c["ParticleSystem"].read_typetree())
            tr = root_c["Transform"].read_typetree()
            for ch in tr["m_Children"]:
                ctr = objs[ch["m_PathID"]].read_typetree()
                cgo = objs[ctr["m_GameObject"]["m_PathID"]]
                ctt = cgo.read_typetree()
                cc = comps(ctt)
                name = ctt["m_Name"].lower().replace(" ", "")
                if "ParticleSystem" in cc:
                    entry[name] = _ps_entry(cc["ParticleSystem"].read_typetree())
                if "Light" in cc:
                    lt = cc["Light"].read_typetree()
                    col = lt["m_Color"]
                    entry["light"] = {"color": [round(col[ch], 5) for ch in "rgb"],
                                      "energy": lt["m_Intensity"], "range": lt["m_Range"]}
            out[m.group(1).lower()] = entry
    return out


# ---------------------------------------------------------------- main

def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("game_dir", help="Lazerbait install folder (or its lazerbait_Data folder)")
    ap.add_argument("--out", default=os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets"))
    args = ap.parse_args()
    if shutil.which("ffmpeg") is None:
        sys.exit("ffmpeg not found on PATH (needed to convert music to Ogg Vorbis)")

    data = find_data_dir(args.game_dir)
    out = os.path.abspath(args.out)
    dirs = {k: os.path.join(out, k) for k in
            ["textures", "skybox", "meshes", "fonts", "video", "data", "audio/music", "audio/sfx"]}
    for d in dirs.values():
        os.makedirs(d, exist_ok=True)
    log(f"loading {data} (this takes a minute)")
    env = UnityPy.load(data)

    tex, audio, meshes, fonts, movies = {}, {}, {}, {}, {}
    for o in env.objects:
        t = o.type.name
        if t not in ("Texture2D", "AudioClip", "Mesh", "Font", "MovieTexture"):
            continue
        try:
            name = o.read_typetree().get("m_Name", "")
        except Exception:
            continue
        bucket = {"Texture2D": tex, "AudioClip": audio, "Mesh": meshes, "Font": fonts, "MovieTexture": movies}[t]
        bucket.setdefault(name, o)  # first occurrence wins

    def need(bucket, name, kind):
        if name not in bucket:
            sys.exit(f"{kind} '{name}' not found - is this the right game?")
        return bucket[name]

    log("textures")
    for n in TEXTURES:
        need(tex, n, "texture").read().image.save(os.path.join(dirs["textures"], n + ".png"))
    for f in SKYBOX:
        need(tex, "BluePinkNebular_" + f, "texture").read().image.save(
            os.path.join(dirs["skybox"], f"BluePinkNebular_{f}.png"))
    # Unity DXT5nm normal maps: rgb = y, a = x. The game also samples them raw as albedo.
    t = np.asarray(need(tex, "terrain01_normal", "texture").read().image.convert("RGBA"), dtype=np.float64) / 255
    alb = np.dstack([srgb_encode(t[..., 0]), srgb_encode(t[..., 1]), srgb_encode(t[..., 2]), np.ones(t.shape[:2])])
    Image.fromarray(to_u8(alb), "RGBA").save(os.path.join(dirs["textures"], "terrain01_albedo.png"))
    x, y = t[..., 3] * 2 - 1, t[..., 1] * 2 - 1
    z = np.sqrt(np.clip(1 - x * x - y * y, 0, 1))
    Image.fromarray(to_u8(np.dstack([(x + 1) / 2, (y + 1) / 2, (z + 1) / 2])), "RGB").save(
        os.path.join(dirs["textures"], "terrain01_normal.png"))
    g = np.asarray(need(tex, "Geo pattern normal", "texture").read().image.convert("RGBA"), dtype=np.float64) / 255
    ga = np.dstack([srgb_encode(g[..., 0]), srgb_encode(g[..., 1]), srgb_encode(g[..., 2]), g[..., 3]])
    Image.fromarray(to_u8(ga), "RGBA").save(os.path.join(dirs["textures"], "geo_pattern_albedo.png"))

    log("meshes")
    for src, dst in MESHES.items():
        txt = need(meshes, src, "mesh").read().export()
        with open(os.path.join(dirs["meshes"], dst + ".obj"), "w") as fh:
            fh.write(convert_mesh(txt))

    log("fonts")
    for src, dst in FONTS.items():
        with open(os.path.join(dirs["fonts"], dst), "wb") as fh:
            fh.write(bytes(need(fonts, src, "font").read().m_FontData))

    log("videos")
    for n in MOVIES:
        tt = need(movies, n, "movie").read_typetree()
        with open(os.path.join(dirs["video"], n + ".ogv"), "wb") as fh:
            fh.write(bytes(tt["m_MovieData"]))

    log("audio")
    tmp = os.path.join(out, ".tmp_audio")
    os.makedirs(tmp, exist_ok=True)

    def wav_of(name):
        samples = need(audio, name, "audio clip").read().samples
        p = os.path.join(tmp, name + ".wav")
        with open(p, "wb") as fh:
            fh.write(next(iter(samples.values())))
        return p

    for n in MUSIC:
        ffmpeg_ogg(wav_of(n), os.path.join(dirs["audio/music"], n.lower().replace(" ", "_") + ".ogg"))
    for n in SFX:
        shutil.copyfile(wav_of(n), os.path.join(dirs["audio/sfx"], n.lower() + ".wav"))
    ffmpeg_ogg(wav_of(AMBIENT), os.path.join(dirs["audio/sfx"], AMBIENT.lower() + ".ogg"))
    shutil.rmtree(tmp, ignore_errors=True)

    log("explosion particle data")
    ex = extract_explosions(env)
    if len(ex) != 9:
        sys.exit(f"expected 9 ClusterExplosion prefabs, found {len(ex)}")
    with open(os.path.join(dirs["data"], "explosions.json"), "w") as fh:
        json.dump(ex, fh, indent=1)

    with open(os.path.join(out, ".extracted"), "w") as fh:
        fh.write("assets extracted from the original Lazerbait\n")
    log(f"done -> {out}")


if __name__ == "__main__":
    main()
