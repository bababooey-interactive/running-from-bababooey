-- =============================================================
--  ItemInteract.client.luau
--  StarterPlayerScripts
--
--  Client-side untuk sistem pickup & carry:
--    1. Nampilin ProximityPrompt "Pick Up" di setiap food/coal item
--       (dibuat dynamic saat item spawn, bukan di MapGenerator)
--    2. Saat player pegang item:
--       - Food: nampilin BillboardGui "🍖 Tekan E untuk Makan"
--       - Coal: cek jarak fireplace setiap frame, nampilin prompt
--         "Drop Coal" saat sudah dekat
--    3. Kirim RemoteEvent ke server (PickupItem, EatFood, DepositCoal, DropItem)
--
--  CATATAN PENTING:
--    ProximityPrompt "Pick Up" TIDAK di-setup di MapGenerator lagi.
--    Script ini yang setup prompt untuk semua item di Workspace secara
--    otomatis saat item muncul (DescendantAdded), lalu menghubungkan
--    ke RemoteEvent PickupItem.
-- =============================================================

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")
local CollectionService = game:GetService("CollectionService")

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
local FIREPLACE_DEPOSIT_RADIUS = 12  -- harus sama dengan server
local PICKUP_RADIUS            = 6   -- jarak ProximityPrompt muncul
local COAL_DEPOSIT_KEY         = Enum.KeyCode.F  -- tekan F untuk deposit
local EAT_KEY                  = Enum.KeyCode.E  -- tekan E untuk makan

-- ── State ──────────────────────────────────────────────────────
local heldItem     = nil   -- Model yang sedang dipegang
local heldCategory = nil   -- "food" | "coal" | nil

local eatGui       = nil   -- BillboardGui "Eat" yang menempel di item
local depositGui   = nil   -- ScreenGui prompt "Drop Coal"

local promptConnections = {} -- { [model] = connection } untuk cleanup

-- ── Helpers ────────────────────────────────────────────────────

local function getPrimaryOrFirstPart(model)
	if model.PrimaryPart then
		return model.PrimaryPart
	end
	return model:FindFirstChildWhichIsA("BasePart")
end

local function findFireplacePosition()
	local genMap = Workspace:FindFirstChild("GeneratedMap")
	if genMap then
		for _, child in ipairs(genMap:GetDescendants()) do
			if child:IsA("Model") and child.Name:lower():find("fireplace") then
				local part = getPrimaryOrFirstPart(child)
				if part then
					return part.Position
				end
			end
		end
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

-- ── GUI Builders ───────────────────────────────────────────────

-- BillboardGui yang nempel di atas item yang dipegang
local function createEatGui(itemModel)
	if eatGui then eatGui:Destroy() end

	local part = getPrimaryOrFirstPart(itemModel)
	if not part then return end

	local gui = Instance.new("BillboardGui")
	gui.Name            = "EatPrompt"
	gui.Adornee         = part
	gui.Size            = UDim2.new(0, 160, 0, 40)
	gui.StudsOffset     = Vector3.new(0, 2.5, 0)
	gui.AlwaysOnTop     = true
	gui.ResetOnSpawn    = false

	local frame = Instance.new("Frame")
	frame.Size            = UDim2.new(1, 0, 1, 0)
	frame.BackgroundColor3 = Color3.fromRGB(30, 20, 10)
	frame.BackgroundTransparency = 0.25
	frame.BorderSizePixel = 0
	frame.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = frame

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Text = string.format("[E] Makan  ·  [Q] Drop")
	label.TextColor3 = Color3.fromRGB(255, 230, 160)
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.Parent = frame

	gui.Parent = player.PlayerGui
	eatGui = gui
end

-- ScreenGui untuk tombol deposit coal (muncul saat dekat fireplace)
local function createDepositGui()
	if depositGui then return end  -- sudah ada

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name         = "CoalDepositPrompt"
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local frame = Instance.new("Frame")
	frame.Name                   = "Prompt"
	frame.Size                   = UDim2.new(0, 220, 0, 50)
	frame.Position               = UDim2.new(0.5, -110, 0.82, 0)
	frame.BackgroundColor3       = Color3.fromRGB(40, 25, 10)
	frame.BackgroundTransparency = 0.15
	frame.BorderSizePixel        = 0
	frame.Parent = screenGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.Color     = Color3.fromRGB(255, 140, 0)
	stroke.Thickness = 2
	stroke.Parent    = frame

	local label = Instance.new("TextLabel")
	label.Size                 = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Text                 = "🔥  [F] Lempar Coal ke Api"
	label.TextColor3           = Color3.fromRGB(255, 200, 80)
	label.TextScaled           = true
	label.Font                 = Enum.Font.GothamBold
	label.Parent               = frame

	screenGui.Parent = player.PlayerGui
	depositGui = screenGui
end

local function destroyDepositGui()
	if depositGui then
		depositGui:Destroy()
		depositGui = nil
	end
end

local function destroyEatGui()
	if eatGui then
		eatGui:Destroy()
		eatGui = nil
	end
end

-- ── Item Detection & ProximityPrompt Setup ─────────────────────

