-- =============================================================
--  ItemPickup.server.luau
--  ServerScriptService
--
--  Mengelola sistem "pickup & carry" untuk:
--    - FoodItems (carrot, meat, waterbottle) → dipegang → dimakan
--    - Coal (TaskObject) → dipegang → di-drop di fireplace
--
--  ARSITEKTUR:
--    Server: physics (weld/unweld), state per-player, damage/hunger logic
--    Client (ItemInteract.client.luau): UI prompt "Eat"/"Drop Coal"
--
--  REMOTE EVENTS (semua di ReplicatedStorage/Remotes):
--    PickupItem       C→S  player minta pickup item (arg: Model)
--    DropItem         C→S  player minta drop item yang dipegang
--    EatFood          C→S  player minta makan food yang dipegang
--    DepositCoal      C→S  player minta deposit coal ke fireplace
--    HeldItemChanged  S→C  broadcast item yang sedang dipegang player
--                          (arg: player, itemModel | nil, itemCategory)
--
--  NOTES:
--    - Satu player hanya bisa pegang SATU item sekaligus.
--    - Coal yang sudah di-deposit dihapus dari dunia + TaskSystem dikasih tahu.
--    - EatFood restore hunger lewat RemoteEvent "HungerChanged" yang
--      sudah dipakai SurvivalSystem.
-- =============================================================

local Players          = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace        = game:GetService("Workspace")

local Remotes = ReplicatedStorage:WaitForChild("Remotes")

-- ── Remote Events ──────────────────────────────────────────────
local RE_PickupItem      = Remotes:WaitForChild("PickupItem")
local RE_DropItem        = Remotes:WaitForChild("DropItem")
local RE_EatFood         = Remotes:WaitForChild("EatFood")
local RE_DepositCoal     = Remotes:WaitForChild("DepositCoal")
local RE_HeldItemChanged = Remotes:WaitForChild("HeldItemChanged")
local RE_HungerChanged   = Remotes:WaitForChild("HungerChanged")   -- dari SurvivalSystem
local RE_CoalDeposited   = Remotes:WaitForChild("CoalDeposited")   -- ke TaskSystem

-- ── Config ─────────────────────────────────────────────────────
local HUNGER_RESTORE = {
	carrot      = 20,
	meat        = 40,
	waterbottle = 15,
}
local HUNGER_RESTORE_DEFAULT = 25

-- Radius proximity agar prompt "Drop Coal" muncul saat dekat fireplace
-- (dicek client-side lewat HeldItemChanged, server verify saat DepositCoal)
local FIREPLACE_DEPOSIT_RADIUS = 12 -- studs

-- Weld offset: item muncul di depan tangan kanan, sedikit terangkat
local CARRY_WELD_OFFSET = CFrame.new(0, -0.15, -1.2)
                        * CFrame.Angles(math.rad(-20), 0, 0)

-- ── State ──────────────────────────────────────────────────────
-- heldItems[player] = { model = Model, category = "food"|"coal", weld = WeldConstraint }
local heldItems = {}

-- ── Helpers ────────────────────────────────────────────────────

local function getRightHand(character)
	return character:FindFirstChild("RightHand")
		or character:FindFirstChild("Right Arm") -- R15 vs R6 fallback
end

local function getPrimaryOrFirstPart(model)
	if model.PrimaryPart then
		return model.PrimaryPart
	end
	return model:FindFirstChildWhichIsA("BasePart")
end

-- Cari fireplace di Workspace (Model bernama "old_fireplace_prop" atau
-- parent folder "GeneratedMap"). Fireplace di-spawn MapGenerator di
-- GeneratedMap folder.
local function findFireplace()
	local genMap = Workspace:FindFirstChild("GeneratedMap")
	if genMap then
		-- Cari secara rekursif di GeneratedMap
		for _, child in ipairs(genMap:GetDescendants()) do
			if child:IsA("Model") and child.Name:lower():find("fireplace") then
				return child
			end
		end
	end
	-- Fallback: cari langsung di Workspace
	return Workspace:FindFirstChild("old_fireplace_prop")
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
	return nil
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

