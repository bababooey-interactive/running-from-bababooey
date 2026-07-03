# Run from Bababooey

[https://www.roblox.com/games/96377400695084/Run-from-Bababooey-Lobby](https://www.roblox.com/games/96377400695084/Run-from-Bababooey-Lobby)

A co-op / solo horror maze game built for **Roblox Studio**, split across two
Roblox places:

- **`lobby/`** — the lobby place. Players pick Solo or Coop, vote on a level,
  ready up, and get teleported into the game place.
- **`game/`** — the game place. Procedurally generates a maze each round,
  spawns an AI monster ("SoulDragger") that hunts players using sight/sound/
  smell, and tracks survival + task objectives (deliver coal, pull levers)
  until the players either escape or die.

The project is built with **Luau** and managed with **Rokit** + **Argon**, so it can be edited in a normal code editor
and synced live into Roblox Studio.

---

## Repository layout

```
.
├── rokit.toml                  # Toolchain manifest (argon, stylua)
│
├── lobby/                      # Roblox "Lobby" place
│   ├── default.project.json    # Argon/Rojo project definition
│   └── src/
│       ├── ReplicatedStorage/Shared/   # Constants.luau, Types.luau, RemoteEvents.luau
│       ├── ServerScriptService/        # Room/plate/progress logic
│       ├── StarterPlayer/StarterPlayerScripts/  # Level select + plate UI
│       └── ...                         # Workspace, StarterGui, etc.
│
├── game/                       # Roblox "Game" place
│   ├── default.project.json
│   └── src/
│       ├── ReplicatedStorage/Shared/   # Constants.luau, Types.luau, RemoteEvents.luau
│       ├── ServerScriptService/        # Map gen, monster AI, tasks, survival, revive
│       ├── StarterPlayer/              # HUD, minimap, camera, lantern throw, etc.
│       └── ...
│
└── assets/
    └── blender_scripts/        # Procedural Blender (bpy) scripts used to
                                 # generate 3D props/assets for Roblox import
        ├── arkan/               # Lantern, lever, coal chunks
        ├── julian/              # Meat, carrot, water bottle
        ├── gilang/               # Cave/dungeon labyrinth asset pack
        └── requirements.txt      # Python/bpy dependencies for the scripts
```

Each place (`lobby/`, `game/`) is a self-contained Argon project with
its own `default.project.json` mapping `src/` folders onto the Roblox
DataModel (`Workspace`, `ReplicatedStorage`, `ServerScriptService`, etc.).

---

## Getting started

### Prerequisites

- [Roblox Studio](https://create.roblox.com/)
- [Rokit](https://github.com/rojo-rbx/rokit) — installs the pinned tool
  versions listed in `rokit.toml`:
  - [`argon`](https://github.com/argon-rbx/argon) — file sync tool (Rojo-compatible)
  - [`stylua`](https://github.com/JohnnyMorganz/stylua) — Luau formatter
- Python 3.13 + `bpy` (only needed if you want to regenerate assets from the
  Blender scripts in `assets/blender_scripts/`)

### Install tooling

```bash
rokit install
```

### Sync a place into Roblox Studio

From inside either `lobby/` or `game/`:

```bash
cd lobby   # or: cd game
argon serve
```

Then connect to the running Argon session from the Argon plugin inside
Roblox Studio, opening the corresponding place file.

### Formatting

```bash
stylua .
```

---

## Game flow

1. **Lobby place** — `LobbyRoomManager.server.luau` and `PlateManager.server.luau`
   handle two physical "plates" (Solo / Coop). Solo players pick a level and
   go straight to `StartingGame`; Coop players join a shared room, vote on a
   level, ready up, and teleport together once everyone is ready.
   `PlayerProgressStore.luau` persists `unlockedLevel` / `highestEndless` per
   player via DataStores.
2. **Teleport** — `TeleportOptions` with `ShouldReserveServer = true` carries
   `{ level, mode, roomId }` to the game place (`Constants.GAME_PLACE_ID`).
3. **Game place** — `GameManager.server.luau` reads the teleport data,
   randomly selects `level` active rules from `Constants.RULES_POOL` (with a
   guaranteed monster "sense" rule), then initializes:
   - `MapGenerator.luau` — procedurally carves a main hall + maze, places
     walls/floor/ceiling, task objects (coal, levers), lanterns, food items,
     and props, all scaled by `level`.
   - `MonsterAI.server.luau` / `MonsterBrain.luau` / `SensorSystem.luau` —
     drives the "SoulDragger" monster's IDLE → INVESTIGATE → SEARCH → CHASE →
     CATCH state machine using hearing/smell/vision rules.
   - `DuplicationSystem.luau` — spawns extra monster clones when the
     `monster_duplicate` rule stacks (level 9+).
   - `TaskSystem.luau` — tracks coal/lever objective progress and fires the
     win condition.
   - `SurvivalSystem.luau` — hunger decay and darkness-timer death, gated by
     active rules.
   - `ReviveSystem.luau` — downed/revive/permanent-death flow for co-op.
4. Players who survive and complete all tasks win; progress is teleported
   back to the lobby and saved.

### Rules system

`Constants.Rules` defines monster buffs (`monster_hear`, `monster_smell`,
`monster_see`, `monster_fast`, `monster_reach`, `monster_duplicate`) and
player debuffs (`player_hunger`, `player_dark_timer`). Level *N* activates
*N* rules picked from `Constants.RULES_POOL`; every 10th level ("Nightmare")
activates the full `Constants.NIGHTMARE_RULES` combo instead.

---

## Blender asset scripts

`assets/blender_scripts/` contains standalone `bpy` scripts (run from
Blender's Scripting tab) that procedurally build low-poly, Roblox-ready
props and export them as `.fbx`/`.blend`:

| Script | Output |
|---|---|
| `arkan/lantern.py` | Pagoda-style lantern |
| `arkan/lever_box.py` | Rotatable lever + housing |
| `arkan/coal_generator.py` | 5 unique coal chunk variants |
| `julian/meat.py`, `julian/carrot.py`, `julian/waterbottle.py` | Food props |
| `gilang/labirynt_asset.py`, `gilang/labirynt_asset_export_4_files.py` | Cave/dungeon wall, ceiling, boulder, and fireplace asset pack |

All scripts convert Blender's Z-up space to Roblox's Y-up space on export
(`axis_forward="-Z"`, `axis_up="Y"`) so imported meshes line up correctly.

---

## Contributors

see commit messages for detailed contributors' contributions
