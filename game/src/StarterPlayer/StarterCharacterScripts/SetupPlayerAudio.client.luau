local hrp = script.Parent:WaitForChild("HumanoidRootPart")

local function addSound(name, id)
	local s = Instance.new("Sound")
	s.Name = name
	s.SoundId = id
	s.Looped = true
	s.Parent = hrp
end

-- Put your actual Audio IDs here!
addSound("FootstepWalk", "rbxassetid://5446226292") -- a loop
addSound("FootstepRun", "rbxassetid://140355631752127") -- not a loop
addSound("BreathingFast", "rbxassetid://94952921557556") -- a loop
addSound("Heartbeat", "rbxassetid://139481207162657")
