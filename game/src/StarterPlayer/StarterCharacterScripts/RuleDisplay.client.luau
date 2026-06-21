-- =============================================================
--  RulesDisplay.client.luau
--  Author: Gilang
--  Path: game/src/StarterPlayer/StarterPlayerScripts/RulesDisplay.client.luau
--
--  Tanggung jawab:
--  - Baca ReplicatedStorage.SessionInfo.ActiveRules (dibuat oleh
--    GameManager.server.luau saat sesi dimulai)
--  - Tampilkan popup besar berisi rules aktif (level + mode + list rules)
--  - Setelah beberapa detik, mengecil jadi bar info permanen di pojok atas
--
--  Tidak pakai RemoteEvent sama sekali — SessionInfo sudah merupakan
--  Folder yang direplicate otomatis ke semua client begitu dibuat di
--  ReplicatedStorage, jadi cukup WaitForChild.
-- =============================================================

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")

local Constants = require(ReplicatedStorage.Shared.Constants)

local LocalPlayer = Players.LocalPlayer
local PlayerGui    = LocalPlayer:WaitForChild("PlayerGui")

-- ============================================================
-- CONFIG
-- ============================================================

local POPUP_DISPLAY_SECONDS = 4.5
local POPUP_FADE_SECONDS    = 0.5
local SHRINK_TWEEN_SECONDS  = 0.6

-- Label tampilan untuk tiap rule id -> teks yang dilihat player.
-- Dipisah Monster / Player supaya gampang ditaruh di 2 kolom popup.
local RuleDisplayNames = {
    [Constants.Rules.MONSTER_HEAR]      = { text = "Monster Can Hear",            group = "monster" },
    [Constants.Rules.MONSTER_SMELL]     = { text = "Monster Can Smell",           group = "monster" },
    [Constants.Rules.MONSTER_SEE]       = { text = "Monster Sees in Light",       group = "monster" },
    [Constants.Rules.MONSTER_FAST]      = { text = "Monster Is Faster",           group = "monster" },
    [Constants.Rules.MONSTER_REACH]     = { text = "Monster Reach Increased",     group = "monster" },
    [Constants.Rules.MONSTER_DUPLICATE] = { text = "Monster Duplicated",          group = "monster" },
    [Constants.Rules.PLAYER_HUNGER]     = { text = "Hunger Drains Over Time",     group = "player" },
    [Constants.Rules.PLAYER_DARK_TIMER] = { text = "Fear of Darkness",            group = "player" },
}

local function getRuleInfo(ruleId)
    return RuleDisplayNames[ruleId] or { text = ruleId, group = "monster" }
end

-- ============================================================
-- BUILD GUI
-- ============================================================

local screenGui = Instance.new("ScreenGui")
screenGui.Name              = "RulesDisplayGui"
screenGui.ResetOnSpawn      = false
screenGui.IgnoreGuiInset    = true
screenGui.ZIndexBehavior    = Enum.ZIndexBehavior.Sibling
screenGui.Parent            = PlayerGui

-- ---------- POPUP BESAR (tampil sebentar di awal) ----------

local popupFrame = Instance.new("Frame")
popupFrame.Name                  = "RulesPopup"
popupFrame.AnchorPoint           = Vector2.new(0.5, 0.5)
popupFrame.Position              = UDim2.new(0.5, 0, 0.4, 0)
popupFrame.Size                  = UDim2.new(0, 480, 0, 320)
popupFrame.BackgroundColor3      = Color3.fromRGB(20, 20, 24)
popupFrame.BackgroundTransparency = 0.1
popupFrame.BorderSizePixel       = 0
popupFrame.Visible               = false
popupFrame.Parent                = screenGui

local popupCorner = Instance.new("UICorner")
popupCorner.CornerRadius = UDim.new(0, 12)
popupCorner.Parent       = popupFrame

local popupStroke = Instance.new("UIStroke")
popupStroke.Color     = Color3.fromRGB(120, 40, 40)
popupStroke.Thickness  = 2
popupStroke.Parent     = popupFrame

