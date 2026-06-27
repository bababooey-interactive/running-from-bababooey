-- =============================================================
--  PlayerNoise.client.luau (in StarterCharacterScripts)
-- =============================================================

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local character = script.Parent
local hrp = character:WaitForChild("HumanoidRootPart")

-- ── SETUP AUDIO ──
local function addSound(name, id, isLooped)
	local s = Instance.new("Sound")
	s.Name = name
	s.SoundId = id
	s.Looped = isLooped
	s.Parent = hrp
end

addSound("FootstepWalk", "rbxassetid://5446226292", true)
addSound("BreathingFast", "rbxassetid://94952921557556", true)
addSound("Heartbeat", "rbxassetid://139481207162657", true)

-- ── NOISE SENDER ──
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local MakeNoise = Remotes:WaitForChild("PlayerMakeNoise")

local WALK_SPEED = 1
local WALK_NOISE = 0.3
local SEND_INTERVAL = 0.35
local lastSent = 0

RunService.Heartbeat:Connect(function()
	local now = os.clock()
	if now - lastSent < SEND_INTERVAL then
		return
	end

	local vel = hrp.AssemblyLinearVelocity
	local speed = Vector2.new(vel.X, vel.Z).Magnitude

	if speed >= WALK_SPEED then
		lastSent = now
		MakeNoise:FireServer(WALK_NOISE, hrp.Position)
	end
end)

-- ── LOCAL PLAYER SFX ──
local sfx = {
	walk = hrp:FindFirstChild("FootstepWalk"),
	breath = hrp:FindFirstChild("BreathingFast"),
	heartbeat = hrp:FindFirstChild("Heartbeat"),
}

local currentAwareness = 0
local AwarenessUpdated = Remotes:WaitForChild("AwarenessUpdated")
AwarenessUpdated.OnClientEvent:Connect(function(awareness: number)
	if awareness ~= nil then
		currentAwareness = awareness
	end
end)

RunService.Heartbeat:Connect(function()
	local vel = hrp.AssemblyLinearVelocity
	local speed = Vector2.new(vel.X, vel.Z).Magnitude

	-- 1. FOOTSTEPS
	if sfx.walk then
		if speed >= WALK_SPEED then
			if not sfx.walk.IsPlaying then
				sfx.walk:Play()
			end
		else
			if sfx.walk.IsPlaying then
				sfx.walk:Stop()
			end
		end
	end

	-- 2. BREATHING
	if sfx.breath then
		if currentAwareness >= 0.8 then
			if not sfx.breath.IsPlaying then
				sfx.breath:Play()
			end
			sfx.breath.Volume = 0.5
		else
			if sfx.breath.IsPlaying then
				sfx.breath:Stop()
			end
		end
	end

	-- 3. HEARTBEAT
	if sfx.heartbeat then
		if currentAwareness >= 0.4 then
			if not sfx.heartbeat.IsPlaying then
				sfx.heartbeat:Play()
			end
			sfx.heartbeat.Volume = currentAwareness
			sfx.heartbeat.PlaybackSpeed = 1 + (currentAwareness * 0.5)
		else
			if sfx.heartbeat.IsPlaying then
				sfx.heartbeat:Stop()
			end
		end
	end
end)
