-- lantern tool
local tool = script.Parent
local handle = tool:WaitForChild("Handle")
local prompt = handle:WaitForChild("ProximityPrompt")

tool.CanBeDropped = true

-- ==========================================
-- FUNGSI UNTUK MENGATUR KEPADATAN LENTERA
-- ==========================================
local function setLanternCollision(isSolid)
	for _, part in ipairs(tool:GetDescendants()) do
		if part:IsA("BasePart") and part ~= handle then
			part.CanCollide = isSolid
		end
	end
end

-- ==========================================
-- 1. SISTEM PENGELASAN & MATIKAN AUTO-EQUIP
-- ==========================================
for _, part in ipairs(tool:GetDescendants()) do
	if part:IsA("BasePart") then
		-- INI KUNCINYA: Matikan fitur sentuh agar tidak auto-equip saat terinjak
		part.CanTouch = false

		if part ~= handle then
			part.Anchored = false
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = handle
			weld.Part1 = part
			weld.Parent = handle
		end
	end
end

handle.Anchored = false
handle.CanCollide = true
setLanternCollision(true)

-- ==========================================
-- 2. SISTEM AMBIL (DENGAN PEMBATASAN 1 LENTERA)
-- ==========================================
prompt.Triggered:Connect(function(player)
	local character = player.Character
	local backpack = player:FindFirstChild("Backpack")

	if not character or not backpack then
		return
	end

	-- Cek apakah sudah bawa lentera
	local hasLantern = backpack:FindFirstChild(tool.Name) or character:FindFirstChild(tool.Name)
	if hasLantern then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		tool.Parent = backpack
		humanoid:EquipTool(tool)
	end
end)

-- ==========================================
-- 3. SISTEM SAAT DIPEGANG & DIBUANG (DROP)
-- ==========================================
tool.Equipped:Connect(function()
	prompt.Enabled = false
	setLanternCollision(false)
end)

tool.Unequipped:Connect(function()
	task.wait(0.1)

	if tool.Parent == workspace then
		prompt.Enabled = true
		setLanternCollision(true)

		local dropPos = handle.Position
		handle.CFrame = CFrame.new(dropPos) * CFrame.Angles(0, 0, 0)
	else
		prompt.Enabled = false
	end
end)