-- Tentukan apakah suatu Model adalah item yang bisa dipickup
local function isPickupable(model)
	if not model:IsA("Model") then return false, nil end

	-- Coal
	local taskType = model:GetAttribute("TaskType")
	if taskType == "coal" then
		return true, "coal"
	end

	-- Food: parent folder bernama FoodItems
	local parent = model.Parent
	if parent and parent.Name == "FoodItems" then
		return true, "food"
	end

	-- Food: attribute eksplisit
	if model:GetAttribute("ItemCategory") == "food" then
		return true, "food"
	end

	-- Food: nama
	local name = model.Name:lower()
	if name:find("carrot") or name:find("meat") or name:find("water") then
		-- Double-check: ada di Workspace/FoodItems atau TaskObjects? Tidak
		-- Kita butuh lebih strict supaya tidak pickup random props.
		-- Hanya pickup kalau ada di FoodItems folder
		if parent and parent.Name == "FoodItems" then
			return true, "food"
		end
	end

	return false, nil
end

local function setupPickupPrompt(model)
	-- Jangan re-setup kalau sudah ada
	if promptConnections[model] then
		return
	end

	local pickupable, category = isPickupable(model)
	if not pickupable then
		return
	end

	local targetPart = getPrimaryOrFirstPart(model)
	if not targetPart then
		return
	end

	-- Label sesuai kategori
	local actionText = category == "coal" and "Ambil" or "Ambil"
	local objectText = category == "coal" and "🪨 Coal" or "🍖 " .. model.Name

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name               = "PickupPrompt"
	prompt.ActionText         = actionText
	prompt.ObjectText         = objectText
	prompt.KeyboardKeyCode    = Enum.KeyCode.E
	prompt.HoldDuration       = 0
	prompt.MaxActivationDistance = PICKUP_RADIUS
	prompt.RequiresLineOfSight = false
	prompt.Parent             = targetPart

	-- Trigger: kirim ke server
	local conn = prompt.Triggered:Connect(function()
		if heldItem then
			-- Sudah pegang sesuatu, jangan pickup lagi
			return
		end
		RE_PickupItem:FireServer(model)
	end)

	-- Simpan connection supaya bisa di-cleanup
	promptConnections[model] = {
		prompt = prompt,
		conn   = conn,
	}
end

local function cleanupPickupPrompt(model)
	local data = promptConnections[model]
	if data then
		if data.conn then data.conn:Disconnect() end
		if data.prompt and data.prompt.Parent then data.prompt:Destroy() end
		promptConnections[model] = nil
	end
end

-- Setup prompt untuk semua item yang sudah ada di Workspace
local function scanExistingItems()
	-- Scan FoodItems folder
	local foodFolder = Workspace:FindFirstChild("FoodItems")
	if foodFolder then
		for _, child in ipairs(foodFolder:GetChildren()) do
			setupPickupPrompt(child)
		end
	end

	-- Scan TaskObjects (untuk coal)
	local taskFolder = Workspace:FindFirstChild("TaskObjects")
	if taskFolder then
		for _, child in ipairs(taskFolder:GetDescendants()) do
			if child:IsA("Model") and child:GetAttribute("TaskType") == "coal" then
				setupPickupPrompt(child)
			end
		end
	end
end

-- Watch untuk item baru yang spawn (saat map di-generate ulang)
Workspace.DescendantAdded:Connect(function(desc)
	if desc:IsA("Model") then
		task.defer(function()
			-- task.defer supaya attribute sempat di-set dulu
			if desc.Parent then
				setupPickupPrompt(desc)
			end
		end)
	end
end)

Workspace.DescendantRemoving:Connect(function(desc)
	if desc:IsA("Model") then
		cleanupPickupPrompt(desc)
	end
end)

-- ── Held Item State ────────────────────────────────────────────

RE_HeldItemChanged.OnClientEvent:Connect(function(whoPlayer, itemModel, category)
	if whoPlayer ~= player then
		-- Bisa dipakai untuk animasi tangan orang lain di masa depan
		return
	end

	heldItem     = itemModel
	heldCategory = category

	if not itemModel then
		-- Tidak pegang apa-apa
		destroyEatGui()
		destroyDepositGui()
		return
	end

	if category == "food" then
		createEatGui(itemModel)
	elseif category == "coal" then
		destroyEatGui()
		-- depositGui akan muncul/hilang di RunService loop sesuai jarak
	end
end)

-- ── Per-Frame Update (cek jarak fireplace untuk coal) ──────────

RunService.Heartbeat:Connect(function()
	if heldCategory ~= "coal" then
		if depositGui then destroyDepositGui() end
		return
	end

	if isNearFireplace() then
		createDepositGui()
	else
		destroyDepositGui()
	end
end)

-- ── Input Handler (E = Eat, F = Deposit, Q = Drop) ─────────────

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end

	-- E: makan food yang dipegang
	if input.KeyCode == EAT_KEY and heldCategory == "food" then
		RE_EatFood:FireServer()
		return
	end

	-- F: deposit coal ke fireplace
	if input.KeyCode == COAL_DEPOSIT_KEY and heldCategory == "coal" then
		if isNearFireplace() then
			RE_DepositCoal:FireServer()
		end
		return
	end

	-- Q: drop item yang dipegang
	if input.KeyCode == Enum.KeyCode.Q and heldItem then
		RE_DropItem:FireServer()
		return
	end
end)

-- ── Character refresh ──────────────────────────────────────────

player.CharacterAdded:Connect(function(newChar)
	character = newChar
	heldItem     = nil
	heldCategory = nil
	destroyEatGui()
	destroyDepositGui()
end)

-- ── Initial scan (tunggu map selesai generate) ─────────────────

task.wait(3)  -- beri waktu MapGenerator selesai
scanExistingItems()

print("[ItemInteract] Client initialized.")
