-- =============================================================
--  ItemInteract.client.luau
--  📁 game/src/StarterPlayer/StarterPlayerScripts/ItemInteract.client.luau
--  🔧 GANTI SELURUH ISI file lama
-- =============================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

-- ── Remote Events ──────────────────────────────────────────────
local RE_PickupItem = Remotes:WaitForChild("PickupItem")
local RE_DropItem = Remotes:WaitForChild("DropItem")
local RE_EatFood = Remotes:WaitForChild("EatFood")
local RE_DepositCoal = Remotes:WaitForChild("DepositCoal")
local RE_HeldItemChanged = Remotes:WaitForChild("HeldItemChanged")

-- ── Config ─────────────────────────────────────────────────────
local FIREPLACE_DEPOSIT_RADIUS = 20
local PICKUP_RADIUS = 5
local BOULDER_NAMES = {
	boulder_small = true,
	boulder_medium = true,
}

-- ── State ──────────────────────────────────────────────────────
local heldItem = nil
local heldCategory = nil
local eatGui = nil
local depositGui = nil
local promptSetup = {}
local boulderHintGui = nil
local isHoldingBoulder = false

-- ── Helpers ────────────────────────────────────────────────────

local function getPrimaryOrFirstPart(model)
	if not model then
		return nil
	end
	if model:IsA("BasePart") then
		return model
	end
	if model.PrimaryPart then
		return model.PrimaryPart
	end
	return model:FindFirstChildWhichIsA("BasePart", true)
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
				-- Fallback: pakai pivot position
				return child:GetPivot().Position
			end
		end
	end
	-- Deep search fallback (server does this too)
	for _, desc in ipairs(Workspace:GetDescendants()) do
		if desc:IsA("Model") and desc.Name:lower():find("fireplace") then
			local part = getPrimaryOrFirstPart(desc)
			if part then
				return part.Position
			end
			return desc:GetPivot().Position
		end
	end
	return nil
end

local function isNearFireplace()
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return false
	end
	local fpPos = findFireplacePosition()
	if not fpPos then
		return false
	end
	return (root.Position - fpPos).Magnitude <= FIREPLACE_DEPOSIT_RADIUS
end

local function getItemCategory(model)
	if not model or not model:IsA("Model") then
		return nil
	end

	local taskType = model:GetAttribute("TaskType")
	if taskType == "coal" then
		return "coal"
	end
	if taskType == "lever" then
		return "lever"
	end -- ADD THIS

	local p = model.Parent
	while p do
		if p.Name == "FoodItems" then
			return "food"
		end
		p = p.Parent
	end

	if model:GetAttribute("ItemCategory") == "food" then
		return "food"
	end

	return nil
end

-- ── GUI ────────────────────────────────────────────────────────

local function createEatGui(itemModel)
	if eatGui then
		eatGui:Destroy()
	end
	local part = getPrimaryOrFirstPart(itemModel)
	if not part then
		return
	end

	local gui = Instance.new("BillboardGui")
	gui.Name = "EatPrompt"
	gui.Adornee = part
	gui.Size = UDim2.new(0, 200, 0, 44)
	gui.StudsOffset = Vector3.new(0, 3, 0)
	gui.AlwaysOnTop = true
	gui.ResetOnSpawn = false

	local frame = Instance.new("Frame")
	frame.Size = UDim2.new(1, 0, 1, 0)
	frame.BackgroundColor3 = Color3.fromRGB(30, 20, 10)
	frame.BackgroundTransparency = 0.2
	frame.BorderSizePixel = 0
	frame.Parent = gui
	Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 8)

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Text = "[Klik Kiri / T] Makan   [Q] Drop"
	label.TextColor3 = Color3.fromRGB(255, 230, 160)
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.Parent = frame

	gui.Parent = player.PlayerGui
	eatGui = gui
end

local function createDepositGui()
	if depositGui then
		return
	end

	local sg = Instance.new("ScreenGui")
	sg.Name = "CoalDepositPrompt"
	sg.ResetOnSpawn = false

	local frame = Instance.new("Frame")
	frame.Size = UDim2.new(0, 240, 0, 54)
	frame.Position = UDim2.new(0.5, -120, 0.82, 0)
	frame.BackgroundColor3 = Color3.fromRGB(40, 25, 10)
	frame.BackgroundTransparency = 0.15
	frame.BorderSizePixel = 0
	frame.Parent = sg
	Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 10)

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(255, 140, 0)
	stroke.Thickness = 2
	stroke.Parent = frame

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Text = "🔥  [F] Lempar Coal ke Api"
	label.TextColor3 = Color3.fromRGB(255, 200, 80)
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.Parent = frame

	sg.Parent = player.PlayerGui
	depositGui = sg
