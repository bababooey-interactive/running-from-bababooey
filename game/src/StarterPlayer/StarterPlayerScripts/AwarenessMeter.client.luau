-- AwarenessMeter.client.luau
-- Place inside StarterPlayerScripts
-- Redesigned to match SurvivalUI style, positioned at bottom-right

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RE_Noise = Remotes:WaitForChild("AwarenessUpdated")

-- ── Color palette (matches SurvivalUI) ────────────────────────
local C = {
	BG_DARK    = Color3.fromRGB(14, 14, 18),
	BAR_BG     = Color3.fromRGB(35, 35, 42),
	BORDER     = Color3.fromRGB(60, 60, 75),
	TEXT_WHITE  = Color3.fromRGB(235, 235, 235),
	TEXT_DIM    = Color3.fromRGB(150, 150, 160),
}

-- ── Build ScreenGui ───────────────────────────────────────────
local gui = Instance.new("ScreenGui")
gui.Name = "DetectionGui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Parent = player.PlayerGui

-- Container at bottom-right (mirrors SurvivalUI's bottom-left bars)
local barsFrame = Instance.new("Frame")
barsFrame.Name = "AwarenessBars"
barsFrame.AnchorPoint = Vector2.new(1, 1)
barsFrame.Position = UDim2.new(1, -12, 1, -12)
barsFrame.Size = UDim2.new(0, 200, 0, 56)
barsFrame.BackgroundTransparency = 1
barsFrame.Parent = gui

local barsLayout = Instance.new("UIListLayout")
barsLayout.FillDirection = Enum.FillDirection.Vertical
barsLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom
barsLayout.Padding = UDim.new(0, 5)
barsLayout.SortOrder = Enum.SortOrder.LayoutOrder
barsLayout.Parent = barsFrame

-- ── Bar builder (matches SurvivalUI bar style) ─────────────────
local function makeBar(icon, barColor, layoutOrder, name)
	local row = Instance.new("Frame")
	row.Name = name
	row.Size = UDim2.new(1, 0, 0, 22)
	row.BackgroundTransparency = 1
	row.LayoutOrder = layoutOrder
	row.Parent = barsFrame

	local iconLabel = Instance.new("TextLabel")
	iconLabel.Name = "Icon"
	iconLabel.Size = UDim2.new(0, 20, 1, 0)
	iconLabel.BackgroundTransparency = 1
	iconLabel.TextColor3 = barColor
	iconLabel.TextSize = 14
	iconLabel.Font = Enum.Font.GothamBold
	iconLabel.Text = icon
	iconLabel.TextYAlignment = Enum.TextYAlignment.Center
	iconLabel.Parent = row

	local trackBg = Instance.new("Frame")
	trackBg.Name = "Track"
	trackBg.Position = UDim2.new(0, 24, 0.5, -7)
	trackBg.Size = UDim2.new(1, -24, 0, 14)
	trackBg.BackgroundColor3 = C.BAR_BG
	trackBg.BorderSizePixel = 0
	trackBg.Parent = row

	local trackCorner = Instance.new("UICorner")
	trackCorner.CornerRadius = UDim.new(0, 4)
	trackCorner.Parent = trackBg

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.new(0, 0, 1, 0)
	fill.BackgroundColor3 = barColor
	fill.BorderSizePixel = 0
	fill.Parent = trackBg

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 4)
	fillCorner.Parent = fill

	local barText = Instance.new("TextLabel")
	barText.Name = "BarText"
	barText.Size = UDim2.new(1, 0, 1, 0)
	barText.BackgroundTransparency = 1
	barText.TextColor3 = C.TEXT_WHITE
	barText.TextSize = 10
	barText.Font = Enum.Font.GothamBold
	barText.Text = ""
	barText.ZIndex = 2
	barText.Parent = trackBg

	return row, fill, barText
end

local noiseRow, noiseFill, noiseText = makeBar("🔊", Color3.fromRGB(180, 120, 40), 1, "NoiseRow")
local lightRow, lightFill, lightText = makeBar("💡", Color3.fromRGB(200, 160, 40), 2, "LightRow")

-- ── Color helpers ─────────────────────────────────────────────
local function noiseColor(t)
	-- grey → amber → red
	if t < 0.5 then
		return Color3.fromRGB(
			math.round(180 + 55 * (t * 2)),
			math.round(180 - 60 * (t * 2)),
			math.round(180 - 130 * (t * 2))
		)
	else
		return Color3.fromRGB(
			math.round(235),
			math.round(120 - 80 * ((t - 0.5) * 2)),
			math.round(50 - 30 * ((t - 0.5) * 2))
		)
	end
end

local function lightColor(t)
	-- grey → amber
	return Color3.fromRGB(math.round(160 + 79 * t), math.round(160 - 1 * t), math.round(160 - 121 * t))
end

local function setBar(fill, t)
	TweenService:Create(
		fill,
		TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = UDim2.new(t, 0, 1, 0) }
	):Play()
end

-- ── Noise: from AwarenessUpdated (2nd arg is noise 0-1) ───────
local currentNoise = 0
local currentLight = 0

RE_Noise.OnClientEvent:Connect(function(_aw, noise)
	-- _aw is monster awareness — ignored entirely
	currentNoise = noise or 0
	noiseFill.BackgroundColor3 = noiseColor(currentNoise)
	setBar(noiseFill, currentNoise)
	noiseText.Text = currentNoise > 0.02 and string.format("%d%%", math.floor(currentNoise * 100)) or ""
end)

-- ── Light: checked locally every frame ────────────────────────
RunService.Heartbeat:Connect(function()
	local char = player.Character
	if not char then
		return
	end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end

	local pos = hrp.Position
	local maxContrib = 0

	for _, light in ipairs(CollectionService:GetTagged("MapLights")) do
		if light:IsA("PointLight") and light.Enabled then
			local part = light.Parent
			if part then
				local dist = (pos - part.Position).Magnitude
				if dist <= light.Range then
					-- closer = brighter contribution
					local contrib = 1 - (dist / light.Range)
					if contrib > maxContrib then
						maxContrib = contrib
					end
				end
			end
		end
	end

	currentLight = maxContrib
	lightFill.BackgroundColor3 = lightColor(maxContrib)
	setBar(lightFill, maxContrib)
	lightText.Text = maxContrib > 0.02 and string.format("%d%%", math.floor(maxContrib * 100)) or ""
end)

-- ── Hide when both bars are at 0 (keeps HUD clean) ────────────
RunService.Heartbeat:Connect(function()
	local anyActivity = currentNoise > 0.02 or currentLight > 0.02
	noiseRow.Visible = anyActivity
	lightRow.Visible = anyActivity
end)
