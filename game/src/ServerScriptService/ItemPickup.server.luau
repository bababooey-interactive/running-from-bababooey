-- =============================================================
--  ItemPickup.server.luau
--  ServerScriptService
-- =============================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local RE_PickupItem = Remotes:WaitForChild("PickupItem")
local RE_DropItem = Remotes:WaitForChild("DropItem")
local RE_EatFood = Remotes:WaitForChild("EatFood")
local RE_DepositCoal = Remotes:WaitForChild("DepositCoal")
local RE_HeldItemChanged = Remotes:WaitForChild("HeldItemChanged")
local RE_HungerChanged = Remotes:WaitForChild("HungerChanged")
local RE_ThrowBoulder = Remotes:WaitForChild("ThrowBoulder")

local SoundManager = require(script.Parent.SoundManager)
local TaskSystem = require(script.Parent.TaskSystem)
local SensorSystem = require(script.Parent.SensorSystem)

-- ── Config ─────────────────────────────────────────────────────
local HUNGER_RESTORE = {
	carrot = 20,
	meat = 40,
	waterbottle = 15,
}
local HUNGER_RESTORE_DEFAULT = 25
local FIREPLACE_DEPOSIT_RADIUS = 12
local THROW_FORCE = 65
local THROW_ARC = 15
local LANDING_NOISE = 0.85
local BOULDER_RESET_TIME = 8
local THROWABLE_BOULDER_NAMES = {
	boulder_small = true,
	boulder_medium = true,
}
local CARRY_WELD_OFFSET = CFrame.new(0, -0.15, -1.2) * CFrame.Angles(math.rad(-20), 0, 0)

-- ── State ──────────────────────────────────────────────────────
local heldItems = {}

-- ── Helpers ────────────────────────────────────────────────────

local function getRightHand(character)
	return character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")
end

local function getPrimaryOrFirstPart(model)
	if model:IsA("BasePart") then
		return model
	end
	if model:IsA("Model") then
		return model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
	end
	return nil
end

local function findFireplace()
	local genMap = Workspace:FindFirstChild("GeneratedMap")
	if genMap then
		for _, child in ipairs(genMap:GetDescendants()) do
			if child:IsA("Model") and child.Name:lower():find("fireplace") then
				return child
			end
		end
	end
	for _, desc in ipairs(Workspace:GetDescendants()) do
		if desc:IsA("Model") and desc.Name:lower():find("fireplace") then
			return desc
		end
	end
	return nil
end

local function getFireplacePosition()
	local fp = findFireplace()
	if not fp then
		return nil
	end
	local part = getPrimaryOrFirstPart(fp)
	if part then
		return part.Position
	end
	return fp:GetPivot().Position
end

local function isNearFireplace(character)
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then
		return false
	end
	local fpPos = getFireplacePosition()
	if not fpPos then
		return false
	end
	return (root.Position - fpPos).Magnitude <= FIREPLACE_DEPOSIT_RADIUS
end

-- Returns true if the model name looks like a waterbottle
local function isWaterItem(modelName: string): boolean
	return modelName:lower():find("water") ~= nil
end

local function weldItemToHand(character, itemModel)
	local hand = getRightHand(character)
	if not hand then
		return nil
	end

	local itemPart = getPrimaryOrFirstPart(itemModel)
	if not itemPart then
		return nil
	end

	for _, desc in ipairs(itemModel:GetDescendants()) do
		if desc:IsA("BasePart") then
			desc.Anchored = false
			desc.CanCollide = false
		end
	end
	itemPart.Anchored = false
	itemPart.CanCollide = false

	itemModel:PivotTo(hand.CFrame * CARRY_WELD_OFFSET)

	local weld = Instance.new("WeldConstraint")
	weld.Name = "CarryWeld"
	weld.Part0 = hand
	weld.Part1 = itemPart
	weld.Parent = itemPart

	if itemModel:IsA("Model") then
		for _, desc in ipairs(itemModel:GetDescendants()) do
			if desc:IsA("BasePart") and desc ~= itemPart then
				local iw = desc:FindFirstChild("InternalWeld")
				if not iw then
					iw = Instance.new("WeldConstraint")
					iw.Name = "InternalWeld"
					iw.Part0 = itemPart
					iw.Part1 = desc
					iw.Parent = desc
				end
			end
		end
	end

	return weld
end

local function unweldItem(playerData)
	if not playerData then
		return
	end
	local model = playerData.model
	local weld = playerData.weld

	if weld and weld.Parent then
		weld:Destroy()
	end

	if model and model.Parent then
		for _, desc in ipairs(model:GetDescendants()) do
			if desc:IsA("WeldConstraint") and desc.Name == "InternalWeld" then
				desc:Destroy()
			end
		end
		for _, desc in ipairs(model:GetDescendants()) do
			if desc:IsA("BasePart") then
				desc.Anchored = true
				desc.CanCollide = true
			end
		end
		local primary = getPrimaryOrFirstPart(model)
		if primary then
			primary.Anchored = true
			primary.CanCollide = true
		end
	end
end

