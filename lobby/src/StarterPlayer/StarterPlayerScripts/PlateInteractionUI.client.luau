-- =============================================================
--  PlateInteractionUI.client.luau
--  Proximity-based ENTER / LEAVE buttons for mode plates.
--  Replaces the old touch-to-enter mechanic.
-- =============================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local EnterPlateRE = Remotes:WaitForChild("EnterPlate") :: RemoteEvent
local LeaveRoomRE = Remotes:WaitForChild("LeaveRoom") :: RemoteEvent

-- ============================================================
-- CONFIG
-- ============================================================

local SOLO_COLOR = Color3.fromRGB(80, 160, 255)
local COOP_COLOR = Color3.fromRGB(80, 255, 140)
local LEAVE_COLOR = Color3.fromRGB(255, 80, 80)
local PROXIMITY_RANGE = 18 -- studs to show ENTER button

-- ============================================================
-- STATE
-- ============================================================

local currentPlateMode: string? = nil -- "SOLO", "COOP", or nil
local nearestPlate: BasePart? = nil

-- ============================================================
-- BUILD GUI
-- ============================================================

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "PlateInteractionGui"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 5 -- above LevelSelectGui
screenGui.Parent = PlayerGui

-- Container frame at bottom center
local container = Instance.new("Frame")
container.Name = "Container"
container.AnchorPoint = Vector2.new(0.5, 1)
container.Position = UDim2.new(0.5, 0, 0.92, 0)
container.Size = UDim2.new(0, 260, 0, 80)
container.BackgroundTransparency = 1
container.Visible = false
container.Parent = screenGui

-- Mode label ("SOLO MODE" / "COOP MODE")
local modeLabel = Instance.new("TextLabel")
modeLabel.Name = "ModeLabel"
modeLabel.Size = UDim2.new(1, 0, 0, 24)
modeLabel.Position = UDim2.new(0, 0, 0, 0)
modeLabel.BackgroundTransparency = 1
modeLabel.Font = Enum.Font.GothamBold
modeLabel.TextSize = 16
modeLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
modeLabel.Text = ""
modeLabel.TextStrokeTransparency = 0.5
modeLabel.Parent = container

-- Interaction button (ENTER / LEAVE)
local button = Instance.new("TextButton")
button.Name = "InteractionButton"
button.Size = UDim2.new(1, 0, 0, 50)
button.Position = UDim2.new(0, 0, 0, 28)
button.BackgroundColor3 = SOLO_COLOR
button.BackgroundTransparency = 0.15
button.Font = Enum.Font.GothamBold
button.TextSize = 20
button.TextColor3 = Color3.fromRGB(255, 255, 255)
button.Text = "▶ ENTER"
button.AutoButtonColor = true
button.Parent = container

local buttonCorner = Instance.new("UICorner")
buttonCorner.CornerRadius = UDim.new(0, 12)
buttonCorner.Parent = button

local buttonStroke = Instance.new("UIStroke")
buttonStroke.Color = Color3.fromRGB(255, 255, 255)
buttonStroke.Transparency = 0.6
buttonStroke.Thickness = 1.5
buttonStroke.Parent = button

-- ============================================================
-- HELPERS
-- ============================================================

local function getPlates(): { BasePart }
	local lobby = game.Workspace:FindFirstChild("Lobby")
	if not lobby then
		return {}
	end
	local modePlates = lobby:FindFirstChild("ModePlates")
	if not modePlates then
		return {}
	end

	local plates = {}
	for _, plate in modePlates:GetChildren() do
		if plate:IsA("BasePart") then
			table.insert(plates, plate)
		end
	end
	return plates
end

local function findNearestPlate(): BasePart?
	local character = LocalPlayer.Character
	if not character then
		return nil
	end
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return nil
	end

	local playerPos = hrp.Position
	local nearest: BasePart? = nil
	local nearestDist = PROXIMITY_RANGE

	for _, plate in getPlates() do
		local dist = (plate.Position - playerPos).Magnitude
		if dist < nearestDist then
			nearestDist = dist
			nearest = plate
		end
	end

	return nearest