-- Buat WeldConstraint antara item ke RightHand
local function weldItemToHand(character, itemModel)
	local hand = getRightHand(character)
	if not hand then
		return nil
	end

	local itemPart = getPrimaryOrFirstPart(itemModel)
	if not itemPart then
		return nil
	end

	-- Unanchor semua part agar bisa di-weld
	for _, desc in ipairs(itemModel:GetDescendants()) do
		if desc:IsA("BasePart") then
			desc.Anchored = false
			desc.CanCollide = false
		end
	end
	itemPart.Anchored = false
	itemPart.CanCollide = false

	-- Posisikan item di depan tangan terlebih dahulu
	itemModel:PivotTo(hand.CFrame * CARRY_WELD_OFFSET)

	-- WeldConstraint: item mengikuti tangan
	local weld = Instance.new("WeldConstraint")
	weld.Name = "CarryWeld"
	weld.Part0 = hand
	weld.Part1 = itemPart
	weld.Parent = itemPart

	return weld
end

-- Lepas item dari tangan player (untuk drop atau makan)
local function unweldItem(playerData)
	if not playerData then
		return
	end

	local model = playerData.model
	local weld  = playerData.weld

	if weld and weld.Parent then
		weld:Destroy()
	end

	-- Re-anchor & re-enable collision supaya item duduk di dunia lagi
	if model and model.Parent then
		for _, desc in ipairs(model:GetDescendants()) do
			if desc:IsA("BasePart") then
				desc.Anchored = true
				desc.CanCollide = true
			end
		end
		-- Re-anchor PrimaryPart
		local primary = getPrimaryOrFirstPart(model)
		if primary then
			primary.Anchored = true
			primary.CanCollide = true
		end
	end
end

-- Restorasi hunger ke player
local function restoreHunger(player, foodName)
	local restore = HUNGER_RESTORE[foodName:lower()] or HUNGER_RESTORE_DEFAULT

	-- Kirim ke SurvivalSystem lewat RemoteEvent (server → server via BindableEvent
	-- ATAU langsung update leaderstats / value). Kita pakai pendekatan broadcast
	-- ke client dulu, SurvivalSystem server yang decide final value.
	--
	-- Jika SurvivalSystem kamu punya BindableEvent atau function global,
	-- ganti bagian ini. Default: update Value di player lewat leaderstats.
	local stats = player:FindFirstChild("Hunger")
		or (player:FindFirstChild("leaderstats") and player.leaderstats:FindFirstChild("Hunger"))

	if stats and stats:IsA("NumberValue") then
		stats.Value = math.min(100, stats.Value + restore)
	end

	-- Broadcast hunger change ke client player tersebut
	RE_HungerChanged:FireClient(player, restore)

	print(string.format("[ItemPickup] %s makan %s (+%d hunger)", player.Name, foodName, restore))
end

-- ── Core: Pickup ───────────────────────────────────────────────

local function pickupItem(player, itemModel)
	if not player.Character then
		return false, "no_character"
	end

	-- Validasi: item masih ada di dunia
	if not itemModel or not itemModel.Parent then
		return false, "item_gone"
	end

	-- Validasi: player tidak sedang pegang item lain
	if heldItems[player] then
		return false, "already_holding"
	end

	-- Tentukan kategori item
	local category
	local taskType = itemModel:GetAttribute("TaskType")
	if taskType == "coal" then
		category = "coal"
	else
		-- Cek apakah ada di folder FoodItems atau punya tag food
		local parent = itemModel.Parent
		if parent and parent.Name == "FoodItems" then
			category = "food"
		elseif itemModel:GetAttribute("ItemCategory") == "food" then
			category = "food"
		else
			-- Fallback: cek nama
			local name = itemModel.Name:lower()
			if name:find("carrot") or name:find("meat") or name:find("water") then
				category = "food"
			end
		end
	end

	if not category then
		return false, "unknown_item"
	end

	-- Disable semua ProximityPrompt di item (tidak perlu lagi saat sudah dipegang)
	for _, pp in ipairs(itemModel:GetDescendants()) do
		if pp:IsA("ProximityPrompt") then
			pp.Enabled = false
		end
	end

	-- Pindahkan item ke character (supaya tidak ke-destroy saat map di-clear)
	itemModel.Parent = player.Character

	-- Weld ke tangan
	local weld = weldItemToHand(player.Character, itemModel)
	if not weld then
		-- Gagal weld, kembalikan ke Workspace
		itemModel.Parent = Workspace
		-- Re-enable prompts
		for _, pp in ipairs(itemModel:GetDescendants()) do
			if pp:IsA("ProximityPrompt") then
				pp.Enabled = true
			end
		end
		return false, "weld_failed"
	end

	heldItems[player] = {
		model    = itemModel,
		category = category,
		weld     = weld,
	}

	-- Broadcast ke semua client (untuk UI feedback & nametag)
	RE_HeldItemChanged:FireAllClients(player, itemModel, category)

	print(string.format("[ItemPickup] %s pickup %s (%s)", player.Name, itemModel.Name, category))
	return true
