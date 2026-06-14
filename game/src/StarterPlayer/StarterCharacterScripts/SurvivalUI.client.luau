-- =============================================================
--  SurvivalUI.client.luau
--  Client-side HUD: Hunger bar, Darkness timer, Task counter
--  Path: game/src/StarterPlayerScripts/SurvivalUI.client.luau
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

local LocalPlayer = Players.LocalPlayer
local PlayerGui   = LocalPlayer:WaitForChild("PlayerGui")

-- ─────────────────────────────────────────────
--  Build GUI
-- ─────────────────────────────────────────────
local function buildGui()
    -- Hapus GUI lama jika ada
    if PlayerGui:FindFirstChild("SurvivalHUD") then
        PlayerGui:FindFirstChild("SurvivalHUD"):Destroy()
    end

    local screenGui = Instance.new("ScreenGui")
    screenGui.Name            = "SurvivalHUD"
    screenGui.ResetOnSpawn    = false
    screenGui.ZIndexBehavior  = Enum.ZIndexBehavior.Sibling
    screenGui.Parent          = PlayerGui

    -- ── TASK COUNTER (top-center) ────────────────
    local taskFrame = Instance.new("Frame")
    taskFrame.Name            = "TaskFrame"
    taskFrame.Size            = UDim2.new(0, 320, 0, 80)
    taskFrame.Position        = UDim2.new(0.5, -160, 0, 12)
    taskFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
    taskFrame.BackgroundTransparency = 0.45
    taskFrame.BorderSizePixel = 0
    taskFrame.Parent          = screenGui

    local taskCorner = Instance.new("UICorner")
    taskCorner.CornerRadius = UDim.new(0, 8)
    taskCorner.Parent = taskFrame

    local taskLabel = Instance.new("TextLabel")
    taskLabel.Name             = "TaskLabel"
    taskLabel.Size             = UDim2.new(1, -16, 1, 0)
    taskLabel.Position         = UDim2.new(0, 8, 0, 0)
    taskLabel.BackgroundTransparency = 1
    taskLabel.TextColor3       = Color3.fromRGB(255, 255, 255)
    taskLabel.TextSize         = 14
    taskLabel.Font             = Enum.Font.GothamBold
    taskLabel.TextXAlignment   = Enum.TextXAlignment.Left
    taskLabel.TextYAlignment   = Enum.TextYAlignment.Center
    taskLabel.RichText         = true
    taskLabel.Text             = "🪨 Coal: 0/0  |  🔧 Lever: 0/0  |  🔋 Battery: 0/0"
    taskLabel.Parent           = taskFrame

    -- ── HUNGER BAR (bottom-left) ─────────────────
    local hungerContainer = Instance.new("Frame")
    hungerContainer.Name   = "HungerContainer"
    hungerContainer.Size   = UDim2.new(0, 220, 0, 54)
    hungerContainer.Position = UDim2.new(0, 16, 1, -70)
    hungerContainer.BackgroundTransparency = 1
    hungerContainer.Visible = false
    hungerContainer.Parent  = screenGui

    local hungerIcon = Instance.new("TextLabel")
    hungerIcon.Size   = UDim2.new(0, 24, 0, 24)
    hungerIcon.Position = UDim2.new(0, 0, 0, 0)
    hungerIcon.BackgroundTransparency = 1
    hungerIcon.TextColor3 = Color3.fromRGB(255, 200, 100)
    hungerIcon.TextSize   = 18
    hungerIcon.Font       = Enum.Font.GothamBold
    hungerIcon.Text       = "🍖"
    hungerIcon.Parent     = hungerContainer

    local hungerText = Instance.new("TextLabel")
    hungerText.Name   = "HungerText"
    hungerText.Size   = UDim2.new(1, -30, 0, 16)
    hungerText.Position = UDim2.new(0, 28, 0, 4)
    hungerText.BackgroundTransparency = 1
    hungerText.TextColor3 = Color3.fromRGB(220, 220, 220)
    hungerText.TextSize   = 12
    hungerText.Font       = Enum.Font.Gotham
    hungerText.TextXAlignment = Enum.TextXAlignment.Left
    hungerText.Text       = "Hunger"
    hungerText.Parent     = hungerContainer

    local hungerBg = Instance.new("Frame")
    hungerBg.Name   = "HungerBg"
    hungerBg.Size   = UDim2.new(1, 0, 0, 18)
    hungerBg.Position = UDim2.new(0, 0, 0, 28)
    hungerBg.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
    hungerBg.BorderSizePixel  = 0
    hungerBg.Parent = hungerContainer

    local hungerBgCorner = Instance.new("UICorner")
    hungerBgCorner.CornerRadius = UDim.new(0, 5)
    hungerBgCorner.Parent = hungerBg

    local hungerFill = Instance.new("Frame")
    hungerFill.Name   = "HungerFill"
    hungerFill.Size   = UDim2.new(1, 0, 1, 0)
    hungerFill.Position = UDim2.new(0, 0, 0, 0)
    hungerFill.BackgroundColor3 = Color3.fromRGB(255, 165, 0)
    hungerFill.BorderSizePixel  = 0
    hungerFill.Parent = hungerBg

    local hungerFillCorner = Instance.new("UICorner")
    hungerFillCorner.CornerRadius = UDim.new(0, 5)
    hungerFillCorner.Parent = hungerFill

    -- ── DARK TIMER (bottom-left, atas hunger) ────
    local darkContainer = Instance.new("Frame")
    darkContainer.Name   = "DarkContainer"
    darkContainer.Size   = UDim2.new(0, 220, 0, 54)
    darkContainer.Position = UDim2.new(0, 16, 1, -130)
    darkContainer.BackgroundTransparency = 1
    darkContainer.Visible = false
    darkContainer.Parent  = screenGui

    local darkIcon = Instance.new("TextLabel")
    darkIcon.Size   = UDim2.new(0, 24, 0, 24)
    darkIcon.Position = UDim2.new(0, 0, 0, 0)
    darkIcon.BackgroundTransparency = 1
    darkIcon.TextColor3 = Color3.fromRGB(150, 100, 255)
    darkIcon.TextSize   = 18
    darkIcon.Font       = Enum.Font.GothamBold
    darkIcon.Text       = "🌑"
    darkIcon.Parent     = darkContainer

    local darkText = Instance.new("TextLabel")
    darkText.Name   = "DarkText"
    darkText.Size   = UDim2.new(1, -30, 0, 16)
    darkText.Position = UDim2.new(0, 28, 0, 4)
    darkText.BackgroundTransparency = 1
    darkText.TextColor3 = Color3.fromRGB(220, 220, 220)
    darkText.TextSize   = 12
    darkText.Font       = Enum.Font.Gotham
    darkText.TextXAlignment = Enum.TextXAlignment.Left
    darkText.Text       = "Get to the light!"
    darkText.Parent     = darkContainer

    local darkBg = Instance.new("Frame")
    darkBg.Name   = "DarkBg"
    darkBg.Size   = UDim2.new(1, 0, 0, 18)
    darkBg.Position = UDim2.new(0, 0, 0, 28)
    darkBg.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
    darkBg.BorderSizePixel  = 0
    darkBg.Parent = darkContainer

    local darkBgCorner = Instance.new("UICorner")
    darkBgCorner.CornerRadius = UDim.new(0, 5)
    darkBgCorner.Parent = darkBg

    local darkFill = Instance.new("Frame")
    darkFill.Name   = "DarkFill"
    darkFill.Size   = UDim2.new(1, 0, 1, 0)
    darkFill.Position = UDim2.new(0, 0, 0, 0)
    darkFill.BackgroundColor3 = Color3.fromRGB(100, 60, 200)
    darkFill.BorderSizePixel  = 0
    darkFill.Parent = darkBg

    local darkFillCorner = Instance.new("UICorner")
    darkFillCorner.CornerRadius = UDim.new(0, 5)
    darkFillCorner.Parent = darkFill

    -- ── DARKNESS VIGNETTE OVERLAY ─────────────────
    local darkOverlay = Instance.new("Frame")
    darkOverlay.Name   = "DarkOverlay"
    darkOverlay.Size   = UDim2.new(1, 0, 1, 0)
    darkOverlay.Position = UDim2.new(0, 0, 0, 0)
    darkOverlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    darkOverlay.BackgroundTransparency = 1  -- mulai transparan
    darkOverlay.BorderSizePixel = 0
    darkOverlay.ZIndex = 10
    darkOverlay.Parent = screenGui

    -- ── WIN / DEATH OVERLAY ───────────────────────
    local messageOverlay = Instance.new("Frame")
    messageOverlay.Name   = "MessageOverlay"
    messageOverlay.Size   = UDim2.new(1, 0, 1, 0)
    messageOverlay.Position = UDim2.new(0, 0, 0, 0)
    messageOverlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    messageOverlay.BackgroundTransparency = 1
    messageOverlay.BorderSizePixel = 0
    messageOverlay.ZIndex = 20
    messageOverlay.Visible = false
    messageOverlay.Parent = screenGui

    local messageLabel = Instance.new("TextLabel")
    messageLabel.Name   = "MessageLabel"
    messageLabel.Size   = UDim2.new(0.6, 0, 0, 80)
    messageLabel.Position = UDim2.new(0.2, 0, 0.4, 0)
    messageLabel.BackgroundTransparency = 1
    messageLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    messageLabel.TextSize   = 36
    messageLabel.Font       = Enum.Font.GothamBold
    messageLabel.Text       = ""
    messageLabel.TextScaled = true
    messageLabel.RichText   = true
    messageLabel.Parent     = messageOverlay

    return {
        taskLabel      = taskLabel,
        hungerContainer = hungerContainer,
        hungerFill     = hungerFill,
        hungerText     = hungerText,
        darkContainer  = darkContainer,
        darkFill       = darkFill,
        darkText       = darkText,
        darkOverlay    = darkOverlay,
        messageOverlay = messageOverlay,
        messageLabel   = messageLabel,
    }
