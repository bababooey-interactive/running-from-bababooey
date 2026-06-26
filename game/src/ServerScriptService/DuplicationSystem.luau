-- =============================================================
--  DuplicationSystem.luau  (ModuleScript — Day 8-9)
--  Clones SoulDragger when MONSTER_DUPLICATE rule is active.
--  Each clone runs its own simple AI coroutine.
--  Exponential: 1 rule = 2 monsters, 2 rules = 4, capped at 4.
-- =============================================================
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService") -- ✨ ADDED TWEEN SERVICE
local Constants = require(game.ReplicatedStorage.Shared.Constants)
local SoundManager = require(script.Parent.SoundManager)
local SensorSystem = require(script.Parent.SensorSystem)
local DuplicationSystem = {}

-- ── Config ────────────────────────────────────────────────────
local MAX_TOTAL = 16 -- including original (so max 3 clones)
local CLONE_SPEED = 13 -- studs/s
local CLONE_Y = 0 -- must match MonsterAI's MONSTER_Y
-- local TILE = 16 -- must match MapGenerator's TILE_SIZE

local activeClones: { Model } = {}
local RE_PlayerDied: RemoteEvent?

function DuplicationSystem.init(playerDiedEvent: RemoteEvent)
	RE_PlayerDied = playerDiedEvent
end

