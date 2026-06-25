-- LightingController.client.luau
-- Place in StarterPlayerScripts

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RE_MonsterPos = Remotes:WaitForChild("MonsterPosition")

-- ── Config ────────────────────────────────────────────────────
local AMBIENT_BASE = Color3.fromRGB(30, 30, 30) -- normal darkness
local AMBIENT_CLOSE = Color3.fromRGB(5, 5, 5) -- monster right on you
local PROX_START = 20 -- studs: lerp starts here
local PROX_FULL = 5 -- studs: fully dark at this distance
local TWEEN_TIME = 0.6 -- seconds to transition

-- ── State ─────────────────────────────────────────────────────
local monsterPos: Vector3? = nil
local currentTween = nil

-- ── Receive monster position ───────────────────────────────────
RE_MonsterPos.OnClientEvent:Connect(function(data)
	monsterPos = data.position
end)

-- ── Update ambient every frame ────────────────────────────────
local lastT = -1 -- track last lerp value to avoid redundant tweens

RunService.Heartbeat:Connect(function()
	local char = player.Character
	if not char or not monsterPos then
		return
	end

	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end

	local dist = (hrp.Position - monsterPos).Magnitude

	-- How deep into the danger zone are we? 0 = safe, 1 = max danger
	local t = 0
	if dist < PROX_START then
		t = 1 - math.clamp((dist - PROX_FULL) / (PROX_START - PROX_FULL), 0, 1)
	end

	-- Only fire a new tween when t changes meaningfully
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
	if currentTween then
		currentTween:Play()
	end
end)
