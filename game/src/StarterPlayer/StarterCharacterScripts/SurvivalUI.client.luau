-- =============================================================
--  SurvivalUI.client.luau  (v2 — Redesign sesuai sketsa)
--  Path: game/src/StarterPlayer/StarterCharacterScripts/SurvivalUI.client.luau
--
--  Layout:
--  ┌─[Roblox]──────────────────────────────[Task Counter]─────┐
--  │                                        [Rules Button]     │
--  │                                                     [←]  │
--  │              [Rules Panel — opsional terbuka]             │
--  │                                                           │
--  │  [Hunger ████░░]                                         │
--  │  [Dark   ████░░]                                         │
--  └───────────────────────────────────────────────────────────┘
--
--  Menggantikan SurvivalUI.client.luau lama DAN menyerap fungsi
--  RuleDisplay.client.luau — cukup satu script HUD terpadu.
--  RuleDisplay.client.luau bisa dihapus atau dibiarkan (tidak
--  konflik karena script ini pakai ScreenGui nama berbeda,
--  "GameHUD" vs "RulesDisplayGui" lama).
-- =============================================================

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")

local Constants = require(ReplicatedStorage.Shared.Constants)

local Remotes         = ReplicatedStorage:WaitForChild("Remotes")
local RE_HungerUpdate = Remotes:WaitForChild("HungerUpdate")
local RE_DarkUpdate   = Remotes:WaitForChild("DarkUpdate")
local RE_TaskProgress = Remotes:WaitForChild("TaskProgress")
local RE_SyncState    = Remotes:WaitForChild("SyncState")
local RE_GameWin      = Remotes:WaitForChild("GameWin")
local RE_PlayerDied   = Remotes:WaitForChild("PlayerDied")
local RE_RulesActivated = Remotes:WaitForChild("RulesActivated")

local LocalPlayer = Players.LocalPlayer
local PlayerGui   = LocalPlayer:WaitForChild("PlayerGui")

-- ─────────────────────────────────────────────
--  WARNA & STYLE (horror dungeon palette)
-- ─────────────────────────────────────────────
local C = {
	BG_DARK     = Color3.fromRGB(14, 14, 18),
	BG_MID      = Color3.fromRGB(22, 22, 28),
	BG_PANEL    = Color3.fromRGB(18, 18, 24),
	ACCENT_RED  = Color3.fromRGB(180, 45, 45),
	ACCENT_ORG  = Color3.fromRGB(220, 120, 40),
	TEXT_WHITE  = Color3.fromRGB(235, 235, 235),
	TEXT_DIM    = Color3.fromRGB(150, 150, 160),
	TEXT_WARN   = Color3.fromRGB(255, 200, 80),
	MONSTER_CLR = Color3.fromRGB(220, 80, 60),
	PLAYER_CLR  = Color3.fromRGB(90, 160, 255),
	BAR_HUNGER  = Color3.fromRGB(200, 140, 40),
	BAR_DARK    = Color3.fromRGB(100, 60, 200),
	BAR_BG      = Color3.fromRGB(35, 35, 42),
	BORDER      = Color3.fromRGB(60, 60, 75),
	WIN_GREEN   = Color3.fromRGB(80, 210, 120),
	DEATH_RED   = Color3.fromRGB(220, 60, 60),
}

