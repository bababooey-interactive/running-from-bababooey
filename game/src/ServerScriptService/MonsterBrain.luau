-- =============================================================
--  MonsterBrain.luau  (ModuleScript)
--  Shared AI brain used by MonsterAI.server.luau (original) and
--  DuplicationSystem.luau (clones).
--
--  Path: game/src/ServerScriptService/MonsterBrain.luau
--
--  CHANGES:
--  • Escape window is now much more forgiving:
--      - CHASE_LOST_TIME reduced 4 → 2.5 s
--      - Chase-duration lostTimer extension halved (×0.15, cap 2 s)
--      - Smell/hearing no longer meaningfully top up lostTimer while
--        the target isn't seen — smell gives 20 % restore (was 80 %),
--        hearing gives 15 % restore (was 40 %)
--      - INVESTIGATE_TIMEOUT reduced 6 → 3.5 s (monster gives up
--        searching sooner after losing the player)
--  • Monster freezes in place during the Spotted animation:
--      - _spottedAnimPlaying flag blocks _handleMovement
--      - lostTimer still ticks normally during the freeze so the
--        player gets a real head-start window before the chase moves
-- =============================================================

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Constants = require(game.ReplicatedStorage.Shared.Constants)
local SensorSystem = require(script.Parent.SensorSystem)
local SoundManager = require(script.Parent.SoundManager)

-- ─────────────────────────────────────────────
--  Constants shared by all instances
-- ─────────────────────────────────────────────
local CHASE_LOST_TIME = 3 -- was 4: seconds before monster loses player when not sensed
local INVESTIGATE_TIMEOUT = 4.5 -- was 6: seconds monster spends searching last known pos
local INVESTIGATE_SPEED_MUL = 0.7
local DISTRACTION_THRESHOLD = 0.4
local SMELL_CHASE_DIST = 8
local IDLE_RANGE = 5 -- tiles
local SEARCH_WANDER_DURATION = 4
local SENSOR_INT = 0.25
local SUSPICION_DECAY_RATE = 0.12
local SUSPICION_CHASE_THRESHOLD = 0.7
local BROADCAST_INTERVAL = 0.5

-- Escape-window tuning
-- lostTimer top-ups when player is sensed indirectly (smell/hearing)
-- but NOT seen. Keeping these low lets the player break line-of-sight
-- and actually escape rather than having the monster perpetually refresh.
local SMELL_LOST_TIMER_RESTORE = 0.60 -- fraction of effectiveLost restored by smell  (was 0.80)
local HEAR_LOST_TIMER_RESTORE = 0.3 -- fraction of effectiveLost restored by hearing (was 0.40)

-- Chase-duration extension cap (makes long chases not last forever)
local CHASE_DURATION_MUL = 0.23 -- was 0.30
local CHASE_DURATION_CAP = 3.0 -- was 4.0

local MonsterBrain = {}
MonsterBrain.__index = MonsterBrain

-- ─────────────────────────────────────────────
--  Constructor
-- ─────────────────────────────────────────────
function MonsterBrain.new(monster: Model, rules: { string }, config: { [string]: any }?)
	config = config or {}

	local self = setmetatable({}, MonsterBrain)

	self.monster = monster
	self.rules = rules
	self.monsterY = config.monsterY or 0
	self.monsterIndex = config.monsterIndex or 1
	self.graceTime = config.graceTime or 0
	self.onDied = config.onDied
	self.onBroadcast = config.onBroadcast

	self.chaseSpeed = config.speed
		or math.min(Constants.MONSTER_SPEED_BASE + Constants.MONSTER_SPEED_PER_LEVEL, Constants.MONSTER_SPEED_MAX)

	self.rootPart = monster:FindFirstChild("HumanoidRootPart") or monster:FindFirstChild("rb") or monster.PrimaryPart
	assert(self.rootPart, "[MonsterBrain] Monster needs a HumanoidRootPart or 'rb' part")
	self.rootPart.Anchored = true
	monster.PrimaryPart = self.rootPart

	self.sounds = SoundManager.new(monster)

	self.tracks = {}
	self:_loadAnimations()

	self.state = "IDLE"
	self.chaseTarget = nil
	self.lostTimer = 0
	self.idleTarget = nil
	self.investigatePos = nil
	self.investigateTimer = 0
	self.lastKnownPos = nil
	self.spotPlayedFor = nil
	self.suspicion = {}
	self.chaseDuration = 0
	self.postChaseSearchPos = nil
	self.searchWanderTimer = 0
	self.lastSensedPlayers = {}
	self.currentMovement = ""

	-- NEW: blocks _handleMovement while the Spotted anim plays
	self._spottedAnimPlaying = false

	self._connection = nil
	self._grid = {}
	self._gridReady = false
	self._sensorCD = 0
	self._broadcastCD = BROADCAST_INTERVAL
	self._graceActive = self.graceTime > 0

	return self
