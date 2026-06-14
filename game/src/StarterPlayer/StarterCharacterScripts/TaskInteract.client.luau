-- =============================================================
--  TaskInteract.client.luau
--  Fallback client-side task trigger (untuk Touch-based task jika butuh)
--  ProximityPrompt sudah di-hook di server — script ini untuk Touch trigger
--  Path: game/src/StarterPlayerScripts/TaskInteract.client.luau
-- =============================================================

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes        = ReplicatedStorage:WaitForChild("Remotes")
local RE_TaskInteract = Remotes:WaitForChild("TaskInteract")
local RE_EatFood      = Remotes:WaitForChild("EatFood")

local LocalPlayer = Players.LocalPlayer

-- ─────────────────────────────────────────────
--  Hook Touch events untuk task objects
--  (Alternatif / tambahan dari ProximityPrompt server-side)
-- ─────────────────────────────────────────────
local function hookTouchTask(obj: BasePart)
    local taskType = obj:GetAttribute("TaskType")
    local taskId   = obj:GetAttribute("TaskId")
    local isTouch  = obj:GetAttribute("UseTouchTrigger")  -- true = pakai Touch

    if not taskType or not taskId or not isTouch then return end

    obj.Touched:Connect(function(hit)
        -- Pastikan yang touch adalah character LocalPlayer
        local character = LocalPlayer.Character
        if not character then return end
        if not hit:IsDescendantOf(character) then return end

        RE_TaskInteract:FireServer({ taskType = taskType, taskId = taskId })
    end)
end

-- ─────────────────────────────────────────────
--  Hook Food pickups (item dengan Attribute "IsFood" = true)
-- ─────────────────────────────────────────────
local function hookFood(obj: BasePart)
    if not obj:GetAttribute("IsFood") then return end

    obj.Touched:Connect(function(hit)
        local character = LocalPlayer.Character
        if not character then return end
        if not hit:IsDescendantOf(character) then return end

        RE_EatFood:FireServer()

        -- Hapus item food dari workspace
        obj:Destroy()
    end)
end

-- ─────────────────────────────────────────────
--  Scan Workspace
-- ─────────────────────────────────────────────
local function scan(folder: Instance)
    for _, obj in ipairs(folder:GetDescendants()) do
        if obj:IsA("BasePart") then
            hookTouchTask(obj)
            hookFood(obj)
        end
    end
    folder.DescendantAdded:Connect(function(obj)
        if obj:IsA("BasePart") then
            hookTouchTask(obj)
            hookFood(obj)
        end
    end)
end

-- Task objects
local taskFolder = workspace:WaitForChild("TaskObjects", 10)
if taskFolder then
    scan(taskFolder)
end

-- Food items
local foodFolder = workspace:FindFirstChild("FoodItems")
if foodFolder then
    scan(foodFolder)
end
