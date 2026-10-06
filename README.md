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
* **Assets**: meshes, textures, skybox, fonts, music, sound effects and the three tutorial videos (Theora) were
  extracted from the original data files.
* **Engine behaviour**: the original depended on Unity specifics, and these are emulated:
  * the 0.08 s fixed physics step, with interpolated kinematic bodies (this sets the ship orbit speed);
  * trigger enter/exit semantics (disabling a collider silently drops its contacts);
  * linear colour space, including Unity 5.4's non-linear light intensity;
  * legacy particle shader maths;
  * `Time.timeScale` pausing;
  * 90 Hz frame-count based logic, made refresh-rate independent with a virtual frame counter.

## Running
Open the folder in Godot 4.6 and press Play, or export with the included presets (Linux / Windows).

* **VR**: start with an OpenXR runtime active (SteamVR, Meta Quest Link, Monado, WMR...). VR is chosen automatically
  when a headset is available.
* **Desktop**: used automatically when no headset is available. To force it, run with `--xr-mode off` or `-- --desktop`.
* Jump straight into a match with your saved menu settings: `godot --path . -- --game`

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
* For a standalone Quest build: install the Android export templates and SDK, add an Android preset with
  XR Mode = OpenXR, and enable the Meta plugin options of the vendors plugin.

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
assets/                     assets extracted from the original game
```

## Differences from the original (and why)
* **Steam stats / leaderboards**: Steamworks isn't available. The same counters (ships destroyed, AIs defeated per
  difficulty) are stored locally in `user://lazerbait-stats.json`, and the leaderboards show your local entry.
* **Arial** (built into Unity) is replaced by the metric-compatible Liberation Sans.
* **Controller models** come from the OpenXR runtime (render models extension), or a simple stand-in is used.
  Controller-mounted UI uses the original Vive offsets relative to the OpenXR aim pose. The original's Oculus-specific
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
game files. Liberation Sans: SIL Open Font License (see `assets/fonts/LiberationSans-LICENSE.txt`). The Godot OpenXR
Vendors plugin is MIT licensed, and the vendor loaders keep their own licences (see the addon folder).