end

-- ============================================================
-- BUTTON VISUALS
-- ============================================================

local function showEnterButton(roomMode: string)
	if roomMode == "SOLO" then
		button.Text = "▶ ENTER SOLO"
		button.BackgroundColor3 = SOLO_COLOR
		modeLabel.Text = "SOLO MODE"
		modeLabel.TextColor3 = SOLO_COLOR
	elseif roomMode == "COOP" then
		button.Text = "▶ ENTER COOP"
		button.BackgroundColor3 = COOP_COLOR
		modeLabel.Text = "COOP MODE"
		modeLabel.TextColor3 = COOP_COLOR
	end
	button.BackgroundTransparency = 0.15
	buttonStroke.Color = Color3.fromRGB(255, 255, 255)
	container.Visible = true
end

local function showLeaveButton()
	button.Text = "X LEAVE"
	button.BackgroundColor3 = LEAVE_COLOR
	button.BackgroundTransparency = 0.15
	modeLabel.Text = (currentPlateMode or "") .. " MODE — ACTIVE"
	modeLabel.TextColor3 = LEAVE_COLOR
	buttonStroke.Color = Color3.fromRGB(255, 200, 200)
	container.Visible = true
end

local function hideButton()
	container.Visible = false
end

-- ============================================================
-- UPDATE LOOP
-- ============================================================

local function updateButton()
	if currentPlateMode then
		-- Player is inside a room — always show LEAVE
		showLeaveButton()
	else
		-- Check for nearby plate
		nearestPlate = findNearestPlate()
		if nearestPlate then
			local roomMode = nearestPlate:GetAttribute("RoomMode")
			if roomMode == "SOLO" or roomMode == "COOP" then
				showEnterButton(roomMode)
			else
				hideButton()
			end
		else
			hideButton()
		end
	end
end

-- ============================================================
-- BUTTON CLICK HANDLERS
-- ============================================================

button.MouseButton1Click:Connect(function()
	if currentPlateMode then
		-- Leave current room
		LeaveRoomRE:FireServer()
		currentPlateMode = nil

		-- Close LevelSelectUI if open
		local levelSelectGui = PlayerGui:FindFirstChild("LevelSelectGui")
		if levelSelectGui and levelSelectGui:IsA("ScreenGui") then
			levelSelectGui.Enabled = false
		end

		updateButton()
	else
		-- Enter nearest plate
		if nearestPlate then
			local roomMode = nearestPlate:GetAttribute("RoomMode")
			if roomMode then
				currentPlateMode = roomMode
				EnterPlateRE:FireServer(roomMode)
				updateButton()
			end
		end
	end
end)

-- ============================================================
-- LISTEN FOR LEVEL SELECT UI CLOSE (from its own close button)
-- ============================================================

local levelSelectGui = PlayerGui:FindFirstChild("LevelSelectGui")
if levelSelectGui and levelSelectGui:IsA("ScreenGui") then
	levelSelectGui:GetPropertyChangedSignal("Enabled"):Connect(function()
		if not levelSelectGui.Enabled then
			currentPlateMode = nil
			updateButton()
		end
	end)
end

-- Also handle when LevelSelectGui is created later
PlayerGui.ChildAdded:Connect(function(child)
	if child.Name == "LevelSelectGui" and child:IsA("ScreenGui") then
		child:GetPropertyChangedSignal("Enabled"):Connect(function()
			if not child.Enabled then
				currentPlateMode = nil
				updateButton()
			end
		end)
	end
end)

-- ============================================================
-- PROXIMITY DETECTION LOOP
-- ============================================================

task.spawn(function()
	while true do
		updateButton()
		task.wait(0.3)
	end
end)

print("[PlateInteractionUI] Ready — proximity-based ENTER/LEAVE buttons active.")
