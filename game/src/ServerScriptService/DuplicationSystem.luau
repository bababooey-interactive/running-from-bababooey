-- =============================================================
--  DuplicationSystem.luau  (ModuleScript — Day 8-9)
--  Clones SoulDragger when MONSTER_DUPLICATE rule is active.
--  Each clone runs its own simple AI coroutine.
--  Exponential: 1 rule = 2 monsters, 2 rules = 4, capped at 4.
-- =============================================================

local Players = game:GetService("Players")
local Constants = require(game.ReplicatedStorage.Shared.Constants)

local DuplicationSystem = {}

-- ── Config ────────────────────────────────────────────────────
local MAX_TOTAL = 4 -- including original (so max 3 clones)
local CLONE_SPEED = 13 -- studs/s
local CLONE_Y = 3 -- must match MonsterAI's MONSTER_Y
local TILE = 16 -- must match MapGenerator's TILE_SIZE

local activeClones: { Model } = {}
local RE_PlayerDied: RemoteEvent?

function DuplicationSystem.init(playerDiedEvent: RemoteEvent)
	RE_PlayerDied = playerDiedEvent
end

-- ── Simple clone AI (runs in task.spawn coroutine) ────────────

local function runCloneAI(clone: Model, rules: { string })
	local root = clone:FindFirstChild("HumanoidRootPart") or clone:FindFirstChild("rb") or clone.PrimaryPart
	if not root then
		return
	end

	clone.PrimaryPart = root

	-- Load walk and run animations
	local hum = clone:FindFirstChildOfClass("Humanoid")
	local animator = hum and hum:FindFirstChildOfClass("Animator")

	local walkTrack, runTrack
	if animator then
		local walkAnim = Instance.new("Animation")
		walkAnim.AnimationId = "rbxassetid://90825719838414"
		walkTrack = animator:LoadAnimation(walkAnim)
		walkTrack.Priority = Enum.AnimationPriority.Movement
		walkTrack.Looped = true
		walkTrack:Play()

		local runAnim = Instance.new("Animation")
		runAnim.AnimationId = "rbxassetid://75452347275172"
		runTrack = animator:LoadAnimation(runAnim)
		runTrack.Priority = Enum.AnimationPriority.Movement
		runTrack.Looped = true
	end

	local idleTimer = 0
	local wanderTarget: Vector3? = nil

	while clone.Parent ~= nil do
		task.wait(0.05)

		local pos = root.Position

		-- Find nearest player within detection range
		local target: Player? = nil
		local targetDist = 60 -- detection range

		for _, pl in ipairs(Players:GetPlayers()) do
			local char = pl.Character
			if not char then
				continue
			end
			local hrp = char:FindFirstChild("HumanoidRootPart")
			if not hrp then
				continue
			end
			local d = (pos - hrp.Position).Magnitude
			if d < targetDist then
				targetDist = d
				target = pl
			end
		end

		if target then
			if walkTrack and walkTrack.IsPlaying then
				walkTrack:Stop(0.2)
			end
			if runTrack and not runTrack.IsPlaying then
				runTrack:Play(0.2)
			end
			local char = target.Character
			if not char then
				continue
			end
			local hrp = char:FindFirstChild("HumanoidRootPart")
			if not hrp then
				continue
			end

			-- Catch radius
			local catchR = Constants.MONSTER_REACH_BASE
			if table.find(rules, Constants.Rules.MONSTER_REACH) then
				catchR += Constants.MONSTER_REACH_BONUS
			end

			if (pos - hrp.Position).Magnitude <= catchR then
				-- Caught!
				local hum2 = char:FindFirstChildOfClass("Humanoid")
				if hum2 then
					hum2.Health = 0
				end
				if RE_PlayerDied then
					RE_PlayerDied:FireAllClients(target.Name)
				end
				task.wait(2)
				continue
			end

			-- Move toward player (direct — no A* for clones)
			local dir = hrp.Position - pos
			local flatDir = Vector3.new(dir.X, 0, dir.Z)
			local flatDist = flatDir.Magnitude

			if flatDist > 0.5 then
				local step = math.min(CLONE_SPEED * 0.05, flatDist)
				local newPos = Vector3.new(pos.X + flatDir.Unit.X * step, CLONE_Y, pos.Z + flatDir.Unit.Z * step)

				if flatDist > 0.001 then
					clone:PivotTo(CFrame.lookAt(newPos, newPos + flatDir.Unit))
				else
					clone:PivotTo(CFrame.new(newPos))
				end
			end
		else
			if runTrack and runTrack.IsPlaying then
				runTrack:Stop(0.2)
			end
			if walkTrack and not walkTrack.IsPlaying then
				walkTrack:Play(0.2)
			end
			-- Idle wander
			idleTimer += 0.05
			if idleTimer >= 3 or not wanderTarget then
				idleTimer = 0
				local spread = 48
				wanderTarget =
					Vector3.new(pos.X + math.random(-spread, spread), CLONE_Y, pos.Z + math.random(-spread, spread))
			end
			if wanderTarget then
				local dir = wanderTarget - pos
				local dist = Vector2.new(dir.X, dir.Z).Magnitude
				if dist > 1 then
					local step = math.min(5 * 0.05, dist)
					local newPos = Vector3.new(pos.X + dir.Unit.X * step, CLONE_Y, pos.Z + dir.Unit.Z * step)

					if dist > 0.001 then
						clone:PivotTo(CFrame.lookAt(newPos, newPos + dir.Unit))
					else
						clone:PivotTo(CFrame.new(newPos))
					end
				else
					wanderTarget = nil
				end
			end
		end
	end
