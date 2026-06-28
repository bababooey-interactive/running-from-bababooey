-- =============================================================
--  PlateInteractionUI.client.luau  (REWRITE)
--  Path: lobby/src/StarterPlayer/StarterPlayerScripts/PlateInteractionUI.client.luau
--
--  Behaviour:
--  • Scan for plates under Lobby/Plates/Solo and Lobby/Plates/Coop
--  • Show an ENTER button when the player walks near a plate
--  • Clicking ENTER fires EnterPlate → server teleports the player on top
--  • While on a plate, show a LEAVE button
--  • Plates are semi-transparent non-collidable parts — you can't
--    walk onto them without pressing ENTER (server controls position)
--  • Occupied solo plates show the occupant's name and are greyed out
-- =============================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local RE_EnterPlate = Remotes:WaitForChild("EnterPlate") :: RemoteEvent
local RE_LeavePlate = Remotes:WaitForChild("LeavePlate") :: RemoteEvent
local RE_PlateOccupied = Remotes:WaitForChild("PlateOccupied") :: RemoteEvent
local _RE_LeaveRoom = Remotes:WaitForChild("LeaveRoom") :: RemoteEvent

-- ============================================================
-- CONFIG
-- ============================================================

local PROXIMITY_RANGE = 16 -- studs to show ENTER button

local COLOR = {
	SOLO = Color3.fromRGB(90, 160, 255),
	COOP = Color3.fromRGB(80, 210, 130),
	LEAVE = Color3.fromRGB(220, 70, 70),
	BG = Color3.fromRGB(18, 18, 22),
	BG_LIGHT = Color3.fromRGB(28, 28, 34),
	TEXT = Color3.fromRGB(235, 235, 235),
	TEXT_DIM = Color3.fromRGB(140, 140, 150),
	OCCUPIED = Color3.fromRGB(60, 60, 65),
}

-- ============================================================
-- STATE
-- ============================================================

-- The plate this player is currently standing on, or nil
-- { roomMode: string, index: number } | nil
local myPlate: { roomMode: string, index: number }? = nil

-- Occupation snapshot from server: { ["SOLO_1"] = "PlayerName", ... }
local occupationMap: { [string]: string } = {}

-- All plates found in workspace (populated lazily after map loads)
type PlateEntry = {
	part: BasePart,
	roomMode: string,
	index: number,
	key: string,
}
local allPlates: { PlateEntry } = {}
local platesScanned = false

-- ============================================================
-- PLATE SCANNING
-- ============================================================

local function scanPlates()
	allPlates = {}
	local lobby = workspace:FindFirstChild("Lobby")
	if not lobby then
		return
	end
	local platesFolder = lobby:FindFirstChild("Plates")
	if not platesFolder then
		return
	end

	for _, modeFolder in ipairs(platesFolder:GetChildren()) do
		if not modeFolder:IsA("Folder") then
			continue
		end
		local roomMode = modeFolder:GetAttribute("RoomMode")
			or (modeFolder.Name == "Solo" and "SOLO")
			or (modeFolder.Name == "Coop" and "COOP")
		if not roomMode then
			continue
		end

		for _, plate in ipairs(modeFolder:GetChildren()) do
			if not plate:IsA("BasePart") then
				continue
			end
			local index = plate:GetAttribute("Index")
			if not index then
				continue
			end

			table.insert(allPlates, {
				part = plate,
				roomMode = roomMode,
				index = index,
				key = roomMode .. "_" .. index,
			})

			-- Make sure players can't physically walk onto plates
			plate.CanCollide = false
			plate.CanTouch = false
		end
	end

	platesScanned = true
end

-- ============================================================
-- BUILD GUI
-- ============================================================

local gui = Instance.new("ScreenGui")
gui.Name = "PlateInteractionGui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 6
gui.Parent = PlayerGui

-- ── Prompt container (slides up from bottom center) ────────

local promptFrame = Instance.new("Frame")
promptFrame.Name = "PromptFrame"
promptFrame.AnchorPoint = Vector2.new(0.5, 1)
promptFrame.Position = UDim2.new(0.5, 0, 1, 90) -- starts hidden below screen
promptFrame.Size = UDim2.new(0, 280, 0, 88)
promptFrame.BackgroundColor3 = COLOR.BG
promptFrame.BackgroundTransparency = 0.08
promptFrame.BorderSizePixel = 0
promptFrame.Visible = false
promptFrame.Parent = gui

Instance.new("UICorner", promptFrame).CornerRadius = UDim.new(0, 14)

