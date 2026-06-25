-- =============================================================
--  MonsterAI.server.luau
-- =============================================================

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Constants)
local SensorSystem = require(script.Parent.SensorSystem)
local SoundManager = require(script.Parent.SoundManager)
local DuplicationSystem = require(script.Parent.DuplicationSystem)

-- ── Remote Events ─────────────────────────────────────────────
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RE = {
	PlayerMakeNoise = Remotes:WaitForChild("PlayerMakeNoise"),
	PlayerDied = Remotes:WaitForChild("PlayerDied"),
	MonsterPosition = Remotes:WaitForChild("MonsterPosition"),
	AwarenessUpdated = Remotes:WaitForChild("AwarenessUpdated"),
}
DuplicationSystem.init(RE.PlayerDied)

-- ── Monster Setup ─────────────────────────────────────────────
-- OPTION A (current): monster pre-placed in Workspace
-- local monster = workspace:WaitForChild("SoulDragger")

-- OPTION B (recommended after reorganization):
local monster = game:GetService("ServerStorage"):WaitForChild("Characters"):WaitForChild("SoulDragger"):Clone()
monster.Parent = workspace

for _, part in ipairs(monster:GetDescendants()) do
	if part:IsA("BasePart") then
		part.CanCollide = false
		part.CanQuery = false
		part.Anchored = false
	end
end

local rootPart = monster:FindFirstChild("HumanoidRootPart") or monster:FindFirstChild("rb") or monster.PrimaryPart
assert(rootPart, "[MonsterAI] SoulDragger needs a HumanoidRootPart or part named 'rb'")
rootPart.Anchored = true
monster.PrimaryPart = rootPart

local sounds = SoundManager.new(monster)

-- ── Constants ─────────────────────────────────────────────────
-- TILE must equal MapGenerator's local TILE_SIZE (currently 16).
-- If Gilang changes his TILE_SIZE value, update this to match.

local TILE = Constants.TILE_SIZE -- 8 (BUKAN 16 lagi)

-- How high the monster's pivot sits above the tile floor (Y=0 center).
-- Tile floor is 1 stud thick → top at Y=0.5.
-- Increase MONSTER_Y if the monster sinks, decrease if it floats.
local MONSTER_Y = 0

-- ── Animation ─────────────────────────────────────────────────
local humanoid = monster:FindFirstChildOfClass("Humanoid")
local animator: Animator?
if humanoid then
	animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator", humanoid)
end

local tracks: { [string]: AnimationTrack } = {}
local animIDs = {
	Walk = "rbxassetid://90825719838414",
	Run = "rbxassetid://75452347275172",
	Spotted = "rbxassetid://91571146490557",
	Jumpscare = "rbxassetid://79583022426609",
}
if animator then
	for name, id in pairs(animIDs) do
		local anim = Instance.new("Animation")
		anim.AnimationId = id
		local track = animator:LoadAnimation(anim)
		track.Priority = (name == "Spotted" or name == "Jumpscare") and Enum.AnimationPriority.Action
			or Enum.AnimationPriority.Movement
		tracks[name] = track
	end
end

local currentMovement = ""

local function playMovement(name: string)
	if currentMovement == name then
		return
	end
	currentMovement = name
	for n, t in pairs(tracks) do
		if t.Priority == Enum.AnimationPriority.Movement and n ~= name and t.IsPlaying then
			t:Stop(0.2)
		end
	end
	if tracks[name] then
		tracks[name].Looped = true
		tracks[name]:Play(0.2)
	end
end

local function playAction(name: string)
	for _, t in pairs(tracks) do
		if t.Priority == Enum.AnimationPriority.Action and t.IsPlaying then
			t:Stop(0.1)
		end
	end
	if tracks[name] then
		tracks[name].Looped = false
		tracks[name]:Play(0.1)
	end
end

-- ── Grid & Tile Helpers ───────────────────────────────────────
--
-- Coordinate system MATCHES MapGenerator.server.luau:
--   gridToWorld(col, row)  =  Vector3( (col-1)*16,  0, (row-1)*16 )
--   so  col=1,row=1  →  world (0,  0, 0)
--       col=2,row=3  →  world (16, 0, 32)
--
-- Round-trip check:
--   tileToWorld(2,3)  =  (16, Y, 32)
--   worldToTile(16,Y,32)  =  round(16/16)+1, round(32/16)+1  =  2, 3  ✓

local grid: { { number } } = {}
local gridReady = false

local function tileToWorld(col: number, row: number): Vector3
	return Vector3.new((col - 1) * TILE, MONSTER_Y, (row - 1) * TILE)
end