local function restoreHunger(player, foodName)
	local restore = HUNGER_RESTORE[foodName:lower()] or HUNGER_RESTORE_DEFAULT
	local stats = player:FindFirstChild("Hunger")
		or (player:FindFirstChild("leaderstats") and player.leaderstats:FindFirstChild("Hunger"))
	if stats and stats:IsA("NumberValue") then
		stats.Value = math.min(100, stats.Value + restore)
	end
	RE_HungerChanged:FireClient(player, restore)
	print(string.format("[ItemPickup] %s ate %s (+%d hunger)", player.Name, foodName, restore))
end

-- ── Core: Pickup ───────────────────────────────────────────────

local function pickupItem(player, itemModel)
	if not player.Character then
		return false, "no_character"
	end
	if not itemModel or not itemModel.Parent then
		return false, "item_gone"
	end
	if heldItems[player] then
		return false, "already_holding"
	end

	local category
	local taskType = itemModel:GetAttribute("TaskType")
	if taskType == "coal" then
		category = "coal"
	else
		local parent = itemModel.Parent
		if parent and parent.Name == "FoodItems" then
			category = "food"
		elseif itemModel:GetAttribute("ItemCategory") == "food" then
			category = "food"
		else
			local name = itemModel.Name:lower()
			if name:find("carrot") or name:find("meat") or name:find("water") then
				category = "food"
			end
		end
	end

	if not category then
		local name = itemModel.Name:lower()
		if THROWABLE_BOULDER_NAMES[name] then
			category = "boulder"
		end
	end

	if not category then
		return false, "unknown_category"
	end

	for _, pp in ipairs(itemModel:GetDescendants()) do
		if pp:IsA("ProximityPrompt") then
			pp.Enabled = false
		end
	end

	itemModel.Parent = player.Character

	local weld = weldItemToHand(player.Character, itemModel)
	if not weld then
		itemModel.Parent = Workspace
		for _, pp in ipairs(itemModel:GetDescendants()) do
			if pp:IsA("ProximityPrompt") then
				pp.Enabled = true
			end
		end
		return false, "weld_failed"
	end

	heldItems[player] = { model = itemModel, category = category, weld = weld }
	RE_HeldItemChanged:FireAllClients(player, itemModel, category)

	local char = player.Character
	if char and char.PrimaryPart then
		SoundManager.itemPickup(char.PrimaryPart.Position)
		SensorSystem.AddNoise(player, char.PrimaryPart.Position, 0.5)
	end

	print(string.format("[ItemPickup] %s picked up %s (%s)", player.Name, itemModel.Name, category))
	return true
end

-- ── Core: Drop ─────────────────────────────────────────────────

local function dropItem(player)
	local data = heldItems[player]
	if not data then
		return
	end

	unweldItem(data)

	if player.Character then
		local root = player.Character:FindFirstChild("HumanoidRootPart")
		if root and data.model and data.model.Parent then
			data.model:PivotTo(root.CFrame * CFrame.new(0, -1, -3))
		end
	end

	if data.model and data.model.Parent then
		if data.category == "coal" then
			local taskFolder = Workspace:FindFirstChild("TaskObjects")
			data.model.Parent = taskFolder or Workspace
		else
			local foodFolder = Workspace:FindFirstChild("FoodItems")
			data.model.Parent = foodFolder or Workspace
		end

		for _, pp in ipairs(data.model:GetDescendants()) do
			if pp:IsA("ProximityPrompt") then
				pp.Enabled = true
			end
		end

		local dropPos = data.model:GetPivot().Position
		local itemName = data.model.Name

		if data.category == "coal" then
			SoundManager.coalDrop(dropPos)
			SensorSystem.AddAreaNoise(dropPos, 0.5, 30)
			SensorSystem.AddWorldNoise(dropPos, 0.5)
		elseif data.category == "boulder" then
			-- Boulder dropped (not thrown) — still makes a loud thud
			SoundManager.boulderHit(dropPos)
			SensorSystem.AddAreaNoise(dropPos, 0.7, 35)
			SensorSystem.AddWorldNoise(dropPos, 0.7)
		else
			-- Food items: waterbottle gets its own sound
			if isWaterItem(itemName) then
				SoundManager.waterDrop(dropPos)
			else
				SoundManager.foodDrop(dropPos)
			end
			SensorSystem.AddAreaNoise(dropPos, 0.35, 25)
			SensorSystem.AddWorldNoise(dropPos, 0.35)
		end
	end

	heldItems[player] = nil
	RE_HeldItemChanged:FireAllClients(player, nil, nil)
	print(string.format("[ItemPickup] %s dropped %s", player.Name, data.model and data.model.Name or "?"))
end

-- ── Core: Eat / Drink ──────────────────────────────────────────

local function eatFood(player)
	local data = heldItems[player]
	if not data or data.category ~= "food" then
		return
	end

	local foodName = data.model and data.model.Name or "unknown"

	-- Position for sound — grab before destroying the model
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local pos = root and root.Position or Vector3.zero

	unweldItem(data)
	if data.model and data.model.Parent then
		data.model:Destroy()
	end

	heldItems[player] = nil
	RE_HeldItemChanged:FireAllClients(player, nil, nil)

	-- Play eat or drink sound based on item type
	if isWaterItem(foodName) then
		SoundManager.drinkWater(pos)
	else
		SoundManager.eatFood(pos)
	end

	restoreHunger(player, foodName)
