-- AwarenessMeter.client.luau
-- Place inside StarterPlayerScripts

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RE_Noise = Remotes:WaitForChild("AwarenessUpdated")

-- ── Build ScreenGui ───────────────────────────────────────────
local gui = Instance.new("ScreenGui")
gui.Name = "DetectionGui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Parent = player.PlayerGui

local hud = Instance.new("Frame")
hud.Size = UDim2.new(0, 160, 0, 46)
hud.Position = UDim2.new(0.5, -80, 1, -60)
hud.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
hud.BackgroundTransparency = 0.3
hud.BorderSizePixel = 0
hud.Parent = gui
Instance.new("UICorner", hud).CornerRadius = UDim.new(0, 8)

local function makeRow(parent, yOffset, labelText)
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(0, 36, 0, 12)
	label.Position = UDim2.new(0, 10, 0, yOffset)
	label.BackgroundTransparency = 1
	label.Text = labelText
	label.TextColor3 = Color3.fromRGB(160, 160, 160)
	label.TextSize = 10
	label.Font = Enum.Font.GothamBold
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Parent = parent

	local track = Instance.new("Frame")
	track.Size = UDim2.new(1, -56, 0, 6)
	track.Position = UDim2.new(0, 50, 0, yOffset + 3)
	track.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
	track.BorderSizePixel = 0
	track.Parent = parent
	Instance.new("UICorner", track).CornerRadius = UDim.new(1, 0)

	local fill = Instance.new("Frame")
	fill.Size = UDim2.new(0, 0, 1, 0)
	fill.BackgroundColor3 = Color3.fromRGB(90, 90, 90)
	fill.BorderSizePixel = 0
	fill.Parent = track
	Instance.new("UICorner", fill).CornerRadius = UDim.new(1, 0)

	return fill
end

local noiseFill = makeRow(hud, 10, "NOISE")
local lightFill = makeRow(hud, 28, "LIGHT")

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

RE_Noise.OnClientEvent:Connect(function(_aw, noise)
	-- _aw is monster awareness — ignored entirely
	currentNoise = noise or 0
	noiseFill.BackgroundColor3 = noiseColor(currentNoise)
	setBar(noiseFill, currentNoise)
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

	lightFill.BackgroundColor3 = lightColor(maxContrib)
	setBar(lightFill, maxContrib)
end)

-- ── Hide when fully 0 (optional, keeps HUD clean) ────────────
RunService.Heartbeat:Connect(function()
	local anyActivity = currentNoise > 0.02
	hud.Visible = anyActivity -- or just remove this if you want it always visible
end)
