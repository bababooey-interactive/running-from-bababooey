-- =============================================================
--  LanternThrowSystem.server.luau
--  Path: game/src/ServerScriptService/LanternThrowSystem.server.luau
--
--  Molotov-style lantern throw.
--  Client fires "ThrowLantern" remote (G key) →
--    1. Consume the player's Tool (lantern)
--    2. Spawn a glowing projectile in an arc
--    3. On first solid hit → ignite():
--         • 4 fire patches cascade outward from the impact point
--         • Each patch has a PointLight tagged "MapLights"
--           (SensorSystem lights players up → monster SEE rule sees them)
--         • Each patch is also tagged "FlickeringLantern"
--           (reuses the existing LanternFlickerManager for free)
--         • Loud world noise → monster HEAR rule investigates
--    4. Fire fades over FIRE_DURATION seconds then destroys itself.
-- =============================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")

local SoundManager = require(script.Parent.SoundManager)
local SensorSystem = require(script.Parent.SensorSystem)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RE_ThrowLantern = Remotes:WaitForChild("ThrowLantern")

-- ─────────────────────────────────────────────
--  CONFIG
-- ─────────────────────────────────────────────

local THROW_SPEED = 55 -- initial studs/s
local THROW_ARC_DEG = 22 -- upward launch angle
local FIRE_DURATION = 12 -- seconds each fire patch lasts
local FIRE_PATCH_COUNT = 4 -- center + spread patches
local SPREAD_RADIUS = 4.5 -- max stud offset per spread patch
local LIGHT_RANGE = 22 -- PointLight range per patch (studs)
local LIGHT_BRIGHTNESS = 3.5
local NOISE_IMPACT = 0.95 -- very loud — almost guarantees monster attention
local NOISE_AREA_RADIUS = 55 -- studs radius for per-player noise push

-- ─────────────────────────────────────────────
--  HELPERS
-- ─────────────────────────────────────────────

-- Returns true if `part` belongs to any connected player's character.
local function isPlayerPart(part: BasePart): boolean
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character and part:IsDescendantOf(p.Character) then
			return true
		end
	end
	return false
end

-- Snap a world XZ position down to the nearest floor surface.
-- CanQuery=false parts (fire patches, ghost anchors, …) are ignored.
local function getFloorY(pos: Vector3): number
	local origin = Vector3.new(pos.X, pos.Y + 4, pos.Z)
	local result = workspace:Raycast(origin, Vector3.new(0, -12, 0))
	return result and result.Position.Y or pos.Y
end

-- ─────────────────────────────────────────────
--  FIRE PATCH
--  One burning tile-sized zone placed on the floor.
-- ─────────────────────────────────────────────

local function spawnFirePatch(pos: Vector3, spawnDelay: number)
	task.delay(spawnDelay, function()
		local floorY = getFloorY(pos)
		local firePos = Vector3.new(pos.X, floorY + 0.25, pos.Z)

		-- Invisible base part that acts as the parent for all effects.
		local part = Instance.new("Part")
		part.Name = "LanternFire"
		part.Size = Vector3.new(3.5, 0.4, 3.5)
		part.CFrame = CFrame.new(firePos)
		part.Anchored = true
		part.CanCollide = false
		part.CanTouch = false
		part.CanQuery = false -- invisible to raycasts
		part.Transparency = 1
		part.Parent = workspace

		-- Roblox built-in Fire effect (handles its own animation)
		local fire = Instance.new("Fire")
		fire.Size = 5 + math.random() * 2
		fire.Heat = 9
		fire.Color = Color3.fromRGB(255, 70, 0)
		fire.SecondaryColor = Color3.fromRGB(255, 195, 40)
		fire.Parent = part

		-- Smoke rising from the fire
		local smoke = Instance.new("Smoke")
		smoke.Opacity = 0.35
		smoke.Size = 1.5
		smoke.RiseVelocity = 6
		smoke.Color = Color3.fromRGB(55, 55, 55)
		smoke.Parent = part

		-- PointLight — tagged so SensorSystem.IsPlayerInLight() catches it
		-- (players standing in fire are lit up → visible to monster SEE rule)
		local light = Instance.new("PointLight")
		light.Brightness = LIGHT_BRIGHTNESS
		light.Range = LIGHT_RANGE
		light.Color = Color3.fromRGB(255, 140, 50)
		light.Parent = part
		CollectionService:AddTag(light, "MapLights")

		-- Tag the base part for LanternFlickerManager (already in ServerScriptService).
		-- It auto-detects new tagged instances and drives the PointLight flicker.
		CollectionService:AddTag(part, "FlickeringLantern")

		-- ── Burn-down: fade over the last 2.5 s ──────────────────
		task.delay(FIRE_DURATION - 2.5, function()
			if not part.Parent then
				return
			end
			TweenService:Create(fire, TweenInfo.new(2.5), { Size = 0, Heat = 0 }):Play()
			TweenService:Create(smoke, TweenInfo.new(2.5), { Opacity = 0 }):Play()
			TweenService:Create(light, TweenInfo.new(2.5), { Brightness = 0 }):Play()
		end)

		-- ── Destroy (CollectionService signals handle tag cleanup) ─
		task.delay(FIRE_DURATION, function()
			if part.Parent then
				part:Destroy()
			end
		end)
	end)
