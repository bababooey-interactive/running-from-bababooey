
-- =============================================================
--  MonsterAI.server.luau  (ServerScript — Day 4-6)
--  A* pathfinding, state machine (IDLE/CHASE/CATCH),
--  noclip CFrame movement, animation control, hearing
--
--  Day 7 adds: smell system, vision raycast
-- =============================================================
-- anim:
-- monster_run: 75452347275172
-- monster_jumpscare: 79583022426609
-- monster_walk: 90825719838414
-- monster_spotted: 91571146490557

-- ── SERVICES ──────────────────────────────────────────────────
local RunService    = game:GetService("RunService")
local Players       = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService  = game:GetService("TweenService")

-- ── DEPENDENCIES ──────────────────────────────────────────────
local Constants    = require(ReplicatedStorage.Shared.Constants)
local SensorSystem = require(script.Parent.SensorSystem)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RE = {
	PlayerMakeNoise     = Remotes:WaitForChild("PlayerMakeNoise"),
	PlayerDied          = Remotes:WaitForChild("PlayerDied"),
	MonsterPosition     = Remotes:WaitForChild("MonsterPosition"),
	AwarenessUpdated    = Remotes:WaitForChild("AwarenessUpdated"),
}

-- ── MONSTER SETUP ─────────────────────────────────────────────
local MONSTER_NAME = "SoulDragger"
local monster = workspace:WaitForChild(MONSTER_NAME)

-- Set noclip on every BasePart
for _, part in ipairs(monster:GetDescendants()) do
	if part:IsA("BasePart") then
		part.CanCollide = false
		part.CanQuery   = false   -- jangan kena raycast accidental
		part.Anchored   = false
	end
end

-- Primary part untuk PivotTo
local rootPart = monster:FindFirstChild("rb") or monster.PrimaryPart
rootPart.Anchored = true
assert(rootPart, "SoulDragger must have part named 'rb'")
monster.PrimaryPart = rootPart

-- ── ANIMATION CONTROLLER ──────────────────────────────────────
local humanoid = monster:FindFirstChildOfClass("Humanoid")
local animator : Animator

if humanoid then
	animator = humanoid:FindFirstChildOfClass("Animator")
		or Instance.new("Animator", humanoid)
end

-- Create and load tracks directly from your published IDs
local tracks : {[string]: AnimationTrack} = {}

local animationIDs = {
    Run = "rbxassetid://75452347275172",
    Jumpscare = "rbxassetid://79583022426609",
    Walk = "rbxassetid://90825719838414",
    Spotted = "rbxassetid://91571146490557"
}

if animator then
    for animName, animID in pairs(animationIDs) do
        local animObj = Instance.new("Animation")
        animObj.AnimationId = animID

        local track = animator:LoadAnimation(animObj)

        -- FIX: Assign priorities so animations blend perfectly without T-posing
        if animName == "Spotted" or animName == "Jumpscare" then
            track.Priority = Enum.AnimationPriority.Action
        else
            track.Priority = Enum.AnimationPriority.Movement
        end

        tracks[animName] = track
    end
end

local currentMovement = ""

local function playMovement(name : string)
    if currentMovement == name then return end
    currentMovement = name

    -- Stop all other MOVEMENT animations
    for tName, track in pairs(tracks) do
        if track.Priority == Enum.AnimationPriority.Movement and tName ~= name then
            track:Stop(0.2)
        end
    end

    if tracks[name] then
        tracks[name].Looped = true
        tracks[name]:Play(0.2)
    end
end

local function playAction(name : string)
    -- Stop all other ACTION animations
    for tName, track in pairs(tracks) do
        if track.Priority == Enum.AnimationPriority.Action then
            track:Stop(0.1)
        end
    end

    if tracks[name] then
        tracks[name].Looped = false
        tracks[name]:Play(0.1)
    end
end

-- ── MAP GRID & SPAWN INTEGRATION ──────────────────────────────
local grid : {{number}} = {}
local gridReady = false