end

-- ─────────────────────────────────────────────
--  Public: set the walkable grid from MapGenerator
-- ─────────────────────────────────────────────
function MonsterBrain:setGrid(grid: { { number } })
	self._grid = grid
	self._gridReady = true
end

-- ─────────────────────────────────────────────
--  Public: start the AI loop
-- ─────────────────────────────────────────────
function MonsterBrain:start()
	if self._graceActive then
		task.delay(self.graceTime, function()
			self._graceActive = false
			self:_beginIdle()
			print(("[MonsterBrain] Grace ended for monster #%d"):format(self.monsterIndex))
		end)
	end

	self._connection = RunService.Heartbeat:Connect(function(dt)
		self:_tick(dt)
	end)
end

-- ─────────────────────────────────────────────
--  Public: stop the AI loop
-- ─────────────────────────────────────────────
function MonsterBrain:stop()
	if self._connection then
		self._connection:Disconnect()
		self._connection = nil
	end
end

-- ─────────────────────────────────────────────
--  Public: update active rules mid-session
-- ─────────────────────────────────────────────
function MonsterBrain:setRules(rules: { string })
	self.rules = rules
end

-- ─────────────────────────────────────────────
--  Animation helpers
-- ─────────────────────────────────────────────
local ANIM_IDS = {
	Walk = "rbxassetid://90825719838414",
	Run = "rbxassetid://75452347275172",
	Spotted = "rbxassetid://91571146490557",
	Jumpscare = "rbxassetid://79583022426609",
}

