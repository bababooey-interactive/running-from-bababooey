-- =============================================================
--  PlateManager.server.luau
--  Path: lobby/src/ServerScriptService/PlateManager.server.luau
--
--  WORKSPACE STRUCTURE:
--  Lobby/
--    Plates/
--      Solo/
--        Solo_1   (BasePart, Attribute: RoomMode="SOLO", Index=1)
--        Solo_2   (BasePart, Attribute: RoomMode="SOLO", Index=2)
--      Coop/
--        Coop_1   (BasePart, Attribute: RoomMode="COOP", Index=1)
--        Coop_2   (BasePart, Attribute: RoomMode="COOP", Index=2)
--
--  Each plate BasePart:
--    - Attribute "RoomMode" = "SOLO" | "COOP"
--    - Attribute "Index"    = number (1, 2, 3...)
--    - CanCollide = false (we handle it ourselves)
--    - Set Transparency ~0.5, whatever color you want
--
--  REMOTES (added to LobbyRemoteSetup.server.luau):
--    EnterPlate   client→server  payload: roomMode (string), index (number)
--    LeavePlate   client→server  (no payload, same as LeaveRoom)
--    PlateOccupied server→all    payload: { [plateKey]: playerName | nil }
-- =============================================================

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = ReplicatedStorage:WaitForChild("Remotes")

-- Ensure remotes exist (idempotent, same pattern as LobbyRemoteSetup)
local function ensureRemote(name: string): RemoteEvent
	local existing = Remotes:FindFirstChild(name)
	if existing then
		return existing :: RemoteEvent
	end
	local re = Instance.new("RemoteEvent")
	re.Name = name
	re.Parent = Remotes
	return re
end

local RE_EnterPlate = ensureRemote("EnterPlate") -- client→server
local RE_LeavePlate = ensureRemote("LeavePlate") -- client→server
local RE_PlateOccupied = ensureRemote("PlateOccupied") -- server→all

-- Also wire up to the existing LobbyRoomManager remotes
local RE_RoomStateUpdated = Remotes:WaitForChild("RoomStateUpdated") :: RemoteEvent
local RE_LeaveRoom = Remotes:WaitForChild("LeaveRoom") :: RemoteEvent

-- ============================================================
-- CONFIG
-- ============================================================

-- Y offset above the plate surface where the player stands
local STAND_Y_OFFSET = 6 -- studs above plate top face

-- ============================================================
-- STATE
-- ============================================================

-- plateKey = "SOLO_1", "COOP_1", etc.
-- occupation[plateKey] = Player | nil
local occupation: { [string]: Player } = {}

-- reverse lookup: which plate is each player on?
-- playerPlate[userId] = plateKey | nil
local playerPlate: { [number]: string } = {}

-- ============================================================
-- HELPERS
-- ============================================================

local function plateKey(roomMode: string, index: number): string
	return roomMode .. "_" .. index
end

local function findPlate(roomMode: string, index: number): BasePart?
	local lobby = Workspace:FindFirstChild("Lobby")
	if not lobby then
		return nil
	end
	local plates = lobby:FindFirstChild("Plates")
	if not plates then
		return nil
	end
	local folder = plates:FindFirstChild(roomMode == "SOLO" and "Solo" or "Coop")
	if not folder then
		return nil
	end

	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("BasePart") then
			local idx = child:GetAttribute("Index")
			if idx == index then
				return child
			end
		end
	end
	return nil
end

local function getStandPosition(plate: BasePart): Vector3
	-- Stand on top of the plate's bounding box
	local halfY = plate.Size.Y / 2
	return plate.Position + Vector3.new(0, halfY + STAND_Y_OFFSET, 0)
end

local function broadcastOccupation()
	-- Build a simple { plateKey = playerName } table for clients
	local snapshot: { [string]: string } = {}
	for key, player in pairs(occupation) do
		if player and player.Parent then
			snapshot[key] = player.Name
		end
	end
	RE_PlateOccupied:FireAllClients(snapshot)
