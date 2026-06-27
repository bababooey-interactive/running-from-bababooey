local SoundService = game:GetService("SoundService")

local LOOP_PAUSE = 1 -- seconds of silence between loops
local music = SoundService:WaitForChild("AmbientLoop")

while true do
	music:Play()
	music.Ended:Wait()
	task.wait(LOOP_PAUSE)
end
