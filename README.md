# Lazerbait — Godot remake

A remake of [Lazerbait](https://store.steampowered.com/app/529150/Lazerbait/) (Taylor Stapleton, Unity 5.4 / SteamVR)
in **Godot 4.6**. It runs on desktop and in VR (OpenXR), and has **optional passthrough** (mixed reality).

## How it was made
The original game files (`/home/ai/Lazerbait`) were used as the reference:

* **Game logic**: `Assembly-CSharp.dll` was decompiled. `MasterController`, `ShipController`, `AIController`,
  `PlanetController`, `ClickHandler`, `LeftControllerHandler`, `MenuClickHandler`, `MenuMaster`, `Env` and `MenuSettings`
  were ported line by line to GDScript, keeping every constant, formula and the original quirks.
  Examples: the map generator and its mirroring, ship limits, capture countdown, AI timings, and `SendWave` sending
  `floor(n)+1` ships.
* **Scenes**: the `startMenu` and `sample` scenes and the prefabs were dumped from the asset files with UnityPy
  (transforms, TextMesh texts/sizes/anchors/colours, materials, lights, audio volumes, particle settings), and are
  rebuilt in code from those exact values (`scripts/core/u.gd` converts Unity's left-handed coordinates).
* **Assets**: meshes, textures, skybox, fonts, music, sound effects and the three tutorial videos (Theora) are
  extracted from your copy of the original data files by `tools/extract_assets.py`.
* **Engine behaviour**: the original depended on Unity specifics, and these are emulated:
  * the 0.08 s fixed physics step, with interpolated kinematic bodies (this sets the ship orbit speed);
  * trigger enter/exit semantics (disabling a collider silently drops its contacts);
  * linear colour space, including Unity 5.4's non-linear light intensity;
  * legacy particle shader maths;
  * `Time.timeScale` pausing;
  * 90 Hz frame-count based logic, made refresh-rate independent with a virtual frame counter.

## Setup (from source)
This repository contains **no assets from the original game**. You need your own copy of Lazerbait
(Steam app 529150, Windows build). The setup script extracts everything the remake needs from it.

### Requirements
* [Godot 4.6](https://godotengine.org/download) (standard build, not .NET)
* Python 3.9+ with the packages in `tools/requirements.txt` (UnityPy, numpy, Pillow)
* [ffmpeg](https://ffmpeg.org/) on your PATH (converts the music to Ogg Vorbis)
* Internet access once, to download the Godot OpenXR Vendors plugin (MIT licensed)

### Steps
```sh
git clone <this repo> lazerbait-remake
cd lazerbait-remake
python3 -m pip install -r tools/requirements.txt      # or use a virtualenv
python3 tools/setup.py "/path/to/steamapps/common/Lazerbait"
```
`tools/setup.py` does three things:
1. runs `tools/extract_assets.py`, which reads `lazerbait_Data` and writes `assets/`: textures, skybox, meshes
   (converted to Godot's coordinate system), fonts, music/SFX, tutorial videos and the explosion particle data;
2. downloads the OpenXR Vendors plugin into `addons/godotopenxrvendors/`;
3. runs `godot --headless --import` (set the `GODOT` environment variable or pass `--godot PATH` if the executable
   isn't called `godot`).

Each step can be skipped with `--skip-assets`, `--skip-addons` or `--skip-import`, and the extractor can be run on its
own: `python3 tools/extract_assets.py <game dir> [--out assets]`. The game folder may be the install folder or its
`lazerbait_Data` folder; a Windows install copied to Linux/macOS works fine.

If you run the project without the assets, it shows a message explaining how to extract them.

## Running
Open the folder in the Godot 4.6 editor and press Play, or run `godot --path .`.

* **VR**: start with an OpenXR runtime active (SteamVR, Meta Quest Link, Monado, WMR...). VR is chosen automatically
  when a headset is available.
* **Desktop**: used automatically when no headset is available. To force it, run with `--xr-mode off` or `-- --desktop`.
* Jump straight into a match with your saved menu settings: `godot --path . -- --game`

## Building
1. Install the Godot 4.6 export templates (Editor → Manage Export Templates, or download them from godotengine.org).
2. Export with one of the included presets, from the editor (Project → Export) or the command line:
   ```sh
   godot --headless --path . --export-release "Linux"           build/linux/Lazerbait.x86_64
   godot --headless --path . --export-release "Windows Desktop" build/windows/Lazerbait.exe
   ```
   The `build/` folder must exist first. Keep the `.pck` and the `libgodotopenxrvendors` library next to the
   executable.
3. Standalone Meta Quest (optional): install the Android export templates and SDK. A ready-made **Meta Quest**
   preset is included (`xr_features/xr_mode=1`, the vendors plugin's Meta options enabled, arm64 only). Export it with:
   ```sh
   godot --headless --path . --export-release "Meta Quest" build/android/Lazerbait.apk
   ```
   The first Android export also needs the Gradle build template (Project → Install Android Build Template), which
   pulls in the Khronos OpenXR loader. The OpenXR loader is bundled by Gradle; no extra step. Use the Mobile renderer
   (already set via `rendering/renderer/rendering_method.mobile`).

   **Important:** the preset's Android "XR Mode" option must be **OpenXR**. If it is "Regular", the APK launches as a
   flat window and `[Lazerbait] Desktop mode` is printed. The included preset selects OpenXR; if you make your own
   preset, set XR Mode accordingly and enable the vendors plugin's Meta options.

Exported builds contain the extracted assets, so **don't redistribute them**. Only the source is meant to be
shared.

## Controls

### VR (same as the original; Vive wands, with equivalents on other controllers)
| Action | Control |
|---|---|
| Point | Right controller laser |
| Select planet / send ships | Right trigger (click a planet, then click the target) |
| Create a link (auto-send new ships) | Right trigger: click and drag from a planet to a planet |
| Deselect | Right trigger on empty space |
| % of ships to send | Touch the right trackpad/thumbstick in a quadrant (25/50/75/100), then click it |
| Mini-map & planet counts | Hold left trigger |
| In-game menu (Quit to Menu / Pause / Mute Music) | Hold left trackpad click (or X/Y), point and click with the right trigger |
| Pause | Right menu button (or B) |
| Drag the world | Grip one controller and move it |
| Zoom (scale the world) | Grip both controllers and pinch/spread |

### Desktop
| Action | Control |
|---|---|
| Point / select / drag a link | Mouse, left button |
| % of ships | Keys 1, 2, 3, 4 (25 / 50 / 75 / 100 %) |
| Mini-map | Hold Tab |
| In-game menu planets | Esc (toggle), then click a planet |
| Pause | P |
| Look | Hold right mouse button and move |
| Move | WASD, Q/E (down/up), Shift = fast, mouse wheel = forward/back, middle mouse drag = pan |
| Help text / fullscreen | H / F11 |

On desktop the two controllers are shown as "virtual controllers" held in view, so the original controller-mounted
UI is still there: ship limit, % selector, mini-map and menu planets.

## Passthrough (mixed reality)
Passthrough is **off by default**. To turn it on, click the **"Passthrough"** planet in the main menu, below
"Graphics". The setting is saved. When passthrough is on, the skybox, sun and star field are hidden so that your
room shows through, and the platform and planets stay visible.

* It uses OpenXR environment blend mode `ALPHA_BLEND` when the runtime offers it, or the runtime's passthrough
  extension otherwise. The included Godot OpenXR Vendors plugin (`addons/godotopenxrvendors`) adds Meta (Quest / Quest
  Link), HTC, Pico and Android XR support. The `meta/passthrough` and `htc/passthrough` extensions are enabled in the
  project settings.
* If the device can't do passthrough, the menu shows "Passthrough = On (unsupported)" and the game stays opaque.

## Project layout
```
scenes/main.tscn            entry point (scripts/main.gd: level switching, fades, quality)
scripts/core/               autoloads (Settings, Stats, GameTime, XRManager, Debug) + helpers (U, A, UI3D, Picker)
scripts/rig/                PlayerRig (XR origin or desktop camera), Hand (input abstraction), LaserPointer
scripts/menu/menu_level.gd  startMenu: MenuMaster + MenuClickHandler + MovieTexturePlayer
scripts/game/               MasterController, Ship, Planet, PlanetController, AIController, ClickHandler,
                            LeftControllerHandler, GameLevel
scripts/fx/                 lines, lasers, explosions, sun, star field, wireframe
shaders/                    6-sided skybox, Unity legacy particle / line shaders, sun, wireframe, fade
tools/                      setup.py, extract_assets.py, requirements.txt
assets/                     created by tools/setup.py (not in git, except the Liberation Sans font)
addons/                     created by tools/setup.py (OpenXR Vendors plugin)
```

## Differences from the original (and why)
* **Steam stats / leaderboards**: Steamworks isn't available. The same counters (ships destroyed, AIs defeated per
  difficulty) are stored locally in `user://lazerbait-stats.json`, and the leaderboards show your local entry.
* **Arial** (built into Unity) is replaced by the metric-compatible Liberation Sans.
* **Controller models** come from the runtime, so they match the controllers you are holding. On Meta Quest
  (2 / 3 / Pro) Meta's own meshes are used via `XR_FB_render_model` (vendors plugin,
  `xr/openxr/extensions/meta/render_model`; the Meta Quest preset requests the render-model permission). On other
  runtimes (SteamVR etc.) `XR_EXT_render_model` is used. If neither is available, a procedural stand-in shaped like
  the active controller type (Touch-style or Vive wand) is shown. Models sit on the OpenXR grip pose. The
  controller-mounted UI uses the original Vive offsets relative to the aim pose. The original's Oculus-specific
  offsets for SteamVR's legacy poses don't map onto OpenXR, so they aren't used.
* **Mini-map orientation**: the original oriented the mini-map using world axes at the moment the match started
  (so it depended on how you held the controller). Here it's built as if the controller was held level.
* **Unity crash paths**: where the original would throw an exception mid-update, the code continues safely. The one
  exception is the AI link search, which ended that AI's turn in the original; this is reproduced because it affects
  AI behaviour.
* **Desktop mode** and **passthrough** are additions; the original was SteamVR-only.

## Development / test switches (after `--`)
`--autotest=SECONDS`, `--ai-player1`, `--timescale=N`, `--shots=T:PATH,...`, `--cam=x,y,z,yaw,pitch`,
`--settings="key=value;..."`, `--demo-select`, `--explosion-test`, `--desktop-menu`, `--cpu-particles`, `--xr-test`.
See `scripts/core/debug.gd`. Test runs started with `--autotest` or `--ai-player1` don't save stats.

## Credits
Original game © Taylor Stapleton. Music, sound effects, textures, fonts and tutorial videos come from the original
game files and are not included in this repository. Liberation Sans: SIL Open Font License (see `assets/fonts/LiberationSans-LICENSE.txt`). The Godot OpenXR
Vendors plugin is MIT licensed, and the vendor loaders keep their own licences (see the addon folder).