end

-- ── Core: Drop ─────────────────────────────────────────────────

local function dropItem(player)
	local data = heldItems[player]
	if not data then
		return
	end

	unweldItem(data)

	-- Posisikan di depan player
	if player.Character then
		local root = player.Character:FindFirstChild("HumanoidRootPart")
		if root and data.model and data.model.Parent then
			local dropCF = root.CFrame * CFrame.new(0, -1, -3)
			data.model:PivotTo(dropCF)
		end
	end

	-- Kembalikan ke Workspace (keluar dari character)
	if data.model and data.model.Parent then
		-- Tentukan parent yang tepat berdasarkan kategori
		if data.category == "coal" then
			local taskFolder = Workspace:FindFirstChild("TaskObjects")
			data.model.Parent = taskFolder or Workspace
		else
			local foodFolder = Workspace:FindFirstChild("FoodItems")
			data.model.Parent = foodFolder or Workspace
		end

		-- Re-enable ProximityPrompt
		for _, pp in ipairs(data.model:GetDescendants()) do
			if pp:IsA("ProximityPrompt") then
				pp.Enabled = true
			end
		end
	end

	heldItems[player] = nil
	RE_HeldItemChanged:FireAllClients(player, nil, nil)

	print(string.format("[ItemPickup] %s drop %s", player.Name, data.model and data.model.Name or "?"))
end

-- ── Core: Eat ──────────────────────────────────────────────────

local function eatFood(player)
	local data = heldItems[player]
	if not data or data.category ~= "food" then
		return
	end

	local foodName = data.model and data.model.Name or "unknown"

	unweldItem(data)

	-- Hapus item dari dunia
	if data.model and data.model.Parent then
		data.model:Destroy()
	end

	heldItems[player] = nil
	RE_HeldItemChanged:FireAllClients(player, nil, nil)

	restoreHunger(player, foodName)
end

-- ── Core: Deposit Coal ─────────────────────────────────────────

local function depositCoal(player)
	local data = heldItems[player]
	if not data or data.category ~= "coal" then
		return
	end

	-- Server verify: player harus dekat fireplace
	if not player.Character or not isNearFireplace(player.Character) then
		warn(string.format("[ItemPickup] %s coba deposit coal tapi jauh dari fireplace", player.Name))
		return
	end

	local coalModel  = data.model
	local coalTaskId = coalModel and coalModel:GetAttribute("TaskId") or nil

	unweldItem(data)

	-- Hapus coal dari dunia
	if coalModel and coalModel.Parent then
		coalModel:Destroy()
	end

	heldItems[player] = nil
	RE_HeldItemChanged:FireAllClients(player, nil, nil)

	-- Beritahu TaskSystem bahwa coal sudah di-deposit
	-- RE_CoalDeposited akan di-handle oleh TaskSystem.server.luau
	RE_CoalDeposited:FireServer()  -- ← TaskSystem listen ini

	print(string.format("[ItemPickup] %s deposit coal (TaskId=%s) ke fireplace", player.Name, tostring(coalTaskId)))
end

-- ── Remote Connections ─────────────────────────────────────────

RE_PickupItem.OnServerEvent:Connect(function(player, itemModel)
	-- Validasi tipe argument
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

-- ── Cleanup saat player leave ───────────────────────────────────

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

-- ── Cleanup saat character respawn (item di-drop) ──────────────

Players.PlayerAdded:Connect(function(player)
	player.CharacterRemoving:Connect(function()
		local data = heldItems[player]
		if data then
			-- Saat karakter mati, item ikut hilang (bisa diubah ke drop kalau mau)
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
