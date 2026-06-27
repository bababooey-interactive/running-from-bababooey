-- =============================================================
--  DuplicationSystem.luau  (ModuleScript — thin orchestrator)
--  Clones SoulDragger when MONSTER_DUPLICATE rule is active.
--  Each clone gets its own MonsterBrain instance (same AI as original).
--  Exponential: 1 rule = 2 monsters, 2 rules = 4, capped at MAX_TOTAL.
-- =============================================================

local Constants = require(game.ReplicatedStorage.Shared.Constants)
local MonsterBrain = require(script.Parent.MonsterBrain)

local DuplicationSystem = {}

-- ── Config ────────────────────────────────────────────────────
local MAX_TOTAL = 16 -- including original
local CLONE_Y = 0 -- must match MonsterAI's MONSTER_Y

-- ── State ─────────────────────────────────────────────────────
local activeClones: { { model: Model, brain: any } } = {}
local RE_PlayerDied: RemoteEvent?
local _grid: { { number } } = {}
local _gridReady = false

-- ── Public: store the PlayerDied remote ────────────────────────

function DuplicationSystem.init(playerDiedEvent: RemoteEvent)
	RE_PlayerDied = playerDiedEvent
end

-- ── Public: set the walkable grid (called when map generates) ─

function DuplicationSystem.setGrid(grid: { { number } })
	_grid = grid
	_gridReady = true
	-- Push grid to any clone brains that were created before the map
	for _, entry in ipairs(activeClones) do
		entry.brain:setGrid(grid)
	end
end

-- ── Public: activate / extend duplication ──────────────────────

function DuplicationSystem.processRules(
	original: Model,
	rules: { string },
	onBroadcastClone: ((Vector3, string, number) -> ())?
)
	local dupCount = 0
	for _, r in ipairs(rules) do
		if r == Constants.Rules.MONSTER_DUPLICATE then
			dupCount += 1
		end
	end
	if dupCount == 0 then
		return
	end

	local totalMonsters = math.min(1 + dupCount, MAX_TOTAL)
	local targetClones = totalMonsters - 1
	local currentClones = #activeClones

	if currentClones >= targetClones then
		-- Already have enough clones
		return
	end

	local clonesToSpawn = targetClones - currentClones

	for i = 1, clonesToSpawn do
		local cloneIndex = currentClones + i
		local clone = original:Clone()
		clone.Name = "SoulDragger_Clone_" .. cloneIndex

		for _, part in ipairs(clone:GetDescendants()) do
			if part:IsA("BasePart") then
				part.CanCollide = false
				part.CanQuery = false
				part.Anchored = false
			end
		end

		local cloneRoot = clone:FindFirstChild("HumanoidRootPart")
			or clone:FindFirstChild("rb")
			or clone.PrimaryPart
		if cloneRoot then
			cloneRoot.Anchored = true
		end

		-- Spawn in a ring around the original
		local angle = (cloneIndex / targetClones) * math.pi * 2
		local offset = Vector3.new(math.cos(angle) * 24, 0, math.sin(angle) * 24)
		local spawnP = original:GetPivot().Position + offset
		clone:PivotTo(CFrame.new(Vector3.new(spawnP.X, CLONE_Y, spawnP.Z)))
		clone.Parent = workspace

		-- Create a MonsterBrain for this clone (no grace, reads speed from Constants)
		local brain = MonsterBrain.new(clone, rules, {
			monsterY = CLONE_Y,
			monsterIndex = cloneIndex + 1, -- original is index 1
			graceTime = 0, -- clones activate immediately
			onDied = function(playerName: string)
				if RE_PlayerDied then
					RE_PlayerDied:FireAllClients(playerName)
				end
			end,
			onBroadcast = onBroadcastClone,
		})

		-- If the grid is already available, give it to the clone brain now
		if _gridReady then
			brain:setGrid(_grid)
		end

		brain:start()

		table.insert(activeClones, { model = clone, brain = brain })
	end

	print(
		("[DupSystem] %d clone(s) spawned → %d total monsters"):format(clonesToSpawn, targetClones + 1)
	)
end

-- ── Public: update rules on all clone brains mid-session ─────

function DuplicationSystem.setRules(rules: { string })
	for _, entry in ipairs(activeClones) do
		entry.brain:setRules(rules)
	end
end

-- ── Public: cleanup all clones (on game end) ─────────────────

function DuplicationSystem.cleanup()
	for _, entry in ipairs(activeClones) do
		entry.brain:stop()
		if entry.model and entry.model.Parent then
			entry.model:Destroy()
		end
	end
	activeClones = {}
	_grid = {}
	_gridReady = false
	print("[DupSystem] All clones cleaned up.")
end

return DuplicationSystem