-- ─────────────────────────────────────────────
--  BUILD GUI
-- ─────────────────────────────────────────────
local function buildGui()
	if PlayerGui:FindFirstChild("GameHUD") then
		PlayerGui:FindFirstChild("GameHUD"):Destroy()
	end

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name           = "GameHUD"
	screenGui.ResetOnSpawn   = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.IgnoreGuiInset = false
	screenGui.Parent         = PlayerGui

	-- ═══════════════════════════════════════════
	--  A. KANAN ATAS — Task Counter + Rules Button
	-- ═══════════════════════════════════════════

	local topRight = Instance.new("Frame")
	topRight.Name                   = "TopRight"
	topRight.AnchorPoint             = Vector2.new(1, 0)
	topRight.Position                = UDim2.new(1, -12, 0, 12)
	topRight.Size                    = UDim2.new(0, 280, 0, 88)
	topRight.BackgroundTransparency  = 1
	topRight.Parent                  = screenGui

	local topRightLayout = Instance.new("UIListLayout")
	topRightLayout.FillDirection     = Enum.FillDirection.Vertical
	topRightLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	topRightLayout.Padding           = UDim.new(0, 6)
	topRightLayout.SortOrder         = Enum.SortOrder.LayoutOrder
	topRightLayout.Parent            = topRight

	-- ── Task Counter box ──────────────────────
	local taskBox = Instance.new("Frame")
	taskBox.Name                  = "TaskBox"
	taskBox.Size                  = UDim2.new(1, 0, 0, 44)
	taskBox.BackgroundColor3      = C.BG_DARK
	taskBox.BackgroundTransparency = 0.25
	taskBox.BorderSizePixel        = 0
	taskBox.LayoutOrder            = 1
	taskBox.Parent                 = topRight

	local taskBoxCorner = Instance.new("UICorner")
	taskBoxCorner.CornerRadius = UDim.new(0, 8)
	taskBoxCorner.Parent       = taskBox

	local taskBoxStroke = Instance.new("UIStroke")
	taskBoxStroke.Color     = C.BORDER
	taskBoxStroke.Thickness  = 1
	taskBoxStroke.Parent     = taskBox

	local taskPad = Instance.new("UIPadding")
	taskPad.PaddingLeft   = UDim.new(0, 12)
	taskPad.PaddingRight  = UDim.new(0, 12)
	taskPad.PaddingTop    = UDim.new(0, 6)
	taskPad.PaddingBottom = UDim.new(0, 6)
	taskPad.Parent        = taskBox

	local taskLabel = Instance.new("TextLabel")
	taskLabel.Name                  = "TaskLabel"
	taskLabel.Size                  = UDim2.new(1, 0, 1, 0)
	taskLabel.BackgroundTransparency = 1
	taskLabel.TextColor3             = C.TEXT_WHITE
	taskLabel.TextSize               = 13
	taskLabel.Font                   = Enum.Font.GothamBold
	taskLabel.TextXAlignment         = Enum.TextXAlignment.Right
	taskLabel.TextYAlignment         = Enum.TextYAlignment.Center
	taskLabel.RichText               = true
	taskLabel.Text                   = "🪨 <font color='#aaaaaa'>0/0</font>  🔧 <font color='#aaaaaa'>0/0</font>  🔋 <font color='#aaaaaa'>0/0</font>"
	taskLabel.Parent                 = taskBox

	-- ── Rules toggle button ───────────────────
	local rulesBtn = Instance.new("TextButton")
	rulesBtn.Name                  = "RulesBtn"
	rulesBtn.Size                  = UDim2.new(1, 0, 0, 32)
	rulesBtn.BackgroundColor3      = C.BG_MID
	rulesBtn.BackgroundTransparency = 0.2
	rulesBtn.BorderSizePixel        = 0
	rulesBtn.Font                   = Enum.Font.GothamBold
	rulesBtn.TextSize               = 12
	rulesBtn.TextColor3             = C.TEXT_DIM
	rulesBtn.Text                   = "▼  RULES AKTIF"
	rulesBtn.LayoutOrder            = 2
	rulesBtn.AutoButtonColor        = false
	rulesBtn.Parent                 = topRight

	local rulesBtnCorner = Instance.new("UICorner")
	rulesBtnCorner.CornerRadius = UDim.new(0, 8)
	rulesBtnCorner.Parent       = rulesBtn

	local rulesBtnStroke = Instance.new("UIStroke")
	rulesBtnStroke.Color     = C.BORDER
	rulesBtnStroke.Thickness  = 1
	rulesBtnStroke.Parent     = rulesBtn

	-- ═══════════════════════════════════════════
	--  B. PANEL RULES (tengah, slide in/out)
	-- ═══════════════════════════════════════════

	local rulesPanel = Instance.new("Frame")
	rulesPanel.Name                   = "RulesPanel"
	rulesPanel.AnchorPoint             = Vector2.new(0.5, 0.5)
	rulesPanel.Position                = UDim2.new(0.5, 0, 0.5, 0)
	rulesPanel.Size                    = UDim2.new(0, 480, 0, 300)
	rulesPanel.BackgroundColor3        = C.BG_PANEL
	rulesPanel.BackgroundTransparency  = 0.08
	rulesPanel.BorderSizePixel         = 0
	rulesPanel.Visible                 = false
	rulesPanel.ZIndex                  = 15
	rulesPanel.Parent                  = screenGui

	local rulesPanelCorner = Instance.new("UICorner")
	rulesPanelCorner.CornerRadius = UDim.new(0, 12)
	rulesPanelCorner.Parent       = rulesPanel

	local rulesPanelStroke = Instance.new("UIStroke")
	rulesPanelStroke.Color     = C.ACCENT_RED
	rulesPanelStroke.Thickness  = 1.5
	rulesPanelStroke.Parent     = rulesPanel

	-- Header panel
	local panelHeader = Instance.new("Frame")
	panelHeader.Name                  = "PanelHeader"
	panelHeader.Size                  = UDim2.new(1, 0, 0, 40)
	panelHeader.BackgroundColor3      = C.ACCENT_RED
	panelHeader.BackgroundTransparency = 0.4
	panelHeader.BorderSizePixel        = 0
	panelHeader.ZIndex                 = 16
	panelHeader.Parent                 = rulesPanel

	local panelHeaderCorner = Instance.new("UICorner")
	panelHeaderCorner.CornerRadius = UDim.new(0, 12)
	panelHeaderCorner.Parent       = panelHeader

	-- Fix corner bawah header (rounded semua sisi, block bawah)
	local headerFix = Instance.new("Frame")
	headerFix.Size                 = UDim2.new(1, 0, 0.5, 0)
	headerFix.Position             = UDim2.new(0, 0, 0.5, 0)
	headerFix.BackgroundColor3     = C.ACCENT_RED
	headerFix.BackgroundTransparency = 0.4
	headerFix.BorderSizePixel      = 0
	headerFix.ZIndex               = 16
	headerFix.Parent               = panelHeader

	local panelTitle = Instance.new("TextLabel")
	panelTitle.Name                  = "PanelTitle"
	panelTitle.Size                  = UDim2.new(1, -48, 1, 0)
	panelTitle.Position              = UDim2.new(0, 16, 0, 0)
	panelTitle.BackgroundTransparency = 1
	panelTitle.TextColor3             = C.TEXT_WHITE
	panelTitle.TextSize               = 15
	panelTitle.Font                   = Enum.Font.GothamBold
	panelTitle.TextXAlignment         = Enum.TextXAlignment.Left
	panelTitle.TextYAlignment         = Enum.TextYAlignment.Center
	panelTitle.Text                   = "⚠  RULES AKTIF SESI INI"
	panelTitle.ZIndex                 = 17
	panelTitle.Parent                 = panelHeader

	-- Close button panel (panah kanan sesuai sketsa)
	local panelClose = Instance.new("TextButton")
	panelClose.Name                  = "PanelClose"
	panelClose.AnchorPoint            = Vector2.new(1, 0.5)
	panelClose.Position               = UDim2.new(1, -10, 0.5, 0)
	panelClose.Size                   = UDim2.new(0, 28, 0, 28)
	panelClose.BackgroundColor3       = C.BG_DARK
	panelClose.BackgroundTransparency = 0.3
	panelClose.BorderSizePixel        = 0
	panelClose.Font                   = Enum.Font.GothamBold
	panelClose.TextSize               = 16
	panelClose.TextColor3             = C.TEXT_WHITE
	panelClose.Text                   = "→"
	panelClose.ZIndex                 = 18
	panelClose.AutoButtonColor        = false
	panelClose.Parent                 = panelHeader

	local panelCloseCorner = Instance.new("UICorner")
	panelCloseCorner.CornerRadius = UDim.new(1, 0)
	panelCloseCorner.Parent       = panelClose

	-- Body panel: 2 kolom (Monster | Player)
	local panelBody = Instance.new("Frame")
	panelBody.Name                  = "PanelBody"
	panelBody.Position              = UDim2.new(0, 0, 0, 40)
	panelBody.Size                  = UDim2.new(1, 0, 1, -40)
	panelBody.BackgroundTransparency = 1
	panelBody.ZIndex                = 16
	panelBody.Parent                = rulesPanel

	local bodyPad = Instance.new("UIPadding")
	bodyPad.PaddingLeft   = UDim.new(0, 16)
	bodyPad.PaddingRight  = UDim.new(0, 16)
	bodyPad.PaddingTop    = UDim.new(0, 12)
	bodyPad.PaddingBottom = UDim.new(0, 12)
	bodyPad.Parent        = panelBody

	-- Divider tengah
	local divider = Instance.new("Frame")
	divider.Name                 = "Divider"
	divider.AnchorPoint           = Vector2.new(0.5, 0)
	divider.Position              = UDim2.new(0.5, 0, 0, 0)
	divider.Size                  = UDim2.new(0, 1, 1, -16)
	divider.BackgroundColor3      = C.BORDER
	divider.BorderSizePixel        = 0
	divider.ZIndex                = 16
	divider.Parent                = panelBody

	-- Kolom Monster (kiri)
	local monsterCol = Instance.new("Frame")
	monsterCol.Name                  = "MonsterCol"
	monsterCol.Position              = UDim2.new(0, 0, 0, 0)
	monsterCol.Size                  = UDim2.new(0.5, -8, 1, 0)
	monsterCol.BackgroundTransparency = 1
	monsterCol.ZIndex                = 16
	monsterCol.Parent                = panelBody

	local monsterColLayout = Instance.new("UIListLayout")
	monsterColLayout.Padding   = UDim.new(0, 4)
	monsterColLayout.SortOrder = Enum.SortOrder.LayoutOrder
	monsterColLayout.Parent    = monsterCol

	local monsterHeader = Instance.new("TextLabel")
	monsterHeader.Name                  = "Header"
	monsterHeader.Size                  = UDim2.new(1, 0, 0, 22)
	monsterHeader.BackgroundTransparency = 1
	monsterHeader.TextColor3             = C.MONSTER_CLR
	monsterHeader.TextSize               = 13
	monsterHeader.Font                   = Enum.Font.GothamBold
	monsterHeader.TextXAlignment         = Enum.TextXAlignment.Left
	monsterHeader.Text                   = "MONSTER"
	monsterHeader.LayoutOrder            = 0
	monsterHeader.ZIndex                 = 17
	monsterHeader.Parent                 = monsterCol

	-- Kolom Player (kanan)
	local playerCol = Instance.new("Frame")
	playerCol.Name                  = "PlayerCol"
	playerCol.Position              = UDim2.new(0.5, 8, 0, 0)
	playerCol.Size                  = UDim2.new(0.5, -8, 1, 0)
	playerCol.BackgroundTransparency = 1
	playerCol.ZIndex                = 16
	playerCol.Parent                = panelBody

	local playerColLayout = Instance.new("UIListLayout")
	playerColLayout.Padding   = UDim.new(0, 4)
	playerColLayout.SortOrder = Enum.SortOrder.LayoutOrder
	playerColLayout.Parent    = playerCol

	local playerHeader = Instance.new("TextLabel")
	playerHeader.Name                  = "Header"
	playerHeader.Size                  = UDim2.new(1, 0, 0, 22)
	playerHeader.BackgroundTransparency = 1
	playerHeader.TextColor3             = C.PLAYER_CLR
	playerHeader.TextSize               = 13
	playerHeader.Font                   = Enum.Font.GothamBold
	playerHeader.TextXAlignment         = Enum.TextXAlignment.Left
	playerHeader.Text                   = "PLAYER"
	playerHeader.LayoutOrder            = 0
	playerHeader.ZIndex                 = 17
	playerHeader.Parent                 = playerCol

	-- ═══════════════════════════════════════════
	--  C. KIRI BAWAH — Hunger + Darkness bars
	-- ═══════════════════════════════════════════

	local barsFrame = Instance.new("Frame")
	barsFrame.Name                   = "BarsFrame"
	barsFrame.AnchorPoint             = Vector2.new(0, 1)
	barsFrame.Position                = UDim2.new(0, 12, 1, -12)
	barsFrame.Size                    = UDim2.new(0, 200, 0, 56)
	barsFrame.BackgroundTransparency  = 1
	barsFrame.Parent                  = screenGui

	local barsLayout = Instance.new("UIListLayout")
	barsLayout.FillDirection     = Enum.FillDirection.Vertical
	barsLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	barsLayout.Padding           = UDim.new(0, 5)
	barsLayout.SortOrder         = Enum.SortOrder.LayoutOrder
	barsLayout.Parent            = barsFrame

	-- Fungsi helper buat satu bar row
	local function makeBar(icon, barColor, layoutOrder, name)
		local row = Instance.new("Frame")
		row.Name                  = name
		row.Size                  = UDim2.new(1, 0, 0, 22)
		row.BackgroundTransparency = 1
		row.LayoutOrder            = layoutOrder
		row.Visible                = false  -- hidden sampai rule aktif
		row.Parent                 = barsFrame

		local iconLabel = Instance.new("TextLabel")
		iconLabel.Name                  = "Icon"
		iconLabel.Size                  = UDim2.new(0, 20, 1, 0)
		iconLabel.BackgroundTransparency = 1
		iconLabel.TextColor3             = barColor
		iconLabel.TextSize               = 14
		iconLabel.Font                   = Enum.Font.GothamBold
		iconLabel.Text                   = icon
		iconLabel.TextYAlignment         = Enum.TextYAlignment.Center
		iconLabel.Parent                 = row

		local trackBg = Instance.new("Frame")
		trackBg.Name                 = "Track"
		trackBg.Position             = UDim2.new(0, 24, 0.5, -7)
		trackBg.Size                 = UDim2.new(1, -24, 0, 14)
		trackBg.BackgroundColor3     = C.BAR_BG
		trackBg.BorderSizePixel      = 0
		trackBg.Parent               = row

		local trackCorner = Instance.new("UICorner")
		trackCorner.CornerRadius = UDim.new(0, 4)
		trackCorner.Parent       = trackBg

		local fill = Instance.new("Frame")
		fill.Name                = "Fill"
		fill.Size                = UDim2.new(1, 0, 1, 0)
		fill.BackgroundColor3    = barColor
		fill.BorderSizePixel     = 0
		fill.Parent              = trackBg

		local fillCorner = Instance.new("UICorner")
		fillCorner.CornerRadius = UDim.new(0, 4)
		fillCorner.Parent       = fill

		-- Teks overlay di dalam bar (nilai %)
		local barText = Instance.new("TextLabel")
		barText.Name                  = "BarText"
		barText.Size                  = UDim2.new(1, 0, 1, 0)
		barText.BackgroundTransparency = 1
		barText.TextColor3             = C.TEXT_WHITE
		barText.TextSize               = 10
		barText.Font                   = Enum.Font.GothamBold
		barText.Text                   = ""
		barText.ZIndex                 = 2
		barText.Parent                 = trackBg

		return row, fill, barText
	end

	local hungerRow, hungerFill, hungerText = makeBar("🍖", C.BAR_HUNGER, 1, "HungerRow")
	local darkRow,   darkFill,   darkText   = makeBar("🌑", C.BAR_DARK,   2, "DarkRow")

	-- ═══════════════════════════════════════════
	--  D. WIN / DEATH OVERLAY
	-- ═══════════════════════════════════════════

	local msgOverlay = Instance.new("Frame")
	msgOverlay.Name                   = "MsgOverlay"
	msgOverlay.Size                   = UDim2.new(1, 0, 1, 0)
	msgOverlay.BackgroundColor3       = C.BG_DARK
	msgOverlay.BackgroundTransparency = 1
	msgOverlay.BorderSizePixel        = 0
	msgOverlay.ZIndex                 = 25
	msgOverlay.Visible                = false
	msgOverlay.Parent                 = screenGui

	local msgLabel = Instance.new("TextLabel")
	msgLabel.Name                   = "MsgLabel"
	msgLabel.AnchorPoint             = Vector2.new(0.5, 0.5)
	msgLabel.Position                = UDim2.new(0.5, 0, 0.45, 0)
	msgLabel.Size                    = UDim2.new(0.55, 0, 0, 80)
	msgLabel.BackgroundTransparency  = 1
	msgLabel.TextColor3              = C.TEXT_WHITE
	msgLabel.TextSize                = 34
	msgLabel.Font                    = Enum.Font.GothamBold
	msgLabel.TextScaled              = true
	msgLabel.RichText                = true
	msgLabel.ZIndex                  = 26
	msgLabel.Parent                  = msgOverlay

	return {
		-- Task
		taskLabel    = taskLabel,
		-- Rules panel
		rulesBtn     = rulesBtn,
		rulesPanel   = rulesPanel,
		panelClose   = panelClose,
		monsterCol   = monsterCol,
		playerCol    = playerCol,
		-- Bars
		hungerRow    = hungerRow,
		hungerFill   = hungerFill,
		hungerText   = hungerText,
		darkRow      = darkRow,
		darkFill     = darkFill,
		darkText     = darkText,
		-- Overlay
		msgOverlay   = msgOverlay,
		msgLabel     = msgLabel,
	}
