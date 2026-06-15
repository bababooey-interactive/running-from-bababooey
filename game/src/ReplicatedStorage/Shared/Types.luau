
-- =============================================================
--  Types.luau  (v2 — Level System + Endless + Conveyor Belt)
--  Salin ke kedua tempat (lobby & game) — isinya sama persis.
-- =============================================================

local Types = {}

-- ─────────────────────────────────────────────
--  GAME MODE & LEVEL
-- ─────────────────────────────────────────────

export type GameMode = "REGULAR" | "ENDLESS"

-- Semua nilai yang derive dari level — dihitung oleh LevelUtils module
-- (bukan disimpan di Constants, karena berubah-ubah per level)
export type LevelConfig = {
    level        : number,
    ruleCount    : number,  -- = level (capped di total rules di pool)
    mapCols      : number,  -- Constants.MAP_COLS_BASE + (level-1) * MAP_GROWTH_PER_LEVEL
    mapRows      : number,
    mainHallLen  : number,  -- Constants.MAIN_HALL_LENGTH_BASE + level * PER_LEVEL
    monsterSpeed : number,  -- Constants.MONSTER_SPEED_BASE + level * PER_LEVEL
    isNightmare  : boolean, -- true kalau level % NIGHTMARE_EVERY_N_LEVELS == 0
}

-- ─────────────────────────────────────────────
--  PLAYER PROGRESS  (disimpan di DataStore oleh Gilang)
-- ─────────────────────────────────────────────

export type PlayerProgress = {
    unlockedLevel  : number,  -- level tertinggi yang sudah di-unlock di Regular mode
    highestEndless : number,  -- level tertinggi yang dicapai di Endless mode
}

-- ─────────────────────────────────────────────
--  TELEPORT  (Lobby → Game)
-- ─────────────────────────────────────────────

export type TeleportPayload = {
    mode         : GameMode,
    level        : number,   -- level yang dipilih lewat voting
    roomId       : string,
    hostMaxLevel : number,   -- level tertinggi yang bisa dipilih (max unlock anggota)
}

-- ─────────────────────────────────────────────
--  LOBBY / ROOM
-- ─────────────────────────────────────────────

export type RoomMode = "SOLO" | "COOP"

export type RoomInfo = {
    id           : string,
    hostName     : string,
    gameMode     : GameMode,   -- REGULAR atau ENDLESS
    roomMode     : RoomMode,   -- SOLO atau COOP
    selectedLevel: number,     -- level yang sedang di-lead di vote
    maxLevel     : number,     -- max level bisa dipilih (tertinggi unlock di antara anggota)
    playerCount  : number,
    maxPlayers   : number,
    readyCount   : number,
}

-- Satu vote dari satu player
export type LevelVote = {
    playerName  : string,
    votedLevel  : number,
}

-- Hasil vote terkini (dikirim ke semua client saat ada perubahan)
export type VoteResult = {
    votes        : { [string]: number },  -- { playerName = votedLevel }
    winningLevel : number,                -- level dengan vote terbanyak (tie → level lebih rendah)
    timeRemaining: number,               -- detik voting tersisa
}

-- ─────────────────────────────────────────────
--  MAP / GRID
-- ─────────────────────────────────────────────

export type TileType = number   -- 0=WALL, 1=FLOOR, 2=SPAWN, 3=CONVEYOR
export type Grid     = { { TileType } }   -- Grid[row][col]
export type TilePos  = { col: number, row: number }

-- ─────────────────────────────────────────────
--  RULES
-- ─────────────────────────────────────────────

export type RuleID      = string
export type ActiveRules = { RuleID }   -- array, bisa ada duplikat (monster_duplicate stacks)

-- ─────────────────────────────────────────────
--  GAME STATE
-- ─────────────────────────────────────────────

export type GameState   = "WAITING" | "IN_GAME" | "LEVEL_CLEARED" | "GAME_OVER"

-- ─────────────────────────────────────────────
--  TASKS
-- ─────────────────────────────────────────────

export type TaskEntry    = { done: number, total: number }
export type TaskProgress = {
    coal    : TaskEntry,
    lever   : TaskEntry,
    battery : TaskEntry,
}

-- ─────────────────────────────────────────────
--  SURVIVAL
-- ─────────────────────────────────────────────

export type SurvivalState = {
    hunger    : number,
    darkTimer : number,
    isDead    : boolean,
}

-- ─────────────────────────────────────────────
--  MONSTER
-- ─────────────────────────────────────────────

export type MonsterState = "IDLE" | "PATROL" | "CHASE" | "CATCH"

-- ─────────────────────────────────────────────
--  ENDLESS MODE
-- ─────────────────────────────────────────────

-- Data yang dikirim ke client saat level cleared di Endless
export type EndlessLevelResult = {
    levelCleared : number,   -- level yang baru saja selesai
    nextLevel    : number,   -- level berikutnya
    nextConfig   : LevelConfig,
}

return Types