local function worldToTile(pos: Vector3): (number, number)
	local COLS = grid[1] and #grid[1] or 15
	local ROWS = #grid > 0 and #grid or 18
	local col = math.clamp(math.round(pos.X / TILE) + 1, 1, COLS)
	local row = math.clamp(math.round(pos.Z / TILE) + 1, 1, ROWS)
	return col, row
end

local function isTileWalkable(col: number, row: number): boolean
	if not grid[row] then
		return false
	end
	local t = grid[row][col]
	return t ~= nil and t ~= 0 -- 0 = WALL; everything else is walkable
end

-- ── Spawn in Arc ──────────────────────────────────────────────

local function spawnAtArc(playerSpawnWorld: Vector3, radiusTiles: number)
	local COLS = grid[1] and #grid[1] or 15
	local ROWS = #grid > 0 and #grid or 18
	local cCol = math.round(playerSpawnWorld.X / TILE) + 1
	local cRow = math.round(playerSpawnWorld.Z / TILE) + 1

	for _ = 1, 60 do
		local angle = math.rad(math.random(0, 359))
		local r = radiusTiles + math.random(-2, 2)
		local col = math.clamp(math.round(cCol + math.cos(angle) * r), 1, COLS)
		local row = math.clamp(math.round(cRow + math.sin(angle) * r), 1, ROWS)
		if isTileWalkable(col, row) then
			monster:PivotTo(CFrame.new(tileToWorld(col, row)))
			print(("[MonsterAI] Spawned at tile (%d,%d)"):format(col, row))
			return
		end
	end
	-- Fallback: opposite side of spawn
	local fb = Vector3.new(playerSpawnWorld.X + radiusTiles * TILE, MONSTER_Y, playerSpawnWorld.Z)
	monster:PivotTo(CFrame.new(fb))
	warn("[MonsterAI] Arc spawn failed — used fallback")
end

-- ── State Machine ─────────────────────────────────────────────

type MonsterState = "IDLE" | "CHASE" | "CATCH"

local state: MonsterState = "IDLE"
local activeRules: { string } = {}
local chaseTarget: Player? = nil

local lostTimer = 0
local idleTarget: Vector3? = nil
local spotPlayedFor: Player? = nil

local LOST_TIME = 5
local IDLE_RANGE = 5 -- tiles

-- beginChase ──────────────────────────────────────────────────
local function beginChase(player: Player)
	if chaseTarget ~= player then
		chaseTarget = player
		playMovement("Run")

		if spotPlayedFor ~= player then
			spotPlayedFor = player

			-- Stagger the action animation slightly to prevent the Animator T-Pose glitch
			task.spawn(function()
				task.wait(0.05)
				playAction("Spotted")
			end)
		end
	end
	lostTimer = LOST_TIME
	state = "CHASE"
	sounds:onStateChange("CHASE", true)
end

-- beginIdle ───────────────────────────────────────────────────
local function beginIdle()
	state = "IDLE"
	chaseTarget = nil
	idleTarget = nil
	playMovement("Walk")
	sounds:onStateChange("IDLE", false)
end

