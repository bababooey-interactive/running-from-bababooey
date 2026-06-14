-- =============================================================
--  GameManager.server.luau
--  Orkestrator utama: init TaskSystem + SurvivalSystem
--  Path: game/src/ServerScriptService/GameManager.server.luau
--
--  Cara kerja:
--  1. Baca level + rules dari TeleportData (dikirim lobby)
--  2. Init TaskSystem (counter + task objects)
--  3. Init SurvivalSystem (hanya rules yang aktif)
-- =============================================================

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService   = game:GetService("TeleportService")

local Constants      = require(ReplicatedStorage.Shared.Constants)
local TaskSystem     = require(script.Parent.TaskSystem)
local SurvivalSystem = require(script.Parent.SurvivalSystem)

-- ─────────────────────────────────────────────
--  Baca TeleportData yang dikirim lobby
--  Format: { level = number, rules = {string}, mode = string }
--
--  Fallback: level 1, rules = slot 1-2 (MONSTER_HEAR + PLAYER_HUNGER)
-- ─────────────────────────────────────────────
local function getSessionData(): {level: number, rules: {string}, mode: string}
    -- Ambil dari player pertama yang masuk
    local firstPlayer = Players:GetPlayers()[1]
    if firstPlayer then
        local ok, data = pcall(function()
            return TeleportService:GetLocalPlayerTeleportData()
        end)
        -- Note: GetLocalPlayerTeleportData hanya tersedia di LocalScript.
        -- Untuk server, gunakan pendekatan via DataStore atau BindableEvent dari lobby.
        -- Sementara fallback ke default:
    end

    -- ── DEFAULT SESSION (untuk testing tanpa lobby) ──
    return {
        level = 1,
        rules = {
            Constants.Rules.MONSTER_HEAR,
            Constants.Rules.PLAYER_HUNGER,
        },
        mode  = Constants.GameMode.REGULAR,
    }
end

-- ─────────────────────────────────────────────
--  Alternatif: terima data via ObjectValue di ServerStorage
--  Lobby bisa set value sebelum teleport.
--  Uncomment jika pakai pendekatan ini:
-- ─────────────────────────────────────────────
--[[
local function getSessionDataFromStorage()
    local ss   = game:GetService("ServerStorage")
    local data = ss:FindFirstChild("SessionData")
    if not data then return getSessionData() end

    local level  = data:FindFirstChild("Level")
    local mode   = data:FindFirstChild("Mode")
    local ruleList = data:FindFirstChild("Rules")

    local rules = {}
    if ruleList then
        for _, v in ipairs(ruleList:GetChildren()) do
            table.insert(rules, v.Value)
        end
    end

    return {
        level = level and level.Value or 1,
        rules = rules,
        mode  = mode and mode.Value or Constants.GameMode.REGULAR,
    }
end
]]

-- ─────────────────────────────────────────────
--  Main init
-- ─────────────────────────────────────────────
local session = getSessionData()

print(string.format(
    "[GameManager] Sesi dimulai — Level: %d | Mode: %s | Rules: %s",
    session.level,
    session.mode,
    table.concat(session.rules, ", ")
))

-- Init task system dulu (task objects di-hook)
TaskSystem.init(session.level)

-- Init survival system (hunger + dark timer sesuai rules)
SurvivalSystem.init(session.rules)

-- ─────────────────────────────────────────────
--  Expose session info ke ReplicatedStorage
--  agar client bisa tahu rules mana yang aktif
-- ─────────────────────────────────────────────
local sessionInfo = Instance.new("Folder")
sessionInfo.Name   = "SessionInfo"
sessionInfo.Parent = ReplicatedStorage

local levelVal = Instance.new("IntValue")
levelVal.Name   = "Level"
levelVal.Value  = session.level
levelVal.Parent = sessionInfo

local modeVal = Instance.new("StringValue")
modeVal.Name   = "Mode"
modeVal.Value  = session.mode
modeVal.Parent = sessionInfo

local rulesFolder = Instance.new("Folder")
rulesFolder.Name   = "ActiveRules"
rulesFolder.Parent = sessionInfo

for _, rule in ipairs(session.rules) do
    local v = Instance.new("StringValue")
    v.Name   = rule
    v.Value  = rule
    v.Parent = rulesFolder
end
