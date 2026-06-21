-- =============================================================
--  PlayerNoise.client.luau  (LocalScript — Day 8-9)
--
--  Two jobs:
--  1. Fire PlayerMakeNoise to the server based on movement speed
--     so the monster can hear the player walking/running.
--  2. Play local player SFX (footstep, breathing, heartbeat).
--     Add Sound instances to StarterCharacterScripts or the
--     character's HumanoidRootPart, then set their SoundIds.
--
--  Action noises (coal drop, lever pull, battery insert) are
--  fired directly by TaskSystem.server.luau via SoundManager,
--  so they don't need to go through this script.
-- =============================================================

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
-- local humanoid  = character:WaitForChild("Humanoid")
local hrp = character:WaitForChild("HumanoidRootPart")

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local MakeNoise = Remotes:WaitForChild("PlayerMakeNoise")

-- ─────────────────────────────────────────────────────────────
--  NOISE THRESHOLDS
-- ─────────────────────────────────────────────────────────────

local WALK_SPEED = 3 -- studs/s: below this = silent
local RUN_SPEED = 14 -- studs/s: at or above this = running noise

local WALK_NOISE = 0.28 -- noise level sent when walking
local RUN_NOISE = 0.72 -- noise level sent when running

local SEND_INTERVAL = 0.35 -- seconds between noise events while moving

local lastSent = 0

-- ─────────────────────────────────────────────────────────────
--  MOVEMENT NOISE → server
-- ─────────────────────────────────────────────────────────────

RunService.Heartbeat:Connect(function()
	local now = os.clock()
	if now - lastSent < SEND_INTERVAL then
		return
	end

	local vel = hrp.AssemblyLinearVelocity
	local speed = Vector2.new(vel.X, vel.Z).Magnitude

	if speed >= WALK_SPEED then
		lastSent = now
		local level = (speed >= RUN_SPEED) and RUN_NOISE or WALK_NOISE
		MakeNoise:FireServer(level, hrp.Position)
	end
end)

-- ─────────────────────────────────────────────────────────────
--  LOCAL PLAYER SFX
--  Add these Sound instances as children of HumanoidRootPart
--  (in StarterCharacterScripts or via a CharacterAdded script).
--  Set their SoundId in Studio and they will play here.
-- ─────────────────────────────────────────────────────────────

-- Sound names expected in HumanoidRootPart:
--   FootstepWalk  — soft stone step, Looped=true
--                   search: "dungeon footstep stone soft"
--   FootstepRun   — heavier quick step, Looped=true
--                   search: "fast footstep stone run"
--   BreathingFast — panting, Looped=true
--                   search: "scared breathing heavy pant"
--   Heartbeat     — low thud, Looped=true
--                   search: "heartbeat horror low"

local sfx = {
	walk = hrp:FindFirstChild("FootstepWalk"),
	run = hrp:FindFirstChild("FootstepRun"),
	breath = hrp:FindFirstChild("BreathingFast"),
	heartbeat = hrp:FindFirstChild("Heartbeat"),
}

-- Awareness level received from server (updated by AwarenessUpdated event)
local currentAwareness = 0
local AwarenessUpdated = Remotes:WaitForChild("AwarenessUpdated")
AwarenessUpdated.OnClientEvent:Connect(function(awareness: number)
	currentAwareness = awareness
end)

-- Update player SFX each frame
RunService.Heartbeat:Connect(function()
	local vel = hrp.AssemblyLinearVelocity
	local speed = Vector2.new(vel.X, vel.Z).Magnitude

	-- Footstep switching
	if sfx.walk and sfx.run then
		if speed >= RUN_SPEED then
			if sfx.walk.IsPlaying then
				sfx.walk:Stop()
			end
			if not sfx.run.IsPlaying then
				sfx.run:Play()
			end
		elseif speed >= WALK_SPEED then
			if sfx.run.IsPlaying then
				sfx.run:Stop()
			end
			if not sfx.walk.IsPlaying then
				sfx.walk:Play()
			end
		else
			if sfx.walk.IsPlaying then
				sfx.walk:Stop()
			end
			if sfx.run.IsPlaying then
				sfx.run:Stop()
			end
		end
	end

	-- Breathing: kicks in when running or monster is aware of us
	if sfx.breath then
		local shouldBreathe = speed >= RUN_SPEED or currentAwareness >= 0.6
		if shouldBreathe then
			if not sfx.breath.IsPlaying then
				sfx.breath:Play()
			end
			-- Louder / faster when more scared
			sfx.breath.Volume = 0.3 + currentAwareness * 0.5
			sfx.breath.PlaybackSpeed = 0.9 + currentAwareness * 0.4
		else
			if sfx.breath.IsPlaying then
				sfx.breath:Stop()
			end
		end
	end

	-- Heartbeat: thumps louder as monster gets closer
	if sfx.heartbeat then
		if currentAwareness >= 0.4 then
			if not sfx.heartbeat.IsPlaying then
				sfx.heartbeat:Play()
			end
			sfx.heartbeat.Volume = (currentAwareness - 0.4) / 0.6 -- 0→1 as awareness 0.4→1
			sfx.heartbeat.PlaybackSpeed = 0.8 + currentAwareness * 0.6 -- speeds up near monster
		else
			if sfx.heartbeat.IsPlaying then
				sfx.heartbeat:Stop()
			end
		end
	end
end)