-- ── Tentacle Attack Visual ─────────────────────────────────────
local function shootBlackTentacles(targetPos: Vector3, extendTime: number)
	local limbs = {
		monster:FindFirstChild("LeftHand", true)
			or monster:FindFirstChild("Left Arm", true)
			or monster:FindFirstChild("leftarm", true),

		monster:FindFirstChild("RightHand", true)
			or monster:FindFirstChild("Right Arm", true)
			or monster:FindFirstChild("rightarm", true),
	}

	local activeTentacles = {}

	for _, limb in ipairs(limbs) do
		if not limb then
			continue
		end

		local att0 = Instance.new("Attachment")
		att0.Parent = limb

		local endPart = Instance.new("Part")
		endPart.Size = Vector3.new(0.1, 0.1, 0.1)
		endPart.Transparency = 1
		endPart.Anchored = true
		endPart.CanCollide = false
		-- Offset it slightly forward so it always shoots out, even if you are hugging the monster
		endPart.Position = limb.Position + (rootPart.CFrame.LookVector * 1)
		endPart.Parent = workspace

		local att1 = Instance.new("Attachment")
		att1.Parent = endPart

		local beam = Instance.new("Beam")
		beam.Attachment0 = att0
		beam.Attachment1 = att1
		beam.Color = ColorSequence.new(Color3.fromRGB(0, 0, 0)) -- Pitch black!
		beam.Transparency = NumberSequence.new(0) -- Completely solid, no see-through
		beam.Width0 = 3.5 -- VERY thick at the monster's arm
		beam.Width1 = 0.2 -- Sharp at the tip (creates the > shape)
		beam.FaceCamera = true
		beam.CurveSize0 = math.random(-4, 4)
		beam.CurveSize1 = math.random(-4, 4)
		beam.Parent = endPart

		table.insert(activeTentacles, { part = endPart, limb = limb })

		-- Shoot it out!
		TweenService:Create(
			endPart,
			TweenInfo.new(extendTime, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
			{ Position = targetPos }
		):Play()
	end

	-- Retract them
	task.delay(extendTime + 0.8, function()
		for _, t in ipairs(activeTentacles) do
			if t.part and t.limb then
				local retract = TweenService:Create(
					t.part,
					TweenInfo.new(0.3, Enum.EasingStyle.Sine, Enum.EasingDirection.In),
					{ Position = t.limb.Position }
				)
				retract:Play()
				retract.Completed:Once(function()
					t.part:Destroy()
				end)
			end
		end
	end)
end

-- beginStrike: lunge → check hit window → catch or miss ───────
-- beginStrike: lunge → check hit window → catch or miss ───────
local function beginStrike(player: Player)
	state = "CATCH"
	sounds:onStateChange("CATCH", false)
	playAction("Jumpscare")

	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then
		task.delay(2, beginIdle)
		return
	end

	-- Snapshot: The exact coordinate the monster is aiming the tentacles at!
	local snapPos = hrp.Position
	local monPos = rootPart.Position
	local flatDir = Vector3.new(snapPos.X - monPos.X, 0, snapPos.Z - monPos.Z)
	local flatDist = flatDir.Magnitude

	-- Force the MONSTER to look at the snapshot position
	rootPart.CFrame = CFrame.lookAt(monPos, monPos + flatDir.Unit)

	-- The Travel Time. You have exactly 0.5 seconds to step out of the snapPos.
	local STRIKE_TIME = 0.25

	-- Lunge slightly toward the spot
	if flatDist > 0.1 then
		local lungePos = monPos + flatDir.Unit * math.max(0, flatDist - 1.5)
		TweenService:Create(
			rootPart,
			TweenInfo.new(STRIKE_TIME, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
			{ CFrame = CFrame.lookAt(lungePos, lungePos + flatDir.Unit) }
		):Play()
	end

	-- Shoot tentacles specifically at the player's chest height at the snapPos
	shootBlackTentacles(snapPos + Vector3.new(0, 1, 0), STRIKE_TIME)

	-- The Hit Check: Exactly when the tentacles reach the spot
	task.delay(STRIKE_TIME, function()
		if not player.Character then
			beginIdle()
			return
		end
		local liveHRP = player.Character:FindFirstChild("HumanoidRootPart")
		if not liveHRP then
			beginIdle()
			return
		end

		-- A strict, tight impact hitbox.
		-- It is just 2.5 studs wide. If you are not literally standing on the
		-- exact spot the monster aimed at 0.5 seconds ago, the monster misses!
		local IMPACT_HITBOX = 4

		if (liveHRP.Position - snapPos).Magnitude <= IMPACT_HITBOX then
			-- ✅ Caught! You stood still or walked backwards into it.
			sounds:playHitSounds()
			local hum = player.Character:FindFirstChildOfClass("Humanoid")
			if hum then
				hum.Health = 0
			end
			RE.PlayerDied:FireAllClients(player.Name)
			task.delay(2, beginIdle)
		else
			-- ❌ Missed! You successfully juked the monster.
			task.delay(1.2, function()
				if state == "CATCH" then
					beginChase(player)
				end
			end)
		end
	end)
end

-- ── Movement ──────────────────────────────────────────────────

-- Clamp a world position to stay within the generated map.
-- margin = 1 tile inward from extreme edge (the outer ring is always walls anyway).
local function clampToMap(pos: Vector3): Vector3
	if not gridReady then
		return pos
	end
	local ROWS = #grid
	local COLS = grid[1] and #grid[1] or ROWS
	local margin = TILE
	return Vector3.new(
		math.clamp(pos.X, margin, (COLS - 1) * TILE - margin),
		pos.Y,
		math.clamp(pos.Z, margin, (ROWS - 1) * TILE - margin)
	)
end

local function stepToward(target: Vector3, speed: number, dt: number): boolean
	local pivot = monster:GetPivot()
	local flat = Vector3.new(target.X, pivot.Position.Y, target.Z)
	local dir = flat - pivot.Position
	local dist = dir.Magnitude
	if dist < 0.6 then
		return true
	end

	local step = math.min(speed * dt, dist)
	local newPos = pivot.Position + dir.Unit * step
	newPos = clampToMap(newPos)

	local targetRotation = CFrame.lookAt(newPos, newPos + dir.Unit)
	local turnSpeed = state == "CHASE" and 14 or 6 -- Turns fast while chasing, slow while idle

	-- Lerp the rotation, but force the exact translation so it doesn't slide backward
	local smoothedCFrame = pivot:Lerp(targetRotation, dt * turnSpeed)
	monster:PivotTo(CFrame.new(newPos) * smoothedCFrame.Rotation)

	return false
end

local function pickIdleTarget(): Vector3
	local col, row = worldToTile(rootPart.Position)
	for _ = 1, 30 do
		local nc = col + math.random(-IDLE_RANGE, IDLE_RANGE)
		local nr = row + math.random(-IDLE_RANGE, IDLE_RANGE)
		if isTileWalkable(nc, nr) then
			return tileToWorld(nc, nr)
		end
	end
	return tileToWorld(col, row)
end

-- ── MONSTER_REACH: Arm Extension ─────────────────────────────
-- Welds a claw-extension part below each arm so they look longer.
-- Only runs when MONSTER_REACH rule is active.
local function applyReachVisual()
	if not table.find(activeRules, Constants.Rules.MONSTER_REACH) then
		return
	end

	local limbNames = {
		"leftarm",
		"rightarm",
		"Left Arm",
		"Right Arm",
		"LeftHand",
		"RightHand",
	}

	for _, name in ipairs(limbNames) do
		local limb = monster:FindFirstChild(name, true)
		if not limb or not limb:IsA("BasePart") then
			continue
		end
		if limb:FindFirstChild("ReachAura") then
			continue
		end

		-- Create a thick, dark blood-blob aura
		local particles = Instance.new("ParticleEmitter")
		particles.Name = "ReachAura"
		particles.Color = ColorSequence.new(Color3.fromRGB(110, 10, 10)) -- Darker crimson blood red
		particles.LightEmission = 0.15 -- Barely glows, looks more physical/blobby
		particles.ZOffset = 0.5
		-- Much thicker size to look like a mass
		particles.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 3.5), NumberSequenceKeypoint.new(1, 0.5) })
		-- Make the center of the blob highly opaque
		particles.Transparency =
			NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
		particles.Texture = "rbxassetid://8006210660"
		particles.Lifetime = NumberRange.new(0.6, 1.2)
		particles.Rate = 60 -- Spam a bit more to keep it thick
		particles.Speed = NumberRange.new(0.5, 1.5) -- Slow down the speed so it clumps around the hand
		particles.Parent = limb
	end
