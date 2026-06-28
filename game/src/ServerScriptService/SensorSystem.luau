-- =============================================================
--  SensorSystem.luau  (ModuleScript)
--  Path: game/src/ServerScriptService/SensorSystem.luau
--
--  Centralises all monster-perception logic:
--    • Noise store  — players and world events emit noise with TTL;
--                     AddNoise / AddAreaNoise / AddWorldNoise write it,
--                     CheckHearing reads it.
--    • Smell        — proximity check when MONSTER_SMELL is active.
--    • Vision       — cone + occlusion + lit-area check when
--                     MONSTER_SEE is active.
--    • Awareness    — 0-1 scalar sent to each player's HUD.
--
--  Light cache:
--    PointLights tagged "MapLights" are tracked via CollectionService
--    so IsPlayerInLight does not call GetTagged() every frame.
-- =============================================================

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Constants = require(game.ReplicatedStorage.Shared.Constants)

local SensorSystem = {}

-- ─────────────────────────────────────────────
--  CONSTANTS
-- ─────────────────────────────────────────────

local NOISE_LIFETIME = 1.2 -- seconds a noise event lives
local LIGHT_RANGE_BONUS = 1.3 -- extend each PointLight's range by this factor for vision checks
-- local SMELL_CHASE_THRESHOLD = 0.25 -- suspicion contribution cap per smell tick (used externally)
local WORLD_NOISE_MERGE_DIST = 10 -- studs: merge anonymous noise events closer than this

-- ─────────────────────────────────────────────
--  LIGHT CACHE
-- ─────────────────────────────────────────────

local activeLights: { PointLight } = {}

for _, light in ipairs(CollectionService:GetTagged("MapLights")) do
	table.insert(activeLights, light)
end

CollectionService:GetInstanceAddedSignal("MapLights"):Connect(function(light)
	table.insert(activeLights, light)
end)

CollectionService:GetInstanceRemovedSignal("MapLights"):Connect(function(light)
	local idx = table.find(activeLights, light)
	if idx then
		table.remove(activeLights, idx)
	end
end)

-- ─────────────────────────────────────────────
--  NOISE STORE
-- ─────────────────────────────────────────────

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RE_AwarenessUpdated = Remotes:WaitForChild("AwarenessUpdated")

type NoiseEvent = {
	player: Player?, -- nil = anonymous world noise (lever, boulder, …)
	position: Vector3,
	level: number, -- 0–1
	expireAt: number, -- os.clock() timestamp
}

local noiseEvents: { NoiseEvent } = {}

-- Remove expired entries (call before any noise read).
local function cleanNoise()
	local now = os.clock()
	for i = #noiseEvents, 1, -1 do
		if now >= noiseEvents[i].expireAt then
			table.remove(noiseEvents, i)
		end
	end
end

-- ─────────────────────────────────────────────
--  PUBLIC: AddNoise
--  Emit (or refresh) a noise event for a specific player.
--  If an event for this player already exists, keep the loudest level.
-- ─────────────────────────────────────────────
function SensorSystem.AddNoise(player: Player, position: Vector3, level: number)
	local clamped = math.clamp(level, 0, 1)
	local expireAt = os.clock() + NOISE_LIFETIME
	local emitted = clamped

	local found = false
	for _, event in ipairs(noiseEvents) do
		if event.player == player then
			event.position = position
			event.level = math.max(event.level, clamped)
			event.expireAt = expireAt
			emitted = event.level
			found = true
			break
		end
	end

	if not found then
		table.insert(noiseEvents, {
			player = player,
			position = position,
			level = clamped,
			expireAt = expireAt,
		})
	end

	-- Push the current noise level to the player's awareness HUD.
	RE_AwarenessUpdated:FireClient(player, nil, emitted)
end

-- ─────────────────────────────────────────────
--  PUBLIC: AddAreaNoise
--  Emit noise for every player within `radius` studs of `position`,
--  attenuated by distance (linear falloff).
-- ─────────────────────────────────────────────
function SensorSystem.AddAreaNoise(position: Vector3, level: number, radius: number)
	local clamped = math.clamp(level, 0, 1)

	for _, player in ipairs(Players:GetPlayers()) do
		local char = player.Character
		if not char then
			continue
		end
		local hrp = char:FindFirstChild("HumanoidRootPart")
		if not hrp then
			continue
		end

		local dist = (hrp.Position - position).Magnitude
		if dist > radius then
			continue
		end

		local attenuated = clamped * (1 - dist / radius)
		if attenuated > 0.05 then
			SensorSystem.AddNoise(player, position, attenuated)
		end
	end