end

-- ── Core: Deposit Coal ─────────────────────────────────────────

local function depositCoal(player)
	local data = heldItems[player]
	if not data or data.category ~= "coal" then
		return
	end

	if not player.Character or not isNearFireplace(player.Character) then
		warn(string.format("[ItemPickup] %s tried to deposit coal but is too far from fireplace", player.Name))
		return
	end

	local coalModel = data.model
	local coalTaskId = coalModel and coalModel:GetAttribute("TaskId") or nil

	unweldItem(data)
	if coalModel and coalModel.Parent then
		coalModel:Destroy()
	end

	heldItems[player] = nil
	RE_HeldItemChanged:FireAllClients(player, nil, nil)

	if coalTaskId then
		TaskSystem.completeTask("coal", coalTaskId, player)
	else
		warn("[ItemPickup] Coal had no TaskId — using fallback id")
		local fallbackId = "coal_" .. player.UserId .. "_" .. tostring(os.clock())
		TaskSystem.completeTask("coal", fallbackId, player)
	end

	local fpPos = getFireplacePosition()
	if fpPos then
		SoundManager.coalIntoFireplace(fpPos)
	end

	print(string.format("[ItemPickup] %s deposited coal (TaskId=%s)", player.Name, tostring(coalTaskId)))
end

-- ── Core: Throw Boulder ────────────────────────────────────────

local function throwBoulder(player: Player)
	local data = heldItems[player]
	if not data or data.category ~= "boulder" then
		return
	end

	local boulderModel = data.model
	local boulderPart = getPrimaryOrFirstPart(boulderModel)
	if not boulderPart then
		return
	end

	unweldItem(data)
	heldItems[player] = nil
	RE_HeldItemChanged:FireAllClients(player, nil, nil)

	boulderModel.Parent = Workspace

	for _, desc in ipairs(boulderModel:GetDescendants()) do
		if desc:IsA("BasePart") then
			desc.Anchored = false
			desc.CanCollide = true
		end
	end
	boulderPart.Anchored = false

	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end

	local arcRad = math.rad(THROW_ARC)
	local forward = root.CFrame.LookVector
	local right = forward:Cross(Vector3.new(0, 1, 0)).Unit
	local arcDir = (CFrame.fromAxisAngle(right, arcRad) * forward).Unit

	boulderPart.AssemblyLinearVelocity = arcDir * THROW_FORCE

	local touchConn
	touchConn = boulderPart.Touched:Connect(function(hit)
		if char and hit:IsDescendantOf(char) then
			return
		end
		if boulderPart.AssemblyLinearVelocity.Magnitude > 5 then
			return
		end

		touchConn:Disconnect()

		-- Boulder landed — play impact sound and add world noise for monster
		SoundManager.boulderHit(boulderPart.Position)
		SensorSystem.AddAreaNoise(boulderPart.Position, LANDING_NOISE, 40)
		SensorSystem.AddWorldNoise(boulderPart.Position, LANDING_NOISE)
		print(string.format("[ItemPickup] %s's boulder landed — noise triggered", player.Name))

		task.delay(BOULDER_RESET_TIME, function()
			if boulderPart and boulderPart.Parent then
				boulderPart.Anchored = true
				boulderPart.AssemblyLinearVelocity = Vector3.zero
				local mapFolder = Workspace:FindFirstChild("GeneratedMap")
				if mapFolder then
					boulderModel.Parent = mapFolder
				end
			end
		end)

		task.delay(0.3, function()
			if boulderModel and boulderModel.Parent then
				boulderModel:Destroy()
			end
		end)
	end)
end

-- ── Remote Connections ─────────────────────────────────────────

RE_PickupItem.OnServerEvent:Connect(function(player, itemModel)
	if typeof(itemModel) ~= "Instance" then
		return
	end
	pickupItem(player, itemModel)
end)

RE_DropItem.OnServerEvent:Connect(function(player)
	dropItem(player)
end)

RE_EatFood.OnServerEvent:Connect(function(player)
	eatFood(player)
end)

RE_DepositCoal.OnServerEvent:Connect(function(player)
	depositCoal(player)
end)

RE_ThrowBoulder.OnServerEvent:Connect(function(player)
	throwBoulder(player)
end)

-- ── Cleanup on disconnect / character removal ───────────────────

Players.PlayerRemoving:Connect(function(player)
	local data = heldItems[player]
	if data then
		unweldItem(data)
		if data.model and data.model.Parent then
			data.model:Destroy()
		end
		heldItems[player] = nil
	end
end)

Players.PlayerAdded:Connect(function(player)
	player.CharacterRemoving:Connect(function()
		local data = heldItems[player]
		if data then
			unweldItem(data)
			if data.model and data.model.Parent then
				data.model:Destroy()
			end
			heldItems[player] = nil
			RE_HeldItemChanged:FireAllClients(player, nil, nil)
		end
	end)
end)

print("[ItemPickup] Server initialized.")