end

-- ─────────────────────────────────────────────
--  IGNITE
--  Called once per throw at the impact position.
-- ─────────────────────────────────────────────

local function ignite(hitPos: Vector3)
	-- Centre patch fires immediately; spread patches cascade outward.
	spawnFirePatch(hitPos, 0)

	for i = 1, FIRE_PATCH_COUNT - 1 do
		local angle = math.rad(math.random(0, 359))
		local dist = math.random(10, math.floor(SPREAD_RADIUS * 10)) / 10
		local offset = Vector3.new(math.cos(angle) * dist, 0, math.sin(angle) * dist)
		spawnFirePatch(hitPos + offset, i * 0.09) -- staggered by ~90 ms
	end

	-- World noise: pulls monster AI to investigate the impact site.
	SensorSystem.AddWorldNoise(hitPos, NOISE_IMPACT)

	-- Area noise: each nearby player also gets a noise push (raises
	-- their bar and alerts the monster to their direction too).
	SensorSystem.AddAreaNoise(hitPos, NOISE_IMPACT * 0.65, NOISE_AREA_RADIUS)

	-- Impact sound (re-using BoulderHit for now — swap the ID for a
	-- glass-smash SFX once you have one in SoundManager.Ids).
	SoundManager.playAt(SoundManager.Ids.BoulderHit, hitPos, 1.0, 70)
end

-- ─────────────────────────────────────────────
--  REMOTE HANDLER
-- ─────────────────────────────────────────────

RE_ThrowLantern.OnServerEvent:Connect(function(player: Player)
	local character = player.Character
	if not character then
		return
	end

	local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then
		return
	end

	-- Find the player's lantern Tool
	local tool: Tool? = character:FindFirstChildWhichIsA("Tool") or player.Backpack:FindFirstChildWhichIsA("Tool")
	if not tool then
		return
	end

	local handle = tool:FindFirstChild("Handle")
	if not handle then
		return
	end

	-- 1. Convert the Tool into a projectile model so it keeps its look
	local projModel = Instance.new("Model")
	projModel.Name = "ThrownLantern"

	for _, child in ipairs(tool:GetChildren()) do
		if child:IsA("BasePart") or child:IsA("PointLight") then
			child.Parent = projModel
		end
	end

	-- Destroy the now-empty tool wrapper
	tool:Destroy()

	-- 2. Position it and enable physics
	projModel.Parent = workspace
	handle.CFrame = hrp.CFrame * CFrame.new(0, 0.3, -1.5)

	for _, part in ipairs(projModel:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CanCollide = true
			part.Anchored = false
			part.CanTouch = true
		end
	end

	-- 3. Apply exact same physics as throwBoulder (Force = 65, Arc = 15)
	local THROW_FORCE = 65
	local THROW_ARC = 15

	local arcRad = math.rad(THROW_ARC)
	local fwd = hrp.CFrame.LookVector
	local right = fwd:Cross(Vector3.new(0, 1, 0)).Unit
	local arcDir = (CFrame.fromAxisAngle(right, arcRad) * fwd).Unit

	handle.AssemblyLinearVelocity = arcDir * THROW_FORCE

	-- 4. Hit detection & Molotov Ignition
	local hitFired = false
	local touchConn: RBXScriptConnection

	touchConn = handle.Touched:Connect(function(hit: BasePart)
		if hitFired then
			return
		end
		if hit:IsDescendantOf(character) or isPlayerPart(hit) then
			return
		end
		if not hit.CanCollide or hit.Name == "LanternFire" then
			return
		end

		hitFired = true
		touchConn:Disconnect()

		local impactPos = handle.Position
		projModel:Destroy() -- Shatter/destroy the physical lantern
		ignite(impactPos) -- Trigger the molotov fire
	end)

	-- 5. Safety cleanup if it falls out of the map
	task.delay(6, function()
		if projModel and projModel.Parent and not hitFired then
			hitFired = true
			if touchConn then
				touchConn:Disconnect()
			end
			local pos = handle.Position
			projModel:Destroy()
			ignite(pos)
		end
	end)
end)

print("[LanternThrowSystem] Initialized.")