end

-- ── Public: activate duplication ─────────────────────────────

function DuplicationSystem.processRules(original: Model, rules: { string })
	-- Count MONSTER_DUPLICATE appearances (stacks)
	local dupCount = 0
	for _, r in ipairs(rules) do
		if r == Constants.Rules.MONSTER_DUPLICATE then
			dupCount += 1
		end
	end
	if dupCount == 0 then
		return
	end

	-- 1 rule = 2 monsters, 2 rules = 4 monsters (2^N), capped at MAX_TOTAL
	local totalMonsters = math.min(2 ^ dupCount, MAX_TOTAL)
	local clonesNeeded = totalMonsters - 1 -- original = 1

	for i = 1, clonesNeeded do
		local clone = original:Clone()
		clone.Name = "SoulDragger_Clone_" .. i

		-- Set noclip
		for _, part in ipairs(clone:GetDescendants()) do
			if part:IsA("BasePart") then
				part.CanCollide = false
				part.CanQuery = false
				part.Anchored = false
			end
		end
		local cloneRoot = clone:FindFirstChild("HumanoidRootPart") or clone:FindFirstChild("rb") or clone.PrimaryPart
		if cloneRoot then
			cloneRoot.Anchored = true
		end

		-- Spread clones evenly around original in a circle
		local angle = (i / clonesNeeded) * math.pi * 2
		local offset = Vector3.new(math.cos(angle) * 24, 0, math.sin(angle) * 24)
		local spawnP = original:GetPivot().Position + offset
		clone:PivotTo(CFrame.new(Vector3.new(spawnP.X, CLONE_Y, spawnP.Z)))
		clone.Parent = workspace

		table.insert(activeClones, clone)

		-- Run AI coroutine for this clone
		local capturedRules = rules
		task.spawn(function()
			task.wait(0.3) -- let clone finish initializing
			runCloneAI(clone, capturedRules)
		end)
	end

	print(("[DupSystem] %d clone(s) spawned → %d total monsters"):format(clonesNeeded, totalMonsters))
end

-- ── Public: cleanup all clones (on game end) ─────────────────

function DuplicationSystem.cleanup()
	for _, clone in ipairs(activeClones) do
		if clone and clone.Parent then
			clone:Destroy()
		end
	end
	activeClones = {}
	print("[DupSystem] All clones cleaned up.")
end

return DuplicationSystem
