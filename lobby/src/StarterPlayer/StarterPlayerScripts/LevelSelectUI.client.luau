-- =============================================================
--  LevelSelectUI.client.luau
--  Author: Gilang
--  Path: lobby/src/StarterPlayer/StarterPlayerScripts/LevelSelectUI.client.luau
-- =============================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
-- local TweenService = game:GetService("TweenService")

local Constants = require(ReplicatedStorage.Shared.Constants)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local function R(name: string): RemoteEvent
	return Remotes:WaitForChild(name) :: RemoteEvent
end

local RE = {
	RoomStateUpdated = R("RoomStateUpdated"),
	CreateRoom = R("CreateRoom"),
	LeaveRoom = R("LeaveRoom"),
	PlayerReadyUp = R("PlayerReadyUp"),
	VoteForLevel = R("VoteForLevel"),
	VoteResultUpdated = R("VoteResultUpdated"),
	StartingGame = R("StartingGame"),
	TeleportFailed = R("TeleportFailed"),
}

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

-- ============================================================
-- STATE
-- ============================================================

local currentRoomInfo = nil
local myVotedLevel = nil
local isReady = false

-- ============================================================
-- BUILD GUI
-- ============================================================

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "LevelSelectGui"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.Enabled = false
screenGui.Parent = PlayerGui

local mainFrame = Instance.new("Frame")
mainFrame.Name = "MainFrame"
mainFrame.AnchorPoint = Vector2.new(0.5, 0.5)
mainFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
mainFrame.Size = UDim2.new(0, 460, 0, 420)
mainFrame.BackgroundColor3 = Color3.fromRGB(22, 22, 26)
mainFrame.BackgroundTransparency = 0.05
mainFrame.BorderSizePixel = 0
mainFrame.Parent = screenGui

local mainCorner = Instance.new("UICorner")
mainCorner.CornerRadius = UDim.new(0, 14)
mainCorner.Parent = mainFrame

local titleLabel = Instance.new("TextLabel")
titleLabel.BackgroundTransparency = 1
titleLabel.Position = UDim2.new(0, 0, 0, 18)
titleLabel.Size = UDim2.new(1, 0, 0, 32)
titleLabel.Font = Enum.Font.GothamBold
titleLabel.TextSize = 22
titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
titleLabel.Text = "SELECT LEVEL"
titleLabel.Parent = mainFrame

local subtitleLabel = Instance.new("TextLabel")
subtitleLabel.BackgroundTransparency = 1
subtitleLabel.Position = UDim2.new(0, 0, 0, 50)
subtitleLabel.Size = UDim2.new(1, 0, 0, 22)
subtitleLabel.Font = Enum.Font.Gotham
subtitleLabel.TextSize = 14
subtitleLabel.TextColor3 = Color3.fromRGB(180, 180, 180)
subtitleLabel.Text = ""
subtitleLabel.Parent = mainFrame

-- ---------- Grid tombol level ----------

local levelGrid = Instance.new("Frame")
levelGrid.Name = "LevelGrid"
levelGrid.BackgroundTransparency = 1
levelGrid.Position = UDim2.new(0, 20, 0, 84)
levelGrid.Size = UDim2.new(1, -40, 0, 180)
levelGrid.Parent = mainFrame

local gridLayout = Instance.new("UIGridLayout")
gridLayout.CellSize = UDim2.new(0, 78, 0, 56)
gridLayout.CellPadding = UDim2.new(0, 8, 0, 8)
gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
gridLayout.Parent = levelGrid

local levelButtons: { [number]: TextButton } = {}

local function refreshLevelButtonVisuals()
	for level, btn in pairs(levelButtons) do
		local locked = currentRoomInfo and level > currentRoomInfo.maxLevel

		if locked then
			btn.BackgroundColor3 = Color3.fromRGB(35, 35, 38)
			btn.TextColor3 = Color3.fromRGB(90, 90, 90)
			btn.Text = "🔒"
		elseif myVotedLevel == level then
			btn.BackgroundColor3 = Color3.fromRGB(80, 170, 100)
			btn.TextColor3 = Color3.fromRGB(255, 255, 255)
			btn.Text = tostring(level)
		else
			btn.BackgroundColor3 = Color3.fromRGB(45, 45, 52)
			btn.TextColor3 = Color3.fromRGB(230, 230, 230)
			btn.Text = tostring(level)
		end
	end
end