end

-- ─────────────────────────────────────────────
--  Update helpers
-- ─────────────────────────────────────────────
local ui = buildGui()

local function updateTaskLabel(data)
    local coal    = string.format("🪨 Coal <b>%d/%d</b>", data.coal_done, data.coal_total)
    local lever   = string.format("🔧 Lever <b>%d/%d</b>", data.lever_done, data.lever_total)
    local battery = string.format("🔋 Battery <b>%d/%d</b>", data.battery_done, data.battery_total)
    ui.taskLabel.Text = coal .. "   " .. lever .. "   " .. battery
end

local function updateHunger(hunger: number)
    ui.hungerContainer.Visible = true
    local ratio = math.clamp(hunger / Constants.HUNGER_MAX, 0, 1)

    TweenService:Create(ui.hungerFill, TweenInfo.new(0.3), {
        Size = UDim2.new(ratio, 0, 1, 0)
    }):Play()

    -- Warna: hijau → kuning → merah
    local r = math.clamp(2 * (1 - ratio), 0, 1)
    local g = math.clamp(2 * ratio, 0, 1)
    ui.hungerFill.BackgroundColor3 = Color3.new(r, g, 0)
    ui.hungerText.Text = string.format("Hunger: %d%%", math.floor(hunger))
end

local function updateDark(timer: number, inDark: boolean)
    ui.darkContainer.Visible = true
    local ratio = math.clamp(timer / Constants.DARK_TIMER_MAX, 0, 1)

    TweenService:Create(ui.darkFill, TweenInfo.new(0.3), {
        Size = UDim2.new(ratio, 0, 1, 0)
    }):Play()

    -- Overlay gelap saat di dark zone, makin gelap saat timer habis
    if inDark then
        local overlayAlpha = 0.3 + (1 - ratio) * 0.5  -- 0.3 sampai 0.8
        TweenService:Create(ui.darkOverlay, TweenInfo.new(0.5), {
            BackgroundTransparency = 1 - overlayAlpha
        }):Play()
        ui.darkText.Text = string.format("Get to the light! %.0fs", timer)
        ui.darkFill.BackgroundColor3 = Color3.fromRGB(
            math.floor(100 + (1 - ratio) * 155),
            math.floor(60 * ratio),
            math.floor(200 * ratio)
        )
    else
        TweenService:Create(ui.darkOverlay, TweenInfo.new(0.8), {
            BackgroundTransparency = 1
        }):Play()
        ui.darkText.Text = "Dark timer (you're safe)"
    end
