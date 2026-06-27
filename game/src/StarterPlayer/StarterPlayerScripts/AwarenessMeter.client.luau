-- AwarenessMeter.client.luau
-- StarterPlayerScripts
--
-- Bottom-right HUD bars showing the player's current noise level and
-- how much ambient light they are standing in.
--
-- Noise sources:
--   • Walking (computed locally each frame)
--   • World events: lever pulls, drops, etc. (pushed from SensorSystem via
--     AwarenessUpdated with a nil first argument)
-- Light: sampled every frame from all tagged MapLights in range.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RE_Awareness = Remotes:WaitForChild("AwarenessUpdated")

-- ── Config ─────────────────────────────────────────────────────
local WALK_SPEED = 1 -- studs/s threshold for walking noise
local WALK_NOISE = 0.3 -- noise level injected while walking
local NOISE_LIFETIME = 1.2 -- seconds until noise fully decays
local DECAY_RATE = 1 / NOISE_LIFETIME

-- ── Color palette (matches SurvivalUI) ────────────────────────
local C = {
	BAR_BG = Color3.fromRGB(35, 35, 42),
	TEXT_WHITE = Color3.fromRGB(235, 235, 235),
}

-- ── Build ScreenGui ───────────────────────────────────────────
local gui = Instance.new("ScreenGui")
gui.Name = "DetectionGui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Parent = player.PlayerGui

local barsFrame = Instance.new("Frame")
barsFrame.Name = "AwarenessBars"
barsFrame.AnchorPoint = Vector2.new(1, 1)
barsFrame.Position = UDim2.new(1, -12, 1, -12)
barsFrame.Size = UDim2.new(0, 200, 0, 56)
barsFrame.BackgroundTransparency = 1
barsFrame.Parent = gui

local layout = Instance.new("UIListLayout")
layout.FillDirection = Enum.FillDirection.Vertical
layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
layout.Padding = UDim.new(0, 5)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = barsFrame

-- ── Bar factory ───────────────────────────────────────────────
local function makeBar(icon: string, barColor: Color3, order: number, name: string)
	local row = Instance.new("Frame")
	row.Name = name
	row.Size = UDim2.new(1, 0, 0, 22)
	row.BackgroundTransparency = 1
	row.LayoutOrder = order
	row.Parent = barsFrame

	local iconLabel = Instance.new("TextLabel")
	iconLabel.Size = UDim2.new(0, 20, 1, 0)
	iconLabel.BackgroundTransparency = 1
	iconLabel.TextColor3 = barColor
	iconLabel.TextSize = 14
	iconLabel.Font = Enum.Font.GothamBold
	iconLabel.Text = icon
	iconLabel.TextYAlignment = Enum.TextYAlignment.Center
	iconLabel.Parent = row

	local track = Instance.new("Frame")
	track.Name = "Track"
	track.Position = UDim2.new(0, 24, 0.5, -7)
	track.Size = UDim2.new(1, -24, 0, 14)
	track.BackgroundColor3 = C.BAR_BG
	track.BorderSizePixel = 0
	track.Parent = row
	Instance.new("UICorner", track).CornerRadius = UDim.new(0, 4)

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.new(0, 0, 1, 0)
	fill.BackgroundColor3 = barColor
	fill.BorderSizePixel = 0
	fill.Parent = track
	Instance.new("UICorner", fill).CornerRadius = UDim.new(0, 4)

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.TextColor3 = C.TEXT_WHITE
	label.TextSize = 10
	label.Font = Enum.Font.GothamBold
	label.Text = ""
	label.ZIndex = 2
	label.Parent = track

	return row, fill, label
end

local noiseRow, noiseFill, noiseText = makeBar("🔊", Color3.fromRGB(180, 120, 40), 1, "NoiseRow")
local lightRow, lightFill, lightText = makeBar("💡", Color3.fromRGB(200, 160, 40), 2, "LightRow")

-- ── Color helpers ─────────────────────────────────────────────
local function noiseColor(t: number): Color3
	if t < 0.5 then
		local s = t * 2
		return Color3.fromRGB(math.round(180 + 55 * s), math.round(180 - 60 * s), math.round(180 - 130 * s))
	else
		local s = (t - 0.5) * 2
		return Color3.fromRGB(235, math.round(120 - 80 * s), math.round(50 - 30 * s))
	end
end

local function lightColor(t: number): Color3
	return Color3.fromRGB(math.round(160 + 79 * t), math.round(160 - t), math.round(160 - 121 * t))
end

local function setBar(fill: Frame, t: number)
	TweenService:Create(
		fill,
		TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = UDim2.new(t, 0, 1, 0) }
	):Play()
end

-- ── State ──────────────────────────────────────────────────────
local currentNoise = 0
local currentLight = 0

-- Receives world-noise pushes from SensorSystem (nil first arg = noise-only update)
RE_Awareness.OnClientEvent:Connect(function(awareness, noise)
	if awareness == nil and noise then
		currentNoise = math.max(currentNoise, noise)
	end
end)

-- ── Main loop — single Heartbeat for both bars ─────────────────
RunService.Heartbeat:Connect(function(dt: number)
	local char = player.Character
	if not char then
		return
	end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end

	-- Light: sample all tagged map lights
	local pos = hrp.Position
	local maxLight = 0
	for _, light in ipairs(CollectionService:GetTagged("MapLights")) do
		if light:IsA("PointLight") and light.Enabled then
			local part = light.Parent
			if part then
				local dist = (pos - part.Position).Magnitude
				if dist <= light.Range then
					local contrib = 1 - dist / light.Range
					if contrib > maxLight then
						maxLight = contrib
					end
				end
			end
		end
	end
	currentLight = maxLight

	-- Noise: walking contribution + decay
	local vel = hrp.AssemblyLinearVelocity
	local speed = Vector2.new(vel.X, vel.Z).Magnitude
	if speed >= WALK_SPEED then
		currentNoise = math.max(currentNoise, WALK_NOISE)
	end
	currentNoise = math.max(0, currentNoise - DECAY_RATE * dt)

	-- Update bars
	lightFill.BackgroundColor3 = lightColor(currentLight)
	setBar(lightFill, currentLight)
	lightText.Text = currentLight > 0.02 and string.format("%d%%", math.floor(currentLight * 100)) or ""

	noiseFill.BackgroundColor3 = noiseColor(currentNoise)
	setBar(noiseFill, currentNoise)
	noiseText.Text = currentNoise > 0.02 and string.format("%d%%", math.floor(currentNoise * 100)) or ""

	-- Hide both bars when there is nothing to show
	local active = currentNoise > 0.02 or currentLight > 0.02
	noiseRow.Visible = active
	lightRow.Visible = active
end)