-- ── FIX: SOLO no longer fires VoteForLevel immediately on level click.
--   For SOLO, the vote is only sent when the player clicks START.
--   For COOP, votes are sent in real-time so all members see the tally.
local function onLevelButtonClicked(level: number)
	if currentRoomInfo and level > currentRoomInfo.maxLevel then
		return -- locked
	end

	myVotedLevel = level
	refreshLevelButtonVisuals()

	-- Only broadcast the vote immediately in COOP mode.
	if currentRoomInfo and currentRoomInfo.roomMode == "COOP" then
		RE.VoteForLevel:FireServer(level)
	end
end

for level = 1, Constants.DEFAULT_UNLOCKED_LEVELS do
	local btn = Instance.new("TextButton")
	btn.Name = "Level" .. level
	btn.Font = Enum.Font.GothamBold
	btn.TextSize = 20
	btn.AutoButtonColor = true
	btn.LayoutOrder = level
	btn.Parent = levelGrid

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = btn

	btn.MouseButton1Click:Connect(function()
		onLevelButtonClicked(level)
	end)

	levelButtons[level] = btn
end

-- ---------- Daftar player + ready status (Coop only) ----------

local playerListFrame = Instance.new("Frame")
playerListFrame.Name = "PlayerList"
playerListFrame.BackgroundTransparency = 1
playerListFrame.Position = UDim2.new(0, 20, 0, 272)
playerListFrame.Size = UDim2.new(1, -40, 0, 70)
playerListFrame.Visible = false
playerListFrame.Parent = mainFrame

local playerListLayout = Instance.new("UIListLayout")
playerListLayout.Padding = UDim.new(0, 2)
playerListLayout.SortOrder = Enum.SortOrder.LayoutOrder
playerListLayout.Parent = playerListFrame

local function clearPlayerListEntries()
	for _, child in ipairs(playerListFrame:GetChildren()) do
		if child:IsA("TextLabel") then
			child:Destroy()
		end
	end
end

-- ---------- Tombol aksi (Mulai / Ready) ----------

local actionButton = Instance.new("TextButton")
actionButton.Name = "ActionButton"
actionButton.AnchorPoint = Vector2.new(0.5, 1)
actionButton.Position = UDim2.new(0.5, 0, 1, -20)
actionButton.Size = UDim2.new(1, -40, 0, 48)
actionButton.BackgroundColor3 = Color3.fromRGB(200, 60, 60)
actionButton.Font = Enum.Font.GothamBold
actionButton.TextSize = 18
actionButton.TextColor3 = Color3.fromRGB(255, 255, 255)
actionButton.Text = "START"
actionButton.Parent = mainFrame

local actionCorner = Instance.new("UICorner")
actionCorner.CornerRadius = UDim.new(0, 10)
actionCorner.Parent = actionButton

local closeButton = Instance.new("TextButton")
closeButton.Name = "CloseButton"
closeButton.AnchorPoint = Vector2.new(1, 0)
closeButton.Position = UDim2.new(1, -14, 0, 14)
closeButton.Size = UDim2.new(0, 28, 0, 28)
closeButton.BackgroundColor3 = Color3.fromRGB(40, 40, 45)
closeButton.Font = Enum.Font.GothamBold
closeButton.TextSize = 16
closeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
closeButton.Text = "X"
closeButton.Parent = mainFrame

local closeCorner = Instance.new("UICorner")
closeCorner.CornerRadius = UDim.new(1, 0)
closeCorner.Parent = closeButton

-- ---------- Countdown overlay (StartingGame) ----------

local countdownLabel = Instance.new("TextLabel")
countdownLabel.Name = "CountdownLabel"
countdownLabel.AnchorPoint = Vector2.new(0.5, 0.5)
countdownLabel.Position = UDim2.new(0.5, 0, 0.5, 0)
countdownLabel.Size = UDim2.new(1, 0, 0, 60)
countdownLabel.BackgroundTransparency = 1
countdownLabel.Font = Enum.Font.GothamBold
countdownLabel.TextSize = 30
countdownLabel.TextColor3 = Color3.fromRGB(255, 220, 100)
countdownLabel.Text = ""
countdownLabel.Visible = false
countdownLabel.Parent = screenGui

-- ============================================================
-- LOGIC
-- ============================================================

