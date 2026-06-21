-- =============================================================
--  LobbyRemoteSetup.server.luau
--  Buat semua RemoteEvent lobby sekaligus — jalankan SEKALI dari server
--  Path: lobby/src/ServerScriptService/LobbyRemoteSetup.server.luau
--
--  Pola sama persis dengan RemoteSetup.server.luau yang ada di Game
--  Place — supaya konsisten. Daftar nama remote di sini HARUS sama
--  dengan yang dipakai RemoteEvents.luau (ReplicatedStorage.Shared
--  atau lobby/src/ReplicatedStorage/Remotes, sesuaikan kalau beda).
--
--  PENTING: script ini HARUS jalan & selesai SEBELUM LobbyRoomManager
--  dan LevelSelectUI memanggil WaitForChild("Remotes"). Default Studio
--  menjalankan script di ServerScriptService secara concurrent (semua
--  langsung start bersamaan, BUKAN alfabetis terurut), jadi:
--  - Script lain pakai ReplicatedStorage:WaitForChild("Remotes") tetap
--    AMAN walau LobbyRemoteSetup belum selesai — WaitForChild akan
--    nunggu sampai folder ini dibuat, bukan langsung error.
--  - Yang TIDAK aman adalah kalau script lain pakai dot notation
--    langsung (ReplicatedStorage.Remotes.Xxx) tanpa WaitForChild,
--    itu bisa race condition. Pastikan semua script pemakai Remotes
--    pakai WaitForChild, bukan dot notation langsung.
-- =============================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Pastikan folder Remotes ada
local Remotes = ReplicatedStorage:FindFirstChild("Remotes")
if not Remotes then
    Remotes = Instance.new("Folder")
    Remotes.Name   = "Remotes"
    Remotes.Parent = ReplicatedStorage
end

local function ensureRemote(name: string)
    local existing = Remotes:FindFirstChild(name)
    if existing then
        return existing
    end
    local re = Instance.new("RemoteEvent")
    re.Name   = name
    re.Parent = Remotes
    return re
end

-- ─── Room List ──────────────────────────────────────────
ensureRemote("RoomListUpdated")      -- server→all: daftar room yang tersedia
ensureRemote("RoomStateUpdated")     -- server→client di room: state room berubah

-- ─── Room Management ────────────────────────────────────
ensureRemote("CreateRoom")           -- client→server: buat room baru
ensureRemote("JoinRoom")             -- client→server: join room yang ada
ensureRemote("LeaveRoom")            -- client→server: keluar room sebelum start
ensureRemote("PlayerReadyUp")        -- client→server: player ready

-- ─── Level Voting ───────────────────────────────────────
ensureRemote("VoteForLevel")         -- client→server: player memilih level
ensureRemote("VoteResultUpdated")    -- server→client di room: hasil vote real-time

-- ─── Game Start ─────────────────────────────────────────
ensureRemote("StartingGame")         -- server→client di room: countdown teleport

-- ─── Player Progress ────────────────────────────────────
ensureRemote("PlayerProgressLoaded") -- server→client spesifik: progress player

print("[LobbyRemoteSetup] Semua RemoteEvent lobby sudah siap di ReplicatedStorage.Remotes")
