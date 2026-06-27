-- =============================================================
--  SurvivalSystem.server.luau
--  Hunger bar + Darkness timer, activated based on active rules.
--  Path: game/src/ServerScriptService/SurvivalSystem.server.luau
--
--  Sound cues (via SoundManager.playAt at the player's world pos):
--    • DarkEnter   — first moment player steps into a dark zone
--    • DarkWarning — dark timer hits 10 s, then again at 5 s
--    • HungerWarning — hunger drops below 30, then below 10
--  Warning flags reset each time the player leaves darkness /
--  respawns, so re-entering a dark zone plays the entry sound again.
-- =============================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local SoundManager = require(script.Parent.SoundManager)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RE_HungerUpdate = Remotes:WaitForChild("HungerUpdate")
local RE_DarkUpdate = Remotes:WaitForChild("DarkUpdate")
local RE_PlayerDied = Remotes:WaitForChild("PlayerDied")
local RE_EatFood = Remotes:WaitForChild("EatFood")

-- ─────────────────────────────────────────────
--  Per-player survival state
-- ─────────────────────────────────────────────
type PlayerState = {
	hunger: number,
	darkTimer: number,
	inDark: boolean,
	alive: boolean,
	-- Sound tracking — reset on respawn / dark-exit
	prevInDark: boolean, -- detect the exact tick a player enters dark
	darkAt10: boolean, -- 10 s warning already played this dark visit
	darkAt5: boolean, -- 5 s warning already played this dark visit
	hungerAt30: boolean, -- 30 hunger warning already played this life
	hungerAt10: boolean, -- 10 hunger warning already played this life
}

local playerStates: { [number]: PlayerState } = {} -- [UserId] = state

local activeRules: { [string]: boolean } = {}

-- ─────────────────────────────────────────────
--  Helpers
-- ─────────────────────────────────────────────
local function getState(player: Player): PlayerState?
	return playerStates[player.UserId]
end

local function getCharacterPos(character: Model): Vector3?
	local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	return hrp and hrp.Position or nil
end

local function killPlayer(player: Player, cause: string)
	local state = getState(player)
	if not state or not state.alive then
		return
	end
	state.alive = false

	local character = player.Character
	if character then
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.Health = 0
		end
	end

	RE_PlayerDied:FireAllClients(player.Name, cause)
	print(string.format("[SurvivalSystem] %s died — cause: %s", player.Name, cause))
end

-- ─────────────────────────────────────────────
--  Darkness detection
--  DarkZone = BasePart with Attribute "IsDarkZone" = true
--  in the Workspace/DarkZones folder.
-- ─────────────────────────────────────────────
local darkZones: { BasePart } = {}

local function refreshDarkZones()
	darkZones = {}
	local folder = workspace:FindFirstChild("DarkZones")
	if not folder then
		return
	end
	for _, obj in ipairs(folder:GetDescendants()) do
		if obj:IsA("BasePart") and obj:GetAttribute("IsDarkZone") then
			table.insert(darkZones, obj)
		end
	end
end

local function isInDark(character: Model): boolean
	local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then
		return false
	end
	local pos = hrp.Position
	for _, zone in ipairs(darkZones) do
		local cf = zone.CFrame
		local sz = zone.Size / 2
		local rel = cf:PointToObjectSpace(pos)
		if math.abs(rel.X) <= sz.X and math.abs(rel.Y) <= sz.Y and math.abs(rel.Z) <= sz.Z then
			return true
		end
	end
	return false
end

-- ─────────────────────────────────────────────
--  Hunger: client fires EatFood on item pickup
-- ─────────────────────────────────────────────
RE_EatFood.OnServerEvent:Connect(function(player: Player)
	local state = getState(player)
	if not state or not state.alive then
		return
	end
	if not activeRules[Constants.Rules.PLAYER_HUNGER] then
		return
	end

	state.hunger = math.min(Constants.HUNGER_MAX, state.hunger + Constants.HUNGER_FOOD_REFILL)
	RE_HungerUpdate:FireClient(player, state.hunger)
	print(string.format("[SurvivalSystem] %s ate food — hunger: %.1f", player.Name, state.hunger))
end)

-- ─────────────────────────────────────────────
--  Main survival tick  (called roughly every second)
-- ─────────────────────────────────────────────
local function survivalTick(dt: number)
	for userId, state in pairs(playerStates) do
		if not state.alive then
			continue
		end

		local player = Players:GetPlayerByUserId(userId)
		if not player then
			continue
		end

		local character = player.Character
		if not character then
			continue
		end

		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if not humanoid or humanoid.Health <= 0 then
			state.alive = false
			continue
		end

		-- ── HUNGER ──────────────────────────────────────────────
		if activeRules[Constants.Rules.PLAYER_HUNGER] then
			state.hunger = math.max(0, state.hunger - Constants.HUNGER_DECAY_RATE * dt)
			RE_HungerUpdate:FireClient(player, state.hunger)

			-- Warning sounds at 30 % and 10 % thresholds
			local pos = getCharacterPos(character)
			if pos then
				if state.hunger <= 30 and not state.hungerAt30 then
					state.hungerAt30 = true
					SoundManager.hungerWarning(pos)
				end
				if state.hunger <= 10 and not state.hungerAt10 then
					state.hungerAt10 = true
					SoundManager.hungerWarning(pos)
				end
			end

			if state.hunger <= 0 then
				killPlayer(player, "hunger")
				continue
			end
		end

		-- ── DARKNESS TIMER ──────────────────────────────────────
		if activeRules[Constants.Rules.PLAYER_DARK_TIMER] then
			local inDark = isInDark(character)
			local pos = getCharacterPos(character)

			-- Detect dark zone entry (first tick the player is inside)
			if inDark and not state.prevInDark then
				if pos then
					SoundManager.darkEnter(pos)
				end
				-- Reset per-visit warning flags so they fire again next visit
				state.darkAt10 = false
				state.darkAt5 = false
			end

			-- Reset warning flags when leaving dark (so re-entry feels fresh)
			if not inDark and state.prevInDark then
				state.darkAt10 = false
				state.darkAt5 = false
			end

			state.prevInDark = inDark
			state.inDark = inDark

			if inDark then
				state.darkTimer = math.max(0, state.darkTimer - dt)

				-- Warning sounds at 10 s and 5 s remaining
				if pos then
					if state.darkTimer <= 10 and not state.darkAt10 then
						state.darkAt10 = true
						SoundManager.darkWarning(pos)
					end
					if state.darkTimer <= 5 and not state.darkAt5 then
						state.darkAt5 = true
						SoundManager.darkWarning(pos)
					end
				end
			else
				-- Fully restore timer when back in light
				state.darkTimer = Constants.DARK_TIMER_MAX
			end

			RE_DarkUpdate:FireClient(player, state.darkTimer, inDark)

			if state.darkTimer <= 0 then
				killPlayer(player, "darkness")
				continue
			end
		end
	end
end

-- ─────────────────────────────────────────────
--  Player lifecycle
-- ─────────────────────────────────────────────
local function freshSoundState(): { [string]: any }
	return {
		prevInDark = false,
		darkAt10 = false,
		darkAt5 = false,
		hungerAt30 = false,
		hungerAt10 = false,
	}
end

local function onPlayerAdded(player: Player)
	local soundState = freshSoundState()
	playerStates[player.UserId] = {
		hunger = Constants.HUNGER_MAX,
		darkTimer = Constants.DARK_TIMER_MAX,
		inDark = false,
		alive = true,
		-- sound tracking
		prevInDark = soundState.prevInDark,
		darkAt10 = soundState.darkAt10,
		darkAt5 = soundState.darkAt5,
		hungerAt30 = soundState.hungerAt30,
		hungerAt10 = soundState.hungerAt10,
	}

	player.CharacterAdded:Connect(function()
		local state = playerStates[player.UserId]
		if not state then
			return
		end

		state.hunger = Constants.HUNGER_MAX
		state.darkTimer = Constants.DARK_TIMER_MAX
		state.inDark = false
		state.alive = true
		-- Reset sound flags on respawn
		state.prevInDark = false
		state.darkAt10 = false
		state.darkAt5 = false
		state.hungerAt30 = false
		state.hungerAt10 = false

		if activeRules[Constants.Rules.PLAYER_HUNGER] then
			RE_HungerUpdate:FireClient(player, state.hunger)
		end
		if activeRules[Constants.Rules.PLAYER_DARK_TIMER] then
			RE_DarkUpdate:FireClient(player, state.darkTimer, false)
		end
	end)
end

local function onPlayerRemoving(player: Player)
	playerStates[player.UserId] = nil
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)
for _, p in ipairs(Players:GetPlayers()) do
	onPlayerAdded(p)