local popupTitle = Instance.new("TextLabel")
popupTitle.Name           = "Title"
popupTitle.BackgroundTransparency = 1
popupTitle.Position       = UDim2.new(0, 0, 0, 16)
popupTitle.Size           = UDim2.new(1, 0, 0, 40)
popupTitle.Font           = Enum.Font.GothamBold
popupTitle.TextSize       = 26
popupTitle.TextColor3     = Color3.fromRGB(255, 80, 80)
popupTitle.Text           = "RULES FOR THIS RUN"
popupTitle.Parent         = popupFrame

local popupSubtitle = Instance.new("TextLabel")
popupSubtitle.Name           = "Subtitle"
popupSubtitle.BackgroundTransparency = 1
popupSubtitle.Position       = UDim2.new(0, 0, 0, 54)
popupSubtitle.Size           = UDim2.new(1, 0, 0, 24)
popupSubtitle.Font           = Enum.Font.Gotham
popupSubtitle.TextSize       = 16
popupSubtitle.TextColor3     = Color3.fromRGB(200, 200, 200)
popupSubtitle.Text           = ""
popupSubtitle.Parent         = popupFrame

local function createColumn(name, xScale, headerText, headerColor)
    local column = Instance.new("Frame")
    column.Name                  = name
    column.BackgroundTransparency = 1
    column.Position              = UDim2.new(xScale, 0, 0, 90)
    column.Size                  = UDim2.new(0.46, 0, 1, -110)
    column.Parent                = popupFrame

    local header = Instance.new("TextLabel")
    header.BackgroundTransparency = 1
    header.Size       = UDim2.new(1, 0, 0, 24)
    header.Font        = Enum.Font.GothamBold
    header.TextSize     = 15
    header.TextColor3   = headerColor
    header.Text          = headerText
    header.LayoutOrder  = 0
    header.Parent        = column

    local list = Instance.new("UIListLayout")
    list.Padding   = UDim.new(0, 4)
    list.SortOrder  = Enum.SortOrder.LayoutOrder
    list.Parent     = column

    return column
end

local monsterColumn = createColumn("MonsterColumn", 0.03, "MONSTER", Color3.fromRGB(255, 120, 80))
local playerColumn  = createColumn("PlayerColumn", 0.51, "YOU", Color3.fromRGB(120, 180, 255))

local function clearColumnEntries(column)
    for _, child in ipairs(column:GetChildren()) do
        if child:IsA("TextLabel") and child.Name == "RuleEntry" then
            child:Destroy()
        end
    end
end

local function addColumnEntry(column, layoutOrder, text)
    local entry = Instance.new("TextLabel")
    entry.Name                 = "RuleEntry"
    entry.BackgroundTransparency = 1
    entry.Size                 = UDim2.new(1, 0, 0, 20)
    entry.Font                  = Enum.Font.Gotham
    entry.TextSize               = 14
    entry.TextColor3             = Color3.fromRGB(230, 230, 230)
    entry.TextXAlignment         = Enum.TextXAlignment.Left
    entry.Text                   = "• " .. text
    entry.LayoutOrder            = layoutOrder
    entry.Parent                 = column
end

-- ---------- BAR PERMANEN (mirip status Coal/Lever/Battery) ----------

local permanentBar = Instance.new("Frame")
permanentBar.Name                  = "RulesPermanentBar"
permanentBar.AnchorPoint           = Vector2.new(0.5, 0)
permanentBar.Position              = UDim2.new(0.5, 0, 0, 16)
permanentBar.Size                  = UDim2.new(0, 0, 0, 0) -- akan di-tween
permanentBar.BackgroundColor3      = Color3.fromRGB(30, 33, 38)
permanentBar.BackgroundTransparency = 0.15
permanentBar.BorderSizePixel       = 0
permanentBar.Visible               = false
permanentBar.Parent                = screenGui

local permanentCorner = Instance.new("UICorner")
permanentCorner.CornerRadius = UDim.new(0, 8)
permanentCorner.Parent       = permanentBar

local permanentLayout = Instance.new("UIListLayout")
permanentLayout.FillDirection      = Enum.FillDirection.Horizontal
permanentLayout.Padding            = UDim.new(0, 14)
permanentLayout.VerticalAlignment  = Enum.VerticalAlignment.Center
permanentLayout.SortOrder          = Enum.SortOrder.LayoutOrder
permanentLayout.Parent             = permanentBar