end

-- ─────────────────────────────────────────────
--  RULES DISPLAY HELPERS
-- ─────────────────────────────────────────────

local RuleNames = {
	[Constants.Rules.MONSTER_HEAR]      = { text = "Dapat Mendengar",         group = "monster" },
	[Constants.Rules.MONSTER_SMELL]     = { text = "Dapat Mencium Bau",       group = "monster" },
	[Constants.Rules.MONSTER_SEE]       = { text = "Dapat Melihat di Cahaya", group = "monster" },
	[Constants.Rules.MONSTER_FAST]      = { text = "Lebih Cepat",             group = "monster" },
	[Constants.Rules.MONSTER_REACH]     = { text = "Jangkauan Lebih Jauh",    group = "monster" },
	[Constants.Rules.MONSTER_DUPLICATE] = { text = "Menduplikasi Diri",       group = "monster" },
	[Constants.Rules.PLAYER_HUNGER]     = { text = "Lapar Seiring Waktu",     group = "player"  },
	[Constants.Rules.PLAYER_DARK_TIMER] = { text = "Takut Kegelapan",         group = "player"  },
}

local function clearColEntries(col)
	for _, child in ipairs(col:GetChildren()) do
		if child:IsA("TextLabel") and child.Name == "RuleEntry" then
			child:Destroy()
		end
	end
