
-- =============================================================
--  Constants.luau
--  Salin file ini ke:
--    lobby/src/ReplicatedStorage/Shared/Constants.luau
--    game/src/ReplicatedStorage/Shared/Constants.luau
--  Kalau ada yang diubah, update keduanya sekaligus.
-- =============================================================

local Constants = {}

-- ─────────────────────────────────────────────
--  PLACE IDs
--  Isi setelah publish ke Roblox.
--  Buka game di Creator Hub → setiap place punya ID masing-masing.
--  Lobby gunakan GAME_PLACE_ID saat memanggil TeleportAsync.
--  Game gunakan LOBBY_PLACE_ID saat teleport balik setelah selesai.
-- ─────────────────────────────────────────────

Constants.LOBBY_PLACE_ID = 0   -- ← ganti setelah publish
Constants.GAME_PLACE_ID  = 0   -- ← ganti setelah publish

-- ─────────────────────────────────────────────
--  MAP & GRID
-- ─────────────────────────────────────────────

Constants.TILE_SIZE   = 8   -- lebar & kedalaman 1 tile (studs)
Constants.WALL_HEIGHT = 8   -- tinggi wall (studs)
Constants.MAP_COLS    = 20  -- lebar map dalam tile
Constants.MAP_ROWS    = 20  -- panjang map dalam tile

-- Konversi tile → world position:
--   worldX = tileCol * TILE_SIZE
--   worldZ = tileRow * TILE_SIZE

Constants.Tile = {
    WALL  = 0,
    FLOOR = 1,
    SPAWN = 2,
}

-- ─────────────────────────────────────────────
--  RULE IDs
--  Gilang random-pick dari pool ini.
--  Arkan & Julian cek apakah rule ada di activeRules.
-- ─────────────────────────────────────────────

Constants.Rules = {
    MONSTER_SMELL     = "monster_smell",
    MONSTER_SEE       = "monster_see",
    MONSTER_HEAR_PLUS = "monster_hear_plus",
    MONSTER_DUPLICATE = "monster_duplicate",
    MONSTER_FAST      = "monster_fast",

    PLAYER_HUNGER     = "player_hunger",
    PLAYER_DARK_TIMER = "player_dark_timer",
}

-- ─────────────────────────────────────────────
--  DIFFICULTY
-- ─────────────────────────────────────────────

Constants.Difficulty = {
    EASY   = { ruleCount = 2, monsterSpeed = 12, taskMult = 1 },
    MEDIUM = { ruleCount = 4, monsterSpeed = 16, taskMult = 2 },
    HARD   = { ruleCount = 6, monsterSpeed = 22, taskMult = 3 },
}

-- ─────────────────────────────────────────────
--  TASKS
-- ─────────────────────────────────────────────

Constants.TASK_COAL_COUNT    = 3
Constants.TASK_LEVER_COUNT   = 2
Constants.TASK_BATTERY_COUNT = 2

-- ─────────────────────────────────────────────
--  SURVIVAL
-- ─────────────────────────────────────────────

Constants.HUNGER_MAX         = 100
Constants.HUNGER_DECAY_RATE  = 1
Constants.HUNGER_FOOD_REFILL = 30
Constants.DARK_TIMER_MAX     = 20

-- ─────────────────────────────────────────────
--  MONSTER
-- ─────────────────────────────────────────────

Constants.MONSTER_HEAR_RADIUS   = 20
Constants.MONSTER_HEAR_PLUS_MUL = 2
Constants.MONSTER_SMELL_RADIUS  = 15
Constants.MONSTER_VISION_RANGE  = 30
Constants.MONSTER_VISION_ANGLE  = 60

-- ─────────────────────────────────────────────
--  REVIVE (coop)
-- ─────────────────────────────────────────────

Constants.REVIVE_TIMER = 60

return Constants