end

local function createBoulderHintGui()
	if boulderHintGui then
		return
	end

	local sg = Instance.new("ScreenGui")
	sg.Name = "BoulderHintGui"
	sg.ResetOnSpawn = false

	local frame = Instance.new("Frame")
	frame.Size = UDim2.new(0, 280, 0, 54)
	frame.Position = UDim2.new(0.5, -140, 0.76, 0)
	frame.BackgroundColor3 = Color3.fromRGB(30, 30, 35)
	frame.BackgroundTransparency = 0.15
	frame.BorderSizePixel = 0
	frame.Parent = sg
	Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 10)

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(180, 140, 80)
	stroke.Thickness = 2
	stroke.Parent = frame

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Text = "🪨  [Klik Kiri Mouse] Lempar  |  [Q] Drop"
	label.TextColor3 = Color3.fromRGB(230, 200, 140)
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.Parent = frame

	sg.Parent = player.PlayerGui
	boulderHintGui = sg
end

local function destroyBoulderHintGui()
	if boulderHintGui then
		boulderHintGui:Destroy()
		boulderHintGui = nil
	end
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

-- ── Setup ProximityPrompt per item ─────────────────────────────

local function setupPrompt(model)
	if promptSetup[model] then
		return
	end
	-- Cek apakah ini boulder (BasePart atau Model dengan nama boulder)
	local modelName = model.Name:lower()
	if BOULDER_NAMES[modelName] then
		-- Boulder pakai ProximityPrompt sederhana (server yang handle pickup)
		local targetPart = getPrimaryOrFirstPart(model)
		if not targetPart then
			return
		end

		for _, pp in ipairs(model:IsA("Model") and model:GetDescendants() or { model }) do
			if pp:IsA("ProximityPrompt") then
				pp:Destroy()
			end
		end

		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Pegang"
		prompt.ObjectText = "🪨 " .. model.Name
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = PICKUP_RADIUS
		prompt.RequiresLineOfSight = false
		prompt.Enabled = true
		prompt.Style = Enum.ProximityPromptStyle.Default
		prompt.Parent = targetPart

		prompt.Triggered:Connect(function()
			if heldItem then
				return
			end
			RE_PickupItem:FireServer(model)
		end)

		promptSetup[model] = true
		model.AncestryChanged:Connect(function()
			if not model.Parent then
				promptSetup[model] = nil
			end
		end)
		return -- stop di sini, boulder tidak perlu flow category di bawah
	end

	local taskType = model:GetAttribute("TaskType")
	if taskType == "lever" then
		-- If already completed (e.g. streaming in late or already pulled), don't show prompt
		if model:GetAttribute("Completed") then
			return
		end

		local targetPart = getPrimaryOrFirstPart(model)
		if not targetPart then
			return
		end

		-- Remove any existing prompts first
		for _, pp in ipairs(model:GetDescendants()) do
			if pp:IsA("ProximityPrompt") then
				pp:Destroy()
			end
		end

		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Tarik"
		prompt.ObjectText = "🔧 Lever"
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.HoldDuration = 0.8
		prompt.MaxActivationDistance = 5
		prompt.RequiresLineOfSight = false
		prompt.Parent = targetPart

		-- LISTEN FOR COMPLETED ATTRIBUTE: If another player completes it, destroy this prompt immediately
		local attrConnection
		attrConnection = model:GetAttributeChangedSignal("Completed"):Connect(function()
			if model:GetAttribute("Completed") then
				-- Destroy the prompt we just made
				prompt.Enabled = false
				prompt:Destroy()

				-- Also aggressively destroy ANY other prompts that might have snuck in
				for _, child in ipairs(targetPart:GetChildren()) do
					if child:IsA("ProximityPrompt") then
						child:Destroy()
					end
				end

				if attrConnection then
					attrConnection:Disconnect()
					attrConnection = nil
				end
			end
		end)

		-- [CRITICAL FIX] If it's ALREADY completed when we are setting it up (e.g., late joiners),
		-- destroy it instantly and exit.
		if model:GetAttribute("Completed") then
			prompt:Destroy()
			return
		end

		prompt.Triggered:Connect(function()
			-- Fire to server (TaskSystem handles the actual completion)
			local RE_TaskInteract = Remotes:FindFirstChild("TaskInteract")
			if RE_TaskInteract then
				RE_TaskInteract:FireServer({
					taskType = "lever",
					taskId = model:GetAttribute("TaskId") or "",
				})
			end
			-- Disable prompt immediately so local player can't click lock it
			prompt.Enabled = false
		end)

		promptSetup[model] = true
		model.AncestryChanged:Connect(function()
			if not model.Parent then
				promptSetup[model] = nil
				if attrConnection then
					attrConnection:Disconnect()
					attrConnection = nil
				end
			end
		end)
		return
	end
	local category = getItemCategory(model)
	if not category then
		return
	end

	local targetPart = getPrimaryOrFirstPart(model)
	if not targetPart then
		return
	end

	-- Hapus prompt lama (dari MapGenerator/hookFoodItem)
	for _, pp in ipairs(model:GetDescendants()) do
		if pp:IsA("ProximityPrompt") then
			pp:Destroy()
		end
	end

	local objectText = category == "coal" and "🪨 Coal" or "🍖 " .. model.Name

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Ambil"
	prompt.ObjectText = objectText
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = PICKUP_RADIUS
	prompt.RequiresLineOfSight = false
	prompt.Parent = targetPart

	prompt.Triggered:Connect(function()
		if heldItem then
			return
		end
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
	if not folder then
		return
	end
	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("Model") then
			setupPrompt(child)
		end
		-- juga scan 1 level dalam (untuk subfolder TaskObjects/Coal/...)
		if child:IsA("Folder") then
			for _, grandchild in ipairs(child:GetChildren()) do
				if grandchild:IsA("Model") then
					setupPrompt(grandchild)
				end
			end
		end
	end
	folder.ChildAdded:Connect(function(child)
		task.defer(function()
			if child and child.Parent then
				if child:IsA("Model") then
					setupPrompt(child)
				end
				if child:IsA("Folder") then
					for _, gc in ipairs(child:GetChildren()) do
						if gc:IsA("Model") then
							setupPrompt(gc)
						end
					end
				end
			end
		end)
	end)
end

local function doScan()
	scanFolder(Workspace:FindFirstChild("FoodItems"))
	scanFolder(Workspace:FindFirstChild("TaskObjects"))
	-- Boulder ada di GeneratedMap (di-spawn MapGenerator)
	local mapFolder = Workspace:FindFirstChild("GeneratedMap")
	if mapFolder then
		for _, obj in ipairs(mapFolder:GetDescendants()) do
			if obj:IsA("BasePart") and BOULDER_NAMES[obj.Name:lower()] then
				setupPrompt(obj) -- obj adalah BasePart, setupPrompt handle ini
			end
		end
		-- Watch untuk boulder yang baru muncul setelah generate
		mapFolder.DescendantAdded:Connect(function(obj)
			if obj:IsA("BasePart") and BOULDER_NAMES[obj.Name:lower()] then
				task.defer(function()
					if obj and obj.Parent then
						setupPrompt(obj)
					end
				end)
			end
		end)
	end
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
	if whoPlayer ~= player then
		return
	end
	heldItem = itemModel
	heldCategory = category

	if not itemModel then
		destroyEatGui()
		destroyDepositGui()
		destroyBoulderHintGui()
		isHoldingBoulder = false
		return
	end

	if category == "food" then
		createEatGui(itemModel)
	elseif category == "boulder" then
		isHoldingBoulder = true
		createBoulderHintGui()
		destroyEatGui()
	else
		destroyEatGui()
		destroyBoulderHintGui()
		isHoldingBoulder = false
	end
end)