local permanentPadding = Instance.new("UIPadding")
permanentPadding.PaddingLeft   = UDim.new(0, 14)
permanentPadding.PaddingRight  = UDim.new(0, 14)
permanentPadding.PaddingTop    = UDim.new(0, 6)
permanentPadding.PaddingBottom = UDim.new(0, 6)
permanentPadding.Parent        = permanentBar

local function clearPermanentBarEntries()
    for _, child in ipairs(permanentBar:GetChildren()) do
        if child:IsA("TextLabel") then
            child:Destroy()
        end
    end
end

local function addPermanentEntry(layoutOrder, text, color)
    local label = Instance.new("TextLabel")
    label.BackgroundTransparency = 1
    label.AutomaticSize           = Enum.AutomaticSize.X
    label.Size                    = UDim2.new(0, 0, 1, 0)
    label.Font                    = Enum.Font.GothamBold
    label.TextSize                 = 13
    label.TextColor3               = color
    label.Text                     = text
    label.LayoutOrder              = layoutOrder
    label.Parent                   = permanentBar
end

-- ============================================================
-- BACA SESSIONINFO & TAMPILKAN
-- ============================================================

local function readLevelAndMode()
    local sessionInfo = ReplicatedStorage:WaitForChild("SessionInfo", 10)

    if not sessionInfo then
        warn("[RulesDisplay] SessionInfo tidak ditemukan dalam 10 detik.")
        return 1, "REGULAR"
    end

    local level = sessionInfo:WaitForChild("Level").Value
    local mode  = sessionInfo:WaitForChild("Mode").Value

    return level, mode
end

-- Pisahkan rule id (array of string) jadi 2 grup (monster/player) untuk
-- ditampilkan. Dipakai baik dari data RemoteEvent maupun dari SessionInfo.
local function splitRulesByGroup(ruleIds)
    local monsterRules = {}
    local playerRules   = {}

    for _, ruleId in ipairs(ruleIds) do
        local info = getRuleInfo(ruleId)

        if info.group == "player" then
            table.insert(playerRules, info.text)
        else
            table.insert(monsterRules, info.text)
        end
    end

    return monsterRules, playerRules
end

-- Fallback: baca rules dari ReplicatedStorage.SessionInfo.ActiveRules
-- (Folder of StringValue) kalau RemoteEvent ketinggalan / belum sempat
-- ditangkap (mis. client baru selesai loading setelah event di-fire).
local function readRuleIdsFromSessionInfo()
    local sessionInfo = ReplicatedStorage:WaitForChild("SessionInfo", 10)

    if not sessionInfo then
        return nil
    end

    local rulesFolder = sessionInfo:WaitForChild("ActiveRules")
    local ruleIds = {}

    -- Children sudah diberi nama unik (rule_id .. "_" .. index) di
    -- GameManager, tapi .Value tetap rule id aslinya, jadi kita pakai
    -- .Value, bukan .Name.
    for _, v in ipairs(rulesFolder:GetChildren()) do
        table.insert(ruleIds, v.Value)
    end

    return ruleIds
end

