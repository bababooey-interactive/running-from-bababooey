-- =============================================================
--  ItemInteract.client.luau
--  📁 game/src/StarterPlayer/StarterPlayerScripts/ItemInteract.client.luau
--  🔧 GANTI SELURUH ISI file lama
-- =============================================================

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")

local player    = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local Remotes   = ReplicatedStorage:WaitForChild("Remotes")

-- ── Remote Events ──────────────────────────────────────────────
local RE_PickupItem      = Remotes:WaitForChild("PickupItem")
local RE_DropItem        = Remotes:WaitForChild("DropItem")
local RE_EatFood         = Remotes:WaitForChild("EatFood")
local RE_DepositCoal     = Remotes:WaitForChild("DepositCoal")
local RE_HeldItemChanged = Remotes:WaitForChild("HeldItemChanged")

-- ── Config ─────────────────────────────────────────────────────
local FIREPLACE_DEPOSIT_RADIUS = 12
local PICKUP_RADIUS            = 5

-- ── State ──────────────────────────────────────────────────────
local heldItem     = nil
local heldCategory = nil
local eatGui       = nil
local depositGui   = nil
local promptSetup  = {}

-- ── Helpers ────────────────────────────────────────────────────

local function getPrimaryOrFirstPart(model)
	if not model then return nil end
	if model:IsA("BasePart") then return model end
	if model.PrimaryPart then return model.PrimaryPart end
	return model:FindFirstChildWhichIsA("BasePart")
end

local function findFireplacePosition()
	local genMap = Workspace:FindFirstChild("GeneratedMap")
	if genMap then
		for _, child in ipairs(genMap:GetDescendants()) do
			if child:IsA("Model") and child.Name:lower():find("fireplace") then
				local part = getPrimaryOrFirstPart(child)
				if part then return part.Position end
			end
		end
	end
	local fp = Workspace:FindFirstChild("old_fireplace_prop")
	if fp then
		local part = getPrimaryOrFirstPart(fp)
		if part then return part.Position end
	end
	return nil
end

local function isNearFireplace()
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then return false end
	local fpPos = findFireplacePosition()
	if not fpPos then return false end
	return (root.Position - fpPos).Magnitude <= FIREPLACE_DEPOSIT_RADIUS
end

local function getItemCategory(model)
	if not model or not model:IsA("Model") then return nil end

	local taskType = model:GetAttribute("TaskType")
	if taskType == "coal" then return "coal" end

	-- Telusur parent chain cari folder FoodItems
	local p = model.Parent
	while p do
		if p.Name == "FoodItems" then return "food" end
		p = p.Parent
	end

	if model:GetAttribute("ItemCategory") == "food" then return "food" end

	return nil
end

-- ── GUI ────────────────────────────────────────────────────────

local function createEatGui(itemModel)
	if eatGui then eatGui:Destroy() end
	local part = getPrimaryOrFirstPart(itemModel)
	if not part then return end

	local gui = Instance.new("BillboardGui")
	gui.Name         = "EatPrompt"
	gui.Adornee      = part
	gui.Size         = UDim2.new(0, 200, 0, 44)
	gui.StudsOffset  = Vector3.new(0, 3, 0)
	gui.AlwaysOnTop  = true
	gui.ResetOnSpawn = false

	local frame = Instance.new("Frame")
	frame.Size                   = UDim2.new(1, 0, 1, 0)
	frame.BackgroundColor3       = Color3.fromRGB(30, 20, 10)
	frame.BackgroundTransparency = 0.2
	frame.BorderSizePixel        = 0
	frame.Parent = gui
	Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 8)

	local label = Instance.new("TextLabel")
	label.Size                   = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Text                   = "[E] Makan   [Q] Drop"
	label.TextColor3             = Color3.fromRGB(255, 230, 160)
	label.TextScaled             = true
	label.Font                   = Enum.Font.GothamBold
	label.Parent                 = frame

	gui.Parent = player.PlayerGui
	eatGui = gui
end

local function createDepositGui()
	if depositGui then return end

	local sg = Instance.new("ScreenGui")
	sg.Name         = "CoalDepositPrompt"
	sg.ResetOnSpawn = false

	local frame = Instance.new("Frame")
	frame.Size                   = UDim2.new(0, 240, 0, 54)
	frame.Position               = UDim2.new(0.5, -120, 0.82, 0)
	frame.BackgroundColor3       = Color3.fromRGB(40, 25, 10)
	frame.BackgroundTransparency = 0.15
	frame.BorderSizePixel        = 0
	frame.Parent = sg
	Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 10)

	local stroke = Instance.new("UIStroke")
	stroke.Color     = Color3.fromRGB(255, 140, 0)
	stroke.Thickness = 2
	stroke.Parent    = frame

	local label = Instance.new("TextLabel")
	label.Size                   = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Text                   = "🔥  [F] Lempar Coal ke Api"
	label.TextColor3             = Color3.fromRGB(255, 200, 80)
	label.TextScaled             = true
	label.Font                   = Enum.Font.GothamBold
	label.Parent                 = frame

	sg.Parent = player.PlayerGui
	depositGui = sg