local TILE = Constants.TILE_SIZE

local function worldToTile(pos : Vector3) : (number, number)
    return math.clamp(math.round(pos.X / TILE), 1, #(grid[1] or {1})),
           math.clamp(math.round(pos.Z / TILE), 1, #grid)
end

local function tileToWorld(col : number, row : number) : Vector3
    return Vector3.new((col - 1) * TILE, rootPart.Position.Y, (row - 1) * TILE)
end

local function isTileWalkable(col : number, row : number) : boolean
    if not grid[row] then return false end
    local t = grid[row][col]
    return t ~= nil and t ~= Constants.Tile.WALL
end

-- ── SPAWN LOGIC ───────────────────────────────────────────────
local function spawnMonsterInArc(spawnWorldPos : Vector3, radiusTiles : number)
    local tries = 0
    local centerCol, centerRow = worldToTile(spawnWorldPos)

    repeat
        tries += 1
        -- Random angle for the "arc" (e.g., between 0 and 180 degrees)
        local angle = math.rad(math.random(0, 180))

        -- Calculate grid offset using sine/cosine
        local dCol = math.round(math.cos(angle) * radiusTiles)
        local dRow = math.round(math.sin(angle) * radiusTiles)

        local targetCol = centerCol + dCol
        local targetRow = centerRow + dRow

        -- BOUNDARY CHECK: Only spawn if the tile is strictly walkable
        if isTileWalkable(targetCol, targetRow) then
            local spawnPoint = tileToWorld(targetCol, targetRow)
            monster:PivotTo(CFrame.new(spawnPoint + Vector3.new(0, 3, 0)))
            return
        end
    until tries > 50

    -- Fallback if arc fails: Just put it on the closest walkable tile
    monster:PivotTo(CFrame.new(tileToWorld(centerCol, centerRow) + Vector3.new(0, 3, 0)))
end


local TILE = Constants.TILE_SIZE
local function worldToTile(pos : Vector3) : (number, number)
	return math.clamp(math.round(pos.X / TILE), 1, #(grid[1] or {1})),
	       math.clamp(math.round(pos.Z / TILE), 1, #grid)
end
local function tileToWorld(col : number, row : number) : Vector3
	return Vector3.new(col * TILE, rootPart.Position.Y, row * TILE)
end
local function isTileWalkable(col : number, row : number) : boolean
	if not grid[row] then return false end
	local t = grid[row][col]
	return t ~= nil and t ~= Constants.Tile.WALL
end

-- ── A* PATHFINDING ────────────────────────────────────────────
-- 8-directional movement. Diagonal cost = √2 ≈ 1.414.
-- Monster adalah noclip → kalau A* gagal, fallback ke direct path.

local DIRS = {
	{0,1,1},{0,-1,1},{1,0,1},{-1,0,1},           -- cardinal  cost 1
	{1,1,1.414},{1,-1,1.414},{-1,1,1.414},{-1,-1,1.414}  -- diagonal cost √2
}

local function aStar(sCol:number, sRow:number, gCol:number, gRow:number) : {{col:number,row:number}}?
	if not gridReady then return nil end

	local function key(c,r) return r * 1000 + c end
	local function h(c,r)   return math.sqrt((c-gCol)^2+(r-gRow)^2) end

	local open   : {{col:number,row:number,f:number}} = {}
	local closed : {[number]:boolean} = {}
	local gScore : {[number]:number}  = {}
	local parent : {[number]:number}  = {}   -- key → parent key

	local sk = key(sCol, sRow)
	gScore[sk] = 0
	table.insert(open, {col=sCol, row=sRow, f=h(sCol,sRow)})

	local MAX_ITER = 800   -- batas iterasi agar tidak freeze saat grid besar
	local iter = 0

	while #open > 0 and iter < MAX_ITER do
		iter += 1

		-- Pop node dengan f terkecil
		local bestIdx = 1
		for i = 2, #open do
			if open[i].f < open[bestIdx].f then bestIdx = i end
		end
		local cur = open[bestIdx]
		table.remove(open, bestIdx)

		local ck = key(cur.col, cur.row)
		if closed[ck] then continue end
		closed[ck] = true

		-- Goal reached → reconstruct
		if cur.col == gCol and cur.row == gRow then
			local path : {{col:number,row:number}} = {}
			local k = ck
			while k ~= sk do
				local r = math.floor(k / 1000)
				local c = k - r * 1000
				table.insert(path, 1, {col=c, row=r})
				k = parent[k]
			end
			return path
		end

		local cg = gScore[ck] or 0

		for _, d in ipairs(DIRS) do
			local nc, nr = cur.col + d[1], cur.row + d[2]
			local nk = key(nc, nr)
			if closed[nk] then continue end
			-- Monster noclip: pakai walkable tiles tapi kalau mau bisa remove check ini
			if not isTileWalkable(nc, nr) then continue end

			local tg = cg + d[3]
			if not gScore[nk] or tg < gScore[nk] then
				gScore[nk] = tg
				parent[nk] = ck
				local f = tg + h(nc, nr)
				-- Update or add ke open
				local found = false
				for _, node in ipairs(open) do
					if node.col == nc and node.row == nr then
						node.f = f ; found = true ; break
					end
				end
				if not found then
					table.insert(open, {col=nc, row=nr, f=f})
				end
			end
		end
	end

	return nil  -- no path → caller akan direct-move
end

-- ── STATE MACHINE ─────────────────────────────────────────────

type MonsterState = "IDLE" | "CHASE" | "CATCH"

local state       : MonsterState = "IDLE"
local activeRules : {string}     = {}   -- diisi dari RulesActivated

-- CHASE state
local chaseTarget   : Player? = nil
local currentPath   : {{col:number,row:number}}? = nil
local waypointIndex = 1
local pathUpdateCD  = 0   -- countdown detik sebelum re-run A*
local PATH_INTERVAL = 1.2 -- detik antar path recalc

-- IDLE state
local idleTarget   : Vector3? = nil
local IDLE_RANGE   = 6       -- tile radius wander
local lostTimer    = 0       -- detik sejak terakhir detect player
local LOST_TIME    = 5       -- detik sampai monster berhenti chase

-- ─── Transisi ke CHASE ───────────────────────────────────────
local spotPlayedFor : Player? = nil

local spotPlayedFor : Player? = nil

local function beginChase(player : Player)
    if chaseTarget ~= player then
        chaseTarget = player
        currentPath = nil
        waypointIndex = 1

        -- 🔧 FIX: Start running underneath immediately!
        playMovement("Run")

        if spotPlayedFor ~= player then
            spotPlayedFor = player
            -- Plays OVER the run animation instantly
            playAction("Spotted")
        end
    end
    lostTimer = LOST_TIME
    state = "CHASE"
end

local function beginIdle()
    state       = "IDLE"
    chaseTarget = nil
    currentPath = nil
    idleTarget  = nil
    playMovement("Walk")
end

-- ─── Transisi ke STRIKE / CATCH ───────────────────────────────
local function beginStrike(player : Player)
    state = "CATCH"
    playAction("Jumpscare") -- Plays OVER movement

    local char = player.Character
    if not char then beginIdle() return end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then beginIdle() return end

    -- 1. Lock the target's position
    local strikeTargetPos = hrp.Position
    local lookPos = Vector3.new(strikeTargetPos.X, rootPart.Position.Y, strikeTargetPos.Z)

    local STRIKE_SPEED = 0.35

    -- 🔧 LUNGE MECHANIC FIX: Prevent NaN crash and physically slide to target
    local dir = (lookPos - rootPart.Position)
    local distance = dir.Magnitude
    local lungeCFrame

    if distance > 0.1 then
        -- Dash towards the player, but stay 1.5 studs back to prevent clipping into them
        local lungePos = rootPart.Position + dir.Unit * math.max(0, distance - 1.5)
        lungeCFrame = CFrame.lookAt(lungePos, lookPos)
    else
        -- Monster is already literally on top of the player
        lungeCFrame = rootPart.CFrame
    end

    -- Physically move the monster's body during the strike!
    local lungeTween = TweenService:Create(
        rootPart,
        TweenInfo.new(STRIKE_SPEED, Enum.EasingStyle.Linear, Enum.EasingDirection.Out),
        {CFrame = lungeCFrame}
    )
    lungeTween:Play()

    -- 2. Fast delay catch check
    task.delay(STRIKE_SPEED, function()
        if not player.Character or not player.Character:FindFirstChild("HumanoidRootPart") then
            beginIdle() return
        end

        local currentHRP = player.Character.HumanoidRootPart
        local dodgeDistance = (currentHRP.Position - strikeTargetPos).Magnitude

        -- Make the dodge radius wider if the monster has long arms!
        local hitRadius = 3.5
        if table.find(activeRules, Constants.Rules.MONSTER_REACH) then
            hitRadius = 8 -- Harder to dodge when REACH rule is active
        end

        if dodgeDistance <= hitRadius then
            -- ❌ CAUGHT!
            currentHRP.Anchored = true

            -- Force player to look at monster
            local playerLook = Vector3.new(rootPart.Position.X, currentHRP.Position.Y, rootPart.Position.Z)
            currentHRP.CFrame = CFrame.lookAt(currentHRP.Position, playerLook)

            -- Kill the player
            local targetHumanoid = player.Character:FindFirstChildOfClass("Humanoid")
            if targetHumanoid then targetHumanoid.Health = 0 end

            RE.PlayerDied:FireAllClients(player.Name)

            task.delay(1.5, function() beginIdle() end)
        else
            -- ✅ MISSED! Player dodged out of the way!
            task.delay(0.5, function()
                if state == "CATCH" then beginChase(player) end
            end)
        end
    end)
end

-- ── MOVEMENT ──────────────────────────────────────────────────
-- Kembalikan true jika sudah "sampai" di targetPos

local function stepToward(targetPos : Vector3, speed : number, dt : number) : boolean
	local pivot = monster:GetPivot()
	local flat  = Vector3.new(targetPos.X, pivot.Position.Y, targetPos.Z)
	local dir   = flat - pivot.Position
	local dist  = dir.Magnitude

	if dist < 0.6 then return true end   -- sudah cukup dekat

	local step    = math.min(speed * dt, dist)
	local newPos  = pivot.Position + dir.Unit * step
	-- local lookAt  = Vector3.new(flat.X, newPos.Y, flat.Z)
	-- monster:PivotTo(CFrame.lookAt(newPos, lookAt))
	-- Replace your lookAt and PivotTo lines with this one line:
	if dist > 0.001 then
		monster:PivotTo(CFrame.lookAt(newPos, newPos + dir.Unit))
	else
		monster:PivotTo(CFrame.new(newPos))
	end

	return false
end

-- ── IDLE WANDER HELPER ────────────────────────────────────────

local function pickIdleTarget() : Vector3
	local col, row = worldToTile(rootPart.Position)
	local tries = 0
	repeat
		tries += 1
		local dc = math.random(-IDLE_RANGE, IDLE_RANGE)
		local dr = math.random(-IDLE_RANGE, IDLE_RANGE)
		local nc, nr = col + dc, row + dr
		if isTileWalkable(nc, nr) then
			return tileToWorld(nc, nr)
		end
	until tries > 20
	return tileToWorld(col, row)
end

-- ── MAIN LOOP (RunService.Heartbeat) ─────────────────────────

local broadcastClock  = 0
local sensorClock     = 0
local SENSOR_INTERVAL = 0.25   -- detik antar sensor check

RunService.Heartbeat:Connect(function(dt)
	if not gridReady then return end

	broadcastClock += dt
	sensorClock    += dt
	pathUpdateCD   = math.max(0, pathUpdateCD - dt)

	local monsterPos = rootPart.Position

	-- ── Sensor check (setiap SENSOR_INTERVAL) ─────────────────
	if sensorClock >= SENSOR_INTERVAL then
		sensorClock = 0

		local allPlayers = Players:GetPlayers()

		if state ~= "CATCH" then

			-- Hearing check
			local noiseHit = SensorSystem.CheckHearing(monsterPos, activeRules)
			if noiseHit then
				local pl = noiseHit.player
				if pl and pl.Character then
					beginChase(pl)
				end
			end

			-- Smell check (Day 7 — stub jalan tapi tidak trigger)
			local smellTarget = SensorSystem.CheckSmell(monsterPos, allPlayers, activeRules)
			if smellTarget then beginChase(smellTarget) end

			-- Vision check (Day 7 — stub)
			local visionTarget = SensorSystem.CheckVision(monster, monsterPos, allPlayers, activeRules)
			if visionTarget then beginChase(visionTarget) end

			-- Lost timer countdown saat CHASE
			if state == "CHASE" then
				lostTimer -= SENSOR_INTERVAL
				if lostTimer <= 0 then
					beginIdle()
				end
			end
		end

		-- ── Broadcast posisi monster (minimap) ────────────────
		if broadcastClock >= 0.5 then
			broadcastClock = 0
			RE.MonsterPosition:FireAllClients({
				position     = monsterPos,
				state        = state,
				monsterIndex = 1,
			})

			-- Kirim awareness level ke tiap player
			for _, player in ipairs(allPlayers) do
				local aw = SensorSystem.GetAwarenessForPlayer(
					monsterPos, monster, player, activeRules,
					state == "CHASE", chaseTarget
				)
				local noise = SensorSystem.GetRecentNoiseForPlayer(player)
				RE.AwarenessUpdated:FireClient(player, aw, noise)
			end
		end
	end

	-- ── IDLE state movement ────────────────────────────────────
	if state == "IDLE" then
		local idleSpeed = Constants.MONSTER_SPEED_BASE * 0.45

		if not idleTarget then
			idleTarget = pickIdleTarget()
			playAnim("Walk", true)
		end

		local reached = stepToward(idleTarget, idleSpeed, dt)
		if reached then
			idleTarget = nil  -- pick a new one next frame
		end
	end

	-- ── CHASE state movement ───────────────────────────────────
	if state == "CHASE" and chaseTarget then
		local char = chaseTarget.Character
		if not char then beginIdle() return end
		local hrp = char:FindFirstChild("HumanoidRootPart")
		if not hrp then beginIdle() return end

		-- Monster speed dari level (from Constants)
		local speed = math.min(
			Constants.MONSTER_SPEED_BASE + (1 * Constants.MONSTER_SPEED_PER_LEVEL),
			Constants.MONSTER_SPEED_MAX
		)

		-- Catch radius
		local catchRadius = Constants.MONSTER_REACH_BASE
		if table.find(activeRules, Constants.Rules.MONSTER_REACH) then
			catchRadius += Constants.MONSTER_REACH_BONUS
		end

		-- Check catch
        local distToPlayer = (monsterPos - hrp.Position).Magnitude
        if distToPlayer <= catchRadius then
            beginStrike(chaseTarget)
            return
        end

		-- A* path update (setiap PATH_INTERVAL atau belum ada path)
		if pathUpdateCD <= 0 or not currentPath then
			pathUpdateCD = PATH_INTERVAL
			local mCol, mRow = worldToTile(monsterPos)
			local pCol, pRow = worldToTile(hrp.Position)
			local newPath = aStar(mCol, mRow, pCol, pRow)
			if newPath then
				currentPath   = newPath
				waypointIndex = 1
			else
				-- Fallback: direct move (noclip menembus dinding)
				currentPath = {{col = pCol, row = pRow}}
				waypointIndex = 1
			end
		end

		-- Move along path
		if currentPath and waypointIndex <= #currentPath then
			local wp = currentPath[waypointIndex]
			local wpWorld = tileToWorld(wp.col, wp.row)
			-- Change it to use the monster's current Y height instead of the player's:
			wpWorld = Vector3.new(wpWorld.X, rootPart.Position.Y, wpWorld.Z)

			local reached = stepToward(wpWorld, speed, dt)
			if reached then
				waypointIndex += 1
				-- Reset timer saat sampai waypoint → player mungkin sudah pindah
				if waypointIndex > #currentPath then
					pathUpdateCD = 0
				end
			end
		end

		-- Animasi run (jika belum)
		-- Ensure Run is the active movement channel
        playMovement("Run")
	end

	-- ── CATCH state: diam menunggu animasi selesai ─────────────
	-- (tidak ada movement logic di sini)
end)

-- ── REMOTE EVENT LISTENERS ────────────────────────────────────

-- Noise dari player (coal drop, lever, footsteps, dll.)
RE.PlayerMakeNoise.OnServerEvent:Connect(function(player, noiseLevel, position)
	SensorSystem.AddNoise(player, position, noiseLevel)
end)

-- Rules diterima dari RulesRandomizer Gilang
-- Server listens via BindableEvent or sets activeRules directly.
-- (OnClientEvent only exists on the client, not the server)

-- TESTING: aktifkan semua rules untuk test
activeRules = {
	Constants.Rules.MONSTER_HEAR,
	Constants.Rules.MONSTER_SMELL,
	Constants.Rules.MONSTER_SEE,
	Constants.Rules.MONSTER_FAST,
	-- Constants.Rules.MONSTER_REACH,
}

-- ── VISUAL RULES (SAFE METHOD) ────────────────────────────────
local function applyVisualRules()
    if table.find(activeRules, Constants.Rules.MONSTER_REACH) then

        -- Support for both R6 ("Left Arm") and R15 ("LeftHand" / "LeftLowerArm")
        local targetLimbs = {"Left Arm", "Right Arm", "LeftHand", "RightHand"}

        for _, limbName in ipairs(targetLimbs) do
            local limb = monster:FindFirstChild(limbName)
            if limb and limb:IsA("BasePart") then

                -- 1. Create the stretched extension
                local stretchPart = Instance.new("Part")
                stretchPart.Name = "ReachExtension"
                stretchPart.Size = Vector3.new(limb.Size.X, 3.5, limb.Size.Z) -- 3.5 studs longer!
                stretchPart.Color = limb.Color
                stretchPart.Material = limb.Material
                stretchPart.Transparency = 0 -- Make it fully visible
                stretchPart.CanCollide = false
                stretchPart.CanQuery = false
                stretchPart.Massless = true

                -- 2. Position it so it hangs down from the original hand
                stretchPart.CFrame = limb.CFrame * CFrame.new(0, -stretchPart.Size.Y/2, 0)

                -- 3. Weld it safely (Does NOT break animations!)
                local weld = Instance.new("WeldConstraint")
                weld.Part0 = limb
                weld.Part1 = stretchPart
                weld.Parent = stretchPart

                stretchPart.Parent = monster
            end
        end
    end
end

-- Apply the visuals before starting
applyVisualRules()

-- ── STARTUP SEQUENCE ──────────────────────────────────────────
-- Wait for the Server BindableEvent, NOT the RemoteEvent!
ReplicatedStorage:WaitForChild("ServerMapGenerated").Event:Connect(function(realGrid, hallInfo)
    grid = realGrid
    gridReady = true

    -- Get the exact world coordinates of the player spawn point
    local spawnWorldPos = Vector3.new((hallInfo.spawnCol - 1) * Constants.TILE_SIZE, 0, (hallInfo.spawnRow - 1) * Constants.TILE_SIZE)

    -- Spawn the monster in an arc 6 tiles away from the players
    spawnMonsterInArc(spawnWorldPos, 6)

    -- Start idle wandering now that the map exists
    beginIdle()
    print("[MonsterAI] Map Loaded. Monster is officially hunting!")
end)
