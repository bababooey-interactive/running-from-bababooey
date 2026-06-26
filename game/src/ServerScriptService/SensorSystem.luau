-- =============================================================
--  SensorSystem.luau
-- =============================================================

local CollectionService = game:GetService("CollectionService")
local Constants = require(game.ReplicatedStorage.Shared.Constants)

local SensorSystem = {}

-- ─── LIGHT CACHING SYSTEM ──────────────────────────────────────
local activeLights = {}

-- 1. Grab all existing lights right now
for _, light in ipairs(CollectionService:GetTagged("MapLights")) do
	table.insert(activeLights, light)
end

-- 2. Listen for any new lights spawned by MapGenerator later
CollectionService:GetInstanceAddedSignal("MapLights"):Connect(function(light)
	table.insert(activeLights, light)
end)

-- 3. Remove lights from our list if they are destroyed (e.g., a breaker trips)
CollectionService:GetInstanceRemovedSignal("MapLights"):Connect(function(light)
	local index = table.find(activeLights, light)
	if index then
		table.remove(activeLights, index)
	end
end)
-- ───────────────────────────────────────────────────────────────

-- ─── Noise Store ──────────────────────────────────────────────

type NoiseEvent = {
	player: Player?, -- nil for anonymous/world noise (lever, boulder, etc.)
	position: Vector3,
	level: number,
	expireAt: number,
}

local noiseEvents: { NoiseEvent } = {}
local NOISE_LIFETIME = 1.2

function SensorSystem.AddNoise(player: Player, position: Vector3, level: number)
	local clamped = math.clamp(level, 0, 1)
	local expireAt = os.clock() + NOISE_LIFETIME

	-- Replace existing event for this player if one exists
	for _, event in ipairs(noiseEvents) do
		if event.player == player then
			event.position = position
			event.level = math.max(event.level, clamped) -- keep loudest
			event.expireAt = expireAt
			return
		end
	end

	-- No existing event, insert fresh
	table.insert(noiseEvents, {
		player = player,
		position = position,
		level = clamped,
		expireAt = expireAt,
	})
end

-- ─── Area Noise ──────────────────────────────────────────────
-- Creates noise events for ALL players within `radius` of `position`.
-- Closer players get higher noise (linear falloff).
-- Used for loud world events like lever pulls, item drops, etc.

function SensorSystem.AddAreaNoise(position: Vector3, level: number, radius: number)
	local Players = game:GetService("Players")
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
		if dist <= radius then
			local distanceFactor = 1 - (dist / radius)
			local noiseLevel = clamped * distanceFactor
			if noiseLevel > 0.05 then
				SensorSystem.AddNoise(player, position, noiseLevel)
			end
		end
	end
end

-- ─── World Noise (anonymous) ──────────────────────────────────
-- Creates an anonymous noise event (player = nil) for world events
-- like lever pulls, boulder landings, item drops.
-- The monster hears the sound but doesn't know WHO made it —
-- it will INVESTIGATE the position instead of chasing a player.

function SensorSystem.AddWorldNoise(position: Vector3, level: number)
	local clamped = math.clamp(level, 0, 1)
	local expireAt = os.clock() + NOISE_LIFETIME

	-- Replace existing world noise if one is nearby (within 10 studs)
	for _, event in ipairs(noiseEvents) do
		if event.player == nil then
			if (event.position - position).Magnitude < 10 then
				if clamped > event.level then
					event.position = position
					event.level = clamped
					event.expireAt = expireAt
				end
				return
			end
		end
	end

	table.insert(noiseEvents, {
		player = nil,
		position = position,
		level = clamped,
		expireAt = expireAt,
	})
end

local function cleanNoise()
	local now = os.clock()
	for i = #noiseEvents, 1, -1 do
		if now >= noiseEvents[i].expireAt then
			table.remove(noiseEvents, i)
		end
	end
end

-- ─── Hearing ──────────────────────────────────────────────────

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
		if dist <= hearRadius then
			local score = event.level * (1 - dist / hearRadius)
			if score > bestScore then
				bestScore = score
				best = event
			end
		end
	end
	return best
end

-- ─── Smell ─────────────────────

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

-- ─── Lit-area check ───────────────────────────────────
-- Player dianggap "in light" kalau dekat PointLight yang cukup terang,
-- OR kalau global ambient sangat terang (game terlalu terang).