end

local function addColEntry(col, order, text, color)
	local entry = Instance.new("TextLabel")
	entry.Name                   = "RuleEntry"
	entry.Size                   = UDim2.new(1, 0, 0, 20)
	entry.BackgroundTransparency  = 1
	entry.TextColor3              = color
	entry.TextSize                = 13
	entry.Font                    = Enum.Font.Gotham
	entry.TextXAlignment          = Enum.TextXAlignment.Left
	entry.Text                    = "• " .. text
	entry.LayoutOrder             = order
	entry.ZIndex                  = 17
	entry.Parent                  = col
end

local function populateRulesPanel(ui, ruleIds)
	clearColEntries(ui.monsterCol)
	clearColEntries(ui.playerCol)

	local monsterOrder, playerOrder = 1, 1
	local hasMonster, hasPlayer = false, false

	-- Hitung duplikat MONSTER_DUPLICATE untuk label "(x2)" dst.
	local dupCount = 0
	for _, id in ipairs(ruleIds) do
		if id == Constants.Rules.MONSTER_DUPLICATE then
			dupCount += 1
		end
	end

	local seenDup = false

	for _, id in ipairs(ruleIds) do
		local info = RuleNames[id]
		if not info then continue end

		if id == Constants.Rules.MONSTER_DUPLICATE then
			if seenDup then continue end  -- label hanya sekali, sudah ada "(x2/x4)"
			seenDup = true
			local label = info.text
			if dupCount >= 2 then
				label = label .. string.format(" (x%d)", 2 ^ dupCount)
			end
			addColEntry(ui.monsterCol, monsterOrder, label, C.MONSTER_CLR)
			monsterOrder += 1
			hasMonster = true
		elseif info.group == "monster" then
			addColEntry(ui.monsterCol, monsterOrder, info.text, C.TEXT_WHITE)
			monsterOrder += 1
			hasMonster = true
		else
			addColEntry(ui.playerCol, playerOrder, info.text, C.TEXT_WHITE)
			playerOrder += 1
			hasPlayer = true
		end
	end

	if not hasMonster then
		addColEntry(ui.monsterCol, 1, "— Tidak ada buff tambahan", C.TEXT_DIM)
	end
	if not hasPlayer then
		addColEntry(ui.playerCol, 1, "— Tidak ada debuff tambahan", C.TEXT_DIM)
	end