function MonsterBrain:_loadAnimations()
	local humanoid = self.monster:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and (humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator", humanoid))
	if not animator then
		return
	end

	for name, id in pairs(ANIM_IDS) do
		local anim = Instance.new("Animation")
		anim.AnimationId = id
		local track = animator:LoadAnimation(anim)
		track.Priority = (name == "Spotted" or name == "Jumpscare") and Enum.AnimationPriority.Action
			or Enum.AnimationPriority.Movement
		self.tracks[name] = track
	end
end

function MonsterBrain:_playMovement(name: string)
	if self.currentMovement == name then
		return
	end
	self.currentMovement = name
	for n, t in pairs(self.tracks) do
		if t.Priority == Enum.AnimationPriority.Movement and n ~= name and t.IsPlaying then
			t:Stop(0.2)
		end
	end
	if self.tracks[name] then
		self.tracks[name].Looped = true
		self.tracks[name]:Play(0.2)
	end
end

function MonsterBrain:_playAction(name: string)
	for _, t in pairs(self.tracks) do
		if t.Priority == Enum.AnimationPriority.Action and t.IsPlaying then
			t:Stop(0.1)
		end
	end
	if self.tracks[name] then
		self.tracks[name].Looped = false
		self.tracks[name]:Play(0.1)
	end
end

-- ─────────────────────────────────────────────
--  Grid helpers
-- ─────────────────────────────────────────────
function MonsterBrain:_tileToWorld(col: number, row: number): Vector3
	return Vector3.new((col - 1) * Constants.TILE_SIZE, self.monsterY, (row - 1) * Constants.TILE_SIZE)
end

function MonsterBrain:_worldToTile(pos: Vector3): (number, number)
	local g = self._grid
	local COLS = g[1] and #g[1] or 15
	local ROWS = #g > 0 and #g or 18
	local col = math.clamp(math.round(pos.X / Constants.TILE_SIZE) + 1, 1, COLS)
	local row = math.clamp(math.round(pos.Z / Constants.TILE_SIZE) + 1, 1, ROWS)
	return col, row
end

function MonsterBrain:_isTileWalkable(col: number, row: number): boolean
	local g = self._grid
	if not g[row] then
		return false
	end
	local t = g[row][col]
	return t ~= nil and t ~= 0
end

function MonsterBrain:_clampToMap(pos: Vector3): Vector3
	if not self._gridReady then
		return pos
	end
	local g = self._grid
	local ROWS = #g
	local COLS = g[1] and #g[1] or ROWS
	local m = Constants.TILE_SIZE
	return Vector3.new(
		math.clamp(pos.X, m, (COLS - 1) * Constants.TILE_SIZE - m),
		pos.Y,
		math.clamp(pos.Z, m, (ROWS - 1) * Constants.TILE_SIZE - m)
	)
end

function MonsterBrain:_pickIdleTarget(): Vector3
	local col, row = self:_worldToTile(self.rootPart.Position)
	for _ = 1, 30 do
		local nc = col + math.random(-IDLE_RANGE, IDLE_RANGE)
		local nr = row + math.random(-IDLE_RANGE, IDLE_RANGE)
		if self:_isTileWalkable(nc, nr) then
			return self:_tileToWorld(nc, nr)
		end
	end
	return self:_tileToWorld(col, row)
end

-- ─────────────────────────────────────────────
--  Movement
-- ─────────────────────────────────────────────
function MonsterBrain:_stepToward(target: Vector3, speed: number, dt: number): boolean
	local pivot = self.monster:GetPivot()
	local flat = Vector3.new(target.X, pivot.Position.Y, target.Z)
	local dir = flat - pivot.Position
	local dist = dir.Magnitude
	if dist < 0.6 then
		return true
	end

	local step = math.min(speed * dt, dist)
	local newPos = pivot.Position + dir.Unit * step
	newPos = self:_clampToMap(newPos)

	local targetRot = CFrame.lookAt(newPos, newPos + dir.Unit)
	local turnSpeed = self.state == "CHASE" and 14 or 6
	local smoothed = pivot:Lerp(targetRot, dt * turnSpeed)
	self.monster:PivotTo(CFrame.new(newPos) * smoothed.Rotation)
	return false
end

-- ─────────────────────────────────────────────
--  Tentacle attack visual
-- ─────────────────────────────────────────────
function MonsterBrain:_shootTentacles(targetPos: Vector3, extendTime: number)
	local limbs = {
		self.monster:FindFirstChild("LeftHand", true) or self.monster:FindFirstChild("Left Arm", true),
		self.monster:FindFirstChild("RightHand", true) or self.monster:FindFirstChild("Right Arm", true),
	}
	local active = {}
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
		endPart.Position = limb.Position + self.rootPart.CFrame.LookVector
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
		table.insert(active, { part = endPart, limb = limb })
		TweenService:Create(
			endPart,
			TweenInfo.new(extendTime, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
			{ Position = targetPos }
		):Play()
	end
	task.delay(extendTime + 0.8, function()
		for _, t in ipairs(active) do
			if t.part and t.limb then
				local r = TweenService:Create(
					t.part,
					TweenInfo.new(0.3, Enum.EasingStyle.Sine, Enum.EasingDirection.In),
					{ Position = t.limb.Position }
				)
				r:Play()
				r.Completed:Once(function()
					t.part:Destroy()
				end)
			end
		end
	end)
end

-- ─────────────────────────────────────────────
--  State transitions
-- ─────────────────────────────────────────────
function MonsterBrain:_beginIdle()
	self.state = "IDLE"
	self.chaseTarget = nil
	self.investigatePos = nil
	self.idleTarget = nil
	self.suspicion = {}
	self.chaseDuration = 0
	self.postChaseSearchPos = nil
	self.searchWanderTimer = 0
	self:_playMovement("Walk")
	self.sounds:onStateChange("IDLE", false)
end

function MonsterBrain:_beginChase(player: Player)
	local isNewTarget = self.chaseTarget ~= player

	if isNewTarget then
		self.chaseTarget = player
		self:_playMovement("Run")

		-- ── Spotted animation: freeze the monster while it plays ──
		-- The lostTimer still ticks down during the freeze, giving the
		-- player a real head-start window before the monster moves.
		if self.spotPlayedFor ~= player then
			self.spotPlayedFor = player
			self._spottedAnimPlaying = true

			task.spawn(function()
				task.wait(0.05)
				self:_playAction("Spotted")

				-- Wait for the animation to finish then release movement.
				-- Use a Stopped signal if the track loaded; fall back to a
				-- fixed delay (1.2 s) if something went wrong loading it.
				local spottedTrack = self.tracks["Spotted"]
				if spottedTrack then
					spottedTrack.Stopped:Wait()
				else
					task.wait(1.2)
				end
				self._spottedAnimPlaying = false
			end)
		end
	end

	if player.Character then
		local hrp = player.Character:FindFirstChild("HumanoidRootPart")
		if hrp then
			self.lastKnownPos = hrp.Position
		end
	end

	local effectiveLost = CHASE_LOST_TIME + math.min(self.chaseDuration * CHASE_DURATION_MUL, CHASE_DURATION_CAP)
	self.lostTimer = effectiveLost
	self.chaseDuration = 0
	self.state = "CHASE"
	self.investigatePos = nil
	self.sounds:onStateChange("CHASE", true)
end

function MonsterBrain:_beginInvestigate(position: Vector3)
	self.investigatePos = position
	self.investigateTimer = INVESTIGATE_TIMEOUT
	self.chaseTarget = nil
	self.state = "INVESTIGATE"
	self:_playMovement("Walk")
	self.sounds:onStateChange("IDLE", false)
end

-- ─────────────────────────────────────────────
--  Catch (strike)
-- ─────────────────────────────────────────────
function MonsterBrain:_beginStrike(player: Player)
	self.state = "CATCH"
	self.sounds:onStateChange("CATCH", false)
	self:_playAction("Jumpscare")

	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then
		task.delay(2, function()
			self:_beginIdle()
		end)
		return
	end

	local snapPos = hrp.Position
	local monPos = self.rootPart.Position
	local flatDir = Vector3.new(snapPos.X - monPos.X, 0, snapPos.Z - monPos.Z)
	local flatDist = flatDir.Magnitude

	if flatDist > 0.1 then
		self.rootPart.CFrame = CFrame.lookAt(monPos, monPos + flatDir.Unit)
	end

	local STRIKE_TIME = 0.25
	if flatDist > 0.1 then
		local lungePos = monPos + flatDir.Unit * math.max(0, flatDist - 1.5)
		TweenService:Create(
			self.rootPart,
			TweenInfo.new(STRIKE_TIME, Enum.EasingStyle.Sine),
			{ CFrame = CFrame.lookAt(lungePos, lungePos + flatDir.Unit) }
		):Play()
	end
	self:_shootTentacles(snapPos + Vector3.new(0, 1, 0), STRIKE_TIME)

	task.delay(STRIKE_TIME, function()
		if not player.Character then
			self:_beginIdle()
			return
		end
		local liveHRP = player.Character:FindFirstChild("HumanoidRootPart")
		if not liveHRP then
			self:_beginIdle()
			return
		end

		if (liveHRP.Position - snapPos).Magnitude <= 4 then
			self.sounds:playHitSounds()
			local hum = player.Character:FindFirstChildOfClass("Humanoid")
			if hum then
				hum.Health = 0
			end
			if self.onDied then
				self.onDied(player.Name)
			end
			task.delay(2, function()
				self:_beginIdle()
			end)
		else
			task.delay(1.2, function()
				if self.state == "CATCH" then
					self:_beginChase(player)
				end
			end)
		end
	end)
end

-- ─────────────────────────────────────────────
--  Main tick (called every frame)
-- ─────────────────────────────────────────────
function MonsterBrain:_tick(dt: number)
	if not self._gridReady then
		return
	end
	if self._graceActive then
		self._broadcastCD = math.max(0, self._broadcastCD - dt)
		if self._broadcastCD <= 0 then
			self._broadcastCD = BROADCAST_INTERVAL
			if self.onBroadcast then
				self.onBroadcast(self.rootPart.Position, "IDLE", self.monsterIndex)
			end
		end
		return
	end

	self._sensorCD = self._sensorCD + dt
	self._broadcastCD = math.max(0, self._broadcastCD - dt)

	local monPos = self.rootPart.Position

	-- ── Sensor tick ───────────────────────────────────────────
	if self._sensorCD >= SENSOR_INT and self.state ~= "CATCH" then
		self._sensorCD = 0
		local all = Players:GetPlayers()
		local heard = SensorSystem.CheckHearing(monPos, self.rules)
		local smelled = SensorSystem.CheckSmell(monPos, all, self.rules)
		local seen = SensorSystem.CheckVision(self.monster, monPos, all, self.rules)

		-- Vision: immediate chase
		if seen then
			local seenHRP = seen.Character and seen.Character:FindFirstChild("HumanoidRootPart")
			if seenHRP then
				self.lastKnownPos = seenHRP.Position
			end
			self.suspicion[seen] = 1.0
			self:_beginChase(seen)
		end

		-- Build suspicion from hearing
		if heard and heard.player then
			local gain = heard.level * 0.35
			self.suspicion[heard.player] = math.min((self.suspicion[heard.player] or 0) + gain, 1.0)
			self.lastKnownPos = heard.position
		end

		-- Build suspicion from smell
		if smelled then
			local smellHRP = smelled.Character and smelled.Character:FindFirstChild("HumanoidRootPart")
			if smellHRP then
				local smellDist = (monPos - smellHRP.Position).Magnitude
				local smellFactor = 1 - (smellDist / Constants.MONSTER_SMELL_RADIUS)
				self.suspicion[smelled] = math.min((self.suspicion[smelled] or 0) + smellFactor * 0.25, 1.0)
				self.lastKnownPos = smellHRP.Position
			end
		end

		-- Track who we're currently sensing (for decay)
		self.lastSensedPlayers = {}
		if seen then
			self.lastSensedPlayers[seen] = true
		end
		if smelled then
			self.lastSensedPlayers[smelled] = true
		end
		if heard and heard.player then
			self.lastSensedPlayers[heard.player] = true
		end

		-- Find highest-suspicion player above chase threshold
		local highestPlayer, highestLevel = nil, 0
		for p, level in pairs(self.suspicion) do
			if level >= SUSPICION_CHASE_THRESHOLD and level > highestLevel then
				highestLevel = level
				highestPlayer = p
			end
		end

		self:_processSensors(seen, heard, smelled, highestPlayer)
	end

	-- ── Suspicion decay ───────────────────────────────────────
	if self.state ~= "CATCH" then
		for p, level in pairs(self.suspicion) do
			if not self.lastSensedPlayers[p] then
				self.suspicion[p] = math.max(0, level - SUSPICION_DECAY_RATE * dt)
				if self.suspicion[p] <= 0 then
					self.suspicion[p] = nil
				end
			end
		end
	end

	if self.state == "CHASE" then
		self.chaseDuration = self.chaseDuration + dt
	end

	-- ── Broadcast ─────────────────────────────────────────────
	if self._broadcastCD <= 0 then
		self._broadcastCD = BROADCAST_INTERVAL
		if self.onBroadcast then
			self.onBroadcast(monPos, self.state, self.monsterIndex)
		end
	end

	-- ── Movement — skip entirely while Spotted anim plays ─────
	if self._spottedAnimPlaying then
		-- Rotate to face the spotted player in place during the animation
		if self.chaseTarget and self.chaseTarget.Character then
			local tHRP = self.chaseTarget.Character:FindFirstChild("HumanoidRootPart")
			if tHRP then
				local pivot = self.monster:GetPivot()
				local flat = Vector3.new(tHRP.Position.X, pivot.Position.Y, tHRP.Position.Z)
				local dir = flat - pivot.Position
				if dir.Magnitude > 0.1 then
					local targetRot = CFrame.lookAt(pivot.Position, pivot.Position + dir.Unit)
					local smoothed = pivot:Lerp(targetRot, dt * 10)
					self.monster:PivotTo(CFrame.new(pivot.Position) * smoothed.Rotation)
				end
			end
		end
		return
	end

	self:_handleMovement(dt, monPos)
end

-- ─────────────────────────────────────────────
--  Sensor state logic (split out to keep _tick readable)
-- ─────────────────────────────────────────────
function MonsterBrain:_processSensors(seen, heard, smelled, highestPlayer)
	local st = self.state

	if st == "IDLE" then
		if highestPlayer then
			self:_beginChase(highestPlayer)
		elseif heard then
			self:_beginInvestigate(heard.position)
		elseif smelled then
			local smellHRP = smelled.Character and smelled.Character:FindFirstChild("HumanoidRootPart")
			if smellHRP then
				local d = (self.rootPart.Position - smellHRP.Position).Magnitude
				if d <= SMELL_CHASE_DIST then
					self.lastKnownPos = smellHRP.Position
					self:_beginChase(smelled)
				else
					self:_beginInvestigate(smellHRP.Position)
				end
			end
		end
	elseif st == "INVESTIGATE" then
		if highestPlayer then
			self:_beginChase(highestPlayer)
		elseif not seen and smelled then
			local smellHRP = smelled.Character and smelled.Character:FindFirstChild("HumanoidRootPart")
			if smellHRP then
				local d = (self.rootPart.Position - smellHRP.Position).Magnitude
				if d <= SMELL_CHASE_DIST then
					self.lastKnownPos = smellHRP.Position
					self:_beginChase(smelled)
				else
					self.investigatePos = smellHRP.Position
					self.investigateTimer = INVESTIGATE_TIMEOUT
				end
			end
		end
		if not seen and heard and heard.level > 0.3 and self.investigatePos then
			local nd = (self.rootPart.Position - heard.position).Magnitude
			local cd = (self.rootPart.Position - self.investigatePos).Magnitude
			if nd < cd * 0.7 or heard.level > 0.7 then
				self.investigatePos = heard.position
				self.investigateTimer = INVESTIGATE_TIMEOUT
			end
		end
		self.investigateTimer = self.investigateTimer - SENSOR_INT
		if self.investigateTimer <= 0 then
			self:_beginIdle()
		end
	elseif st == "SEARCH" then
		if highestPlayer then
			self:_beginChase(highestPlayer)
		elseif heard then
			self:_beginInvestigate(heard.position)
		elseif smelled then
			local smellHRP = smelled.Character and smelled.Character:FindFirstChild("HumanoidRootPart")
			if smellHRP then
				local d = (self.rootPart.Position - smellHRP.Position).Magnitude
				if d <= SMELL_CHASE_DIST then
					self.lastKnownPos = smellHRP.Position
					self:_beginChase(smelled)
				else
					self:_beginInvestigate(smellHRP.Position)
				end
			end
		end
	elseif st == "CHASE" then
		local effectiveLost = CHASE_LOST_TIME + math.min(self.chaseDuration * CHASE_DURATION_MUL, CHASE_DURATION_CAP)

		if seen then
			-- Direct line of sight: fully refresh the timer
			self.lostTimer = effectiveLost
		elseif smelled then
			-- Smell: only a small top-up so breaking LoS still helps a lot
			local smellHRP = smelled.Character and smelled.Character:FindFirstChild("HumanoidRootPart")
			if smellHRP then
				local d = (self.rootPart.Position - smellHRP.Position).Magnitude
				local proximity = 1 - (d / Constants.MONSTER_SMELL_RADIUS)
				self.lostTimer = math.max(self.lostTimer, effectiveLost * SMELL_LOST_TIMER_RESTORE * proximity)
			end
		elseif heard and heard.player == self.chaseTarget then
			-- Hearing the chase target: tiny top-up
			self.lostTimer = math.max(self.lostTimer, effectiveLost * HEAR_LOST_TIMER_RESTORE)
		else
			-- No sensor input: count down normally
			if not self._spottedAnimPlaying then
				self.lostTimer = self.lostTimer - SENSOR_INT
			end
		end

		-- Distraction by anonymous world noise
		if not seen and heard and heard.player == nil then
			local dist = (self.rootPart.Position - heard.position).Magnitude
			local hr = Constants.MONSTER_HEAR_RADIUS
			if dist <= hr then
				local score = heard.level * (1 - dist / hr)
				local threshold = DISTRACTION_THRESHOLD + math.min(self.chaseDuration * 0.04, 0.35)
				if smelled then
					threshold = threshold * 1.5
				end
				if score >= threshold then
					self.postChaseSearchPos = self.lastKnownPos
					self:_beginInvestigate(heard.position)
				end
			end
		end

		if self.lostTimer <= 0 then
			self.postChaseSearchPos = self.lastKnownPos
			if self.lastKnownPos then
				self:_beginInvestigate(self.lastKnownPos)
			else
				self:_beginIdle()
			end
		end
	end
end

-- ─────────────────────────────────────────────
--  Movement handler
-- ─────────────────────────────────────────────
function MonsterBrain:_handleMovement(dt: number, monPos: Vector3)
	local st = self.state

	if st == "IDLE" then
		if not self.idleTarget then
			self.idleTarget = self:_pickIdleTarget()
			self:_playMovement("Walk")
		end
		if self:_stepToward(self.idleTarget, Constants.MONSTER_SPEED_BASE * 0.45, dt) then
			self.idleTarget = nil
		end
	elseif st == "INVESTIGATE" and self.investigatePos then
		local speed = Constants.MONSTER_SPEED_BASE * INVESTIGATE_SPEED_MUL
		if self:_stepToward(self.investigatePos, speed, dt) then
			if self.postChaseSearchPos then
				self.state = "SEARCH"
				self.searchWanderTimer = SEARCH_WANDER_DURATION
				self:_playMovement("Walk")
			else
				self:_beginIdle()
			end
		end
	elseif st == "SEARCH" then
		self.searchWanderTimer = self.searchWanderTimer - dt
		if self.searchWanderTimer <= 0 then
			self:_beginIdle()
			return
		end
		if not self.idleTarget then
			local center = self.postChaseSearchPos or monPos
			local col, row = self:_worldToTile(center)
			for _ = 1, 30 do
				local nc = col + math.random(-3, 3)
				local nr = row + math.random(-3, 3)
				if self:_isTileWalkable(nc, nr) then
					self.idleTarget = self:_tileToWorld(nc, nr)
					break
				end
			end
			self.idleTarget = self.idleTarget or center
		end
		if self:_stepToward(self.idleTarget, Constants.MONSTER_SPEED_BASE * 0.5, dt) then
			self.idleTarget = nil
		end
	elseif st == "CHASE" and self.chaseTarget then
		local char = self.chaseTarget.Character
		if not char then
			self.postChaseSearchPos = self.lastKnownPos
			if self.lastKnownPos then
				self:_beginInvestigate(self.lastKnownPos)
			else
				self:_beginIdle()
			end
			return
		end
		local hrp = char:FindFirstChild("HumanoidRootPart")
		if not hrp then
			self.postChaseSearchPos = self.lastKnownPos
			if self.lastKnownPos then
				self:_beginInvestigate(self.lastKnownPos)
			else
				self:_beginIdle()
			end
			return
		end

		self.lastKnownPos = hrp.Position

		local speed = self.chaseSpeed
		if table.find(self.rules, Constants.Rules.MONSTER_FAST) then
			speed = math.min(speed * 1.35, Constants.MONSTER_SPEED_MAX)
		end

		local catchR = Constants.MONSTER_REACH_BASE
		if table.find(self.rules, Constants.Rules.MONSTER_REACH) then
			catchR = catchR + Constants.MONSTER_REACH_BONUS
		end

		local flatMon = Vector3.new(monPos.X, 0, monPos.Z)
		local flatPlayer = Vector3.new(hrp.Position.X, 0, hrp.Position.Z)

		if (flatMon - flatPlayer).Magnitude <= catchR then
			self:_beginStrike(self.chaseTarget)
			return
		end

		self:_stepToward(hrp.Position, speed, dt)
		self:_playMovement("Run")
	end
end

return MonsterBrain
