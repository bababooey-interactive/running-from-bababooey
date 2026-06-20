-- =============================================================
--  TaskSystem.server.luau
--  Server-side task counter management + win condition
--  Path: game/src/ServerScriptService/TaskSystem.server.luau
-- =============================================================

local Players        = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService     = game:GetService("RunService")

local Constants = require(ReplicatedStorage.Shared.Constants)

-- ─────────────────────────────────────────────
--  RemoteEvents  (buat folder Remotes di ReplicatedStorage)
-- ─────────────────────────────────────────────
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local RE_TaskProgress = Remotes:WaitForChild("TaskProgress")   -- server→all clients
local RE_TaskInteract = Remotes:WaitForChild("TaskInteract")   -- client→server (touch/prompt)
local RE_GameWin      = Remotes:WaitForChild("GameWin")        -- server→all clients
local RE_SyncState    = Remotes:WaitForChild("SyncState")      -- server→joining client

-- ─────────────────────────────────────────────
--  Shared state  (counters dikelola server saja)
-- ─────────────────────────────────────────────
local taskState = {
    coal_done  = 0,
    coal_total = 0,
    lever_done = 0,
    lever_total = 0,
    battery_done  = 0,
    battery_total = 0,
    won = false,
}

-- Track which task objects sudah selesai (by object StringValue name / id)
local completedTasks: {[string]: boolean} = {}

-- ─────────────────────────────────────────────
--  Init: hitung totals berdasarkan level
-- ─────────────────────────────────────────────
local function initTaskCounts(level: number)
    local extra = math.max(0, level - 1) * Constants.TASK_ADD_PER_LEVEL
    taskState.coal_total    = Constants.TASK_COAL_COUNT    + extra
    taskState.lever_total   = Constants.TASK_LEVER_COUNT   + extra
    taskState.battery_total = Constants.TASK_BATTERY_COUNT + extra
    taskState.coal_done     = 0
    taskState.lever_done    = 0
    taskState.battery_done  = 0
    taskState.won           = false
    completedTasks          = {}
end

-- ─────────────────────────────────────────────
--  Broadcast progress ke semua player
-- ─────────────────────────────────────────────
local function broadcastProgress()
    RE_TaskProgress:FireAllClients({
        coal_done     = taskState.coal_done,
        coal_total    = taskState.coal_total,
        lever_done    = taskState.lever_done,
        lever_total   = taskState.lever_total,
        battery_done  = taskState.battery_done,
        battery_total = taskState.battery_total,
    })
end

-- ─────────────────────────────────────────────
--  Win condition check
-- ─────────────────────────────────────────────
local function checkWin()
    if taskState.won then return end

    local allDone =
        taskState.coal_done    >= taskState.coal_total    and
        taskState.lever_done   >= taskState.lever_total   and
        taskState.battery_done >= taskState.battery_total

    if allDone then
        taskState.won = true
        print("[TaskSystem] WIN — semua task selesai!")
        RE_GameWin:FireAllClients()

        -- Delay sebentar sebelum teleport ke lobby
        task.delay(5, function()
            for _, player in ipairs(Players:GetPlayers()) do
                local teleportService = game:GetService("TeleportService")
                teleportService:Teleport(Constants.LOBBY_PLACE_ID, player)
            end
        end)
    end
end

-- ─────────────────────────────────────────────
--  Handle task interaction dari client
--  payload = { taskType: string, taskId: string }
-- ─────────────────────────────────────────────
local function onTaskInteract(player: Player, payload: {taskType: string, taskId: string})
    if taskState.won then return end
    if not payload or not payload.taskType or not payload.taskId then return end

    local taskType = payload.taskType  -- "coal" | "lever" | "battery"
    local taskId   = payload.taskId    -- unique identifier for tiap task object

    -- Hindari double-complete
    if completedTasks[taskId] then return end

    -- Validasi player masih hidup
    local character = player.Character
    if not character then return end
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid or humanoid.Health <= 0 then return end

    -- Update counter sesuai type
    if taskType == "coal" and taskState.coal_done < taskState.coal_total then
        completedTasks[taskId] = true
        taskState.coal_done += 1
        print(string.format("[TaskSystem] Coal %d/%d — oleh %s", taskState.coal_done, taskState.coal_total, player.Name))

    elseif taskType == "lever" and taskState.lever_done < taskState.lever_total then
        completedTasks[taskId] = true
        taskState.lever_done += 1
        print(string.format("[TaskSystem] Lever %d/%d — oleh %s", taskState.lever_done, taskState.lever_total, player.Name))

    elseif taskType == "battery" and taskState.battery_done < taskState.battery_total then
        completedTasks[taskId] = true
        taskState.battery_done += 1
        print(string.format("[TaskSystem] Battery %d/%d — oleh %s", taskState.battery_done, taskState.battery_total, player.Name))

    else
        return -- type tidak dikenal / sudah penuh
    end

    broadcastProgress()
    checkWin()
