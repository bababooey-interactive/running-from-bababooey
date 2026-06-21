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
local monster = workspace:WaitForChild("SoulDragger")

-- OPTION B (recommended after reorganization):
-- local monster = game:GetService("ServerStorage")
--     :WaitForChild("Characters"):WaitForChild("SoulDragger"):Clone()
-- monster.Parent = workspace

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
local TILE = 16

-- How high the monster's pivot sits above the tile floor (Y=0 center).
-- Tile floor is 1 stud thick → top at Y=0.5.
-- Increase MONSTER_Y if the monster sinks, decrease if it floats.
local MONSTER_Y = 3

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
			playAction("Spotted")
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

	-- Snapshot: where is the player RIGHT NOW when strike is decided?
	local snapPos = hrp.Position
	local monPos = rootPart.Position
	local flatDir = Vector3.new(snapPos.X - monPos.X, 0, snapPos.Z - monPos.Z)
	local flatDist = flatDir.Magnitude

	-- Freeze player to look at monster
	hrp.Anchored = true
	hrp.CFrame = CFrame.lookAt(hrp.Position, Vector3.new(monPos.X, hrp.Position.Y, monPos.Z))

	-- Lunge tween: physically slide monster toward snapshot
	local LUNGE_T = 0.3
	if flatDist > 0.1 then
		local lungePos = monPos + flatDir.Unit * math.max(0, flatDist - 1.5)
		TweenService:Create(
			rootPart,
			TweenInfo.new(LUNGE_T, Enum.EasingStyle.Linear),
			{ CFrame = CFrame.lookAt(lungePos, lungePos + flatDir.Unit) }
		):Play()
	end

	task.delay(LUNGE_T, function()
		if not player.Character then
			beginIdle()
			return
		end
		local liveHRP = player.Character:FindFirstChild("HumanoidRootPart")
		if not liveHRP then
			beginIdle()
			return
		end

		-- How big is the "you got caught" window?
		local hitRadius = 3.5
		if table.find(activeRules, Constants.Rules.MONSTER_REACH) then
			hitRadius = 8.0 -- harder to dodge with long arms
		end

		-- Did the player move out of the snapshot position in time?
		if (liveHRP.Position - snapPos).Magnitude <= hitRadius then
			-- ✅ Caught!
			sounds:playHitSounds()
			local hum = player.Character:FindFirstChildOfClass("Humanoid")
			if hum then
				hum.Health = 0
			end
			RE.PlayerDied:FireAllClients(player.Name)
			task.delay(2, beginIdle)
		else
			-- ❌ Missed — player dodged
			liveHRP.Anchored = false
			task.delay(1.2, function()
				if state == "CATCH" then
					beginChase(player)
				end
			end)
		end
	end)
end

-- ── Movement ──────────────────────────────────────────────────

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
	monster:PivotTo(CFrame.lookAt(newPos, newPos + dir.Unit))
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

	-- SoulDragger uses lowercase: "leftarm", "rightarm"
	-- R6 / R15 fallbacks included in case the rig differs
	local limbNames = {
		"leftarm",
		"rightarm",
		"Left Arm",
		"Right Arm",
		"LeftHand",
		"RightHand",
	}

	for _, name in ipairs(limbNames) do
		local limb = monster:FindFirstChild(name, true) -- true = recursive
		if not limb or not limb:IsA("BasePart") then
			continue
		end
		if limb:FindFirstChild("ReachExtension") then
			continue
		end -- already done

		local ext = Instance.new("Part")
		ext.Name = "ReachExtension"
		ext.Size = Vector3.new(limb.Size.X * 0.75, 3.5, limb.Size.Z * 0.75)
		ext.Color = limb.Color
		ext.Material = limb.Material
		ext.Transparency = 0
		ext.CanCollide = false
		ext.CanQuery = false
		ext.Massless = true
		-- Hang below the hand center
		ext.CFrame = limb.CFrame * CFrame.new(0, -(limb.Size.Y / 2 + ext.Size.Y / 2), 0)

		local weld = Instance.new("WeldConstraint")
		weld.Part0 = limb
		weld.Part1 = ext
		weld.Parent = ext
		ext.Parent = monster
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

		if (monPos - hrp.Position).Magnitude <= catchR then
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

-- Gilang fires a BindableEvent alongside his RemoteEvent for server→server comms
local rulesBE = ReplicatedStorage:FindFirstChild("ServerRulesActivated")
if rulesBE and rulesBE:IsA("BindableEvent") then
	rulesBE.Event:Connect(onRulesActivated)
end

-- ── TEST rules (remove / comment out once Gilang's system is wired) ──
activeRules = {
	Constants.Rules.MONSTER_HEAR,
	-- Constants.Rules.MONSTER_SMELL,
	-- Constants.Rules.MONSTER_SEE,
	-- Constants.Rules.MONSTER_REACH,
	-- Constants.Rules.MONSTER_DUPLICATE,
}
applyReachVisual()

-- ── Startup ───────────────────────────────────────────────────

local mapBE = ReplicatedStorage:WaitForChild("ServerMapGenerated")
mapBE.Event:Connect(function(realGrid, hallInfo)
	grid = realGrid
	gridReady = true

	local spawnWorld = Vector3.new((hallInfo.spawnCol - 1) * TILE, MONSTER_Y, (hallInfo.spawnRow - 1) * TILE)

	applyReachVisual()
	spawnAtArc(spawnWorld, 8)
	DuplicationSystem.processRules(monster, activeRules)
	beginIdle()
	print("[MonsterAI] Map loaded. Hunt begins.")
end)

print("[MonsterAI] Initialized. Waiting for map...")