local function closeUI()
	screenGui.Enabled = false

	if currentRoomInfo and currentRoomInfo.roomMode == "COOP" then
		RE.LeaveRoom:FireServer()
	end

	currentRoomInfo = nil
	myVotedLevel = nil
	isReady = false
end

closeButton.MouseButton1Click:Connect(closeUI)

local function updateUIFromRoomInfo(info)
	currentRoomInfo = info
	subtitleLabel.Text = string.format("Mode: %s", info.roomMode)

	local isCoop = info.roomMode == "COOP"
	playerListFrame.Visible = isCoop

	if isCoop then
		actionButton.Text = isReady and "WAITING FOR OTHERS..." or "READY UP"
		actionButton.BackgroundColor3 = isReady and Color3.fromRGB(80, 80, 85) or Color3.fromRGB(80, 170, 100)
		actionButton.Active = not isReady

		clearPlayerListEntries()

		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.new(1, 0, 0, 20)
		label.Font = Enum.Font.Gotham
		label.TextSize = 13
		label.TextColor3 = Color3.fromRGB(200, 200, 200)
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.Text = string.format(
			"Players: %d/%d   •   Ready: %d/%d",
			info.playerCount,
			info.maxPlayers,
			info.readyCount,
			info.playerCount
		)
		label.Parent = playerListFrame
	else
		-- SOLO: START button sends the vote (and triggers teleport server-side).
		actionButton.Text = "START"
		actionButton.BackgroundColor3 = Color3.fromRGB(200, 60, 60)
		actionButton.Active = true
	end

	refreshLevelButtonVisuals()
end

actionButton.MouseButton1Click:Connect(function()
	if not currentRoomInfo then
		return
	end
	if not myVotedLevel then
		-- Nudge the player to pick a level first
		subtitleLabel.Text = "⚠ Pilih level dulu!"
		return
	end

	if currentRoomInfo.roomMode == "SOLO" then
		-- ── FIX: VoteForLevel is fired HERE (once), not on level-button click.
		RE.VoteForLevel:FireServer(myVotedLevel)
		actionButton.Text = "STARTING..."
		actionButton.Active = false
	else
		-- COOP: ready up
		if isReady then
			return
		end
		isReady = true
		RE.PlayerReadyUp:FireServer()
		actionButton.Text = "WAITING FOR OTHERS..."
		actionButton.BackgroundColor3 = Color3.fromRGB(80, 80, 85)
		actionButton.Active = false
	end
end)

-- ============================================================
-- LISTENERS
-- ============================================================

RE.RoomStateUpdated.OnClientEvent:Connect(function(info)
	screenGui.Enabled = true
	updateUIFromRoomInfo(info)
end)

RE.VoteResultUpdated.OnClientEvent:Connect(function(voteResult)
	if not currentRoomInfo then
		return
	end

	clearPlayerListEntries()

	local summary = Instance.new("TextLabel")
	summary.BackgroundTransparency = 1
	summary.Size = UDim2.new(1, 0, 0, 20)
	summary.Font = Enum.Font.Gotham
	summary.TextSize = 13
	summary.TextColor3 = Color3.fromRGB(200, 200, 200)
	summary.TextXAlignment = Enum.TextXAlignment.Left
	summary.Text = string.format("Most voted: Level %d", voteResult.winningLevel)
	summary.Parent = playerListFrame
end)

RE.StartingGame.OnClientEvent:Connect(function(level, gameMode, countdown)
	-- Lock the UI so the player can't interfere during the countdown.
	actionButton.Active = false
	actionButton.Text = "STARTING..."
	countdownLabel.Visible = true

	task.spawn(function()
		local remaining = countdown

		while remaining > 0 do
			countdownLabel.Text = string.format("Starting Level %d in %d...", level, remaining)
			task.wait(1)
			remaining -= 1
		end

		countdownLabel.Text = "Teleporting..."
		task.wait(3)
		countdownLabel.Visible = false
		screenGui.Enabled = false
	end)
end)

RE.TeleportFailed.OnClientEvent:Connect(function(reason)
	-- Show a clear error message when teleport fails
	countdownLabel.Visible = false
	actionButton.Active = true
	actionButton.Text = "START"
	actionButton.BackgroundColor3 = Color3.fromRGB(200, 60, 60)
	subtitleLabel.Text = "⚠ Teleport failed: " .. tostring(reason)

	task.delay(8, function()
		if subtitleLabel.Text:find("Teleport failed") then
			subtitleLabel.Text = ""
		end
	end)
end)
