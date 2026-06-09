
-- =============================================================
--  RemoteEvents.luau  (GAME PLACE)
--  Akses semua RemoteEvent yang ada di Game.
--  Instance-nya didefinisikan di game/default.project.json.
--
--  Cara pakai:
--    local RE = require(game.ReplicatedStorage.Shared.RemoteEvents)
--    RE.RulesActivated:FireAllClients(activeRules)
--    RE.PlayerMakeNoise.OnServerEvent:Connect(function(player, level, pos) ... end)
-- =============================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local function R(name: string): RemoteEvent
    return Remotes:WaitForChild(name) :: RemoteEvent
end

local RemoteEvents = {

    -- ─── SETUP ──────────────────────────────────────────────
    -- Client → Server: player kirim data teleport mereka ke game server
    -- Payload: Types.TeleportPayload { difficulty, mode, roomId }
    -- Julian listen + game server collect dari semua player → init game
    TeleportDataReceived = R("TeleportDataReceived"),

    -- ─── RULES ──────────────────────────────────────────────
    -- Server → semua Client: rules yang aktif ronde ini
    -- Payload: Types.ActiveRules — array of string
    -- Gilang fire, Arkan & Julian listen
    RulesActivated       = R("RulesActivated"),

    -- ─── MAP ────────────────────────────────────────────────
    -- Server → semua Client: grid map setelah generate selesai
    -- Payload: Types.Grid — 2D array
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
    -- Server → Client spesifik: update bar survival player tsb
    -- Payload: Types.SurvivalState { hunger, darkTimer, isDead }
    SurvivalUpdated      = R("SurvivalUpdated"),

    -- Client → Server: player bikin suara
    -- Payload: noiseLevel (number 0–1), worldPosition (Vector3)
    -- Arkan listen di SensorSystem untuk trigger hearing
    PlayerMakeNoise      = R("PlayerMakeNoise"),

    -- ─── DEATH & REVIVE ─────────────────────────────────────
    -- Server → semua Client: player mati
    -- Payload: playerName (string)
    PlayerDied           = R("PlayerDied"),

    -- Server → semua Client: player berhasil di-revive
    -- Payload: playerName (string)
    PlayerRevived        = R("PlayerRevived"),

    -- Client → Server: player bawa body ke fireplace
    -- Payload: targetPlayerName (string)
    ReviveRequest        = R("ReviveRequest"),

    -- ─── MONSTER (untuk minimap) ────────────────────────────
    -- Server → semua Client: posisi & state monster terbaru
    -- Payload: { position: Vector3, state: Types.MonsterState }
    -- Arkan fire tiap ~0.5 detik, Julian listen untuk dot merah di minimap
    MonsterPosition      = R("MonsterPosition"),

    -- ─── GAME END ───────────────────────────────────────────
    -- Server → semua Client: game selesai
    -- Payload: didWin (boolean)
    -- Setelah ini Julian tampilkan screen, lalu teleport balik ke Lobby
    GameEnded            = R("GameEnded"),
}

return RemoteEvents
