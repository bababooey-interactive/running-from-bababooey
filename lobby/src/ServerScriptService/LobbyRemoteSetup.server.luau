-- =============================================================
--  LobbyRemoteSetup.server.luau  (updated — adds plate remotes)
--  Path: lobby/src/ServerScriptService/LobbyRemoteSetup.server.luau
-- =============================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = ReplicatedStorage:FindFirstChild("Remotes")
if not Remotes then
	Remotes = Instance.new("Folder")
	Remotes.Name = "Remotes"
	Remotes.Parent = ReplicatedStorage
end

local function ensureRemote(name: string)
	if Remotes:FindFirstChild(name) then
		return
	end
	local re = Instance.new("RemoteEvent")
	re.Name = name
	re.Parent = Remotes
end

-- ─── Room List ──────────────────────────────────────────
ensureRemote("RoomListUpdated")
ensureRemote("RoomStateUpdated")

-- ─── Room Management ────────────────────────────────────
ensureRemote("CreateRoom")
ensureRemote("JoinRoom")
ensureRemote("LeaveRoom")
ensureRemote("PlayerReadyUp")

-- ─── Level Voting ───────────────────────────────────────
ensureRemote("VoteForLevel")
ensureRemote("VoteResultUpdated")

-- ─── Game Start ─────────────────────────────────────────
ensureRemote("StartingGame")

-- ─── Player Progress ────────────────────────────────────
ensureRemote("PlayerProgressLoaded")
ensureRemote("TeleportFailed")

-- ─── Plate Interaction ──────────────────────────────────
ensureRemote("EnterPlate") -- client→server: roomMode (string), index (number)
ensureRemote("LeavePlate") -- client→server: (no payload)
ensureRemote("PlateOccupied") -- server→all:   { [plateKey] = playerName }

print("[LobbyRemoteSetup] All lobby RemoteEvents ready.")
