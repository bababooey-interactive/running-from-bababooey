
-- =============================================================
--  RemoteEvents.luau  (LOBBY PLACE — v2)
--  Instance didefinisikan di lobby/default.project.json
-- =============================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local function R(name: string): RemoteEvent
    return Remotes:WaitForChild(name) :: RemoteEvent
end

local RemoteEvents = {

    -- ─── ROOM LIST ──────────────────────────────────────────
    -- Server → semua Client: daftar room yang tersedia
    -- Payload: { Types.RoomInfo }
    RoomListUpdated  = R("RoomListUpdated"),

    -- Server → semua Client di room: state room berubah (player join/leave/ready)
    -- Payload: Types.RoomInfo
    RoomStateUpdated = R("RoomStateUpdated"),

    -- ─── ROOM MANAGEMENT ────────────────────────────────────
    -- Client → Server: buat room baru
    -- Payload: gameMode (GameMode), roomMode (RoomMode)
    CreateRoom       = R("CreateRoom"),

    -- Client → Server: join room yang ada
    -- Payload: roomId (string)
    JoinRoom         = R("JoinRoom"),

    -- Client → Server: keluar room sebelum start
    -- Payload: (tidak ada)
    LeaveRoom        = R("LeaveRoom"),

    -- Client → Server: player ready (sudah memilih level lewat vote)
    -- Payload: (tidak ada)
    PlayerReadyUp    = R("PlayerReadyUp"),

    -- ─── LEVEL VOTING ───────────────────────────────────────
    -- Client → Server: player memilih level di room
    -- Payload: votedLevel (number) — harus 1 ≤ level ≤ RoomInfo.maxLevel
    VoteForLevel     = R("VoteForLevel"),

    -- Server → semua Client di room: update hasil vote real-time
    -- Payload: Types.VoteResult { votes, winningLevel, timeRemaining }
    VoteResultUpdated = R("VoteResultUpdated"),

    -- ─── GAME START ─────────────────────────────────────────
    -- Server → semua Client di room: voting selesai, countdown teleport
    -- Payload: selectedLevel (number), gameMode (GameMode), countdown (number)
    -- Setelah countdown habis: Gilang fire TeleportAsync()
    StartingGame     = R("StartingGame"),

    -- ─── PLAYER PROGRESS ────────────────────────────────────
    -- Server → Client spesifik: kirim progress player saat join lobby
    -- Payload: Types.PlayerProgress { unlockedLevel, highestEndless }
    PlayerProgressLoaded = R("PlayerProgressLoaded"),
}

return RemoteEvents