function SensorSystem.IsPlayerInLight(playerPos: Vector3): boolean
	-- INSTEAD OF THIS: for _, light in ipairs(CollectionService:GetTagged("MapLights")) do
	-- WE USE OUR CACHE:
	for _, light in ipairs(activeLights) do
		-- Make sure the light actually exists and is turned on
		if light:IsA("PointLight") and light.Enabled then
			local lightPart = light.Parent
			if lightPart then
				local dist = (playerPos - lightPart.Position).Magnitude

				-- If the player is inside the light's radius, they are visible!
				if dist <= light.Range * 1.25 then -- 25% further reach
					return true
				end
			end
		end
	end

	return false
end

-- ─── Vision ─────────────────

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
	local eyePos = monsterPos + Vector3.new(0, 1.5, 0) -- monster eye height

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

		-- ── 1. Cone check ─────────────────────────────────────
		if forward:Dot(dir.Unit) < halfAngleCos then
			continue
		end

		-- ── 2. Occlusion raycast (WALL CHECK) ─────────────────
		local playerHeadPos = hrp.Position + Vector3.new(0, 1.5, 0)
		local rayDir = playerHeadPos - eyePos

		-- Ignore BOTH the monster and the player.
		-- If the ray hits anything now, it MUST be a wall/obstacle.
		rayParams.FilterDescendantsInstances = { monster, char }

		local blocked = workspace:Raycast(eyePos, rayDir, rayParams)
		if blocked then
			continue -- Wall detected!
		end

		-- ── 3. Player must be in lit area ─────────────────────
		if not SensorSystem.IsPlayerInLight(hrp.Position) then
			continue
		end

		return player
	end
	return nil
end

-- ─── Awareness level for UI ───────────────────────────────────

function SensorSystem.GetAwarenessForPlayer(
	monsterPos: Vector3,
	monster: Model,
	player: Player,
	activeRules: { string },
	isChasing: boolean,
	chaseTarget: Player?
): number
	local char = player.Character
	if not char then
		return 0
	end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return 0
	end

	if isChasing and chaseTarget == player then
		return 1.0
	end

	local playerPos = hrp.Position
	local awareness = 0

	if table.find(activeRules, Constants.Rules.MONSTER_HEAR) then
		cleanNoise()
		for _, event in ipairs(noiseEvents) do
			if event.player ~= player then
				continue
			end
			local dist = (monsterPos - event.position).Magnitude
			if dist <= Constants.MONSTER_HEAR_RADIUS then
				local c = event.level * (1 - dist / Constants.MONSTER_HEAR_RADIUS) * 0.85
				awareness = math.max(awareness, c)
			end
		end
	end

	if table.find(activeRules, Constants.Rules.MONSTER_SMELL) then
		local dist = (monsterPos - playerPos).Magnitude
		if dist <= Constants.MONSTER_SMELL_RADIUS then
			awareness = math.max(awareness, (1 - dist / Constants.MONSTER_SMELL_RADIUS) * 0.7)
		end
	end

	if table.find(activeRules, Constants.Rules.MONSTER_SEE) then
		local rp = monster:FindFirstChild("HumanoidRootPart") or monster:FindFirstChild("rb") or monster.PrimaryPart
		if rp then
			local eyePos = monsterPos + Vector3.new(0, 1.5, 0)
			local playerHeadPos = hrp.Position + Vector3.new(0, 1.5, 0)
			local dir = playerHeadPos - eyePos
			local dist = dir.Magnitude

			if dist >= 0.1 and dist <= Constants.MONSTER_VISION_RANGE then
				local cosA = rp.CFrame.LookVector:Dot(dir.Unit)
				local half = math.cos(math.rad(Constants.MONSTER_VISION_ANGLE))

				if cosA >= half then
					-- WALL CHECK for the Awareness UI
					local rayParams = RaycastParams.new()
					rayParams.FilterType = Enum.RaycastFilterType.Exclude
					rayParams.FilterDescendantsInstances = { monster, char }

					local blocked = workspace:Raycast(eyePos, dir, rayParams)

					if not blocked then
						local inLight = SensorSystem.IsPlayerInLight(playerPos)
						local contrib = inLight and (1 - dist / Constants.MONSTER_VISION_RANGE) * cosA
							or (1 - dist / Constants.MONSTER_VISION_RANGE) * cosA * 0.05
						awareness = math.max(awareness, contrib)
					end
				end
			end
		end
	end

	return math.clamp(awareness, 0, 1)
end

function SensorSystem.GetRecentNoiseForPlayer(player: Player): number
	cleanNoise()
	local now = os.clock()
	local highest = 0
	for _, event in ipairs(noiseEvents) do
		if event.player == player then
			-- fade out as the event approaches expiry
			local age = 1 - ((event.expireAt - now) / NOISE_LIFETIME)
			local decayed = event.level * (1 - age)
			highest = math.max(highest, decayed)
		end
	end
	return highest
end

return SensorSystem