local promptStroke = Instance.new("UIStroke")
promptStroke.Color = Color3.fromRGB(60, 60, 75)
promptStroke.Thickness = 1.5
promptStroke.Parent = promptFrame

-- Mode label e.g. "SOLO PLATE  #1"
local modeLabel = Instance.new("TextLabel")
modeLabel.Name = "ModeLabel"
modeLabel.Size = UDim2.new(1, -24, 0, 22)
modeLabel.Position = UDim2.new(0, 12, 0, 10)
modeLabel.BackgroundTransparency = 1
modeLabel.Font = Enum.Font.GothamBold
modeLabel.TextSize = 12
modeLabel.TextColor3 = COLOR.TEXT_DIM
modeLabel.TextXAlignment = Enum.TextXAlignment.Left
modeLabel.Text = ""
modeLabel.Parent = promptFrame

-- Occupant name (solo only, shown when taken)
local occupantLabel = Instance.new("TextLabel")
occupantLabel.Name = "OccupantLabel"
occupantLabel.Size = UDim2.new(1, -24, 0, 16)
occupantLabel.Position = UDim2.new(0, 12, 0, 28)
occupantLabel.BackgroundTransparency = 1
occupantLabel.Font = Enum.Font.Gotham
occupantLabel.TextSize = 11
occupantLabel.TextColor3 = COLOR.TEXT_DIM
occupantLabel.TextXAlignment = Enum.TextXAlignment.Left
occupantLabel.Text = ""
occupantLabel.Parent = promptFrame

-- Action button
local actionBtn = Instance.new("TextButton")
actionBtn.Name = "ActionBtn"
actionBtn.AnchorPoint = Vector2.new(0.5, 1)
actionBtn.Position = UDim2.new(0.5, 0, 1, -10)
actionBtn.Size = UDim2.new(1, -24, 0, 36)
actionBtn.BackgroundColor3 = COLOR.SOLO
actionBtn.BackgroundTransparency = 0.1
actionBtn.BorderSizePixel = 0
actionBtn.Font = Enum.Font.GothamBold
actionBtn.TextSize = 15
actionBtn.TextColor3 = COLOR.TEXT
actionBtn.Text = "ENTER"
actionBtn.AutoButtonColor = true
actionBtn.Parent = promptFrame

Instance.new("UICorner", actionBtn).CornerRadius = UDim.new(0, 8)

-- ============================================================
-- ANIMATION HELPERS
-- ============================================================

local visibleY = UDim2.new(0.5, 0, 1, -24) -- resting position above bottom edge
local hiddenY = UDim2.new(0.5, 0, 1, 90) -- off-screen below

local currentTween: Tween? = nil
local promptVisible = false

local function showPrompt()
	if promptVisible then
		return
	end
	promptVisible = true
	promptFrame.Visible = true
	if currentTween then
		currentTween:Cancel()
	end
	local tween = TweenService:Create(
		promptFrame,
		TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Position = visibleY }
	)
	currentTween = tween
	tween:Play()
end

local function hidePrompt()
	if not promptVisible then
		return
	end
	promptVisible = false
	if currentTween then
		currentTween:Cancel()
	end
	local tween = TweenService:Create(
		promptFrame,
		TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ Position = hiddenY }
	)
	currentTween = tween
	tween:Play()
	tween.Completed:Connect(function()
		if not promptVisible then
			promptFrame.Visible = false
		end
	end)
end

-- ============================================================
-- NEAREST PLATE LOGIC
-- ============================================================

local function getNearestPlate(): PlateEntry?
	local char = LocalPlayer.Character
	if not char then
		return nil
	end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return nil
	end

	local pos = hrp.Position
	local best: PlateEntry? = nil
	local bestDist = PROXIMITY_RANGE

	for _, entry in ipairs(allPlates) do
		if not entry.part.Parent then
			continue
		end
		local dist = (entry.part.Position - pos).Magnitude
		if dist < bestDist then
			bestDist = dist
			best = entry
		end
	end
	return best
end

-- ============================================================
-- UI STATE MACHINE
-- ============================================================