end

-- ── Main Heartbeat ────────────────────────────────────────────

local broadcastCD = 0.5
local sensorCD = 0
local SENSOR_INT = 0.25

RunService.Heartbeat:Connect(function(dt)
	if not gridReady then
		return
	end

	sensorCD += dt
	broadcastCD = math.max(0, broadcastCD - dt)

	local monPos = rootPart.Position

	-- Sensor + broadcast tick
	if sensorCD >= SENSOR_INT then
		sensorCD = 0
		local all = Players:GetPlayers()

		if state ~= "CATCH" then
			local heard = SensorSystem.CheckHearing(monPos, activeRules)
			if heard and heard.player and heard.player.Character then
				beginChase(heard.player)
			end

			local smelled = SensorSystem.CheckSmell(monPos, all, activeRules)
			if smelled then
				beginChase(smelled)
			end

			local seen = SensorSystem.CheckVision(monster, monPos, all, activeRules)
			if seen then
				beginChase(seen)
			end

			if state == "CHASE" then
				lostTimer -= SENSOR_INT
				if lostTimer <= 0 then
					beginIdle()
				end
			end
		end

		if broadcastCD <= 0 then
			broadcastCD = 0.5
			RE.MonsterPosition:FireAllClients({
				position = monPos,
				state = state,
				monsterIndex = 1,
			})
			for _, pl in ipairs(all) do
				local aw =
					SensorSystem.GetAwarenessForPlayer(monPos, monster, pl, activeRules, state == "CHASE", chaseTarget)
				local noise = SensorSystem.GetRecentNoiseForPlayer(pl)
				RE.AwarenessUpdated:FireClient(pl, aw, noise)
			end
		end
	end

	-- IDLE movement
	if state == "IDLE" then
		if not idleTarget then
			idleTarget = pickIdleTarget()
			playMovement("Walk")
		end
		if stepToward(idleTarget :: Vector3, Constants.MONSTER_SPEED_BASE * 0.45, dt) then
			idleTarget = nil
		end
		return
	end

	-- CHASE movement
	if state == "CHASE" and chaseTarget then
		local char = chaseTarget.Character
		if not char then
			beginIdle()
			return
		end
		local hrp = char:FindFirstChild("HumanoidRootPart")
		if not hrp then
			beginIdle()
			return
		end

		local speed =
			math.min(Constants.MONSTER_SPEED_BASE + Constants.MONSTER_SPEED_PER_LEVEL, Constants.MONSTER_SPEED_MAX)
		if table.find(activeRules, Constants.Rules.MONSTER_FAST) then
			speed = math.min(speed * 1.35, Constants.MONSTER_SPEED_MAX)
		end

		local catchR = Constants.MONSTER_REACH_BASE
		if table.find(activeRules, Constants.Rules.MONSTER_REACH) then
			catchR += Constants.MONSTER_REACH_BONUS
		end

		local flatMonPos = Vector3.new(monPos.X, 0, monPos.Z)
		local flatPlayerPos = Vector3.new(hrp.Position.X, 0, hrp.Position.Z)

		if (flatMonPos - flatPlayerPos).Magnitude <= catchR then
			beginStrike(chaseTarget)
			return
		end

		-- Noclip straight to the player
		stepToward(hrp.Position, speed, dt)

		playMovement("Run")
	end

	-- CATCH state: tween handles movement, nothing to do here
end)

