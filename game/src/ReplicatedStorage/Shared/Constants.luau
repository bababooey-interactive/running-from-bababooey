
-- =============================================================
--  Constants.luau  (v2 — Level System + Endless + Conveyor Belt)
--  Salin file ini ke lobby/src/ReplicatedStorage/Shared/ juga.
--  Kalau ada yang diubah, update keduanya sekaligus.
-- =============================================================

local Constants = {}

-- ─────────────────────────────────────────────
--  PLACE IDs  ← isi setelah publish ke Roblox
-- ─────────────────────────────────────────────

Constants.LOBBY_PLACE_ID = 0
Constants.GAME_PLACE_ID  = 0

-- ─────────────────────────────────────────────
--  GAME MODES
-- ─────────────────────────────────────────────

Constants.GameMode = {
    REGULAR = "REGULAR",  -- pilih level, selesai → unlock level berikutnya
    ENDLESS = "ENDLESS",  -- mulai dari pilihan level, terus naik sampai mati
}

-- ─────────────────────────────────────────────
--  LEVEL SYSTEM
-- ─────────────────────────────────────────────

-- Level N = N rules aktif  (level 1 = 1 rule, level 8 = semua 8 rule unik)
-- Level 9+ = rule_duplicate mulai stack (2x, 4x, 8x monster)
Constants.DEFAULT_UNLOCKED_LEVELS  = 10   -- level 1–10 terbuka untuk semua player baru
Constants.NIGHTMARE_EVERY_N_LEVELS = 10   -- level 10, 20, 30... = preset Nightmare combo
Constants.VOTE_DURATION            = 25   -- detik untuk voting level di lobby

-- ─────────────────────────────────────────────
--  RULES
-- ─────────────────────────────────────────────

Constants.Rules = {
    -- Monster buffs
    MONSTER_HEAR = "monster_hear",  -- bisa dengar (sound)
    MONSTER_SMELL     = "monster_smell",      -- bisa cium player (jarak)
    MONSTER_SEE       = "monster_see",        -- bisa lihat player di area terang
    MONSTER_FAST      = "monster_fast",       -- lebih cepat
    MONSTER_REACH     = "monster_reach",      -- ← NEW: catch radius jauh lebih besar
    MONSTER_DUPLICATE = "monster_duplicate",  -- spawn 1 monster lagi (stackable level 9+)

    -- Player debuffs
    PLAYER_HUNGER     = "player_hunger",      -- hunger bar aktif, habis = mati
    PLAYER_DARK_TIMER = "player_dark_timer",  -- terlalu lama di gelap = mati
}

-- Pool rules berurutan: level N random-pick N dari seluruh pool
-- Level 9+: monster_duplicate bisa muncul lebih dari sekali (jadi 4, 8 monster dst.)
Constants.RULES_POOL = {
    Constants.Rules.MONSTER_HEAR,  -- slot 1
    Constants.Rules.PLAYER_HUNGER,      -- slot 2
    Constants.Rules.MONSTER_SMELL,      -- slot 3
    Constants.Rules.PLAYER_DARK_TIMER,  -- slot 4
    Constants.Rules.MONSTER_SEE,        -- slot 5
    Constants.Rules.MONSTER_FAST,       -- slot 6
    Constants.Rules.MONSTER_REACH,      -- slot 7  ← NEW
    Constants.Rules.MONSTER_DUPLICATE,  -- slot 8  (level 9+: muncul lagi)
}

-- Nightmare combo (dipakai tiap level kelipatan NIGHTMARE_EVERY_N_LEVELS)
Constants.NIGHTMARE_RULES = {
    Constants.Rules.MONSTER_HEAR,
    Constants.Rules.MONSTER_SMELL,
    Constants.Rules.MONSTER_SEE,
    Constants.Rules.MONSTER_FAST,
    Constants.Rules.MONSTER_REACH,
    Constants.Rules.MONSTER_DUPLICATE,
    Constants.Rules.PLAYER_HUNGER,
    Constants.Rules.PLAYER_DARK_TIMER,
}

