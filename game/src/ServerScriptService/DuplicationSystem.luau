-- DuplicationSystem.luau  (ModuleScript)
-- ServerScriptService
--
-- Spawns additional SoulDragger clones when the MONSTER_DUPLICATE rule is active.
-- Each clone gets its own MonsterBrain instance with the same rule set.
-- Stacking: each occurrence of MONSTER_DUPLICATE adds one more clone
-- (capped at MAX_TOTAL including the original).

local Constants = require(game.ReplicatedStorage.Shared.Constants)
local MonsterBrain = require(script.Parent.MonsterBrain)

local DuplicationSystem = {}

-- ── Config ────────────────────────────────────────────────────
local MAX_TOTAL = 16 -- maximum monsters alive at once (original + clones)
local CLONE_Y = 0 -- must match MONSTER_Y in MonsterAI

-- ── State ─────────────────────────────────────────────────────
local activeClones: { { model: Model, brain: any } } = {}
local RE_PlayerDied: RemoteEvent?
local cachedGrid: { { number } } = {}
local gridReady = false

-- ── Public: store the PlayerDied remote ───────────────────────

function DuplicationSystem.init(playerDiedEvent: RemoteEvent)
	RE_PlayerDied = playerDiedEvent
end

-- ── Public: forward the walkable grid to existing clone brains ─

function DuplicationSystem.setGrid(grid: { { number } })
	cachedGrid = grid
	gridReady = true
	for _, entry in ipairs(activeClones) do
		entry.brain:setGrid(grid)
	end
end

-- ── Public: spawn clones to match the rules ────────────────────
-- `onBroadcastClone` is forwarded to each clone brain's onBroadcast
-- config so clones replicate their position to clients.

function DuplicationSystem.processRules(
	original: Model,
	rules: { string },
	onBroadcastClone: ((Vector3, string, number) -> ())?
)
	-- Count how many MONSTER_DUPLICATE rules are active (stackable)
	local dupCount = 0
	for _, r in ipairs(rules) do
		if r == Constants.Rules.MONSTER_DUPLICATE then
			dupCount += 1
		end
	end

	if dupCount == 0 then
		return
	end

	local targetTotal = math.min(1 + dupCount, MAX_TOTAL)
	local targetClones = targetTotal - 1
	local toSpawn = targetClones - #activeClones

	if toSpawn <= 0 then
		return
	end

	for i = 1, toSpawn do
		local cloneIndex = #activeClones + i
		local clone = original:Clone()
		clone.Name = "SoulDragger_Clone_" .. cloneIndex

		for _, part in ipairs(clone:GetDescendants()) do
			if part:IsA("BasePart") then
				part.CanCollide = false
				part.CanQuery = false
				part.Anchored = false
			end
		end

		-- Root must be anchored so MonsterBrain can PivotTo it
		local root = clone:FindFirstChild("HumanoidRootPart") or clone:FindFirstChild("rb") or clone.PrimaryPart
		if root then
			root.Anchored = true
		end

		-- Spread clones in a ring around the original
		local angle = (cloneIndex / targetClones) * math.pi * 2
		local offset = Vector3.new(math.cos(angle) * 24, 0, math.sin(angle) * 24)
		local spawn = original:GetPivot().Position + offset
		clone:PivotTo(CFrame.new(Vector3.new(spawn.X, CLONE_Y, spawn.Z)))
		clone.Parent = workspace

		local brain = MonsterBrain.new(clone, rules, {
			monsterY = CLONE_Y,
			monsterIndex = cloneIndex + 1, -- original is index 1
			graceTime = 0, -- clones start immediately
			onDied = function(playerName: string)
				if RE_PlayerDied then
					RE_PlayerDied:FireAllClients(playerName)
				end
			end,
			onBroadcast = onBroadcastClone,
		})

		if gridReady then
			brain:setGrid(cachedGrid)
		end
		brain:start()

		table.insert(activeClones, { model = clone, brain = brain })
	end

	print(("[DupSystem] %d clone(s) spawned → %d total monsters"):format(toSpawn, targetClones + 1))
end

-- ── Public: push updated rules to all clone brains ─────────────

function DuplicationSystem.setRules(rules: { string })
	for _, entry in ipairs(activeClones) do
		entry.brain:setRules(rules)
	end
end

-- ── Public: destroy all clones (call on game end / round reset) ─

function DuplicationSystem.cleanup()
	for _, entry in ipairs(activeClones) do
		entry.brain:stop()
		if entry.model and entry.model.Parent then
			entry.model:Destroy()
		end
	end
	activeClones = {}
	cachedGrid = {}
	gridReady = false
	print("[DupSystem] All clones cleaned up.")
end

return DuplicationSystem