-- ── Core: Cook Meat ────────────────────────────────────────────

local function startCookingEffect(player)
    -- Beritahu client untuk tampilkan efek api
    local RE_CookingEffect = Remotes:FindFirstChild("CookingEffect")
    if RE_CookingEffect then
        RE_CookingEffect:FireClient(player, true)
    end
end

local function stopCookingEffect(player)
    local RE_CookingEffect = Remotes:FindFirstChild("CookingEffect")
    if RE_CookingEffect then
        RE_CookingEffect:FireClient(player, false)
    end
end

local function cookMeat(player)
    local data = heldItem[player]
    if not data or data.category ~= "food" then return end
    if not data.model or not data.model.Name:lower():find("^meat") then return end
    
    -- Sudah cooked_meat, skip
    if data.model.Name:lower():find("cooked") then return end

    local cookedAsset = getCookedMeatAsset()
    if not cookedAsset then
        warn("[ItemPickup] cooked_meat asset tidak ditemukan di FoodItems!")
        return
    end

    -- Simpan posisi hand sebelum unweld
    local char = player.Character
    local hand = getRightHand(char)
    local handCFrame = hand and hand.CFrame or CFrame.new()

    -- Unweld meat lama
    unweldItem(data)
    if data.model and data.model.Parent then
        data.model:Destroy()
    end
    heldItem[player] = nil

    -- Clone cooked_meat dan langsung weld ke tangan
    local cookedClone = cookedAsset:Clone()
    cookedClone.Parent = char

    -- Preserve original scale dari attribute (sama seperti placeFoodItems)
    local originalScale = cookedAsset:GetAttribute("OriginalScale") or 1
    cookedClone:ScaleTo(originalScale * 1.5)  -- FOOD_SCALE = 1.5
    cookedClone:PivotTo(handCFrame)

    local newWeld = weldItemToHand(char, cookedClone)
    if not newWeld then
        cookedClone:Destroy()
        return
    end

    heldItem[player] = { model = cookedClone, category = "food", weld = newWeld }
    RE_HeldItemChanged:FireAllClients(player, cookedClone, "food")

    stopCookingEffect(player)
    cookingTimers[player] = nil

    -- Efek suara sizzle saat matang
    SoundManager.eatFood(cookedClone:GetPivot().Position) -- pakai sound yang ada dulu
    print(string.format("[ItemPickup] %s's meat is now cooked!", player.Name))
