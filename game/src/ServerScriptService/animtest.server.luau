-- Find the monster in the workspace instead of using script.Parent
local monster = workspace:WaitForChild("Character_Sketchfab")

-- Find the Animation Controller and Animator
local animController = monster:WaitForChild("AnimationController")
local animator = animController:WaitForChild("Animator")

-- Create the animation
local chaseAnimation = Instance.new("Animation")
-- PASTE YOUR ID NUMBER RIGHT HERE:
chaseAnimation.AnimationId = "rbxassetid://122789968828942"

-- Load and play
local chaseTrack = animator:LoadAnimation(chaseAnimation)
chaseTrack.Looped = true
chaseTrack:Play()