end

-- ─────────────────────────────────────────────
--  Public API
-- ─────────────────────────────────────────────
local SurvivalSystem = {}
local tickConnection: RBXScriptConnection? = nil

function SurvivalSystem.init(rules: { string })
	activeRules = {}
	for _, rule in ipairs(rules) do
		activeRules[rule] = true
	end

	for _, player in ipairs(Players:GetPlayers()) do
		local state = playerStates[player.UserId]
		if state then
			state.hunger = Constants.HUNGER_MAX
			state.darkTimer = Constants.DARK_TIMER_MAX
			state.inDark = false
			state.alive = true
			state.prevInDark = false
			state.darkAt10 = false
			state.darkAt5 = false
			state.hungerAt30 = false
			state.hungerAt10 = false
		end
	end

	refreshDarkZones()

	if tickConnection then
		tickConnection:Disconnect()
		tickConnection = nil
	end

	local needsTick = activeRules[Constants.Rules.PLAYER_HUNGER] or activeRules[Constants.Rules.PLAYER_DARK_TIMER]

	if needsTick then
		local accumulator = 0
		tickConnection = RunService.Heartbeat:Connect(function(dt)
			accumulator += dt
			if accumulator >= 1 then
				survivalTick(accumulator)
				accumulator = 0
			end
		end)
	end

	local ruleList = {}
	for r in pairs(activeRules) do
		table.insert(ruleList, r)
	end
	print("[SurvivalSystem] Init — active rules:", table.concat(ruleList, ", "))
end

function SurvivalSystem.stop()
	if tickConnection then
		tickConnection:Disconnect()
		tickConnection = nil
	end
	activeRules = {}
end

function SurvivalSystem.setPlayerInDark(player: Player, inDark: boolean)
	local state = getState(player)
	if state then
		state.inDark = inDark
	end
end

return SurvivalSystem