end

-- ── Cooking Heartbeat (server-side proximity check) ────────────

local RunService = game:GetService("RunService")

RunService.Heartbeat:Connect(function()
    for player, data in pairs(heldItem) do
        if data.category ~= "food" then continue end
        if not data.model then continue end
        
        local name = data.model.Name:lower()
        -- Hanya meat biasa (bukan cooked_meat)
        if not name:match("^meat") or name:find("cooked") then
            -- Bukan meat atau sudah cooked — reset timer
            if cookingTimers[player] then
                cookingTimers[player] = nil
                stopCookingEffect(player)
            end
            continue
        end

        local char = player.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        if not root then continue end

        local fpPos = getFireplacePosition()
        if not fpPos then continue end

        local dist = (root.Position - fpPos).Magnitude

        if dist <= COOKING_RADIUS then
            if not cookingTimers[player] then
                -- Baru masuk radius api
                cookingTimers[player] = os.clock()
                startCookingEffect(player)
            elseif os.clock() - cookingTimers[player] >= COOKING_TIME then
                -- Sudah cukup lama dekat api → masak!
                cookMeat(player)
            end
        else
            -- Keluar dari radius api → reset timer
            if cookingTimers[player] then
                cookingTimers[player] = nil
                stopCookingEffect(player)
            end
        end
    end
end)

-- ── Per-frame cek jarak fireplace ──────────────────────────────

RunService.Heartbeat:Connect(function()
	if heldCategory ~= "coal" then
		if depositGui then
			destroyDepositGui()
		end
		return
	end
	if isNearFireplace() then
		createDepositGui()
	else
		destroyDepositGui()
	end
end)

-- ── Input ──────────────────────────────────────────────────────

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	if input.KeyCode == Enum.KeyCode.T and heldCategory == "food" then
		RE_EatFood:FireServer()
	elseif input.KeyCode == Enum.KeyCode.F and heldCategory == "coal" then
		if isNearFireplace() then
			RE_DepositCoal:FireServer()
		end
	elseif input.KeyCode == Enum.KeyCode.Q and heldItem then
		RE_DropItem:FireServer()
		destroyBoulderHintGui() -- tambahkan
		isHoldingBoulder = false -- tambahkan
	elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
		if isHoldingBoulder then -- tambahkan blok ini
			local RE_ThrowBoulder = Remotes:FindFirstChild("ThrowBoulder")
			if RE_ThrowBoulder then
				RE_ThrowBoulder:FireServer()
				destroyBoulderHintGui()
				isHoldingBoulder = false
			end
		elseif heldCategory == "food" then
			RE_EatFood:FireServer()
		end
	end
