-- =============================================================
--  SpectateSystem.client.luau
--  Path: game/src/StarterPlayer/StarterPlayerScripts/SpectateSystem.client.luau
--
--  Aktif saat local player mati (downed), nonaktif saat di-revive.
--  Mode: follow player hidup tertentu, bisa ganti target.
--
--  Cara kerja:
--  1. RE_PlayerDowned (local player) → aktifkan spectate
--  2. RE_PlayerRevived (local player) → nonaktifkan spectate
--  3. RE_GameOver → spectate tetap aktif (tidak ada yang bisa revive)
--
--  Kontrol:
--  - Keyboard: Q / E untuk ganti target
--  - UI: klik tombol nama player untuk langsung spectate mereka
--
--  Kamera:
--  - Camera.CameraType = Scriptable
--  - Posisi di belakang/atas target (third-person follow)
--  - Smooth lerp agar tidak patah-patah
--
--  Sinergi dengan HorrorCamera.client.luau:
--  HorrorCamera hanya aktif kalau player punya karakter hidup.
--  Saat spectate, local player tidak punya karakter aktif (sudah mati),
--  jadi HorrorCamera tidak interferensi.
-- =============================================================

local Players          = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService       = game:GetService("RunService")
local TweenService     = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui   = LocalPlayer:WaitForChild("PlayerGui")
local Camera      = workspace.CurrentCamera

local Remotes          = ReplicatedStorage:WaitForChild("Remotes")
local RE_PlayerDowned  = Remotes:WaitForChild("PlayerDowned")
local RE_PlayerRevived = Remotes:WaitForChild("PlayerRevived")

-- ─────────────────────────────────────────────
--  CONFIG
-- ─────────────────────────────────────────────
local CAM_DISTANCE = 12    -- stud di belakang target
local CAM_HEIGHT   = 6     -- stud di atas target
local CAM_LERP     = 0.08  -- smooth factor (0=tidak bergerak, 1=instant)

-- ─────────────────────────────────────────────
--  STATE
-- ─────────────────────────────────────────────
local isSpectating   = false
local spectateTarget: Player? = nil
local camConnection: RBXScriptConnection? = nil

-- ─────────────────────────────────────────────
--  BUILD SPECTATE GUI
-- ─────────────────────────────────────────────
local screenGui = Instance.new("ScreenGui")
screenGui.Name           = "SpectateGui"
screenGui.ResetOnSpawn   = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.IgnoreGuiInset = false
screenGui.DisplayOrder   = 30
screenGui.Enabled        = false
screenGui.Parent         = PlayerGui

-- ── Background strip bawah ───────────────────
local bottomBar = Instance.new("Frame")
bottomBar.Name                   = "BottomBar"
bottomBar.AnchorPoint             = Vector2.new(0.5, 1)
bottomBar.Position                = UDim2.new(0.5, 0, 1, -12)
bottomBar.Size                    = UDim2.new(0, 520, 0, 52)
bottomBar.BackgroundColor3        = Color3.fromRGB(12, 12, 18)
bottomBar.BackgroundTransparency  = 0.2
bottomBar.BorderSizePixel         = 0
bottomBar.Parent                  = screenGui

local bottomCorner = Instance.new("UICorner")
bottomCorner.CornerRadius = UDim.new(0, 12)
bottomCorner.Parent       = bottomBar

local bottomStroke = Instance.new("UIStroke")
bottomStroke.Color     = Color3.fromRGB(80, 80, 110)
bottomStroke.Thickness  = 1
bottomStroke.Parent     = bottomBar

-- ── Label "SPECTATING" ───────────────────────
local spectateLabel = Instance.new("TextLabel")
spectateLabel.Name                  = "SpectateLabel"
spectateLabel.AnchorPoint            = Vector2.new(0.5, 0)
spectateLabel.Position               = UDim2.new(0.5, 0, 0, 6)
spectateLabel.Size                   = UDim2.new(1, -16, 0, 18)
spectateLabel.BackgroundTransparency = 1
spectateLabel.TextColor3             = Color3.fromRGB(140, 140, 180)
spectateLabel.TextSize               = 11
spectateLabel.Font                   = Enum.Font.GothamBold
spectateLabel.Text                   = "👁  SPECTATING"
spectateLabel.Parent                 = bottomBar

