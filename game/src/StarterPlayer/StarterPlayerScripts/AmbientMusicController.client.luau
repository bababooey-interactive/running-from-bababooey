local SoundService = game:GetService("SoundService")
local ambientMusic = SoundService:WaitForChild("AmbientLoop")

-- How many seconds of silence you want between loops
local PAUSE_TIME = 1

-- This loop will run forever in the background
while true do
	ambientMusic:Play()

	-- Wait for the song to completely finish playing
	ambientMusic.Ended:Wait()

	-- The creepy silence...
	task.wait(PAUSE_TIME)
end
