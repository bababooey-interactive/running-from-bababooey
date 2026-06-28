-- =============================================================
--  ReviveUI.client.luau
--  Path: game/src/StarterPlayer/StarterPlayerScripts/ReviveUI.client.luau
--
--  Tanggung jawab:
--  1. Saat LOCAL PLAYER downed → tampilkan countdown timer besar
--     di tengah layar ("Menunggu bantuan... 60s")
--  2. Saat player lain downed → tampilkan notif kecil di sisi layar
--  3. Saat player di-revive → hilangkan semua UI terkait player itu
--  4. Saat permanent dead → tampilkan "Kamu mati permanen"
-- =============================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RE_PlayerDowned = Remotes:WaitForChild("PlayerDowned")
local RE_PlayerRevived = Remotes:WaitForChild("PlayerRevived")

local Constants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Constants"))

-- ─────────────────────────────────────────────
--  BUILD GUI
-- ─────────────────────────────────────────────
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "ReviveGui"
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.IgnoreGuiInset = false
screenGui.DisplayOrder = 20 -- di atas HUD biasa
screenGui.Parent = PlayerGui

-- ── A. DOWNED OVERLAY (untuk local player) ───
local downedOverlay = Instance.new("Frame")
downedOverlay.Name = "DownedOverlay"
downedOverlay.Size = UDim2.new(1, 0, 1, 0)
downedOverlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
downedOverlay.BackgroundTransparency = 0.45
downedOverlay.BorderSizePixel = 0
downedOverlay.ZIndex = 21
downedOverlay.Visible = false
downedOverlay.Parent = screenGui

-- Vignette merah saat downed
local vigRed = Instance.new("Frame")
vigRed.Size = UDim2.new(1, 0, 1, 0)
vigRed.BackgroundColor3 = Color3.fromRGB(180, 0, 0)
vigRed.BackgroundTransparency = 0.65
vigRed.BorderSizePixel = 0
vigRed.ZIndex = 21
vigRed.Parent = downedOverlay

local vigGrad = Instance.new("UIGradient")
vigGrad.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0),
	NumberSequenceKeypoint.new(0.4, 0.8),
	NumberSequenceKeypoint.new(1, 1),
})
vigGrad.Rotation = 0
vigGrad.Parent = vigRed

-- Teks utama "BUTUH BANTUAN"
local downedTitle = Instance.new("TextLabel")
downedTitle.Name = "DownedTitle"
downedTitle.AnchorPoint = Vector2.new(0.5, 0.5)
downedTitle.Position = UDim2.new(0.5, 0, 0.40, 0)
downedTitle.Size = UDim2.new(0, 400, 0, 60)
downedTitle.BackgroundTransparency = 1
downedTitle.TextColor3 = Color3.fromRGB(255, 80, 80)
downedTitle.TextSize = 32
downedTitle.Font = Enum.Font.GothamBold
downedTitle.Text = "💀  BUTUH BANTUAN"
downedTitle.TextScaled = false
downedTitle.ZIndex = 22
downedTitle.Parent = downedOverlay

-- Countdown timer
local downedTimer = Instance.new("TextLabel")
downedTimer.Name = "DownedTimer"
downedTimer.AnchorPoint = Vector2.new(0.5, 0.5)
downedTimer.Position = UDim2.new(0.5, 0, 0.50, 0)
downedTimer.Size = UDim2.new(0, 300, 0, 48)
downedTimer.BackgroundTransparency = 1
downedTimer.TextColor3 = Color3.fromRGB(255, 200, 200)
downedTimer.TextSize = 26
downedTimer.Font = Enum.Font.GothamBold
downedTimer.Text = "Menunggu bantuan... 60s"
downedTimer.ZIndex = 22
downedTimer.Parent = downedOverlay

-- Progress bar revive (muncul saat seseorang sedang me-revive kita)
-- Diisi oleh animasi lokal — tidak ada remote khusus, cukup visual
local reviveBarBg = Instance.new("Frame")
reviveBarBg.Name = "ReviveBarBg"
reviveBarBg.AnchorPoint = Vector2.new(0.5, 0.5)
reviveBarBg.Position = UDim2.new(0.5, 0, 0.60, 0)
reviveBarBg.Size = UDim2.new(0, 280, 0, 18)
reviveBarBg.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
reviveBarBg.BorderSizePixel = 0
reviveBarBg.ZIndex = 22
reviveBarBg.Visible = false
reviveBarBg.Parent = downedOverlay

Instance.new("UICorner", reviveBarBg).CornerRadius = UDim.new(0, 5)

local reviveBarFill = Instance.new("Frame")
reviveBarFill.Name = "Fill"
reviveBarFill.Size = UDim2.new(0, 0, 1, 0)
reviveBarFill.BackgroundColor3 = Color3.fromRGB(100, 200, 255)
reviveBarFill.BorderSizePixel = 0
reviveBarFill.ZIndex = 23
reviveBarFill.Parent = reviveBarBg