-- ── Row tombol player ────────────────────────
local playerRow = Instance.new("Frame")
playerRow.Name                   = "PlayerRow"
playerRow.AnchorPoint             = Vector2.new(0.5, 1)
playerRow.Position                = UDim2.new(0.5, 0, 1, -6)
playerRow.Size                    = UDim2.new(1, -16, 0, 26)
playerRow.BackgroundTransparency  = 1
playerRow.Parent                  = bottomBar

local rowLayout = Instance.new("UIListLayout")
rowLayout.FillDirection       = Enum.FillDirection.Horizontal
rowLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
rowLayout.VerticalAlignment   = Enum.VerticalAlignment.Center
rowLayout.Padding             = UDim.new(0, 8)
rowLayout.SortOrder           = Enum.SortOrder.LayoutOrder
rowLayout.Parent              = playerRow

-- ── Tombol prev / next ───────────────────────
local function makeNavBtn(text: string, xAnchor: number, xPos: number): TextButton
    local btn = Instance.new("TextButton")
    btn.AnchorPoint            = Vector2.new(xAnchor, 0.5)
    btn.Position               = UDim2.new(xPos, 0, 0.5, 0)
    btn.Size                   = UDim2.new(0, 36, 0, 36)
    btn.BackgroundColor3       = Color3.fromRGB(30, 30, 40)
    btn.BackgroundTransparency = 0.2
    btn.BorderSizePixel        = 0
    btn.Font                   = Enum.Font.GothamBold
    btn.TextSize               = 18
    btn.TextColor3             = Color3.fromRGB(200, 200, 220)
    btn.Text                   = text
    btn.AutoButtonColor        = false
    btn.Parent                 = screenGui

    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(1, 0)
    c.Parent       = btn

    local s = Instance.new("UIStroke")
    s.Color     = Color3.fromRGB(80, 80, 110)
    s.Thickness  = 1
    s.Parent     = btn

    return btn
end

local prevBtn = makeNavBtn("◀", 1, 0)
prevBtn.AnchorPoint = Vector2.new(0, 0.5)
prevBtn.Position    = UDim2.new(0, 12, 0, 0)
prevBtn.Parent      = bottomBar

local nextBtn = makeNavBtn("▶", 1, 0)
nextBtn.AnchorPoint = Vector2.new(1, 0.5)
nextBtn.Position    = UDim2.new(1, -12, 0, 0)
nextBtn.Parent      = bottomBar

-- ── Target name label ────────────────────────
local targetName = Instance.new("TextLabel")
targetName.Name                  = "TargetName"
targetName.AnchorPoint            = Vector2.new(0.5, 0.5)
targetName.Position               = UDim2.new(0.5, 0, 0.5, 0)
targetName.Size                   = UDim2.new(1, -100, 1, 0)
targetName.BackgroundTransparency = 1
targetName.TextColor3             = Color3.fromRGB(230, 230, 255)
targetName.TextSize               = 15
targetName.Font                   = Enum.Font.GothamBold
targetName.Text                   = ""
targetName.Parent                 = bottomBar

-- ── "DOWNED" badge kiri atas ─────────────────
local downedBadge = Instance.new("Frame")
downedBadge.Name                   = "DownedBadge"
downedBadge.AnchorPoint             = Vector2.new(0, 0)
downedBadge.Position                = UDim2.new(0, 12, 0, 52)
downedBadge.Size                    = UDim2.new(0, 160, 0, 32)
downedBadge.BackgroundColor3        = Color3.fromRGB(120, 20, 20)
downedBadge.BackgroundTransparency  = 0.25
downedBadge.BorderSizePixel         = 0
downedBadge.Parent                  = screenGui

local badgeCorner = Instance.new("UICorner")
badgeCorner.CornerRadius = UDim.new(0, 8)
badgeCorner.Parent       = downedBadge

local badgeLabel = Instance.new("TextLabel")
badgeLabel.Size                  = UDim2.new(1, 0, 1, 0)
badgeLabel.BackgroundTransparency = 1
badgeLabel.TextColor3             = Color3.fromRGB(255, 160, 160)
badgeLabel.TextSize               = 13
badgeLabel.Font                   = Enum.Font.GothamBold
badgeLabel.Text                   = "💀  KAMU DOWNED"
badgeLabel.Parent                 = downedBadge