end

-- ─────────────────────────────────────────────
--  UPDATE HELPERS
-- ─────────────────────────────────────────────
local function updateTaskLabel(ui, data)
	local function fmt(icon, done, total)
		local color = (done >= total and total > 0) and "#50d080" or "#cccccc"
		return string.format("%s <font color='%s'>%d/%d</font>", icon, color, done, total)
	end
	ui.taskLabel.Text =
		fmt("🪨", data.coal_done,  data.coal_total)  .. "     " ..
		fmt("🔧", data.lever_done, data.lever_total)
end

local function updateHunger(ui, hunger)
	ui.hungerRow.Visible = true
	local ratio = math.clamp(hunger / Constants.HUNGER_MAX, 0, 1)

	TweenService:Create(ui.hungerFill, TweenInfo.new(0.3), {
		Size = UDim2.new(ratio, 0, 1, 0)
	}):Play()

	-- Warna: hijau → kuning → merah sesuai level
	local r = math.clamp(2 * (1 - ratio), 0, 1)
	local g = math.clamp(2 * ratio, 0, 1)
	ui.hungerFill.BackgroundColor3 = Color3.new(r, g, 0)
	ui.hungerText.Text = string.format("%d%%", math.floor(hunger))
end

local function updateDark(ui, timer, inDark)
	ui.darkRow.Visible = true
	local ratio = math.clamp(timer / Constants.DARK_TIMER_MAX, 0, 1)

	TweenService:Create(ui.darkFill, TweenInfo.new(0.3), {
		Size = UDim2.new(ratio, 0, 1, 0)
	}):Play()

	if inDark then
		ui.darkFill.BackgroundColor3 = Color3.fromRGB(
			math.floor(100 + (1 - ratio) * 155),
			math.floor(60 * ratio),
			math.floor(200 * ratio)
		)
		ui.darkText.Text = string.format("%.0fs", timer)
	else
		ui.darkFill.BackgroundColor3 = C.BAR_DARK
		ui.darkText.Text = "aman"
	end
