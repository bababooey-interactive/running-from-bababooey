-- =============================================================
--  SurvivalSystem.server.luau
--  Hunger bar + Darkness timer, diaktifkan sesuai rules aktif
--  Path: game/src/ServerScriptService/SurvivalSystem.server.luau
-- =============================================================

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")

local Constants = require(ReplicatedStorage.Shared.Constants)

local Remotes          = ReplicatedStorage:WaitForChild("Remotes")
local RE_HungerUpdate  = Remotes:WaitForChild("HungerUpdate")   -- server→client (per player)
local RE_DarkUpdate    = Remotes:WaitForChild("DarkUpdate")     -- server→client (per player)
local RE_PlayerDied    = Remotes:WaitForChild("PlayerDied")     -- server→all (cause: string)
local RE_EatFood       = Remotes:WaitForChild("EatFood")        -- client→server

-- ─────────────────────────────────────────────
--  Per-player survival state
-- ─────────────────────────────────────────────
type PlayerState = {
    hunger     : number,   -- 0–100
    darkTimer  : number,   -- detik tersisa di dark zone (turun kalau di gelap)
    inDark     : boolean,  -- apakah player sedang di dark zone
    alive      : boolean,
}

local playerStates: {[number]: PlayerState} = {}  -- [UserId] = state

-- Rules yang aktif sesi ini (di-set via SurvivalSystem.init)
local activeRules: {[string]: boolean} = {}

-- ─────────────────────────────────────────────
--  Helpers
-- ─────────────────────────────────────────────
local function getState(player: Player): PlayerState?
    return playerStates[player.UserId]
end

local function killPlayer(player: Player, cause: string)
    local state = getState(player)
    if not state or not state.alive then return end
    state.alive = false

    local character = player.Character
    if character then
        local humanoid = character:FindFirstChildOfClass("Humanoid")
        if humanoid then
            humanoid.Health = 0
        end
    end

    RE_PlayerDied:FireAllClients(player.Name, cause)
    print(string.format("[SurvivalSystem] %s mati — sebab: %s", player.Name, cause))
end

-- ─────────────────────────────────────────────
--  Darkness detection
--  Konvensi: DarkZone = BasePart dengan Attribute "IsDarkZone" = true
--  di folder Workspace/DarkZones
-- ─────────────────────────────────────────────
local darkZones: {BasePart} = {}

local function refreshDarkZones()
    darkZones = {}
    local folder = workspace:FindFirstChild("DarkZones")
    if not folder then return end
    for _, obj in ipairs(folder:GetDescendants()) do
        if obj:IsA("BasePart") and obj:GetAttribute("IsDarkZone") then
            table.insert(darkZones, obj)
        end
    end
end

local function isInDark(character: Model): boolean
    local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart?
    if not hrp then return false end
    local pos = hrp.Position
    for _, zone in ipairs(darkZones) do
        local cf  = zone.CFrame
        local sz  = zone.Size / 2
        local rel = cf:PointToObjectSpace(pos)
        if math.abs(rel.X) <= sz.X and
           math.abs(rel.Y) <= sz.Y and
           math.abs(rel.Z) <= sz.Z then
            return true
        end
    end
    return false
end

-- ─────────────────────────────────────────────
--  Hunger: client fires EatFood saat pickup item
-- ─────────────────────────────────────────────
RE_EatFood.OnServerEvent:Connect(function(player: Player)
    local state = getState(player)
    if not state or not state.alive then return end
    if not activeRules[Constants.Rules.PLAYER_HUNGER] then return end

    state.hunger = math.min(Constants.HUNGER_MAX, state.hunger + Constants.HUNGER_FOOD_REFILL)
    RE_HungerUpdate:FireClient(player, state.hunger)
    print(string.format("[SurvivalSystem] %s makan — hunger: %.1f", player.Name, state.hunger))
end)