-- ─────────────────────────────────────────────
--  HELPERS: dapatkan list player hidup
-- ─────────────────────────────────────────────
local function getLivePlayers(): { Player }
    local list = {}
    for _, player in ipairs(Players:GetPlayers()) do
        if player == LocalPlayer then continue end
        local char = player.Character
        if not char then continue end
        local hum = char:FindFirstChildOfClass("Humanoid")
        if hum and hum.Health > 0 then
            table.insert(list, player)
        end
    end
    return list
end

local function getTargetIndex(list: { Player }): number
    if not spectateTarget then return 1 end
    for i, p in ipairs(list) do
        if p == spectateTarget then return i end
    end
    return 1
end

-- ─────────────────────────────────────────────
--  SET TARGET
-- ─────────────────────────────────────────────
local function setTarget(player: Player?)
    spectateTarget = player
    if player then
        targetName.Text = "👤  " .. player.Name
    else
        targetName.Text = "— Tidak ada player —"
    end
end

-- ─────────────────────────────────────────────
--  REFRESH PLAYER BUTTONS di playerRow
-- ─────────────────────────────────────────────
local playerButtons: { TextButton } = {}

local function refreshPlayerButtons()
    -- Clear tombol lama
    for _, btn in ipairs(playerButtons) do
        if btn.Parent then btn:Destroy() end
    end
    playerButtons = {}

    local list = getLivePlayers()

    for i, player in ipairs(list) do
        local btn = Instance.new("TextButton")
        btn.Name                   = "PlayerBtn_" .. player.Name
        btn.Size                   = UDim2.new(0, 90, 1, 0)
        btn.BackgroundColor3       = (spectateTarget == player)
            and Color3.fromRGB(60, 80, 140)
            or  Color3.fromRGB(30, 30, 45)
        btn.BackgroundTransparency = 0.15
        btn.BorderSizePixel        = 0
        btn.Font                   = Enum.Font.GothamBold
        btn.TextSize               = 12
        btn.TextColor3             = (spectateTarget == player)
            and Color3.fromRGB(200, 220, 255)
            or  Color3.fromRGB(160, 160, 190)
        btn.Text                   = player.Name
        btn.AutoButtonColor        = false
        btn.LayoutOrder            = i
        btn.Parent                 = playerRow

        local c = Instance.new("UICorner")
        c.CornerRadius = UDim.new(0, 6)
        c.Parent       = btn

        btn.MouseButton1Click:Connect(function()
            setTarget(player)
            refreshPlayerButtons()
        end)

        -- Hover
        btn.MouseEnter:Connect(function()
            if spectateTarget ~= player then
                TweenService:Create(btn, TweenInfo.new(0.1), {
                    BackgroundColor3 = Color3.fromRGB(45, 45, 65)
                }):Play()
            end
        end)
        btn.MouseLeave:Connect(function()
            if spectateTarget ~= player then
                TweenService:Create(btn, TweenInfo.new(0.1), {
                    BackgroundColor3 = Color3.fromRGB(30, 30, 45)
                }):Play()
            end
        end)

        table.insert(playerButtons, btn)
    end

    -- Kalau target tidak ada di list (sudah mati), cari player hidup pertama
    if #list > 0 then
        local found = false
        for _, p in ipairs(list) do
            if p == spectateTarget then found = true; break end
        end
        if not found then setTarget(list[1]) end
    else
        setTarget(nil)
    end
end