end

local function showMessage(ui, text, color)
	ui.msgOverlay.Visible = true
	ui.msgLabel.Text       = text
	ui.msgLabel.TextColor3 = color
	TweenService:Create(ui.msgOverlay, TweenInfo.new(0.4), {
		BackgroundTransparency = 0.35
	}):Play()
end

-- ─────────────────────────────────────────────
--  RULES PANEL TOGGLE
-- ─────────────────────────────────────────────
local function setupPanelToggle(ui)
	local panelOpen = false

	local function openPanel()
		panelOpen = true
		ui.rulesPanel.Visible = true
		ui.rulesPanel.BackgroundTransparency = 1
		TweenService:Create(ui.rulesPanel, TweenInfo.new(0.22, Enum.EasingStyle.Quad), {
			BackgroundTransparency = 0.08
		}):Play()
		ui.rulesBtn.Text       = "▲  RULES AKTIF"
		ui.rulesBtn.TextColor3 = C.TEXT_WHITE
	end

	local function closePanel()
		panelOpen = false
		TweenService:Create(ui.rulesPanel, TweenInfo.new(0.18, Enum.EasingStyle.Quad), {
			BackgroundTransparency = 1
		}):Play()
		task.delay(0.2, function()
			ui.rulesPanel.Visible = false
		end)
		ui.rulesBtn.Text       = "▼  RULES AKTIF"
		ui.rulesBtn.TextColor3 = C.TEXT_DIM
	end

	ui.rulesBtn.MouseButton1Click:Connect(function()
		if panelOpen then closePanel() else openPanel() end
	end)

	ui.panelClose.MouseButton1Click:Connect(function()
		closePanel()
	end)

	-- Hover effect pada rulesBtn
	ui.rulesBtn.MouseEnter:Connect(function()
		if not panelOpen then
			TweenService:Create(ui.rulesBtn, TweenInfo.new(0.12), {
				BackgroundTransparency = 0.0,
				TextColor3 = C.TEXT_WHITE,
			}):Play()
		end
	end)
	ui.rulesBtn.MouseLeave:Connect(function()
		if not panelOpen then
			TweenService:Create(ui.rulesBtn, TweenInfo.new(0.12), {
				BackgroundTransparency = 0.2,
				TextColor3 = C.TEXT_DIM,
			}):Play()
		end
	end)
