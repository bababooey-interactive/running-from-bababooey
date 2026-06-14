
-- =============================================================
--  RemoteEvents.luau  (LOBBY PLACE)
--  Akses semua RemoteEvent yang ada di Lobby.
--  Instance-nya didefinisikan di lobby/default.project.json.
--
--  Cara pakai:
--    local RE = require(game.ReplicatedStorage.Shared.RemoteEvents)
--    RE.CreateRoom:FireServer("HARD", "COOP")
--    RE.RoomListUpdated.OnClientEvent:Connect(function(rooms) ... end)
-- =============================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local function R(name: string): RemoteEvent
    return Remotes:WaitForChild(name) :: RemoteEvent
end

local RemoteEvents = {

    -- Server → semua Client: kirim daftar room yang tersedia
    -- Payload: { Types.RoomInfo } — array of room info
    RoomListUpdated  = R("RoomListUpdated"),

    -- Server → semua Client: update state room tertentu (siapa yang join, siapa ready)
    -- Payload: Types.RoomInfo
    RoomStateUpdated = R("RoomStateUpdated"),

    -- Client → Server: buat room baru
    -- Payload: difficulty (string), mode (string)
    CreateRoom       = R("CreateRoom"),

    -- Client → Server: join room yang sudah ada
    -- Payload: roomId (string)
    JoinRoom         = R("JoinRoom"),

    -- Client → Server: keluar dari room sebelum start
    -- Payload: (tidak ada)
    LeaveRoom        = R("LeaveRoom"),

    -- Client → Server: player ready
    -- Payload: (tidak ada)
    PlayerReadyUp    = R("PlayerReadyUp"),

    -- Server → semua Client di room: countdown dimulai, teleport incoming
    -- Payload: countdown (number) — detik sebelum teleport
    -- Setelah ini Gilang panggil TeleportService:TeleportAsync()
    StartingGame     = R("StartingGame"),
}

return RemoteEvents
