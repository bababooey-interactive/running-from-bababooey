--!strict
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

-- CONFIGURATION
local LANTERN_TAG = "FlickeringLantern"
local FLICKER_INTENSITY = 0.35

-- Interference pattern speeds (Mismatched prime numbers prevent an obvious loop pattern)
local WAVE_SPEED_FAST = 31
local WAVE_SPEED_SLOW = 13

-- Tracks each PointLight's baseline brightness
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

-- Scan for existing map lanterns and handle dynamic streaming/spawning
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

-- Central Heartbeat thread processing the sine waves simultaneously
RunService.Heartbeat:Connect(function()
	local currentTime = os.clock()

	-- Calculate two intersecting sine waves
	local fastWave = math.sin(currentTime * WAVE_SPEED_FAST) * 0.65
	local slowWave = math.sin(currentTime * WAVE_SPEED_SLOW) * 0.35
	local combinedNoise = (fastWave + slowWave) * FLICKER_INTENSITY

	for light, baseBrightness in pairs(activeLanterns) do
		if light and light.Parent then
			light.Brightness = baseBrightness + combinedNoise
		else
			activeLanterns[light] = nil
		end
	end
end)
