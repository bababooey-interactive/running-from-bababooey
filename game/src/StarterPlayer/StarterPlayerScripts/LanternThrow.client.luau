-- =============================================================
--  LanternThrow.client.luau
--  Path: game/src/StarterPlayer/StarterPlayerScripts/LanternThrow.client.luau
--
--  • Shows a hint badge when the player has a lantern (Tool).
--  • Press G to throw it — fires ThrowLantern remote to server.
--  • Works whether the lantern is equipped (in Character) or
--    sitting unequipped in the Backpack.
-- =============================================================

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RE_ThrowLantern = Remotes:WaitForChild("ThrowLantern")

-- ─────────────────────────────────────────────
--  HINT UI
--  Positioned just above the coal-deposit hint (if both show at once
--  they stack cleanly because they use different Y offsets).
-- ─────────────────────────────────────────────

-- Destroy any leftover GUI from a previous character load.
local oldGui = PlayerGui:FindFirstChild("LanternThrowGui")
if oldGui then
	oldGui:Destroy()
end

local hintGui = Instance.new("ScreenGui")
hintGui.Name = "LanternThrowGui"
hintGui.ResetOnSpawn = false
hintGui.IgnoreGuiInset = true
hintGui.DisplayOrder = 5
hintGui.Parent = PlayerGui

local hintFrame = Instance.new("Frame")
hintFrame.Name = "HintFrame"
hintFrame.Size = UDim2.new(0, 270, 0, 48)
hintFrame.AnchorPoint = Vector2.new(0.5, 1)
-- Sits just above the coal-deposit prompt (which uses 0.82)
hintFrame.Position = UDim2.new(0.5, 0, 0.74, 0)
hintFrame.BackgroundColor3 = Color3.fromRGB(30, 20, 10)
hintFrame.BackgroundTransparency = 0.15
hintFrame.BorderSizePixel = 0
hintFrame.Visible = false
hintFrame.Parent = hintGui

Instance.new("UICorner", hintFrame).CornerRadius = UDim.new(0, 10)

local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(255, 160, 50)
stroke.Thickness = 2
stroke.Parent = hintFrame

local hintLabel = Instance.new("TextLabel")
hintLabel.Size = UDim2.new(1, 0, 1, 0)
hintLabel.BackgroundTransparency = 1
hintLabel.Text = "🔥  [G] Lempar Lentera"
hintLabel.TextColor3 = Color3.fromRGB(255, 210, 100)
hintLabel.TextScaled = true
hintLabel.Font = Enum.Font.GothamBold
hintLabel.Parent = hintFrame

-- ─────────────────────────────────────────────
--  LANTERN CHECK
-- ─────────────────────────────────────────────

local function hasLantern(): boolean
	-- Check character (equipped Tool)
	local char = player.Character
	if char then
		for _, child in ipairs(char:GetChildren()) do
			if child:IsA("Tool") then
				return true
			end
		end
	end
	-- Check Backpack (unequipped Tool)
	local bp = player:FindFirstChildOfClass("Backpack")
	if bp then
		for _, child in ipairs(bp:GetChildren()) do
			if child:IsA("Tool") then
				return true
			end
		end
	end
	return false
end

-- ─────────────────────────────────────────────
--  HEARTBEAT — show / hide hint
-- ─────────────────────────────────────────────

RunService.Heartbeat:Connect(function()
	hintFrame.Visible = hasLantern()
end)

-- ─────────────────────────────────────────────
--  INPUT
-- ─────────────────────────────────────────────

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	if input.KeyCode ~= Enum.KeyCode.G then
		return
	end
	if not hasLantern() then
		return
	end

	RE_ThrowLantern:FireServer()

	-- Optimistically hide the hint — the server will destroy the Tool,
	-- which triggers the Heartbeat check and confirms the hide.
	hintFrame.Visible = false
end)

print("[LanternThrow] Client ready — G to throw lantern.")