Instance.new("UICorner", reviveBarFill).CornerRadius = UDim.new(0, 5)

local reviveBarLabel = Instance.new("TextLabel")
reviveBarLabel.Size = UDim2.new(1, 0, 1, 0)
reviveBarLabel.BackgroundTransparency = 1
reviveBarLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
reviveBarLabel.TextSize = 12
reviveBarLabel.Font = Enum.Font.GothamBold
reviveBarLabel.Text = "Sedang diselamatkan..."
reviveBarLabel.ZIndex = 24
reviveBarLabel.Parent = reviveBarBg

-- ── B. NOTIF PLAYER LAIN DOWNED (sisi kanan) ─
local notifContainer = Instance.new("Frame")
notifContainer.Name = "NotifContainer"
notifContainer.AnchorPoint = Vector2.new(1, 0)
notifContainer.Position = UDim2.new(1, -12, 0, 110)
notifContainer.Size = UDim2.new(0, 240, 0, 200)
notifContainer.BackgroundTransparency = 1
notifContainer.ZIndex = 21
notifContainer.Parent = screenGui

local notifLayout = Instance.new("UIListLayout")
notifLayout.FillDirection = Enum.FillDirection.Vertical
notifLayout.Padding = UDim.new(0, 6)
notifLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
notifLayout.SortOrder = Enum.SortOrder.LayoutOrder
notifLayout.Parent = notifContainer

-- ─────────────────────────────────────────────
--  STATE
-- ─────────────────────────────────────────────
-- notifFrames[playerName] = Frame
local notifFrames: { [string]: Frame } = {}
local isLocalDowned = false

-- ─────────────────────────────────────────────
--  NOTIF: player lain downed
-- ─────────────────────────────────────────────
local function createOrUpdateNotif(playerName: string, timeLeft: number, permanent: boolean)
	local existing = notifFrames[playerName]

	if permanent then
		-- Hapus notif kalau permanent dead
		if existing then
			existing:Destroy()
			notifFrames[playerName] = nil
		end
		return
	end

	if not existing then
		local frame = Instance.new("Frame")
		frame.Name = "Notif_" .. playerName
		frame.Size = UDim2.new(1, 0, 0, 44)
		frame.BackgroundColor3 = Color3.fromRGB(25, 20, 30)
		frame.BackgroundTransparency = 0.15
		frame.BorderSizePixel = 0
		frame.ZIndex = 22
		frame.Parent = notifContainer

		Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 8)

		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.fromRGB(200, 60, 60)
		stroke.Thickness = 1.5
		stroke.Parent = frame

		local lbl = Instance.new("TextLabel")
		lbl.Name = "Label"
		lbl.Size = UDim2.new(1, -8, 1, 0)
		lbl.Position = UDim2.new(0, 8, 0, 0)
		lbl.BackgroundTransparency = 1
		lbl.TextColor3 = Color3.fromRGB(255, 180, 180)
		lbl.TextSize = 13
		lbl.Font = Enum.Font.GothamBold
		lbl.TextXAlignment = Enum.TextXAlignment.Left
		lbl.RichText = true
		lbl.ZIndex = 23
		lbl.Parent = frame

		notifFrames[playerName] = frame
		existing = frame
	end

	-- Update teks
	local label = existing:FindFirstChild("Label")
	if label then
		local color = timeLeft > 20 and "#ffaaaa" or "#ff4444"
		label.Text = string.format("💀 <b>%s</b>\n<font color='%s'>%.0fs tersisa</font>", playerName, color, timeLeft)
	end
end

local function removeNotif(playerName: string)
	local frame = notifFrames[playerName]
	if frame then
		-- Fade out
		TweenService:Create(frame, TweenInfo.new(0.3), {
			BackgroundTransparency = 1,
		}):Play()
		local lbl = frame:FindFirstChild("Label")
		if lbl then
			TweenService:Create(lbl, TweenInfo.new(0.3), { TextTransparency = 1 }):Play()
		end
		task.delay(0.35, function()
			if frame.Parent then
				frame:Destroy()
			end
		end)
		notifFrames[playerName] = nil
	end
end

-- ─────────────────────────────────────────────
--  LOCAL PLAYER DOWNED UI
-- ─────────────────────────────────────────────
local function showDownedUI(timeLeft: number)
	isLocalDowned = true
	downedOverlay.Visible = true
	downedTimer.Text = string.format("Menunggu bantuan... %.0fs", timeLeft)
end

local function updateDownedTimer(timeLeft: number)
	if not isLocalDowned then
		return
	end
	downedTimer.Text = string.format("Menunggu bantuan... %.0fs", timeLeft)

	-- Makin merah saat mendekati 0
	local ratio = math.clamp(timeLeft / (Constants.REVIVE_TIMER or 60), 0, 1)
	downedTimer.TextColor3 = Color3.new(1, ratio * 0.4, ratio * 0.4)