end

local function showMessage(text: string, color: Color3)
    ui.messageOverlay.Visible = true
    ui.messageLabel.Text      = text
    ui.messageLabel.TextColor3 = color

    TweenService:Create(ui.messageOverlay, TweenInfo.new(0.4), {
        BackgroundTransparency = 0.3
    }):Play()
end

-- ─────────────────────────────────────────────
--  Remote listeners
-- ─────────────────────────────────────────────
RE_TaskProgress.OnClientEvent:Connect(function(data)
    updateTaskLabel(data)
end)

RE_SyncState.OnClientEvent:Connect(function(data)
    updateTaskLabel(data)
end)

RE_HungerUpdate.OnClientEvent:Connect(function(hunger: number)
    updateHunger(hunger)
end)

RE_DarkUpdate.OnClientEvent:Connect(function(timer: number, inDark: boolean)
    updateDark(timer, inDark)
end)

RE_GameWin.OnClientEvent:Connect(function()
    showMessage("<b>🎉 ESCAPED!</b>\nReturning to lobby...", Color3.fromRGB(100, 255, 150))
end)

RE_PlayerDied.OnClientEvent:Connect(function(playerName: string, cause: string)
    if playerName == LocalPlayer.Name then
        local causeText = cause == "hunger" and "💀 You starved!" or "💀 Darkness consumed you!"
        showMessage(causeText, Color3.fromRGB(255, 80, 80))
    else
        -- notif kecil kalau player lain mati
        print(string.format("[SurvivalUI] %s mati — %s", playerName, cause))
    end
end)