end

-- ─────────────────────────────────────────────
--  PUBLIC: AddWorldNoise
--  Emit an anonymous noise event (player = nil) so the monster
--  investigates the position without knowing which player caused it.
--  Nearby duplicate world-noise events are merged (loudest wins).
-- ─────────────────────────────────────────────
function SensorSystem.AddWorldNoise(position: Vector3, level: number)
	local clamped = math.clamp(level, 0, 1)
	local expireAt = os.clock() + NOISE_LIFETIME

	for _, event in ipairs(noiseEvents) do
		if event.player == nil and (event.position - position).Magnitude < WORLD_NOISE_MERGE_DIST then
			if clamped > event.level then
				event.position = position
				event.level = clamped
				event.expireAt = expireAt
			end
			return
		end
	end

	table.insert(noiseEvents, {
		player = nil,
		position = position,
		level = clamped,
		expireAt = expireAt,
	})
end

-- ─────────────────────────────────────────────
--  PUBLIC: CheckHearing
--  Returns the loudest unexpired noise event within
--  MONSTER_HEAR_RADIUS, or nil if MONSTER_HEAR is inactive.
-- ─────────────────────────────────────────────
function SensorSystem.CheckHearing(monsterPos: Vector3, activeRules: { string }): NoiseEvent?
	if not table.find(activeRules, Constants.Rules.MONSTER_HEAR) then
		return nil
	end

	cleanNoise()

	local hearRadius = Constants.MONSTER_HEAR_RADIUS
	local best: NoiseEvent? = nil
	local bestScore = 0

	for _, event in ipairs(noiseEvents) do
		local dist = (monsterPos - event.position).Magnitude
		if dist > hearRadius then
			continue
		end

		local score = event.level * (1 - dist / hearRadius)
		if score > bestScore then
			bestScore = score
			best = event
		end
	end

	return best
end

-- ─────────────────────────────────────────────
--  PUBLIC: CheckSmell
--  Returns the closest player within MONSTER_SMELL_RADIUS,
--  or nil if MONSTER_SMELL is inactive.
-- ─────────────────────────────────────────────
function SensorSystem.CheckSmell(monsterPos: Vector3, players: { Player }, activeRules: { string }): Player?
	if not table.find(activeRules, Constants.Rules.MONSTER_SMELL) then
		return nil
	end

	local closest: Player? = nil
	local closestDist = Constants.MONSTER_SMELL_RADIUS

	for _, player in ipairs(players) do
		local char = player.Character
		if not char then
			continue
		end
		local hrp = char:FindFirstChild("HumanoidRootPart")
		if not hrp then
			continue
		end

		local dist = (monsterPos - hrp.Position).Magnitude
		if dist < closestDist then
			closestDist = dist
			closest = player
		end
	end

	return closest
end

-- ─────────────────────────────────────────────
--  PUBLIC: IsPlayerInLight
--  Returns true if `playerPos` falls inside any active tagged PointLight.
-- ─────────────────────────────────────────────
function SensorSystem.IsPlayerInLight(playerPos: Vector3): boolean
	for _, light in ipairs(activeLights) do
		if not (light:IsA("PointLight") and light.Enabled) then
			continue
		end
		local part = light.Parent
		if not part then
			continue
		end
		if (playerPos - part.Position).Magnitude <= light.Range * LIGHT_RANGE_BONUS then
			return true
		end
	end
	return false
end

-- ─────────────────────────────────────────────
--  PUBLIC: CheckVision
--  Returns the first player seen by the monster (cone + occlusion +
--  lit area), or nil if MONSTER_SEE is inactive.
-- ─────────────────────────────────────────────
function SensorSystem.CheckVision(
	monster: Model,
	monsterPos: Vector3,
	players: { Player },
	activeRules: { string }
): Player?
	if not table.find(activeRules, Constants.Rules.MONSTER_SEE) then
		return nil
	end

	local rootPart = monster:FindFirstChild("HumanoidRootPart") or monster:FindFirstChild("rb") or monster.PrimaryPart
	if not rootPart then
		return nil
	end

	local visionRange = Constants.MONSTER_VISION_RANGE
	local halfAngleCos = math.cos(math.rad(Constants.MONSTER_VISION_ANGLE))
	local forward = rootPart.CFrame.LookVector
	local eyePos = monsterPos + Vector3.new(0, 1.5, 0)

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude

	for _, player in ipairs(players) do
		local char = player.Character
		if not char then
			continue
		end
		local hrp = char:FindFirstChild("HumanoidRootPart")
		if not hrp then
			continue
		end

		local dir = hrp.Position - monsterPos
		local dist = dir.Magnitude
		if dist < 0.1 or dist > visionRange then
			continue
		end

		-- 1. Cone check
		if forward:Dot(dir.Unit) < halfAngleCos then
			continue
		end

		-- 2. Wall occlusion — any hit means blocked
		local headPos = hrp.Position + Vector3.new(0, 1.5, 0)
		rayParams.FilterDescendantsInstances = { monster, char }
		if workspace:Raycast(eyePos, headPos - eyePos, rayParams) then
			continue
		end

		-- 3. Player must be standing in light
		if not SensorSystem.IsPlayerInLight(hrp.Position) then
			continue
		end

		return player
	end

	return nil