end

-- ─────────────────────────────────────────────
--  FALLBACK: baca rules dari SessionInfo
-- ─────────────────────────────────────────────
local function readRulesFromSessionInfo()
	local si = ReplicatedStorage:WaitForChild("SessionInfo", 10)
	if not si then return nil end
	local folder = si:WaitForChild("ActiveRules")
	local ids = {}
	for _, v in ipairs(folder:GetChildren()) do
		table.insert(ids, v.Value)
	end
	return ids
end

-- ─────────────────────────────────────────────
--  MAIN
-- ─────────────────────────────────────────────
local ui = buildGui()
setupPanelToggle(ui)

local rulesLoaded = false
local function onRulesReceived(ruleIds)
	if rulesLoaded then return end
	rulesLoaded = true
	populateRulesPanel(ui, ruleIds)
end

-- Jalur utama: RemoteEvent dari GameManager
RE_RulesActivated.OnClientEvent:Connect(function(ruleIds)
	onRulesReceived(ruleIds)
end)

-- Fallback: SessionInfo (kalau client telat load)
task.spawn(function()
	task.wait(1)
	local ids = readRulesFromSessionInfo()
	if ids then onRulesReceived(ids) end
end)

-- Task progress
RE_TaskProgress.OnClientEvent:Connect(function(data)
	updateTaskLabel(ui, data)
end)

RE_SyncState.OnClientEvent:Connect(function(data)
	updateTaskLabel(ui, data)
end)

-- Survival bars
RE_HungerUpdate.OnClientEvent:Connect(function(hunger)
	updateHunger(ui, hunger)
end)

RE_DarkUpdate.OnClientEvent:Connect(function(timer, inDark)
	updateDark(ui, timer, inDark)
end)

-- Win / death
RE_GameWin.OnClientEvent:Connect(function()
	showMessage(ui, "<b>🎉 KABUR!</b>\nKembali ke lobby...", C.WIN_GREEN)
end)

RE_PlayerDied.OnClientEvent:Connect(function(playerName, cause)
	if playerName == LocalPlayer.Name then
		local txt = cause == "hunger"
			and "💀 Kamu kelaparan!"
			or  "💀 Kegelapan menelanmu!"
		showMessage(ui, txt, C.DEATH_RED)
	end
end)
