
-- =============================================================
--  RemoteEvents.luau  (GAME PLACE — v2)
--  Instance didefinisikan di game/default.project.json
-- =============================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local function R(name: string): RemoteEvent
    return Remotes:WaitForChild(name) :: RemoteEvent
end

local RemoteEvents = {

    -- ─── SETUP ──────────────────────────────────────────────
    -- Client → Server: tiap player kirim teleport data ke game server
    -- Payload: Types.TeleportPayload { mode, level, roomId, hostMaxLevel }
    -- Game server kumpulkan dari semua player → init game
    TeleportDataReceived = R("TeleportDataReceived"),

    -- ─── RULES ──────────────────────────────────────────────
    -- Server → semua Client: rules yang aktif ronde ini
    -- Payload: Types.ActiveRules — array of string (bisa ada duplikat)
    -- Gilang fire, Arkan & Julian listen
    RulesActivated       = R("RulesActivated"),

    -- ─── MAP ────────────────────────────────────────────────
    -- Server → semua Client: grid setelah generate selesai
    -- Payload: Types.Grid + Types.LevelConfig (untuk skala minimap)
    -- Gilang fire, Julian listen (minimap), Arkan listen (pathfinding grid)
    MapGenerated         = R("MapGenerated"),

    -- ─── TASKS ──────────────────────────────────────────────
    -- Server → semua Client: progress task terbaru
    -- Payload: Types.TaskProgress
    TaskProgressUpdated  = R("TaskProgressUpdated"),

    -- Client → Server: player selesaikan 1 task object
    -- Payload: taskType ("coal"|"lever"|"battery"), taskObjectId (string)
    PlayerInteractTask   = R("PlayerInteractTask"),

    -- ─── SURVIVAL ───────────────────────────────────────────
    -- Server → Client spesifik: update survival state player tsb
    -- Payload: Types.SurvivalState { hunger, darkTimer, isDead }
    SurvivalUpdated      = R("SurvivalUpdated"),

    -- Client → Server: player bikin suara
    -- Payload: noiseLevel (number 0–1), worldPosition (Vector3)
    -- Arkan listen di SensorSystem untuk trigger hearing monster
    PlayerMakeNoise      = R("PlayerMakeNoise"),

    -- ─── CONVEYOR BELT ──────────────────────────────────────
    -- Server → Client: player masuk/keluar zona conveyor belt
    -- Payload: isOnConveyor (boolean), direction (Vector3 — arah push)
    -- Julian listen untuk apply / stop BodyVelocity di client character
    ConveyorStateChanged = R("ConveyorStateChanged"),

    -- ─── DEATH & REVIVE ─────────────────────────────────────
    -- Server → semua Client: player mati
    -- Payload: playerName (string)
    PlayerDied           = R("PlayerDied"),

    -- Server → semua Client: player di-revive
    -- Payload: playerName (string)
    PlayerRevived        = R("PlayerRevived"),

    -- Client → Server: player bawa body ke fireplace
    -- Payload: targetPlayerName (string)
    ReviveRequest        = R("ReviveRequest"),

    -- ─── MONSTER ────────────────────────────────────────────
    -- Server → semua Client: posisi & state monster terbaru (untuk minimap)
    -- Payload: { position: Vector3, state: Types.MonsterState, monsterIndex: number }
    -- Arkan fire tiap ~0.5s per monster instance
    MonsterPosition      = R("MonsterPosition"),

    -- ─── LEVEL FLOW ─────────────────────────────────────────
    -- Server → semua Client: semua task selesai, level cleared!
    -- Regular mode: tampilkan screen "Level X Clear!" → teleport balik ke lobby
    -- Endless mode: tampilkan screen → reset server untuk level berikutnya (NO teleport)
    -- Payload: Types.EndlessLevelResult { levelCleared, nextLevel, nextConfig }
    LevelCleared         = R("LevelCleared"),

    -- Server → semua Client: player ketangkap / seluruh team mati = game over
    -- Payload: finalLevel (number), gameMode (GameMode)
    -- Setelah ini: Julian tampilkan result screen → teleport balik ke lobby
    GameOver             = R("GameOver"),

    -- Server → Client spesifik: konfirmasi level baru sudah disave ke DataStore
    -- Payload: newUnlockedLevel (number)
    -- Hanya di Regular mode, hanya player yang unlock level baru
    LevelProgressSaved   = R("LevelProgressSaved"),
}

return RemoteEvents