end

-- ─────────────────────────────────────────────
--  PUBLIC: GetAwarenessForPlayer
--  Returns a 0-1 scalar representing how aware the monster is of
--  `player` right now (used by the client HUD awareness meter).
-- ─────────────────────────────────────────────
function SensorSystem.GetAwarenessForPlayer(
	monsterPos: Vector3,
	monster: Model,
	player: Player,
	activeRules: { string },
	isChasing: boolean,
	chaseTarget: Player?
): number
	-- Actively chasing this player → maximum awareness
	if isChasing and chaseTarget == player then
		return 1.0
	end

	local char = player.Character
	if not char then
		return 0
	end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return 0
	end

	local playerPos = hrp.Position
	local awareness = 0

	-- Hearing contribution
	if table.find(activeRules, Constants.Rules.MONSTER_HEAR) then
		cleanNoise()
		for _, event in ipairs(noiseEvents) do
			if event.player ~= player then
				continue
			end
			local dist = (monsterPos - event.position).Magnitude
			if dist <= Constants.MONSTER_HEAR_RADIUS then
				local contrib = event.level * (1 - dist / Constants.MONSTER_HEAR_RADIUS) * 0.85
				awareness = math.max(awareness, contrib)
			end
		end
	end

	-- Smell contribution
	if table.find(activeRules, Constants.Rules.MONSTER_SMELL) then
		local dist = (monsterPos - playerPos).Magnitude
		if dist <= Constants.MONSTER_SMELL_RADIUS then
			awareness = math.max(awareness, (1 - dist / Constants.MONSTER_SMELL_RADIUS) * 0.7)
		end
	end

	-- Vision contribution
	if table.find(activeRules, Constants.Rules.MONSTER_SEE) then
		local rootPart = monster:FindFirstChild("HumanoidRootPart")
			or monster:FindFirstChild("rb")
			or monster.PrimaryPart

		if rootPart then
			local eyePos = monsterPos + Vector3.new(0, 1.5, 0)
			local headPos = playerPos + Vector3.new(0, 1.5, 0)
			local dir = headPos - eyePos
			local dist = dir.Magnitude

			if dist >= 0.1 and dist <= Constants.MONSTER_VISION_RANGE then
				local cosA = rootPart.CFrame.LookVector:Dot(dir.Unit)
				local halfCos = math.cos(math.rad(Constants.MONSTER_VISION_ANGLE))

				if cosA >= halfCos then
					local rayParams = RaycastParams.new()
					rayParams.FilterType = Enum.RaycastFilterType.Exclude
					rayParams.FilterDescendantsInstances = { monster, char }

					local blocked = workspace:Raycast(eyePos, dir, rayParams)
					if not blocked then
						local inLight = SensorSystem.IsPlayerInLight(playerPos)
						-- Dimly visible even in shadow (5 % factor); full factor in light
						local lightFactor = inLight and 1 or 0.06
						local contrib = (1 - dist / Constants.MONSTER_VISION_RANGE) * cosA * lightFactor
						awareness = math.max(awareness, contrib)
					end
				end
			end
		end
	end

	return math.clamp(awareness, 0, 1)
end

-- ─────────────────────────────────────────────
--  PUBLIC: GetRecentNoiseForPlayer
--  Returns the highest decayed noise level for `player` in the store.
--  Used by the client HUD noise bar.
-- ─────────────────────────────────────────────
function SensorSystem.GetRecentNoiseForPlayer(player: Player): number
	cleanNoise()
	local now = os.clock()
	local highest = 0

	for _, event in ipairs(noiseEvents) do
		if event.player ~= player then
			continue
		end
		-- Linearly decay from full level down to 0 as the event ages.
		local age = 1 - (event.expireAt - now) / NOISE_LIFETIME -- 0 (fresh) → 1 (expiring)
		local decayed = event.level * (1 - age)
		highest = math.max(highest, decayed)
	end

	return highest
end

return SensorSystem