end

local function vacatePlate(player: Player)
	local key = playerPlate[player.UserId]
	if not key then
		return
	end

	if occupation[key] == player then
		occupation[key] = nil
	end
	playerPlate[player.UserId] = nil

	broadcastOccupation()

	-- Tell LobbyRoomManager the player left their room
	RE_LeaveRoom:FireServer()
end

-- ============================================================
-- ENTER PLATE
-- ============================================================

RE_EnterPlate.OnServerEvent:Connect(function(player: Player, roomMode: string, index: number)
	-- Validate inputs
	if roomMode ~= "SOLO" and roomMode ~= "COOP" then
		return
	end
	if type(index) ~= "number" then
		return
	end

	local plate = findPlate(roomMode, index)
	if not plate then
		warn(("[PlateManager] Plate not found: %s #%d"):format(roomMode, index))
		return
	end

	local key = plateKey(roomMode, index)

	-- If already on a plate, vacate first
	if playerPlate[player.UserId] then
		local oldKey = playerPlate[player.UserId]
		if occupation[oldKey] == player then
			occupation[oldKey] = nil
		end
		playerPlate[player.UserId] = nil
	end

	-- For COOP plates: allow multiple players (no occupation lock)
	-- For SOLO plates: one player per plate slot
	if roomMode == "SOLO" then
		local occupant = occupation[key]
		if occupant and occupant.Parent ~= nil and occupant ~= player then
			-- Plate taken — find a free solo plate or bounce the player
			warn(("[PlateManager] Solo plate %s taken by %s"):format(key, occupant.Name))
			return
		end
	end

	-- Teleport character to stand position
	local character = player.Character
	if not character then
		return
	end

	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end

	local standPos = getStandPosition(plate)
	-- Face the center of the lobby (roughly) — rotate toward -Z
	local lookTarget = standPos + Vector3.new(0, 0, -10)
	character:PivotTo(CFrame.lookAt(standPos, lookTarget))

	-- Register occupation
	occupation[key] = player
	playerPlate[player.UserId] = key

	broadcastOccupation()

	print(("[PlateManager] %s entered %s plate #%d"):format(player.Name, roomMode, index))

	-- Fire RoomStateUpdated so LevelSelectUI opens
	-- (RoomMode, index, maxLevel) — LobbyRoomManager fills the rest
	-- We send a minimal stub; LobbyRoomManager's plate Touched handler
	-- fired the full RoomStateUpdated before, now we replicate that here.
	RE_RoomStateUpdated:FireClient(player, {
		id = key,
		hostName = player.Name,
		gameMode = "REGULAR",
		roomMode = roomMode,
		selectedLevel = 1,
		maxLevel = 10, -- LobbyRoomManager will override with real progress
		playerCount = 1,
		maxPlayers = roomMode == "SOLO" and 1 or 8,
		readyCount = 0,
	})
end)

-- ============================================================
-- LEAVE PLATE
-- ============================================================

RE_LeavePlate.OnServerEvent:Connect(function(player: Player)
	vacatePlate(player)
end)

-- ============================================================
-- CLEANUP
-- ============================================================

Players.PlayerRemoving:Connect(function(player: Player)
	vacatePlate(player)
end)

Players.PlayerAdded:Connect(function(player: Player)
	player.CharacterRemoving:Connect(function()
		-- Vacate if they die / reset while on a plate
		if playerPlate[player.UserId] then
			local key = playerPlate[player.UserId]
			if occupation[key] == player then
				occupation[key] = nil
			end
			playerPlate[player.UserId] = nil
			broadcastOccupation()
		end
	end)
end)

for _, player in ipairs(Players:GetPlayers()) do
	player.CharacterRemoving:Connect(function()
		if playerPlate[player.UserId] then
			local key = playerPlate[player.UserId]
			if occupation[key] == player then
				occupation[key] = nil
			end
			playerPlate[player.UserId] = nil
			broadcastOccupation()
		end
	end)
end

print("[PlateManager] Initialized.")