end

local function hideDownedUI()
	isLocalDowned = false
	TweenService:Create(downedOverlay, TweenInfo.new(0.4), {
		BackgroundTransparency = 1,
	}):Play()
	task.delay(0.45, function()
		downedOverlay.Visible = false
		downedOverlay.BackgroundTransparency = 0.45
		reviveBarBg.Visible = false
		reviveBarFill.Size = UDim2.new(0, 0, 1, 0)
	end)
end

local function showPermanentDeathUI()
	isLocalDowned = false
	downedTitle.Text = "💀  KAMU MATI"
	downedTitle.TextColor3 = Color3.fromRGB(255, 50, 50)
	downedTimer.Text = "Tidak ada yang menolongmu..."
	downedTimer.TextColor3 = Color3.fromRGB(200, 150, 150)
	-- Overlay tetap tampil (hilang hanya saat game over screen muncul)
end

-- ─────────────────────────────────────────────
--  REMOTE LISTENERS
-- ─────────────────────────────────────────────
RE_PlayerDowned.OnClientEvent:Connect(function(data)
	local playerName = data.playerName
	local timeLeft = data.timeLeft or 0
	local permanent = data.permanent or false

	if playerName == LocalPlayer.Name then
		-- Local player
		if permanent then
			showPermanentDeathUI()
		elseif isLocalDowned then
			updateDownedTimer(timeLeft)
		else
			showDownedUI(timeLeft)
		end
	else
		-- Player lain
		if permanent then
			createOrUpdateNotif(playerName, 0, true)
		else
			createOrUpdateNotif(playerName, timeLeft, false)
		end
	end
end)

RE_PlayerRevived.OnClientEvent:Connect(function(data)
	local playerName = data.playerName
	local rescuerName = data.rescuerName or "seseorang"

	if playerName == LocalPlayer.Name then
		-- Kita yang di-revive
		hideDownedUI()
	else
		-- Player lain di-revive → hapus notif
		removeNotif(playerName)
	end

	-- Notif singkat "X diselamatkan oleh Y"
	local reviveNotif = Instance.new("ScreenGui")
	reviveNotif.Name = "ReviveNotif"
	reviveNotif.ResetOnSpawn = false
	reviveNotif.DisplayOrder = 25
	reviveNotif.Parent = PlayerGui

	local notifFrame = Instance.new("Frame")
	notifFrame.AnchorPoint = Vector2.new(0.5, 0)
	notifFrame.Position = UDim2.new(0.5, 0, 0.08, 0)
	notifFrame.Size = UDim2.new(0, 320, 0, 44)
	notifFrame.BackgroundColor3 = Color3.fromRGB(30, 60, 40)
	notifFrame.BackgroundTransparency = 0.1
	notifFrame.BorderSizePixel = 0
	notifFrame.Parent = reviveNotif

	Instance.new("UICorner", notifFrame).CornerRadius = UDim.new(0, 10)

	local notifStroke = Instance.new("UIStroke")
	notifStroke.Color = Color3.fromRGB(80, 200, 100)
	notifStroke.Thickness = 1.5
	notifStroke.Parent = notifFrame

	local notifLabel = Instance.new("TextLabel")
	notifLabel.Size = UDim2.new(1, -16, 1, 0)
	notifLabel.Position = UDim2.new(0, 8, 0, 0)
	notifLabel.BackgroundTransparency = 1
	notifLabel.TextColor3 = Color3.fromRGB(150, 255, 150)
	notifLabel.TextSize = 14
	notifLabel.Font = Enum.Font.GothamBold
	notifLabel.Text = string.format("✅ %s diselamatkan oleh %s!", playerName, rescuerName)
	notifLabel.TextXAlignment = Enum.TextXAlignment.Center
	notifLabel.Parent = notifFrame

	-- Auto destroy setelah 3 detik
	task.delay(3, function()
		if reviveNotif.Parent then
			TweenService:Create(notifFrame, TweenInfo.new(0.4), {
				BackgroundTransparency = 1,
			}):Play()
			TweenService:Create(notifLabel, TweenInfo.new(0.4), {
				TextTransparency = 1,
			}):Play()
			task.delay(0.45, function()
				reviveNotif:Destroy()
			end)
		end
	end)
end)

-- ─────────────────────────────────────────────
--  CLEANUP saat respawn (script di StarterPlayerScripts = tidak re-run)
-- ─────────────────────────────────────────────
LocalPlayer.CharacterAdded:Connect(function()
	-- Saat karakter baru (setelah di-revive), pastikan UI bersih
	if isLocalDowned then
		hideDownedUI()
	end
end)

print("[ReviveUI] Client initialized.")