end

local function destroyDepositGui()
	if depositGui then depositGui:Destroy(); depositGui = nil end
end

local function destroyEatGui()
	if eatGui then eatGui:Destroy(); eatGui = nil end
end

-- ── Setup ProximityPrompt per item ─────────────────────────────

local function setupPrompt(model)
	if promptSetup[model] then return end
	local category = getItemCategory(model)
	if not category then return end

	local targetPart = getPrimaryOrFirstPart(model)
	if not targetPart then return end

	-- Hapus prompt lama (dari MapGenerator/hookFoodItem)
	for _, pp in ipairs(model:GetDescendants()) do
		if pp:IsA("ProximityPrompt") then pp:Destroy() end
	end

	local objectText = category == "coal" and "🪨 Coal" or "🍖 " .. model.Name

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText            = "Ambil"
	prompt.ObjectText            = objectText
	prompt.KeyboardKeyCode       = Enum.KeyCode.E
	prompt.HoldDuration          = 0
	prompt.MaxActivationDistance = PICKUP_RADIUS
	prompt.RequiresLineOfSight   = false
	prompt.Parent                = targetPart

	prompt.Triggered:Connect(function()
		if heldItem then return end
		RE_PickupItem:FireServer(model)
	end)

	promptSetup[model] = true

	model.AncestryChanged:Connect(function()
		if not model.Parent then
			promptSetup[model] = nil
		end
	end)
end

-- ── Scan folder ────────────────────────────────────────────────

local function scanFolder(folder)
	if not folder then return end
	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("Model") then setupPrompt(child) end
		-- juga scan 1 level dalam (untuk subfolder TaskObjects/Coal/...)
		if child:IsA("Folder") then
			for _, grandchild in ipairs(child:GetChildren()) do
				if grandchild:IsA("Model") then setupPrompt(grandchild) end
			end
		end
	end
	folder.ChildAdded:Connect(function(child)
		task.defer(function()
			if child and child.Parent then
				if child:IsA("Model") then setupPrompt(child) end
				if child:IsA("Folder") then
					for _, gc in ipairs(child:GetChildren()) do
						if gc:IsA("Model") then setupPrompt(gc) end
					end
				end
			end
		end)
	end)
end

local function doScan()
	scanFolder(Workspace:FindFirstChild("FoodItems"))
	scanFolder(Workspace:FindFirstChild("TaskObjects"))
end

-- Watch kalau folder belum ada saat script jalan
Workspace.ChildAdded:Connect(function(child)
	if child.Name == "FoodItems" or child.Name == "TaskObjects" then
		task.wait(0.5)
		scanFolder(child)
	end
end)

doScan()

-- ── HeldItemChanged ────────────────────────────────────────────

RE_HeldItemChanged.OnClientEvent:Connect(function(whoPlayer, itemModel, category)
	if whoPlayer ~= player then return end
	heldItem     = itemModel
	heldCategory = category

	if not itemModel then
		destroyEatGui()
		destroyDepositGui()
		return
	end

	if category == "food" then
		createEatGui(itemModel)
	else
		destroyEatGui()
	end
end)

-- ── Per-frame cek jarak fireplace ──────────────────────────────

RunService.Heartbeat:Connect(function()
	if heldCategory ~= "coal" then
		if depositGui then destroyDepositGui() end
		return
	end
	if isNearFireplace() then createDepositGui()
	else destroyDepositGui() end
end)

-- ── Input ──────────────────────────────────────────────────────

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if input.KeyCode == Enum.KeyCode.E and heldCategory == "food" then
		RE_EatFood:FireServer()
	elseif input.KeyCode == Enum.KeyCode.F and heldCategory == "coal" then
		if isNearFireplace() then RE_DepositCoal:FireServer() end
	elseif input.KeyCode == Enum.KeyCode.Q and heldItem then
		RE_DropItem:FireServer()
	end
end)

-- ── Character refresh ──────────────────────────────────────────

player.CharacterAdded:Connect(function(newChar)
	character    = newChar
	heldItem     = nil
	heldCategory = nil
	destroyEatGui()
	destroyDepositGui()
	task.wait(1)
	doScan()
end)

print("[ItemInteract] Client initialized.")