end

RE_TaskInteract.OnServerEvent:Connect(onTaskInteract)

-- ─────────────────────────────────────────────
--  Sync state ke player yang baru join (late-join)
-- ─────────────────────────────────────────────
Players.PlayerAdded:Connect(function(player)
    -- Kirim state sekarang ke player ini saja
    RE_SyncState:FireClient(player, {
        coal_done     = taskState.coal_done,
        coal_total    = taskState.coal_total,
        lever_done    = taskState.lever_done,
        lever_total   = taskState.lever_total,
        battery_done  = taskState.battery_done,
        battery_total = taskState.battery_total,
        won           = taskState.won,
    })
end)

-- ─────────────────────────────────────────────
--  Setup ProximityPrompts dari Workspace task objects
--  Konvensi: setiap task object punya:
--    - Attribute "TaskType"  = "coal" | "lever" | "battery"
--    - Attribute "TaskId"    = unique string (misal: "Coal_01")
--    - Child ProximityPrompt (sudah dipasang di Studio)
-- ─────────────────────────────────────────────
local function hookTaskObject(obj: BasePart)
    local taskType = obj:GetAttribute("TaskType")
    local taskId   = obj:GetAttribute("TaskId")
    if not taskType or not taskId then return end

    local prompt = obj:FindFirstChildOfClass("ProximityPrompt")
        or obj:FindFirstChild("ProximityPrompt", true)
    if not prompt then
        -- Auto-create prompt jika belum ada
        prompt = Instance.new("ProximityPrompt")
        prompt.ActionText   = taskType:sub(1,1):upper() .. taskType:sub(2) -- capitalize
        prompt.ObjectText   = taskId
        prompt.HoldDuration = 1.5
        prompt.MaxActivationDistance = 8
        prompt.Parent = obj
    end

    prompt.Triggered:Connect(function(player: Player)
        -- Client juga bisa trigger langsung via server-side event ini
        onTaskInteract(player, { taskType = taskType, taskId = taskId })
    end)

    -- Disable prompt jika sudah selesai (hook buat completed-tasks)
    local function refreshPrompt()
        if completedTasks[taskId] then
            prompt.Enabled = false
            -- Visual feedback: ganti warna part
            if obj:IsA("BasePart") then
                obj.BrickColor = BrickColor.new("Bright green")
            end
        end
    end

    -- Poll setiap 0.5 detik (ringan)
    task.spawn(function()
        while not taskState.won do
            refreshPrompt()
            task.wait(0.5)
        end
    end)
end

-- ─────────────────────────────────────────────
--  Scan Workspace untuk task objects
-- ─────────────────────────────────────────────
local function scanTaskObjects()
    -- Cari di folder TaskObjects (buat folder ini di Workspace)
    local taskFolder = workspace:WaitForChild("TaskObjects", 10)
    if not taskFolder then
        warn("[TaskSystem] Folder 'TaskObjects' tidak ditemukan di Workspace!")
        return
    end

    for _, obj in ipairs(taskFolder:GetDescendants()) do
        if obj:IsA("BasePart") and obj:GetAttribute("TaskType") then
            hookTaskObject(obj)
        end
    end

    -- Watch for dynamically added task objects
    taskFolder.DescendantAdded:Connect(function(obj)
        if obj:IsA("BasePart") and obj:GetAttribute("TaskType") then
            hookTaskObject(obj)
        end
    end)
end

-- ─────────────────────────────────────────────
--  Public API (dipanggil oleh GameManager)
-- ─────────────────────────────────────────────
local TaskSystem = {}

function TaskSystem.init(level: number)
    initTaskCounts(level)
    broadcastProgress()
    scanTaskObjects()
    print(string.format(
        "[TaskSystem] Init level %d — Coal:%d Lever:%d Battery:%d",
        level,
        taskState.coal_total,
        taskState.lever_total,
        taskState.battery_total
    ))
end

function TaskSystem.getState()
    return taskState
end

return TaskSystem