-- ── Tentacle Attack Visual (For Clones) ───────────────────────
local function shootBlackTentacles(cloneModel: Model, rootPart: BasePart, targetPos: Vector3, extendTime: number)
	local leftLimb = cloneModel:FindFirstChild("LeftHand", true)
		or cloneModel:FindFirstChild("Left Arm", true)
		or cloneModel:FindFirstChild("leftarm", true)
		or rootPart

	local rightLimb = cloneModel:FindFirstChild("RightHand", true)
		or cloneModel:FindFirstChild("Right Arm", true)
		or cloneModel:FindFirstChild("rightarm", true)
		or rootPart

	local limbs = { leftLimb, rightLimb }
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
		endPart.Position = limb.Position + (rootPart.CFrame.LookVector * 1)
		endPart.Parent = workspace

		local att1 = Instance.new("Attachment")
		att1.Parent = endPart

		local beam = Instance.new("Beam")
		beam.Attachment0 = att0
		beam.Attachment1 = att1
		beam.Color = ColorSequence.new(Color3.fromRGB(0, 0, 0))
		beam.Transparency = NumberSequence.new(0)
		beam.Width0 = 3.5
		beam.Width1 = 0.2
		beam.FaceCamera = true
		beam.CurveSize0 = math.random(-4, 4)
		beam.CurveSize1 = math.random(-4, 4)
		beam.Parent = endPart

		table.insert(activeTentacles, { part = endPart, limb = limb })

		TweenService:Create(
			endPart,
			TweenInfo.new(extendTime, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
			{ Position = targetPos }
		):Play()
	end

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

-- ── Simple clone AI (runs in task.spawn coroutine) ────────────

local function runCloneAI(clone: Model, rules: { string })
	local root = clone:FindFirstChild("HumanoidRootPart") or clone:FindFirstChild("rb") or clone.PrimaryPart
	if not root then
		return
	end

	clone.PrimaryPart = root
	local cloneSounds = SoundManager.new(clone)
	local currentState = "IDLE"
	cloneSounds:onStateChange("IDLE", false)

	-- Load walk and run animations
	local hum = clone:FindFirstChildOfClass("Humanoid")
	local animator = hum and hum:FindFirstChildOfClass("Animator")

	local walkTrack, runTrack, spottedTrack, jumpscareTrack
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

		local spottedAnim = Instance.new("Animation")
		spottedAnim.AnimationId = "rbxassetid://91571146490557"
		spottedTrack = animator:LoadAnimation(spottedAnim)
		spottedTrack.Priority = Enum.AnimationPriority.Action

		local jumpAnim = Instance.new("Animation")
		jumpAnim.AnimationId = "rbxassetid://79583022426609"
		jumpscareTrack = animator:LoadAnimation(jumpAnim)
		jumpscareTrack.Priority = Enum.AnimationPriority.Action
	end

	local idleTimer = 0
	local wanderTarget: Vector3? = nil

	-- ── Suspicion / Certainty System (matches MonsterAI) ────────
	local suspicion: { [Player]: number } = {}
	local SUSPICION_DECAY_RATE = 0.12
	local SUSPICION_CHASE_THRESHOLD = 0.7

	-- ── Chase Persistence (matches MonsterAI) ───────────────────
	local chaseTarget: Player? = nil
	local lostTimer = 0
	local chaseDuration = 0
	local lastKnownPos: Vector3? = nil
	local postChaseSearchPos: Vector3? = nil
	local searchWanderTimer = 0

	-- ── Constants (matches MonsterAI) ───────────────────────────
	local CHASE_LOST_TIME = 4
	local INVESTIGATE_TIMEOUT = 6
	local INVESTIGATE_SPEED_MUL = 0.7
	local DISTRACTION_THRESHOLD = 0.4
	local SMELL_CHASE_DIST = 8
	local SEARCH_WANDER_DURATION = 4
	local SENSOR_INT = 0.25

	local investigatePos: Vector3? = nil
	local investigateTimer = 0
	local spotPlayedFor: Player? = nil
	local lastSensedPlayers: { [Player]: boolean } = {}

	-- ── State transition helpers (matches MonsterAI) ────────────
	local function beginChase(player: Player)
		if chaseTarget ~= player then
			chaseTarget = player
			if walkTrack and walkTrack.IsPlaying then walkTrack:Stop(0.2) end
			if runTrack and not runTrack.IsPlaying then runTrack:Play(0.2) end
			if spotPlayedFor ~= player then
				spotPlayedFor = player
				if spottedTrack then
					task.spawn(function()
						task.wait(0.05)
						spottedTrack:Play(0.1)
					end)
				end
			end
		end
		if player.Character then
			local hrp = player.Character:FindFirstChild("HumanoidRootPart")
			if hrp then
				lastKnownPos = hrp.Position
			end
		end
		local effectiveLostTime = CHASE_LOST_TIME + math.min(chaseDuration * 0.3, 4)
		lostTimer = effectiveLostTime
		chaseDuration = 0
		currentState = "CHASE"
		investigatePos = nil
		cloneSounds:onStateChange("CHASE", true)
	end

	local function beginIdle()
		currentState = "IDLE"
		chaseTarget = nil
		investigatePos = nil
		wanderTarget = nil
		suspicion = {}
		chaseDuration = 0
		postChaseSearchPos = nil
		searchWanderTimer = 0
		spotPlayedFor = nil
		if runTrack and runTrack.IsPlaying then runTrack:Stop(0.2) end
		if walkTrack and not walkTrack.IsPlaying then walkTrack:Play(0.2) end
		cloneSounds:onStateChange("IDLE", false)
	end

	local function beginInvestigate(position: Vector3)
		investigatePos = position
		investigateTimer = INVESTIGATE_TIMEOUT
		chaseTarget = nil
		currentState = "INVESTIGATE"
		if runTrack and runTrack.IsPlaying then runTrack:Stop(0.2) end
		if walkTrack and not walkTrack.IsPlaying then walkTrack:Play(0.2) end
		cloneSounds:onStateChange("IDLE", false)
	end

	local sensorCD = 0

	while clone.Parent ~= nil do
		local dt = RunService.Heartbeat:Wait()
		local pos = root.Position

		sensorCD += dt

		-- ── Sensor tick (every SENSOR_INT seconds) ──────────────
		if sensorCD >= SENSOR_INT and currentState ~= "CATCH" then
			sensorCD = 0
			local all = Players:GetPlayers()

			local heard = SensorSystem.CheckHearing(pos, rules)
			local smelled = SensorSystem.CheckSmell(pos, all, rules)
			local seen = SensorSystem.CheckVision(clone, pos, all, rules)

			-- Vision: always triggers immediate CHASE
			if seen then
				local seenChar = seen.Character
				local seenHRP = seenChar and seenChar:FindFirstChild("HumanoidRootPart")
				if seenHRP then
					lastKnownPos = seenHRP.Position
				end
				suspicion[seen] = 1.0
				beginChase(seen)
			end

			-- Build suspicion from hearing
			if heard and heard.player then
				local p = heard.player
				local gain = heard.level * 0.35
				suspicion[p] = math.min((suspicion[p] or 0) + gain, 1.0)
				lastKnownPos = heard.position
			end

			-- Build suspicion from smell
			if smelled then
				local smellChar = smelled.Character
				local smellHRP = smellChar and smelled.Character:FindFirstChild("HumanoidRootPart")
				if smellHRP then
					local smellDist = (pos - smellHRP.Position).Magnitude
					local smellFactor = 1 - (smellDist / Constants.MONSTER_SMELL_RADIUS)
					suspicion[smelled] = math.min((suspicion[smelled] or 0) + smellFactor * 0.25, 1.0)
					lastKnownPos = smellHRP.Position
				end
			end

			-- Track sensed players for suspicion decay
			lastSensedPlayers = {}
			if seen then lastSensedPlayers[seen] = true end
			if smelled then lastSensedPlayers[smelled] = true end
			if heard and heard.player then lastSensedPlayers[heard.player] = true end

			-- Check if any player reached chase threshold
			local highestSuspPlayer: Player? = nil
			local highestSuspLevel = 0
			for p, level in pairs(suspicion) do
				if level >= SUSPICION_CHASE_THRESHOLD and level > highestSuspLevel then
					highestSuspLevel = level
					highestSuspPlayer = p
				end
			end

			-- ── State-specific sensor processing ─────────────────
			if currentState == "IDLE" then
				if highestSuspPlayer then
					beginChase(highestSuspPlayer)
				elseif heard and heard.player then
					beginInvestigate(heard.position)
				elseif heard then
					beginInvestigate(heard.position)
				elseif smelled then
					local smellChar = smelled.Character
					local smellHRP = smellChar and smelled.Character:FindFirstChild("HumanoidRootPart")
					if smellHRP then
						local smellDist = (pos - smellHRP.Position).Magnitude
						if smellDist <= SMELL_CHASE_DIST then
							lastKnownPos = smellHRP.Position
							beginChase(smelled)
						else
							beginInvestigate(smellHRP.Position)
						end
					end
				end
			elseif currentState == "INVESTIGATE" then
				if highestSuspPlayer then
					beginChase(highestSuspPlayer)
				elseif not seen and smelled then
					local smellChar = smelled.Character
					local smellHRP = smellChar and smelled.Character:FindFirstChild("HumanoidRootPart")
					if smellHRP then
						local smellDist = (pos - smellHRP.Position).Magnitude
						if smellDist <= SMELL_CHASE_DIST then
							lastKnownPos = smellHRP.Position
							beginChase(smelled)
						else
							investigatePos = smellHRP.Position
							investigateTimer = INVESTIGATE_TIMEOUT
						end
					end
				end

				if not seen and heard and heard.level > 0.3 then
					if investigatePos then
						local newDist = (pos - heard.position).Magnitude
						local curDist = (pos - investigatePos).Magnitude
						if newDist < curDist * 0.7 or heard.level > 0.7 then
							investigatePos = heard.position
							investigateTimer = INVESTIGATE_TIMEOUT
						end
					else
						investigatePos = heard.position
						investigateTimer = INVESTIGATE_TIMEOUT
					end
				end

				investigateTimer -= SENSOR_INT
				if investigateTimer <= 0 then
					beginIdle()
				end
			elseif currentState == "SEARCH" then
				if highestSuspPlayer then
					beginChase(highestSuspPlayer)
				elseif heard then
					beginInvestigate(heard.position)
				elseif smelled then
					local smellChar = smelled.Character
					local smellHRP = smellChar and smelled.Character:FindFirstChild("HumanoidRootPart")
					if smellHRP then
						local smellDist = (pos - smellHRP.Position).Magnitude
						if smellDist <= SMELL_CHASE_DIST then
							lastKnownPos = smellHRP.Position
							beginChase(smelled)
						else
							beginInvestigate(smellHRP.Position)
						end
					end
				end
			elseif currentState == "CHASE" then
				local effectiveLostTime = CHASE_LOST_TIME + math.min(chaseDuration * 0.3, 4)

				if seen then
					lostTimer = effectiveLostTime
				elseif smelled then
					local smellChar = smelled.Character
					local smellHRP = smellChar and smelled.Character:FindFirstChild("HumanoidRootPart")
					if smellHRP then
						local smellDist = (pos - smellHRP.Position).Magnitude
						local smellProximity = 1 - (smellDist / Constants.MONSTER_SMELL_RADIUS)
						local smellReset = effectiveLostTime * smellProximity * 0.8
						lostTimer = math.max(lostTimer, smellReset)
					end
				elseif heard and heard.player == chaseTarget then
					lostTimer = math.max(lostTimer, effectiveLostTime * 0.4)
				else
					lostTimer -= SENSOR_INT
				end

				-- Distraction: anonymous world noise can break the chase
				if not seen and heard and heard.player == nil then
					local dist = (pos - heard.position).Magnitude
					local hearRadius = Constants.MONSTER_HEAR_RADIUS
					if dist <= hearRadius then
						local distractionScore = heard.level * (1 - dist / hearRadius)
						local effectiveThreshold = DISTRACTION_THRESHOLD + math.min(chaseDuration * 0.04, 0.35)
						if smelled then
							effectiveThreshold *= 1.5
						end
						if distractionScore >= effectiveThreshold then
							postChaseSearchPos = lastKnownPos
							beginInvestigate(heard.position)
						end
					end
				end

				if lostTimer <= 0 then
					postChaseSearchPos = lastKnownPos
					if lastKnownPos then
						beginInvestigate(lastKnownPos)
					else
						beginIdle()
					end
				end
			end
		end

		-- ── Suspicion decay ──────────────────────────────────────
		if currentState ~= "CATCH" then
			for p, level in pairs(suspicion) do
				if not lastSensedPlayers[p] then
					suspicion[p] = math.max(0, level - SUSPICION_DECAY_RATE * dt)
					if suspicion[p] <= 0 then
						suspicion[p] = nil
					end
				end
			end
		end

		-- ── Chase duration tracking ─────────────────────────────
		if currentState == "CHASE" then
			chaseDuration += dt
		end

		-- ── Movement by state ────────────────────────────────────
		if currentState == "IDLE" then
			idleTimer += 0.05
			if idleTimer >= 3 or not wanderTarget then
				idleTimer = 0
				local spread = 24
				wanderTarget = Vector3.new(pos.X + math.random(-spread, spread), CLONE_Y, pos.Z + math.random(-spread, spread))
			end
			if wanderTarget then
				local dir = wanderTarget - pos
				local flatDir = Vector3.new(dir.X, 0, dir.Z)
				local dist = flatDir.Magnitude
				if dist > 1 then
					local step = math.min(5 * dt, dist)
					local newPos = Vector3.new(pos.X + flatDir.Unit.X * step, CLONE_Y, pos.Z + flatDir.Unit.Z * step)
					if dist > 0.001 then
						clone:PivotTo(CFrame.lookAt(newPos, newPos + flatDir.Unit))
					else
						clone:PivotTo(CFrame.new(newPos))
					end
				else
					wanderTarget = nil
				end
			end
		elseif currentState == "INVESTIGATE" and investigatePos then
			local dir = investigatePos - pos
			local flatDir = Vector3.new(dir.X, 0, dir.Z)
			local dist = flatDir.Magnitude
			if dist > 1 then
				local speed = CLONE_SPEED * INVESTIGATE_SPEED_MUL
				local step = math.min(speed * dt, dist)
				local newPos = Vector3.new(pos.X + flatDir.Unit.X * step, CLONE_Y, pos.Z + flatDir.Unit.Z * step)
				if dist > 0.001 then
					clone:PivotTo(CFrame.lookAt(newPos, newPos + flatDir.Unit))
				else
					clone:PivotTo(CFrame.new(newPos))
				end
			else
				-- Reached investigation target
				if postChaseSearchPos then
					currentState = "SEARCH"
					searchWanderTimer = SEARCH_WANDER_DURATION
				else
					beginIdle()
				end
			end
		elseif currentState == "SEARCH" then
			searchWanderTimer -= dt
			if searchWanderTimer <= 0 then
				beginIdle()
			else
				if not wanderTarget then
					local searchCenter = postChaseSearchPos or pos
					local spread = 12
					wanderTarget = Vector3.new(
						searchCenter.X + math.random(-spread, spread),
						CLONE_Y,
						searchCenter.Z + math.random(-spread, spread)
					)
				end
				if wanderTarget then
					local dir = wanderTarget - pos
					local flatDir = Vector3.new(dir.X, 0, dir.Z)
					local dist = flatDir.Magnitude
					if dist > 1 then
						local speed = CLONE_SPEED * 0.5
						local step = math.min(speed * dt, dist)
						local newPos = Vector3.new(pos.X + flatDir.Unit.X * step, CLONE_Y, pos.Z + flatDir.Unit.Z * step)
						if dist > 0.001 then
							clone:PivotTo(CFrame.lookAt(newPos, newPos + flatDir.Unit))
						else
							clone:PivotTo(CFrame.new(newPos))
						end
					else
						wanderTarget = nil
					end
				end
			end
		elseif currentState == "CHASE" and chaseTarget then
			local char = chaseTarget.Character
			if not char then
				postChaseSearchPos = lastKnownPos
				if lastKnownPos then
					beginInvestigate(lastKnownPos)
				else
					beginIdle()
				end
				continue
			end
			local hrp = char:FindFirstChild("HumanoidRootPart")
			if not hrp then
				postChaseSearchPos = lastKnownPos
				if lastKnownPos then
					beginInvestigate(lastKnownPos)
				else
					beginIdle()
				end
				continue
			end

			lastKnownPos = hrp.Position

			-- Catch radius
			local catchR = Constants.MONSTER_REACH_BASE
			if table.find(rules, Constants.Rules.MONSTER_REACH) then
				catchR += Constants.MONSTER_REACH_BONUS
			end

			-- ── Flat XZ distance (consistent with primary MonsterAI) ─────
			local flatCPos = Vector3.new(pos.X, 0, pos.Z)
			local flatPPos = Vector3.new(hrp.Position.X, 0, hrp.Position.Z)

			if (flatCPos - flatPPos).Magnitude <= catchR then
				local snapPos = hrp.Position
				local monPos = root.Position
				local flatDir = Vector3.new(snapPos.X - monPos.X, 0, snapPos.Z - monPos.Z)
				local flatDist = flatDir.Magnitude

				-- FIX: guard against NaN when player is directly above clone
				if flatDist > 0.1 then
					root.CFrame = CFrame.lookAt(monPos, monPos + flatDir.Unit)
				end

				local STRIKE_TIME = 0.25

				if flatDist > 0.1 then
					local lungePos = monPos + flatDir.Unit * math.max(0, flatDist - 1.5)
					TweenService:Create(
						root,
						TweenInfo.new(STRIKE_TIME, Enum.EasingStyle.Sine),
						{ CFrame = CFrame.lookAt(lungePos, lungePos + flatDir.Unit) }
					):Play()
				end

				currentState = "CATCH"
				cloneSounds:onStateChange("CATCH", false)
				if jumpscareTrack then
					jumpscareTrack:Play()
				end
				shootBlackTentacles(clone, root, snapPos + Vector3.new(0, 1, 0), STRIKE_TIME)
				task.wait(STRIKE_TIME)

				if not chaseTarget or not chaseTarget.Character then
					currentState = "IDLE"
					continue
				end
				local liveHRP = chaseTarget.Character:FindFirstChild("HumanoidRootPart")
				if liveHRP then
					local IMPACT_HITBOX = 4
					if (liveHRP.Position - snapPos).Magnitude <= IMPACT_HITBOX then
						cloneSounds:playHitSounds()
						local hum2 = char:FindFirstChildOfClass("Humanoid")
						if hum2 and hum2.Health > 0 then
							hum2.Health = 0
							if RE_PlayerDied then
								RE_PlayerDied:FireAllClients(chaseTarget.Name)
							end
						end
						task.wait(2)
					else
						task.wait(1.2)
					end
				end
				currentState = "IDLE"
				continue
			end

			-- Move toward player
			local dir = hrp.Position - pos
			local flatDir = Vector3.new(dir.X, 0, dir.Z)
			local flatDist = flatDir.Magnitude

			if flatDist > 0.5 then
				local step = math.min(CLONE_SPEED * dt, flatDist)
				local newPos = Vector3.new(pos.X + flatDir.Unit.X * step, CLONE_Y, pos.Z + flatDir.Unit.Z * step)

				if flatDist > 0.001 then
					clone:PivotTo(CFrame.lookAt(newPos, newPos + flatDir.Unit))
				else
					clone:PivotTo(CFrame.new(newPos))
				end
			end
		end
	end
end

-- ── Public: activate duplication ─────────────────────────────

function DuplicationSystem.processRules(original: Model, rules: { string })
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
	local clonesNeeded = totalMonsters - 1

	for i = 1, clonesNeeded do
		local clone = original:Clone()
		clone.Name = "SoulDragger_Clone_" .. i

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

		local angle = (i / clonesNeeded) * math.pi * 2
		local offset = Vector3.new(math.cos(angle) * 24, 0, math.sin(angle) * 24)
		local spawnP = original:GetPivot().Position + offset
		clone:PivotTo(CFrame.new(Vector3.new(spawnP.X, CLONE_Y, spawnP.Z)))
		clone.Parent = workspace

		table.insert(activeClones, clone)

		local capturedRules = rules
		task.spawn(function()
			task.wait(0.3)
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