local function showRules(sessionData)
    clearColumnEntries(monsterColumn)
    clearColumnEntries(playerColumn)
    clearPermanentBarEntries()

    popupSubtitle.Text = string.format("Level %d — %s", sessionData.level, sessionData.mode)

    if #sessionData.monsterRules == 0 then
        addColumnEntry(monsterColumn, 1, "No extra ability")
    else
        for i, text in ipairs(sessionData.monsterRules) do
            addColumnEntry(monsterColumn, i, text)
        end
    end

    if #sessionData.playerRules == 0 then
        addColumnEntry(playerColumn, 1, "No extra debuff")
    else
        for i, text in ipairs(sessionData.playerRules) do
            addColumnEntry(playerColumn, i, text)
        end
    end

    local order = 0

    for _, text in ipairs(sessionData.monsterRules) do
        order += 1
        addPermanentEntry(order, text, Color3.fromRGB(255, 140, 100))
    end

    for _, text in ipairs(sessionData.playerRules) do
        order += 1
        addPermanentEntry(order, text, Color3.fromRGB(140, 190, 255))
    end

    -- ---------- ANIMASI: popup masuk ----------
    popupFrame.Visible              = true
    popupFrame.BackgroundTransparency = 1
    popupStroke.Transparency         = 1

    for _, descendant in ipairs(popupFrame:GetDescendants()) do
        if descendant:IsA("TextLabel") then
            descendant.TextTransparency = 1
        end
    end

    TweenService:Create(
        popupFrame,
        TweenInfo.new(POPUP_FADE_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        { BackgroundTransparency = 0.1 }
    ):Play()

    TweenService:Create(
        popupStroke,
        TweenInfo.new(POPUP_FADE_SECONDS),
        { Transparency = 0 }
    ):Play()

    for _, descendant in ipairs(popupFrame:GetDescendants()) do
        if descendant:IsA("TextLabel") then
            TweenService:Create(
                descendant,
                TweenInfo.new(POPUP_FADE_SECONDS),
                { TextTransparency = 0 }
            ):Play()
        end
    end

    -- ---------- TUNGGU, LALU FADE OUT POPUP + MUNCULKAN BAR PERMANEN ----------
    task.delay(POPUP_DISPLAY_SECONDS, function()
        local fadeOut = TweenService:Create(
            popupFrame,
            TweenInfo.new(POPUP_FADE_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
            { BackgroundTransparency = 1 }
        )

        TweenService:Create(
            popupStroke,
            TweenInfo.new(POPUP_FADE_SECONDS),
            { Transparency = 1 }
        ):Play()

        for _, descendant in ipairs(popupFrame:GetDescendants()) do
            if descendant:IsA("TextLabel") then
                TweenService:Create(
                    descendant,
                    TweenInfo.new(POPUP_FADE_SECONDS),
                    { TextTransparency = 1 }
                ):Play()
            end
        end

        fadeOut.Completed:Connect(function()
            popupFrame.Visible = false

            permanentBar.Visible             = true
            permanentBar.BackgroundTransparency = 1

            task.wait() -- biar AutomaticSize anak2nya settle dulu

            TweenService:Create(
                permanentBar,
                TweenInfo.new(SHRINK_TWEEN_SECONDS, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
                { BackgroundTransparency = 0.15 }
            ):Play()
        end)

        fadeOut:Play()
    end)
end

-- ============================================================
-- INIT
--
-- Sumber utama: RemoteEvent "RulesActivated" (Server -> Client),
-- sudah disiapkan RemoteSetup.server.luau dan di-fire oleh
-- GameManager.server.luau begitu sesi mulai. Ini lebih cepat &
-- konsisten dengan rencana tim (lihat komentar RemoteSetup.lua:
-- "server→all: active rules list").
--
-- Fallback: kalau client baru selesai loading SETELAH event itu
-- di-fire (jadi listener di bawah miss event-nya), baca langsung
-- dari ReplicatedStorage.SessionInfo.ActiveRules sebagai cadangan,
-- dengan delay singkat untuk memberi waktu SessionInfo kebentuk.
-- ============================================================

local rulesAlreadyShown = false

local function tryShowFromRuleIds(ruleIds)
    if rulesAlreadyShown then
        return
    end
    rulesAlreadyShown = true

    local level, mode = readLevelAndMode()
    local monsterRules, playerRules = splitRulesByGroup(ruleIds)

    showRules({
        level = level,
        mode = mode,
        monsterRules = monsterRules,
        playerRules = playerRules,
    })
end

-- Dengar RemoteEvent (jalur utama)
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RE_RulesActivated = Remotes:WaitForChild("RulesActivated")

RE_RulesActivated.OnClientEvent:Connect(function(ruleIds)
    tryShowFromRuleIds(ruleIds)
end)

-- Fallback via SessionInfo (jalur cadangan, jalan paralel)
task.spawn(function()
    task.wait(1) -- beri kesempatan RemoteEvent datang duluan kalau memang belum telat
    local ruleIds = readRuleIdsFromSessionInfo()

    if ruleIds then
        tryShowFromRuleIds(ruleIds)
    end
end)