-- ─────────────────────────────────────────────
--  Main survival tick (dipanggil setiap 1 detik)
-- ─────────────────────────────────────────────
local function survivalTick(dt: number)
    for userId, state in pairs(playerStates) do
        if not state.alive then continue end

        local player = Players:GetPlayerByUserId(userId)
        if not player then continue end

        local character = player.Character
        if not character then continue end

        local humanoid = character:FindFirstChildOfClass("Humanoid")
        if not humanoid or humanoid.Health <= 0 then
            state.alive = false
            continue
        end

        -- ── HUNGER ──────────────────────────────
        if activeRules[Constants.Rules.PLAYER_HUNGER] then
            state.hunger = math.max(0, state.hunger - Constants.HUNGER_DECAY_RATE * dt)
            RE_HungerUpdate:FireClient(player, state.hunger)

            if state.hunger <= 0 then
                killPlayer(player, "hunger")
                continue
            end
        end

        -- ── DARKNESS TIMER ───────────────────────
        if activeRules[Constants.Rules.PLAYER_DARK_TIMER] then
            local inDark = isInDark(character)
            state.inDark = inDark

            if inDark then
                -- Countdown turun
                state.darkTimer = math.max(0, state.darkTimer - dt)
            else
                -- Restore saat keluar dark zone (restore ke max)
                state.darkTimer = Constants.DARK_TIMER_MAX
            end

            RE_DarkUpdate:FireClient(player, state.darkTimer, inDark)

            if state.darkTimer <= 0 then
                killPlayer(player, "darkness")
                continue
            end
        end
    end
end

-- ─────────────────────────────────────────────
--  Player lifecycle
-- ─────────────────────────────────────────────
local function onPlayerAdded(player: Player)
    playerStates[player.UserId] = {
        hunger    = Constants.HUNGER_MAX,
        darkTimer = Constants.DARK_TIMER_MAX,
        inDark    = false,
        alive     = true,
    }

    -- Reset saat respawn
    player.CharacterAdded:Connect(function()
        local state = playerStates[player.UserId]
        if state then
            state.hunger    = Constants.HUNGER_MAX
            state.darkTimer = Constants.DARK_TIMER_MAX
            state.inDark    = false
            state.alive     = true

            -- Kirim initial values ke client
            if activeRules[Constants.Rules.PLAYER_HUNGER] then
                RE_HungerUpdate:FireClient(player, state.hunger)
            end
            if activeRules[Constants.Rules.PLAYER_DARK_TIMER] then
                RE_DarkUpdate:FireClient(player, state.darkTimer, false)
            end
        end
    end)
end

local function onPlayerRemoving(player: Player)
    playerStates[player.UserId] = nil
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)
for _, p in ipairs(Players:GetPlayers()) do
    onPlayerAdded(p)
end

-- ─────────────────────────────────────────────
--  Public API
-- ─────────────────────────────────────────────
local SurvivalSystem = {}
local tickConnection: RBXScriptConnection? = nil

function SurvivalSystem.init(rules: {string})
    -- Reset active rules
    activeRules = {}
    for _, rule in ipairs(rules) do
        activeRules[rule] = true
    end

    -- Reset semua player states
    for _, player in ipairs(Players:GetPlayers()) do
        local state = playerStates[player.UserId]
        if state then
            state.hunger    = Constants.HUNGER_MAX
            state.darkTimer = Constants.DARK_TIMER_MAX
            state.inDark    = false
            state.alive     = true
        end
    end

    refreshDarkZones()

    -- Disconnect tick lama jika ada
    if tickConnection then
        tickConnection:Disconnect()
        tickConnection = nil
    end

    -- Hanya jalankan tick jika ada survival rule aktif
    local needsTick =
        activeRules[Constants.Rules.PLAYER_HUNGER] or
        activeRules[Constants.Rules.PLAYER_DARK_TIMER]

    if needsTick then
        local accumulator = 0
        tickConnection = RunService.Heartbeat:Connect(function(dt)
            accumulator += dt
            if accumulator >= 1 then
                survivalTick(accumulator)
                accumulator = 0
            end
        end)
    end

    local ruleList = {}
    for r, _ in pairs(activeRules) do
        table.insert(ruleList, r)
    end
    print("[SurvivalSystem] Init — rules aktif:", table.concat(ruleList, ", "))
end

function SurvivalSystem.stop()
    if tickConnection then
        tickConnection:Disconnect()
        tickConnection = nil
    end
    activeRules = {}
end

function SurvivalSystem.setPlayerInDark(player: Player, inDark: boolean)
    local state = getState(player)
    if state then
        state.inDark = inDark
    end
end

return SurvivalSystem
