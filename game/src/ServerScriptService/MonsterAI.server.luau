-- MonsterAI.server.luau  (Script — thin orchestrator)
-- ServerScriptService
--
-- Responsibilities:
--   • Clone SoulDragger from ServerStorage and prepare it for simulation.
--   • Create the primary MonsterBrain (index 1) and wire up its callbacks.
--   • Apply visual effects for active rules (MONSTER_REACH arm aura).
--   • Forward map data to brain and DuplicationSystem when MapGenerator fires.
--   • Forward rules from GameManager's BindableEvent (+ SessionInfo fallback).
--   • Relay noise events from clients to SensorSystem.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Constants = require(ReplicatedStorage.Shared.Constants)
local SensorSystem = require(script.Parent.SensorSystem)
local MonsterBrain = require(script.Parent.MonsterBrain)
local DuplicationSystem = require(script.Parent.DuplicationSystem)

-- ── Remotes ───────────────────────────────────────────────────
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RE = {
	PlayerMakeNoise = Remotes:WaitForChild("PlayerMakeNoise"),
	PlayerDied = Remotes:WaitForChild("PlayerDied"),
	MonsterPosition = Remotes:WaitForChild("MonsterPosition"),
	AwarenessUpdated = Remotes:WaitForChild("AwarenessUpdated"),
}
DuplicationSystem.init(RE.PlayerDied)

-- ── Monster setup ─────────────────────────────────────────────
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
local MONSTER_Y = 0.428
local GRACE_PERIOD = 8

-- ── State ─────────────────────────────────────────────────────
local activeRules: { string } = {}
local grid: { { number } } = {}

-- ── Create primary brain ──────────────────────────────────────
local brain
brain = MonsterBrain.new(monster, activeRules, {
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
		-- Per-player awareness (original monster only; clones skip awareness)
		for _, pl in ipairs(Players:GetPlayers()) do
			local aw = SensorSystem.GetAwarenessForPlayer(
				pos,
				monster,
				pl,
				activeRules,
				stateStr == "CHASE",
				brain.chaseTarget
			)
			local noise = SensorSystem.GetRecentNoiseForPlayer(pl)
			RE.AwarenessUpdated:FireClient(pl, aw, noise)
		end
	end,
})

-- ── Arc spawn ─────────────────────────────────────────────────
-- Places the monster on a walkable tile at a distance from the player spawn.

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
		local tileType = grid[row] and grid[row][col]
		-- Allow spawning as long as it's not a WALL and not the SPAWN point
		if tileType and tileType ~= Constants.Tile.WALL and tileType ~= Constants.Tile.SPAWN then
			monster:PivotTo(CFrame.new(Vector3.new((col - 1) * TILE, MONSTER_Y, (row - 1) * TILE)))
			print(("[MonsterAI] Spawned at tile (%d, %d)"):format(col, row))
			return
		end
	end

	-- Fallback: directly opposite the spawn on the X axis
	monster:PivotTo(CFrame.new(playerSpawnWorld.X + radiusTiles * TILE, MONSTER_Y, playerSpawnWorld.Z))
	warn("[MonsterAI] Arc spawn failed — used fallback position")
end

-- ── MONSTER_REACH visual — red particle aura on arms ─────────

local function applyReachVisual()
	if not table.find(activeRules, Constants.Rules.MONSTER_REACH) then
		return
	end

	local limbNames = { "leftarm", "rightarm", "Left Arm", "Right Arm", "LeftHand", "RightHand" }

	for _, name in ipairs(limbNames) do
		local limb = monster:FindFirstChild(name, true)
		if not limb or not limb:IsA("BasePart") then
			continue
		end
		if limb:FindFirstChild("ReachAura") then
			continue
		end

		local emitter = Instance.new("ParticleEmitter")
		emitter.Name = "ReachAura"
		emitter.Color = ColorSequence.new(Color3.fromRGB(110, 10, 10))
		emitter.LightEmission = 0.15
		emitter.ZOffset = 0.5
		emitter.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 3.5),
			NumberSequenceKeypoint.new(1, 0.5),
		})
		emitter.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.1),
			NumberSequenceKeypoint.new(1, 1.0),
		})
		emitter.Texture = "rbxassetid://8006210660"
		emitter.Lifetime = NumberRange.new(0.6, 1.2)
		emitter.Rate = 60
		emitter.Speed = NumberRange.new(0.5, 1.5)
		emitter.Parent = limb
	end
end

-- ── Clone broadcast helper ────────────────────────────────────
-- Clones only broadcast position/state; awareness is tracked for the
-- original monster only (to avoid N² FireClient calls per frame).

local function cloneBroadcast(pos: Vector3, stateStr: string, index: number)
	RE.MonsterPosition:FireAllClients({ position = pos, state = stateStr, monsterIndex = index })
end

-- ── Remote: player noise relay ────────────────────────────────
RE.PlayerMakeNoise.OnServerEvent:Connect(function(player, level, position)
	SensorSystem.AddNoise(player, position, level)
end)

-- ── Rules activation ──────────────────────────────────────────
local function onRulesActivated(rules: { string })
	activeRules = rules
	brain:setRules(rules)
	applyReachVisual()
	DuplicationSystem.setRules(rules)
	DuplicationSystem.processRules(monster, rules, cloneBroadcast)
end

-- Primary path: BindableEvent from GameManager (fires once at session start)
local RulesBindable = Remotes:WaitForChild("RulesBindable", 5)
if RulesBindable and RulesBindable:IsA("BindableEvent") then
	RulesBindable.Event:Connect(onRulesActivated)
end

-- FIX: Gunakan WaitForChild dengan timeout agar aman menunggu inisialisasi GameManager
local sessionInfo = ReplicatedStorage:WaitForChild("SessionInfo", 5)
if sessionInfo then
	local rulesFolder = sessionInfo:WaitForChild("ActiveRules", 5)
	if rulesFolder then
		-- Beri jeda micro-second memastikan seluruh StringValue selesai di-parent oleh GameManager
		task.wait()
		local loaded = {}
		for _, v in ipairs(rulesFolder:GetChildren()) do
			table.insert(loaded, v.Value)
		end
		if #loaded > 0 then
			onRulesActivated(loaded)
		end
	end
end

applyReachVisual()

-- ── Map generated ─────────────────────────────────────────────
local mapBE = ReplicatedStorage:WaitForChild("ServerMapGenerated")
mapBE.Event:Connect(function(realGrid, hallInfo)
	grid = realGrid
	brain:setGrid(realGrid)
	DuplicationSystem.setGrid(realGrid)

	-- Spawn radius ≈ 28 % of map diagonal, clamped to a sensible range
	local ROWS = #realGrid
	local COLS = realGrid[1] and #realGrid[1] or ROWS
	local radius = math.clamp(math.round(math.sqrt(COLS ^ 2 + ROWS ^ 2) * 0.28), 3, 10)

	local TILE = Constants.TILE_SIZE
	local spawnWorld = Vector3.new((hallInfo.spawnCol - 1) * TILE, MONSTER_Y, (hallInfo.spawnRow - 1) * TILE)

	applyReachVisual()
	spawnAtArc(spawnWorld, radius)
	brain:start()

	-- Process rules again in case they arrived before the map did
	DuplicationSystem.processRules(monster, activeRules, cloneBroadcast)

	print(("[MonsterAI] Map loaded. Spawn radius = %d tiles. Grace = %ds"):format(radius, GRACE_PERIOD))
end)

print("[MonsterAI] Initialized. Waiting for map...")
