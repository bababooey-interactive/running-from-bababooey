-- =============================================================
--  Constants.lua
--  Semua angka dan string ID yang dipakai bersama.
--  Kalau mau ganti nilai, cukup ganti di sini — satu tempat.
--  Dipakai oleh: semua script (server, client, shared)
-- =============================================================

local Constants = {}

-- ─────────────────────────────────────────────
--  MAP & GRID
--  Gilang pakai ini untuk naruh part.
--  Arkan pakai ini untuk konversi grid → Vector3.
--  Julian pakai ini untuk skala minimap.
--  Harus sama persis antar ketiganya!
-- ─────────────────────────────────────────────

Constants.TILE_SIZE   = 8   -- lebar & kedalaman 1 tile (studs)
Constants.WALL_HEIGHT = 8   -- tinggi wall (studs)  — bikin wall jadi kubus 8×8×8
Constants.MAP_COLS    = 20  -- lebar map dalam tile
Constants.MAP_ROWS    = 20  -- panjang map dalam tile

-- Konversi tile → world:
--   worldX = tileCol * TILE_SIZE
--   worldZ = tileRow * TILE_SIZE
-- Contoh: tile (col=2, row=3) → world (16, 0, 24)

-- Tile type values — dipakai di dalam Grid 2D array
Constants.Tile = {
    WALL  = 0,  -- blok solid, monster bisa lewat (noclip), player nggak
    FLOOR = 1,  -- area jalan
    SPAWN = 2,  -- floor + titik spawn player
}

-- ─────────────────────────────────────────────
--  RULE IDs
--  Gilang random-pick dari list ini.
--  Arkan & Julian cek apakah rule ini ada di activeRules.
--
--  Format yang dikirim lewat RemoteEvent:
--    { "monster_smell", "player_hunger", "monster_duplicate" }
--
--  Pakai Constants.Rules.MONSTER_SMELL bukan raw string
--  supaya autocomplete jalan dan typo ketangkap.
-- ─────────────────────────────────────────────

Constants.Rules = {
    -- Monster buffs
    MONSTER_SMELL     = "monster_smell",      -- bisa cium player (jarak)
    MONSTER_SEE       = "monster_see",        -- bisa lihat player di area terang
    MONSTER_HEAR_PLUS = "monster_hear_plus",  -- radius dengar 2× lebih jauh
    MONSTER_DUPLICATE = "monster_duplicate",  -- spawn 1 monster tambahan (stack-able)
    MONSTER_FAST      = "monster_fast",       -- monster lebih cepat

    -- Player debuffs
    PLAYER_HUNGER     = "player_hunger",      -- hunger bar aktif, habis → mati
    PLAYER_DARK_TIMER = "player_dark_timer",  -- terlalu lama di gelap → mati
}

-- ─────────────────────────────────────────────
--  DIFFICULTY
--  ruleCount  = berapa banyak rules yang di-random aktifkan
--  monsterSpeed = WalkSpeed monster
--  taskMult   = pengali jumlah task (TASK_*_COUNT × taskMult)
-- ─────────────────────────────────────────────

Constants.Difficulty = {
    EASY   = { ruleCount = 2, monsterSpeed = 12, taskMult = 1 },
    MEDIUM = { ruleCount = 4, monsterSpeed = 16, taskMult = 2 },
    HARD   = { ruleCount = 6, monsterSpeed = 22, taskMult = 3 },
}

-- ─────────────────────────────────────────────
--  TASKS  (base count, sebelum dikali taskMult)
-- ─────────────────────────────────────────────

Constants.TASK_COAL_COUNT    = 3
Constants.TASK_LEVER_COUNT   = 2
Constants.TASK_BATTERY_COUNT = 2

-- ─────────────────────────────────────────────
--  SURVIVAL
-- ─────────────────────────────────────────────

Constants.HUNGER_MAX         = 100   -- nilai awal hunger
Constants.HUNGER_DECAY_RATE  = 1     -- dikurangi per detik saat rule aktif
Constants.HUNGER_FOOD_REFILL = 30    -- tambahan hunger saat makan
Constants.DARK_TIMER_MAX     = 20    -- detik sebelum mati kalau di dark zone

-- ─────────────────────────────────────────────
--  MONSTER SENSOR
-- ─────────────────────────────────────────────

Constants.MONSTER_BASE_SPEED    = 12   -- WalkSpeed default (sebelum difficulty)
Constants.MONSTER_HEAR_RADIUS   = 20   -- studs, default hearing
Constants.MONSTER_HEAR_PLUS_MUL = 2    -- multiplier kalau rule MONSTER_HEAR_PLUS aktif
Constants.MONSTER_SMELL_RADIUS  = 15   -- studs, hanya aktif kalau rule MONSTER_SMELL on
Constants.MONSTER_VISION_RANGE  = 30   -- studs, hanya aktif kalau rule MONSTER_SEE on
Constants.MONSTER_VISION_ANGLE  = 60   -- derajat (setengah sudut cone)

-- ─────────────────────────────────────────────
--  REVIVE (coop)
-- ─────────────────────────────────────────────

Constants.REVIVE_TIMER = 60  -- detik sebelum permanent death kalau nggak di-revive

return Constants
