-- LanternFlickerManager
-- Manages flickering PointLight effects on all lanterns in the game.
-- Each lantern flickers independently with slightly different timing for a natural look.

local FLICKER_INTERVAL = 0.05 -- seconds between brightness updates
local BASE_BRIGHTNESS = 1.5
local FLICKER_AMPLITUDE = 0.4 -- normal flicker range (+/-)
local DIP_CHANCE = 0.02 -- chance per update of a stronger dip
local DIP_AMPLITUDE = 0.8 -- extra brightness loss during a dip
local DIP_RECOVERY_RATE = 0.1 -- how fast brightness recovers from a dip

-- Track per-lantern state
local lanternStates = {} -- [PointLight] = { phase, speed, dipOffset }

local function registerLantern(light)
	if light.Name ~= "LanternLight" or not light:IsA("PointLight") then
		return
	end
	if lanternStates[light] then
		return -- already registered
	end
	lanternStates[light] = {
		phase = math.random() * math.pi * 2, -- random start phase
		speed = 3 + math.random() * 4, -- flicker speed (3-7 Hz)
		dipOffset = 0, -- current dip amount (fades to 0)
	}
end

local function unregisterLantern(light)
	lanternStates[light] = nil
end

-- Register all existing lantern lights
for _, descendant in game:GetDescendants() do
	if descendant:IsA("PointLight") then
		registerLantern(descendant)
	end
end

-- Register lanterns added later (e.g. cloned, spawned)
game.DescendantAdded:Connect(function(descendant)
	if descendant:IsA("PointLight") then
		registerLantern(descendant)
	end
end)

game.DescendantRemoving:Connect(function(descendant)
	if descendant:IsA("PointLight") then
		unregisterLantern(descendant)
	end
end)

-- Main flicker loop
local timeAccumulator = 0

while task.wait(FLICKER_INTERVAL) do
	timeAccumulator += FLICKER_INTERVAL

	for light, state in lanternStates do
		-- Skip lights whose parent is destroyed or nil
		if light.Parent == nil then
			continue
		end

		-- Advance phase
		state.phase += state.speed * FLICKER_INTERVAL

		-- Random chance of a dip (simulates wind gust)
		if math.random() < DIP_CHANCE then
			state.dipOffset = DIP_AMPLITUDE * (0.5 + math.random() * 0.5)
		end

		-- Recover from dip gradually
		if state.dipOffset > 0 then
			state.dipOffset = math.max(0, state.dipOffset - DIP_RECOVERY_RATE)
		end

		-- Calculate brightness: base + sine wave flicker - dip offset
		local flicker = math.sin(state.phase) * FLICKER_AMPLITUDE
			+ math.sin(state.phase * 2.3) * (FLICKER_AMPLITUDE * 0.3) -- harmonic for complexity
		local brightness = BASE_BRIGHTNESS + flicker - state.dipOffset

		-- Clamp to reasonable range
		light.Brightness = math.max(0.3, math.min(2.5, brightness))
	end
end