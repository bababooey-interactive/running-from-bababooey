-- =============================================================
--  SensorSystem.luau  (ModuleScript — Day 4-7, COMPLETE)
--  Day 7 additions: real vision raycast + IsPlayerInLight
-- =============================================================

local Constants = require(game.ReplicatedStorage.Shared.Constants)

local SensorSystem = {}

-- ─── Noise Store ──────────────────────────────────────────────

type NoiseEvent = {
	player   : Player,
	position : Vector3,
	level    : number,
	expireAt : number,
}

local noiseEvents : {NoiseEvent} = {}
local NOISE_LIFETIME = 3.5

function SensorSystem.AddNoise(player : Player, position : Vector3, level : number)
	table.insert(noiseEvents, {
		player   = player,
		position = position,
		level    = math.clamp(level, 0, 1),
		expireAt = os.clock() + NOISE_LIFETIME,
	})
end

local function cleanNoise()
	local now = os.clock()
	for i = #noiseEvents, 1, -1 do
		if now >= noiseEvents[i].expireAt then table.remove(noiseEvents, i) end
	end
end

-- ─── Hearing ──────────────────────────────────────────────────

function SensorSystem.CheckHearing(monsterPos : Vector3, activeRules : {string}) : NoiseEvent?
	if not table.find(activeRules, Constants.Rules.MONSTER_HEAR) then return nil end
	cleanNoise()
	local hearRadius = Constants.MONSTER_HEAR_RADIUS
	local best : NoiseEvent? = nil
	local bestScore = 0
	for _, event in ipairs(noiseEvents) do
		local dist = (monsterPos - event.position).Magnitude
		if dist <= hearRadius then
			local score = event.level * (1 - dist / hearRadius)
			if score > bestScore then bestScore = score; best = event end
		end
	end
	return best
end

-- ─── Smell (Day 7 — real implementation) ─────────────────────

function SensorSystem.CheckSmell(
	monsterPos  : Vector3,
	players     : {Player},
	activeRules : {string}
) : Player?

	if not table.find(activeRules, Constants.Rules.MONSTER_SMELL) then return nil end
	local closest : Player? = nil
	local closestDist = Constants.MONSTER_SMELL_RADIUS
	for _, player in ipairs(players) do
		local char = player.Character
		if not char then continue end
		local hrp = char:FindFirstChild("HumanoidRootPart")
		if not hrp then continue end
		local dist = (monsterPos - hrp.Position).Magnitude
		if dist < closestDist then closestDist = dist; closest = player end
	end
	return closest
end

-- ─── Lit-area check (Day 7) ───────────────────────────────────
-- Player dianggap "in light" kalau dekat PointLight yang cukup terang,
-- OR kalau global ambient sangat terang (game terlalu terang).

function SensorSystem.IsPlayerInLight(position : Vector3) : boolean
	-- Cek semua PointLight aktif di workspace
	for _, desc in ipairs(workspace:GetDescendants()) do
		if not desc:IsA("PointLight") then continue end
		local parent = desc.Parent
		if not parent or not parent:IsA("BasePart") then continue end
		if not desc.Enabled or desc.Brightness < 0.3 then continue end
		local dist = (position - parent.Position).Magnitude
		-- Player lit kalau dalam 65% dari range light
		if dist < desc.Range * 0.65 then return true end
	end
	-- Fallback: cek ambient global (gelap = tidak lit)
	local amb = game.Lighting.Ambient
	local avgBrightness = (amb.R + amb.G + amb.B) / 3
	return avgBrightness > 0.45
end

-- ─── Vision (Day 7 — full raycast + lit area) ─────────────────

function SensorSystem.CheckVision(
	monster     : Model,
	monsterPos  : Vector3,
	players     : {Player},
	activeRules : {string}
) : Player?

	if not table.find(activeRules, Constants.Rules.MONSTER_SEE) then return nil end

	local rootPart = monster:FindFirstChild("HumanoidRootPart")
		or monster:FindFirstChild("rb")
		or monster.PrimaryPart
	if not rootPart then return nil end

	local visionRange  = Constants.MONSTER_VISION_RANGE
	local halfAngleCos = math.cos(math.rad(Constants.MONSTER_VISION_ANGLE))
	local forward      = rootPart.CFrame.LookVector
	local eyePos       = monsterPos + Vector3.new(0, 1.5, 0)   -- monster eye height

	-- Raycast param: exclude monster model itself
	local rayParams = RaycastParams.new()
	rayParams.FilterDescendantsInstances = {monster}
	rayParams.FilterType = Enum.RaycastFilterType.Exclude

	for _, player in ipairs(players) do
		local char = player.Character
		if not char then continue end
		local hrp = char:FindFirstChild("HumanoidRootPart")
		if not hrp then continue end

		local dir  = hrp.Position - monsterPos
		local dist = dir.Magnitude
		if dist < 0.1 or dist > visionRange then continue end

		-- ── 1. Cone check ─────────────────────────────────────
		if forward:Dot(dir.Unit) < halfAngleCos then continue end

		-- ── 2. Occlusion raycast ──────────────────────────────
		-- Cast from monster eye toward player head
		local playerHeadPos = hrp.Position + Vector3.new(0, 1.5, 0)
		local rayDir = playerHeadPos - eyePos

		-- Temporarily exclude player char from filter so ray CAN hit other things
		local result = workspace:Raycast(eyePos, rayDir, rayParams)

		-- If ray hit something that is NOT the player → blocked
		if result and not result.Instance:IsDescendantOf(char) then
			continue
		end

		-- ── 3. Player must be in lit area ─────────────────────
		if not SensorSystem.IsPlayerInLight(hrp.Position) then continue end

		return player
	end
	return nil
end

-- ─── Awareness level for UI ───────────────────────────────────

function SensorSystem.GetAwarenessForPlayer(
	monsterPos  : Vector3,
	monster     : Model,
	player      : Player,
	activeRules : {string},
	isChasing   : boolean,
	chaseTarget : Player?
) : number

	local char = player.Character
	if not char then return 0 end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then return 0 end

	if isChasing and chaseTarget == player then return 1.0 end

	local playerPos = hrp.Position
	local awareness = 0

	if table.find(activeRules, Constants.Rules.MONSTER_HEAR) then
		cleanNoise()
		for _, event in ipairs(noiseEvents) do
			if event.player ~= player then continue end
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
		local rp = monster:FindFirstChild("HumanoidRootPart")
			or monster:FindFirstChild("rb")
			or monster.PrimaryPart
		if rp then
			local dir  = playerPos - monsterPos
			local dist = dir.Magnitude
			if dist >= 0.1 and dist <= Constants.MONSTER_VISION_RANGE then
				local cosA = rp.CFrame.LookVector:Dot(dir.Unit)
				local half = math.cos(math.rad(Constants.MONSTER_VISION_ANGLE))
				if cosA >= half then
					local inLight = SensorSystem.IsPlayerInLight(playerPos)
					local contrib = inLight
						and (1 - dist / Constants.MONSTER_VISION_RANGE) * cosA
						or  (1 - dist / Constants.MONSTER_VISION_RANGE) * cosA * 0.2
					awareness = math.max(awareness, contrib)
				end
			end
		end
	end

	return math.clamp(awareness, 0, 1)
end

function SensorSystem.GetRecentNoiseForPlayer(player : Player) : number
	cleanNoise()
	local highest = 0
	for _, event in ipairs(noiseEvents) do
		if event.player == player then
			highest = math.max(highest, event.level)
		end
	end
	return highest
end

return SensorSystem
