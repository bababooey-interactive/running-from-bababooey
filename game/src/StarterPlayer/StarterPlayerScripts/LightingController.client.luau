-- LightingController.client.luau
-- StarterPlayerScripts
--
-- Tweens the global ambient toward near-black as the closest monster approaches.
-- Listens to MonsterPosition (fired for every monster, including clones) and
-- always uses whichever monster is nearest to the local player.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RE_MonsterPos = Remotes:WaitForChild("MonsterPosition")

-- ── Config ─────────────────────────────────────────────────────
local AMBIENT_BASE = Color3.fromRGB(30, 30, 30) -- default darkness
local AMBIENT_CLOSE = Color3.fromRGB(5, 5, 5) -- monster right on you
local PROX_START = 20 -- studs: lerp begins here
local PROX_FULL = 5 -- studs: maximum darkness at this distance
local TWEEN_TIME = 0.6 -- seconds per ambient transition

-- ── State ──────────────────────────────────────────────────────
-- All active monster positions, keyed by monsterIndex.
-- Updated by every MonsterPosition broadcast (original + clones).
local monsterPositions: { [number]: Vector3 } = {}

local lastT = -1
local currentTween = nil

-- ── Receive monster positions ───────────────────────────────────
RE_MonsterPos.OnClientEvent:Connect(function(data)
	monsterPositions[data.monsterIndex or 1] = data.position
end)

-- ── Update ambient every frame ─────────────────────────────────
RunService.Heartbeat:Connect(function()
	local char = player.Character
	if not char then
		return
	end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end

	-- Find the closest monster among all active ones (original + clones)
	local closestDist = math.huge
	for _, mPos in pairs(monsterPositions) do
		local d = (hrp.Position - mPos).Magnitude
		if d < closestDist then
			closestDist = d
		end
	end

	if closestDist == math.huge then
		return
	end

	-- Map distance → danger [0, 1]
	local t = 0
	if closestDist < PROX_START then
		t = 1 - math.clamp((closestDist - PROX_FULL) / (PROX_START - PROX_FULL), 0, 1)
	end

	if math.abs(t - lastT) < 0.02 then
		return
	end
	lastT = t

	local targetAmbient = AMBIENT_BASE:Lerp(AMBIENT_CLOSE, t)

	if currentTween then
		currentTween:Cancel()
	end
	currentTween = TweenService:Create(
		Lighting,
		TweenInfo.new(TWEEN_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Ambient = targetAmbient }
	)
	currentTween:Play()
end)
