-- =============================================================
--  MonsterAI.server.luau  (Script — thin orchestrator)
--  Sets up the original monster and delegates all AI to MonsterBrain.
--  Also handles: remotes, rules, map startup, reach visuals,
--  awareness broadcasts, and duplication via DuplicationSystem.
-- =============================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Constants = require(ReplicatedStorage.Shared.Constants)
local SensorSystem = require(script.Parent.SensorSystem)
local MonsterBrain = require(script.Parent.MonsterBrain)
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
local monster = ServerStorage:WaitForChild("Characters"):WaitForChild("SoulDragger"):Clone()
monster.Parent = workspace

for _, part in ipairs(monster:GetDescendants()) do
	if part:IsA("BasePart") then
		part.CanCollide = false
		part.CanQuery = false
		part.Anchored = false
	end
end

-- ── Constants ─────────────────────────────────────────────────
local MONSTER_Y = 0
local GRACE_PERIOD = 8

-- ── Grid (set when map is generated) ──────────────────────────
local grid = {}

-- ── Active Rules ─────────────────────────────────────────────
local activeRules: { string } = {}

-- ── Create Brain ─────────────────────────────────────────────
local brain = MonsterBrain.new(monster, activeRules, {
	monsterY = MONSTER_Y,
	monsterIndex = 1,
	graceTime = GRACE_PERIOD,
	onDied = function(playerName: string)
		RE.PlayerDied:FireAllClients(playerName)
	end,
	onBroadcast = function(pos: Vector3, stateStr: string, index: number)
		RE.MonsterPosition:FireAllClients({
			position = pos,
			state = stateStr,
			monsterIndex = index,
		})
		-- Awareness update (original monster only)
		for _, pl in ipairs(Players:GetPlayers()) do
			local aw = SensorSystem.GetAwarenessForPlayer(
				pos, monster, pl, activeRules, stateStr == "CHASE", brain.chaseTarget
			)
			local noise = SensorSystem.GetRecentNoiseForPlayer(pl)
			RE.AwarenessUpdated:FireClient(pl, aw, noise)
		end
	end,
})

-- ── Spawn in Arc ──────────────────────────────────────────────

local function spawnAtArc(playerSpawnWorld: Vector3, radiusTiles: number)
	local TILE = Constants.TILE_SIZE
	local COLS = grid[1] and #grid[1] or 15
	local ROWS = #grid > 0 and #grid or 18
	local cCol = math.round(playerSpawnWorld.X / TILE) + 1
	local cRow = math.round(playerSpawnWorld.Z / TILE) + 1

	for _ = 1, 60 do
		local angle = math.rad(math.random(0, 359))
		local r = radiusTiles + math.random(-2, 2)
		local col = math.clamp(math.round(cCol + math.cos(angle) * r), 1, COLS)
		local row = math.clamp(math.round(cRow + math.sin(angle) * r), 1, ROWS)
		if grid[row] and grid[row][col] and grid[row][col] ~= 0 then
			monster:PivotTo(CFrame.new(Vector3.new((col - 1) * TILE, MONSTER_Y, (row - 1) * TILE)))
			print(("[MonsterAI] Spawned at tile (%d,%d)"):format(col, row))
			return
		end
	end
	-- Fallback: opposite side of spawn
	local fb = Vector3.new(playerSpawnWorld.X + radiusTiles * TILE, MONSTER_Y, playerSpawnWorld.Z)
	monster:PivotTo(CFrame.new(fb))
	warn("[MonsterAI] Arc spawn failed — used fallback")
end

-- ── MONSTER_REACH: Arm Extension Visual ──────────────────────

local function applyReachVisual()
	if not table.find(activeRules, Constants.Rules.MONSTER_REACH) then
		return
	end

	local limbNames = {
		"leftarm", "rightarm",
		"Left Arm", "Right Arm",
		"LeftHand", "RightHand",
	}

	for _, name in ipairs(limbNames) do
		local limb = monster:FindFirstChild(name, true)
		if not limb or not limb:IsA("BasePart") then
			continue
		end
		if limb:FindFirstChild("ReachAura") then
			continue
		end

		local particles = Instance.new("ParticleEmitter")
		particles.Name = "ReachAura"
		particles.Color = ColorSequence.new(Color3.fromRGB(110, 10, 10))
		particles.LightEmission = 0.15
		particles.ZOffset = 0.5
		particles.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 3.5),
			NumberSequenceKeypoint.new(1, 0.5),
		})
		particles.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.1),
			NumberSequenceKeypoint.new(1, 1),
		})
		particles.Texture = "rbxassetid://8006210660"
		particles.Lifetime = NumberRange.new(0.6, 1.2)
		particles.Rate = 60
		particles.Speed = NumberRange.new(0.5, 1.5)
		particles.Parent = limb
	end
end

-- ── Clone broadcast helper ────────────────────────────────────

local function cloneBroadcast(pos: Vector3, stateStr: string, index: number)
	RE.MonsterPosition:FireAllClients({
		position = pos,
		state = stateStr,
		monsterIndex = index,
	})
end

-- ── Remote Listeners ──────────────────────────────────────────

RE.PlayerMakeNoise.OnServerEvent:Connect(function(player, level, position)
	SensorSystem.AddNoise(player, position, level)
end)

-- ── Rules Processing ──────────────────────────────────────────

local function onRulesActivated(rules: { string })
	activeRules = rules
	brain:setRules(rules)
	applyReachVisual()
	DuplicationSystem.setRules(rules)
	DuplicationSystem.processRules(monster, rules, cloneBroadcast)
end

-- 1. Listen for the BindableEvent from GameManager
local RulesBindable = Remotes:WaitForChild("RulesBindable", 5)
if RulesBindable and RulesBindable:IsA("BindableEvent") then
	RulesBindable.Event:Connect(onRulesActivated)
end

-- 2. FALLBACK: read rules directly from SessionInfo if event already fired
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

applyReachVisual()

-- ── Startup: Map Generated ────────────────────────────────────

local mapBE = ReplicatedStorage:WaitForChild("ServerMapGenerated")
mapBE.Event:Connect(function(realGrid, hallInfo)
	grid = realGrid
	brain:setGrid(realGrid)
	DuplicationSystem.setGrid(realGrid)

	-- Dynamic radius: ~28% of map diagonal, clamped 3–10 tiles
	local ROWS = #realGrid
	local COLS = realGrid[1] and #realGrid[1] or ROWS
	local dynamicRadius = math.clamp(
		math.round(math.sqrt(COLS ^ 2 + ROWS ^ 2) * 0.28),
		3,
		10
	)

	local TILE = Constants.TILE_SIZE
	local spawnWorld = Vector3.new(
		(hallInfo.spawnCol - 1) * TILE, MONSTER_Y, (hallInfo.spawnRow - 1) * TILE
	)
	applyReachVisual()
	spawnAtArc(spawnWorld, dynamicRadius)

	-- Start the brain (begins grace period + Heartbeat loop)
	brain:start()

	-- Process rules again in case map loaded after rules were activated
	DuplicationSystem.processRules(monster, activeRules, cloneBroadcast)

	print(("[MonsterAI] Map loaded. Spawn radius = %d tiles. Grace = %ds"):format(dynamicRadius, GRACE_PERIOD))
end)

print("[MonsterAI] Initialized. Waiting for map...")