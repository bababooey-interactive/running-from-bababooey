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

-- ─────────────────────────────────────────────
--  Boulder Pickup & Throw (terintegrasi dengan ItemPickup.server)
-- ─────────────────────────────────────────────
local UserInputService = game:GetService("UserInputService")
local RunService       = game:GetService("RunService")

local RE_PickupItem  = Remotes:WaitForChild("PickupItem")
local RE_DropItem    = Remotes:WaitForChild("DropItem")
local RE_ThrowBoulder = Remotes:WaitForChild("ThrowBoulder")

local MAX_BOULDER_DIST = 12
local THROWABLE_NAMES  = { boulder_small = true, boulder_medium = true }

local nearbyBoulder: BasePart? = nil
local isHoldingBoulder = false

-- Highlight
local highlight = Instance.new("SelectionBox")
highlight.Color3 = Color3.fromRGB(255, 220, 80)
highlight.LineThickness = 0.05
highlight.SurfaceTransparency = 0.8
highlight.SurfaceColor3 = Color3.fromRGB(255, 220, 80)
highlight.Parent = workspace

-- Cari boulder terdekat di GeneratedMap
local function findNearbyBoulder(): BasePart?
    if isHoldingBoulder then return nil end
    local char = LocalPlayer.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not root then return nil end

    local mapFolder = workspace:FindFirstChild("GeneratedMap")
    if not mapFolder then return nil end

    local closest, closestDist = nil, MAX_BOULDER_DIST
    for _, obj in ipairs(mapFolder:GetDescendants()) do
        if obj:IsA("BasePart") and THROWABLE_NAMES[obj.Name:lower()] and obj.Anchored then
            local dist = (root.Position - obj.Position).Magnitude
            if dist < closestDist then
                closestDist = dist
                closest = obj
            end
        end
    end
    return closest
end

-- Input
UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end

    if input.KeyCode == Enum.KeyCode.E then
        if isHoldingBoulder then
            -- Drop
            RE_DropItem:FireServer()
            isHoldingBoulder = false
            highlight.Adornee = nil
        elseif nearbyBoulder then
            -- Pickup: boulder adalah Model atau Part, kirim parent Model-nya
            local target = nearbyBoulder
            -- Kalau Part, cari parent Model-nya
            if not target:IsA("Model") then
                local parent = target.Parent
                if parent and parent:IsA("Model") then
                    target = parent
                end
            end
            RE_PickupItem:FireServer(target)
            isHoldingBoulder = true
            highlight.Adornee = nil
        end
    end

    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        if isHoldingBoulder then
            RE_ThrowBoulder:FireServer()
            isHoldingBoulder = false
        end
    end
end)

-- Update highlight tiap frame
RunService.RenderStepped:Connect(function()
    if isHoldingBoulder then
        highlight.Adornee = nil
        return
    end
    local nearby = findNearbyBoulder()
    if nearby ~= nearbyBoulder then
        nearbyBoulder = nearby
        highlight.Adornee = nearby
    end
end)

-- Reset saat karakter respawn
LocalPlayer.CharacterAdded:Connect(function()
    isHoldingBoulder = false
    nearbyBoulder = nil
    highlight.Adornee = nil
end)