-- ── Remote Listeners ──────────────────────────────────────────

RE.PlayerMakeNoise.OnServerEvent:Connect(function(player, level, position)
	SensorSystem.AddNoise(player, position, level)
end)

-- ── Rules Processing ──────────────────────────────────────────

local function onRulesActivated(rules: { string })
	activeRules = rules
	applyReachVisual()
	DuplicationSystem.processRules(monster, rules)
end

-- 1. Listen for the correct BindableEvent from GameManager
local RulesBindable = Remotes:WaitForChild("RulesBindable", 5)
if RulesBindable and RulesBindable:IsA("BindableEvent") then
	RulesBindable.Event:Connect(onRulesActivated)
end

-- 2. FALLBACK: Fix the timing issue!
-- If GameManager already fired the event BEFORE MonsterAI finished loading,
-- we can just read the rules directly from the SessionInfo folder GameManager created.
local sessionInfo = ReplicatedStorage:FindFirstChild("SessionInfo")
if sessionInfo then
	local rulesFolder = sessionInfo:FindFirstChild("ActiveRules")
	if rulesFolder then
		local loadedRules = {}
		for _, stringVal in ipairs(rulesFolder:GetChildren()) do
			table.insert(loadedRules, stringVal.Value)
		end
		if #loadedRules > 0 then
			onRulesActivated(loadedRules)
		end
	end
end

-- ── TEST rules (remove / comment out once Gilang's system is wired) ──
-- activeRules = {
-- Constants.Rules.MONSTER_HEAR,
-- Constants.Rules.MONSTER_SMELL,
-- Constants.Rules.MONSTER_SEE,
-- Constants.Rules.MONSTER_REACH,
-- Constants.Rules.MONSTER_DUPLICATE,
-- }
applyReachVisual()

-- ── Startup ───────────────────────────────────────────────────

local mapBE = ReplicatedStorage:WaitForChild("ServerMapGenerated")
mapBE.Event:Connect(function(realGrid, hallInfo)
	grid = realGrid
	gridReady = true

	-- Dynamic radius: ~28% of map diagonal, clamped between 3–10 tiles.
	-- Level 1 (12×12 → diag≈17): 17×0.28 ≈ 5 tiles  ← was 8, now reasonable
	-- Level 5 (20×20 → diag≈28): 28×0.28 ≈ 8 tiles
	-- Level 10 (32×32 → diag≈45): capped at 10 tiles
	local ROWS = #realGrid
	local COLS = realGrid[1] and #realGrid[1] or ROWS
	local dynamicRadius = math.clamp(
		math.round(math.sqrt(COLS ^ 2 + ROWS ^ 2) * 0.28),
		3, -- never closer than 3 tiles to player
		10 -- never farther than 10 tiles (prevents edge-spawning on big maps)
	)

	local spawnWorld = Vector3.new((hallInfo.spawnCol - 1) * TILE, MONSTER_Y, (hallInfo.spawnRow - 1) * TILE)
	applyReachVisual()
	spawnAtArc(spawnWorld, dynamicRadius)
	DuplicationSystem.processRules(monster, activeRules)
	beginIdle()
	print(("[MonsterAI] Map loaded. Spawn radius = %d tiles."):format(dynamicRadius))
end)

print("[MonsterAI] Initialized. Waiting for map...")
