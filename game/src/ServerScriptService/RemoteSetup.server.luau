-- =============================================================
--  RemoteSetup.luau
--  Buat semua RemoteEvent sekaligus — jalankan SEKALI dari server
--  Path: game/src/ServerScriptService/RemoteSetup.server.luau
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
    if existing then return existing end
    local re = Instance.new("RemoteEvent")
    re.Name   = name
    re.Parent = Remotes
    return re
end

-- Task system
ensureRemote("TaskProgress")   -- server→all: counter update
ensureRemote("TaskInteract")   -- client→server: player complete task
ensureRemote("GameWin")        -- server→all: win event
ensureRemote("SyncState")      -- server→client: late-join sync

-- Survival system
ensureRemote("HungerUpdate")   -- server→client: hunger value
ensureRemote("DarkUpdate")     -- server→client: dark timer + inDark
ensureRemote("PlayerDied")     -- server→all: (name, cause)
ensureRemote("EatFood")        -- client→server: food pickup

print("[RemoteSetup] Semua RemoteEvent sudah siap di ReplicatedStorage.Remotes")
