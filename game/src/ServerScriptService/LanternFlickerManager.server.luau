local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local LANTERN_TAG = "FlickeringLantern"
local FLICKER_INTENSITY = 0.35

-- Prime-number speeds prevent a perceptible loop pattern
local WAVE_SPEED_FAST = 31
local WAVE_SPEED_SLOW = 13

-- [PointLight] = baseline Brightness before flicker offset is applied
local activeLanterns: { [PointLight]: number } = {}

local function registerLantern(glass: Instance)
	if not glass:IsA("BasePart") then
		return
	end
	local light = glass:FindFirstChildOfClass("PointLight")
	if light then
		activeLanterns[light] = light.Brightness
	end
end

for _, glass in ipairs(CollectionService:GetTagged(LANTERN_TAG)) do
	registerLantern(glass)
end

CollectionService:GetInstanceAddedSignal(LANTERN_TAG):Connect(registerLantern)

CollectionService:GetInstanceRemovedSignal(LANTERN_TAG):Connect(function(glass)
	local light = glass:FindFirstChildOfClass("PointLight")
	if light then
		activeLanterns[light] = nil
	end
end)

RunService.Heartbeat:Connect(function()
	local t = os.clock()
	local offset = (math.sin(t * WAVE_SPEED_FAST) * 0.65 + math.sin(t * WAVE_SPEED_SLOW) * 0.35) * FLICKER_INTENSITY

	for light, base in pairs(activeLanterns) do
		if light and light.Parent then
			light.Brightness = base + offset
		else
			activeLanterns[light] = nil
		end
	end
end)
