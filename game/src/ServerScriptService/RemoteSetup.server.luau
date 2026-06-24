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
	Remotes.Name = "Remotes"
	Remotes.Parent = ReplicatedStorage
end

local function ensureRemote(name: string)
	local existing = Remotes:FindFirstChild(name)
	if existing then
		return existing
	end
	local re = Instance.new("RemoteEvent")
	re.Name = name
	re.Parent = Remotes
	return re
end

-- Task system
ensureRemote("TaskProgress") -- server→all: counter update
ensureRemote("TaskInteract") -- client→server: player complete task
ensureRemote("GameWin") -- server→all: win event
ensureRemote("SyncState") -- server→client: late-join sync

-- Survival system
ensureRemote("HungerUpdate") -- server→client: hunger value
ensureRemote("DarkUpdate") -- server→client: dark timer + inDark
ensureRemote("PlayerDied") -- server→all: (name, cause)
ensureRemote("EatFood") -- client→server: food pickup

-- Monster / Sensor system
ensureRemote("MonsterPosition") -- server→all: monster pos + state
ensureRemote("PlayerMakeNoise") -- client→server: player made noise
ensureRemote("AwarenessUpdated") -- server→client: awareness level per player
ensureRemote("RulesActivated") -- server→all: active rules list
ensureRemote("MapGenerated") -- server→all: map grid data
ensureRemote("ReviveRequest") -- client→server: request revive
ensureRemote("PlayerRevived") -- server→all: player revived
ensureRemote("ConveyorStateChanged") -- server→all: conveyor on/off
ensureRemote("SurvivalUpdated") -- server→client: survival state
ensureRemote("PlayerInteractTask") -- client→server: interact with task
ensureRemote("TaskProgressUpdated") -- server→client: task progress
ensureRemote("LevelProgressSaved") -- server→client: level progress
ensureRemote("GameOver") -- server→all: game over
ensureRemote("LevelCleared") -- server→all: level cleared
ensureRemote("TeleportDataReceived") -- server→client: teleport data
-- Item Pickup System
ensureRemote("PickupItem")
ensureRemote("DropItem")
ensureRemote("DepositCoal")
ensureRemote("HeldItemChanged")
ensureRemote("CoalDeposited")
ensureRemote("HungerChanged")

print("[RemoteSetup] Semua RemoteEvent sudah siap di ReplicatedStorage.Remotes")