local function updatePromptForPlate(entry: PlateEntry)
	local accentColor = entry.roomMode == "SOLO" and COLOR.SOLO or COLOR.COOP
	local occupant = occupationMap[entry.key]
	local isSelf = myPlate and myPlate.roomMode == entry.roomMode and myPlate.index == entry.index

	modeLabel.Text = string.format("%s PLATE  #%d", entry.roomMode, entry.index)
	modeLabel.TextColor3 = accentColor

	promptStroke.Color = accentColor

	if isSelf then
		-- Player is on this plate → show LEAVE
		occupantLabel.Text = "You are here"
		occupantLabel.TextColor3 = accentColor
		actionBtn.Text = "LEAVE"
		actionBtn.BackgroundColor3 = COLOR.LEAVE
		actionBtn.Active = true
	elseif occupant and entry.roomMode == "SOLO" then
		-- Solo plate taken by someone else → disabled
		occupantLabel.Text = "Taken by " .. occupant
		occupantLabel.TextColor3 = COLOR.TEXT_DIM
		actionBtn.Text = "OCCUPIED"
		actionBtn.BackgroundColor3 = COLOR.OCCUPIED
		actionBtn.Active = false
	else
		-- Free to enter
		if occupant and entry.roomMode == "COOP" then
			occupantLabel.Text = occupant .. " is here"
			occupantLabel.TextColor3 = COLOR.TEXT_DIM
		else
			occupantLabel.Text = ""
		end
		actionBtn.Text = "ENTER"
		actionBtn.BackgroundColor3 = accentColor
		actionBtn.Active = true
	end
end

-- ============================================================
-- BUTTON CLICK
-- ============================================================

local lastNearEntry: PlateEntry? = nil

actionBtn.MouseButton1Click:Connect(function()
	local isSelf = myPlate ~= nil

	if isSelf then
		-- LEAVE
		myPlate = nil
		RE_LeavePlate:FireServer()

		-- Also close LevelSelectUI
		local lsGui = PlayerGui:FindFirstChild("LevelSelectGui")
		if lsGui then
			lsGui.Enabled = false
		end

		hidePrompt()
	else
		-- ENTER
		if not lastNearEntry then
			return
		end
		local entry = lastNearEntry

		-- Don't enter a taken solo plate
		local occupant = occupationMap[entry.key]
		if occupant and entry.roomMode == "SOLO" then
			return
		end

		myPlate = { roomMode = entry.roomMode, index = entry.index }
		RE_EnterPlate:FireServer(entry.roomMode, entry.index)
		-- Prompt stays visible but switches to LEAVE mode — updatePromptForPlate
		-- will handle it on the next loop tick
	end
end)

-- ============================================================
-- OCCUPATION SYNC FROM SERVER
-- ============================================================

RE_PlateOccupied.OnClientEvent:Connect(function(snapshot: { [string]: string })
	occupationMap = snapshot
end)

-- ============================================================
-- LEVEL SELECT UI CLOSED EXTERNALLY (e.g. X button)
-- ============================================================

local function watchLevelSelectGui(lsGui: ScreenGui)
	lsGui:GetPropertyChangedSignal("Enabled"):Connect(function()
		if not lsGui.Enabled and myPlate then
			-- User dismissed the UI without pressing LEAVE — fire leave anyway
			myPlate = nil
			RE_LeavePlate:FireServer()
		end
	end)
end

local existingLSGui = PlayerGui:FindFirstChild("LevelSelectGui")
if existingLSGui and existingLSGui:IsA("ScreenGui") then
	watchLevelSelectGui(existingLSGui :: ScreenGui)
end

PlayerGui.ChildAdded:Connect(function(child)
	if child.Name == "LevelSelectGui" and child:IsA("ScreenGui") then
		watchLevelSelectGui(child :: ScreenGui)
	end
end)

-- ============================================================
-- MAIN LOOP
-- ============================================================

-- Lazy scan: retry until the Lobby folder exists
task.spawn(function()
	while not platesScanned do
		if workspace:FindFirstChild("Lobby") then
			scanPlates()
		end
		task.wait(1)
	end
end)

RunService.Heartbeat:Connect(function()
	if not platesScanned then
		return
	end

	-- If local player is on a plate, always show LEAVE prompt
	if myPlate then
		-- Find the entry for our plate to display it
		for _, entry in ipairs(allPlates) do
			if entry.roomMode == myPlate.roomMode and entry.index == myPlate.index then
				lastNearEntry = entry
				updatePromptForPlate(entry)
				showPrompt()
				return
			end
		end
	end

	-- Otherwise show ENTER if near a plate
	local nearest = getNearestPlate()
	lastNearEntry = nearest

	if nearest then
		updatePromptForPlate(nearest)
		showPrompt()
	else
		hidePrompt()
	end
end)

-- Reset on respawn
LocalPlayer.CharacterAdded:Connect(function()
	if myPlate then
		RE_LeavePlate:FireServer()
		myPlate = nil
	end
	hidePrompt()
end)

print("[PlateInteractionUI] Ready.")