end)

-- ── Character refresh ──────────────────────────────────────────

player.CharacterAdded:Connect(function(newChar)
	character = newChar
	heldItem = nil
	heldCategory = nil
	isHoldingBoulder = false
	destroyEatGui()
	destroyDepositGui()
	destroyBoulderHintGui()
	task.wait(1)
	doScan()
end)

-- ── Cooking Effect (api saat meat dipanggang) ──────────────────

local RE_CookingEffect = Remotes:WaitForChild("CookingEffect")
local cookingGui = nil
local cookingTween = nil

local function createCookingEffect()
    if cookingGui then return end

    -- ScreenGui progress bar + teks
    local sg = Instance.new("ScreenGui")
    sg.Name = "CookingGui"
    sg.ResetOnSpawn = false

    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(0, 220, 0, 60)
    frame.Position = UDim2.new(0.5, -110, 0.70, 0)
    frame.BackgroundColor3 = Color3.fromRGB(40, 15, 5)
    frame.BackgroundTransparency = 0.1
    frame.BorderSizePixel = 0
    frame.Parent = sg
    Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 10)

    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(255, 80, 0)
    stroke.Thickness = 2
    stroke.Parent = frame

    local label = Instance.new("TextLabel")
    label.Name = "CookLabel"
    label.Size = UDim2.new(1, 0, 0.5, 0)
    label.BackgroundTransparency = 1
    label.Text = "🔥  Memanggang Daging..."
    label.TextColor3 = Color3.fromRGB(255, 180, 60)
    label.TextScaled = true
    label.Font = Enum.Font.GothamBold
    label.Parent = frame

    -- Progress bar background
    local barBg = Instance.new("Frame")
    barBg.Name = "BarBg"
    barBg.Size = UDim2.new(0.9, 0, 0.25, 0)
    barBg.Position = UDim2.new(0.05, 0, 0.65, 0)
    barBg.BackgroundColor3 = Color3.fromRGB(20, 10, 5)
    barBg.BorderSizePixel = 0
    barBg.Parent = frame
    Instance.new("UICorner", barBg).CornerRadius = UDim.new(1, 0)

    -- Progress bar fill (mulai dari 0)
    local barFill = Instance.new("Frame")
    barFill.Name = "BarFill"
    barFill.Size = UDim2.new(0, 0, 1, 0)
    barFill.BackgroundColor3 = Color3.fromRGB(255, 100, 0)
    barFill.BorderSizePixel = 0
    barFill.Parent = barBg
    Instance.new("UICorner", barFill).CornerRadius = UDim.new(1, 0)

    sg.Parent = player.PlayerGui
    cookingGui = sg

    -- Tween progress bar dari 0 → 100% dalam COOKING_TIME detik
    local COOKING_TIME_CLIENT = 3  -- harus sama dengan server
    local TweenService = game:GetService("TweenService")
    cookingTween = TweenService:Create(
        barFill,
        TweenInfo.new(COOKING_TIME_CLIENT, Enum.EasingStyle.Linear),
        { Size = UDim2.new(1, 0, 1, 0) }
    )
    cookingTween:Play()

    -- Flicker warna label seperti api
    task.spawn(function()
        local colors = {
            Color3.fromRGB(255, 180, 60),
            Color3.fromRGB(255, 100, 20),
            Color3.fromRGB(255, 220, 80),
        }
        local i = 1
        while cookingGui do
            label.TextColor3 = colors[i]
            i = (i % #colors) + 1
            task.wait(0.2)
        end
    end)
end

local function destroyCookingEffect()
    if cookingTween then
        cookingTween:Cancel()
        cookingTween = nil
    end
    if cookingGui then
        cookingGui:Destroy()
        cookingGui = nil
    end
end

RE_CookingEffect.OnClientEvent:Connect(function(isActive)
    if isActive then
        createCookingEffect()
    else
        destroyCookingEffect()
    end
end)

-- Pastikan efek hilang saat item di-drop
RE_HeldItemChanged.OnClientEvent:Connect(function(whoPlayer, itemModel, category)
    -- handler asli sudah ada di atas, ini khusus untuk reset cooking effect
    if whoPlayer == player and not itemModel then
        destroyCookingEffect()
    end
end)

print("[ItemInteract] Client initialized.")
