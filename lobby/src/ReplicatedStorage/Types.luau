
-- =============================================================
--  Types.luau
--  Salin ke kedua tempat (lobby & game) — isinya sama persis.
-- =============================================================

local Types = {}

-- ─────────────────────────────────────────────
--  TELEPORT  (dipakai di Lobby dan Game)
-- ─────────────────────────────────────────────

-- Data yang dikirim dari Lobby ke Game saat TeleportAsync.
-- Lobby pack ini → Game unpack ini.
export type TeleportPayload = {
    difficulty : string,  -- "EASY" | "MEDIUM" | "HARD"
    mode       : string,  -- "SOLO" | "COOP"
    roomId     : string,  -- ID unik room (untuk logging/debug)
}

-- ─────────────────────────────────────────────
--  MAP / GRID
-- ─────────────────────────────────────────────

export type TileType = number
export type Grid     = { { TileType } }  -- Grid[row][col]

export type TilePos  = {
    col : number,
    row : number,
}

-- ─────────────────────────────────────────────
--  RULES
-- ─────────────────────────────────────────────

export type RuleID      = string
export type ActiveRules = { RuleID }

-- ─────────────────────────────────────────────
--  GAME STATE
-- ─────────────────────────────────────────────

export type GameState  = "LOBBY" | "STARTING" | "IN_GAME" | "WIN" | "LOSE"
export type Difficulty = "EASY" | "MEDIUM" | "HARD"
export type RoomMode   = "SOLO" | "COOP"

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
--  LOBBY
-- ─────────────────────────────────────────────

export type RoomInfo = {
    id          : string,
    hostName    : string,
    difficulty  : Difficulty,
    mode        : RoomMode,
    playerCount : number,
    maxPlayers  : number,
    isReady     : boolean,
}

-- ─────────────────────────────────────────────
--  MONSTER
-- ─────────────────────────────────────────────

export type MonsterState = "IDLE" | "PATROL" | "CHASE" | "CATCH"

return Types