-- ─────────────────────────────────────────────
--  NAVIGASI PREV / NEXT
-- ─────────────────────────────────────────────
local function navigateTarget(delta: number)
    local list = getLivePlayers()
    if #list == 0 then setTarget(nil); return end

    local idx = getTargetIndex(list)
    idx = ((idx - 1 + delta) % #list) + 1
    setTarget(list[idx])
    refreshPlayerButtons()
end

prevBtn.MouseButton1Click:Connect(function() navigateTarget(-1) end)
nextBtn.MouseButton1Click:Connect(function() navigateTarget(1) end)

-- Keyboard Q / E
UserInputService.InputBegan:Connect(function(input, processed)
    if processed or not isSpectating then return end
    if input.KeyCode == Enum.KeyCode.Q then
        navigateTarget(-1)
    elseif input.KeyCode == Enum.KeyCode.E then
        navigateTarget(1)
    end
end)

-- ─────────────────────────────────────────────
--  CAMERA FOLLOW LOOP
-- ─────────────────────────────────────────────
local currentCamCF = CFrame.new(0, 10, 0)

local function startCameraFollow()
    if camConnection then camConnection:Disconnect() end

    camConnection = RunService.RenderStepped:Connect(function(dt)
        if not isSpectating then return end

        local target = spectateTarget
        if not target then return end

        local char = target.Character
        if not char then return end

        local hrp = char:FindFirstChild("HumanoidRootPart")
        if not hrp then return end

        -- Target CFrame: di belakang dan atas target, menghadap ke target
        local targetCF = hrp.CFrame
            * CFrame.new(0, CAM_HEIGHT, CAM_DISTANCE)  -- offset belakang + atas

        -- Arahkan kamera ke kepala target
        local headPos = hrp.Position + Vector3.new(0, 2, 0)
        local camPos  = targetCF.Position
        local lookCF  = CFrame.lookAt(camPos, headPos)

        -- Smooth lerp
        local lerpFactor = math.clamp(CAM_LERP * (dt / (1/60)), 0, 1)
        currentCamCF = currentCamCF:Lerp(lookCF, lerpFactor)

        Camera.CFrame     = currentCamCF
        Camera.CameraType = Enum.CameraType.Scriptable
    end)
end

local function stopCameraFollow()
    if camConnection then
        camConnection:Disconnect()
        camConnection = nil
    end
    -- Kembalikan ke kamera normal
    Camera.CameraType = Enum.CameraType.Custom
end

-- ─────────────────────────────────────────────
--  AKTIFKAN / NONAKTIFKAN SPECTATE
-- ─────────────────────────────────────────────
local refreshInterval: thread? = nil

local function startSpectate()
    if isSpectating then return end
    isSpectating = true

    screenGui.Enabled = true

    -- Pilih target awal: player hidup pertama
    local list = getLivePlayers()
    if #list > 0 then
        setTarget(list[1])
    else
        setTarget(nil)
    end
    refreshPlayerButtons()

    startCameraFollow()

    -- Refresh player buttons tiap 2 detik (antisipasi player mati/revive)
    refreshInterval = task.spawn(function()
        while isSpectating do
            task.wait(2)
            if isSpectating then
                refreshPlayerButtons()
            end
        end
    end)

    print("[SpectateSystem] Spectate aktif.")
end

local function stopSpectate()
    if not isSpectating then return end
    isSpectating = false

    screenGui.Enabled = false
    stopCameraFollow()

    if refreshInterval then
        task.cancel(refreshInterval)
        refreshInterval = nil
    end

    spectateTarget = nil
    print("[SpectateSystem] Spectate nonaktif.")
end

-- ─────────────────────────────────────────────
--  REMOTE LISTENERS
-- ─────────────────────────────────────────────
RE_PlayerDowned.OnClientEvent:Connect(function(data)
    if data.playerName ~= LocalPlayer.Name then return end
    -- Local player downed → aktifkan spectate
    startSpectate()
end)

RE_PlayerRevived.OnClientEvent:Connect(function(data)
    if data.playerName ~= LocalPlayer.Name then return end
    -- Local player di-revive → nonaktifkan spectate
    stopSpectate()
end)

-- ─────────────────────────────────────────────
--  HANDLE player lain mati saat sedang di-spectate
--  → kalau target kita yang mati, auto pindah ke player berikutnya
-- ─────────────────────────────────────────────
RE_PlayerDowned.OnClientEvent:Connect(function(data)
    if not isSpectating then return end
    if data.playerName == LocalPlayer.Name then return end

    -- Kalau target kita yang downed, cari target lain
    if spectateTarget and data.playerName == spectateTarget.Name then
        task.wait(0.5)  -- beri waktu state ter-update
        navigateTarget(1)
    end

    refreshPlayerButtons()
end)

RE_PlayerRevived.OnClientEvent:Connect(function(data)
    if not isSpectating then return end
    if data.playerName == LocalPlayer.Name then return end
    -- Player lain di-revive → refresh list (mungkin ada target baru)
    refreshPlayerButtons()
end)

-- ─────────────────────────────────────────────
--  CLEANUP saat script init (reset state)
-- ─────────────────────────────────────────────
LocalPlayer.CharacterAdded:Connect(function()
    -- Karakter baru = sudah di-revive, pastikan spectate off
    stopSpectate()
end)

print("[SpectateSystem] Initialized.")