-- ─────────────────────────────────────────────
--  MAP & GRID
-- ─────────────────────────────────────────────

Constants.TILE_SIZE   = 8   -- lebar & kedalaman 1 tile (studs)
Constants.WALL_HEIGHT = 8   -- tinggi wall (studs)

-- Map scaling per level: cols/rows = BASE + (level - 1) * GROWTH, capped at MAX
Constants.MAP_COLS_BASE          = 12
Constants.MAP_ROWS_BASE          = 12
Constants.MAP_GROWTH_PER_LEVEL   = 2   -- tambah 2 tile per level tiap dimensi
Constants.MAP_MAX_COLS           = 44
Constants.MAP_MAX_ROWS           = 44

-- Tile types
Constants.Tile = {
    WALL     = 0,
    FLOOR    = 1,
    SPAWN    = 2,
    CONVEYOR = 3,   -- ← NEW: tile conveyor belt (hanya di Main Hall)
}

-- ─────────────────────────────────────────────
--  MAIN HALL  (selalu ada, conveyor belt ada di sini)
--  Main hall = koridor utama dari spawn ke arah fireplace.
--  Gilang generates-nya sebagai fixed structure sebelum random rooms.
-- ─────────────────────────────────────────────

Constants.MAIN_HALL_WIDTH            = 3   -- tile wide (24 studs)
Constants.MAIN_HALL_LENGTH_BASE      = 8   -- tile panjang di level 1
Constants.MAIN_HALL_LENGTH_PER_LEVEL = 1   -- bertambah per level

-- ─────────────────────────────────────────────
--  CONVEYOR BELT
--  Conveyor mengarah ke fireplace (dari spawn ke ujung hall).
--  Player yang berada di tile CONVEYOR dapat velocity push.
--  Monster immune — MonsterAI mengabaikan push.
-- ─────────────────────────────────────────────

Constants.CONVEYOR_SPEED = 18   -- studs/detik push ke arah fireplace

-- ─────────────────────────────────────────────
--  MONSTER
-- ─────────────────────────────────────────────

Constants.MONSTER_SPEED_BASE       = 12    -- studs/s di level 1
Constants.MONSTER_SPEED_PER_LEVEL  = 0.4  -- naik per level
Constants.MONSTER_SPEED_MAX        = 28   -- cap

Constants.MONSTER_HEAR_RADIUS      = 20   -- studs (base)
Constants.MONSTER_HEAR_PLUS_MUL    = 2    -- multiplier dengan rule HEAR_PLUS

Constants.MONSTER_SMELL_RADIUS     = 15   -- studs (hanya aktif dengan rule)
Constants.MONSTER_VISION_RANGE     = 30   -- studs (hanya aktif dengan rule)
Constants.MONSTER_VISION_ANGLE     = 60   -- derajat (half-angle cone)

Constants.MONSTER_REACH_BASE       = 4    -- studs catch radius (default)
Constants.MONSTER_REACH_BONUS      = 10   -- studs TAMBAHAN dengan rule MONSTER_REACH
-- Total reach dengan rule: REACH_BASE + REACH_BONUS = 14 studs

-- ─────────────────────────────────────────────
--  TASKS
-- ─────────────────────────────────────────────

Constants.TASK_COAL_COUNT    = 3
Constants.TASK_LEVER_COUNT   = 2
Constants.TASK_BATTERY_COUNT = 2
Constants.TASK_ADD_PER_LEVEL = 2

-- ─────────────────────────────────────────────
--  SURVIVAL
-- ─────────────────────────────────────────────

Constants.HUNGER_MAX         = 100
Constants.HUNGER_DECAY_RATE  = 1     -- per detik
Constants.HUNGER_FOOD_REFILL = 30
Constants.DARK_TIMER_MAX     = 20    -- detik sebelum mati di dark zone

-- ─────────────────────────────────────────────
--  REVIVE (coop)
-- ─────────────────────────────────────────────

Constants.REVIVE_TIMER = 60   -- detik sebelum permanent death

return Constants
