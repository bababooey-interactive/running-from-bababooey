-- SoundManager.luau  (ModuleScript)
-- ServerScriptService
--
-- Two responsibilities:
--
--   1. SoundManager.playAt() + named wrappers
--      One-shot spatial sounds for world events. Roblox replicates
--      Sound:Play() on a server Part → all clients hear it in 3D.
--
--   2. SoundManager.new(monster) → MonsterSounds object
--      Drives SFX inside SoulDragger based on AI state changes.
--      Called by MonsterBrain (and therefore MonsterAI + DuplicationSystem).
--      All Sound instances must already exist inside:
--        SoulDragger > HumanoidRootPart  (FootstepSFX, RoarSFX, BiteSFX, etc.)
--      Set their SoundIds in Studio; this module only calls :Play()/:Stop().

local SoundManager = {}

-- ─────────────────────────────────────────────────────────────
--  SOUND IDs
-- ─────────────────────────────────────────────────────────────

SoundManager.Ids = {
	-- Coal
	CoalDrop = "rbxassetid://9125869797",
	CoalFireplace = "rbxassetid://128344217763318",

	-- Boulder
	BoulderHit = "rbxassetid://9125869797",

	-- Food & drink
	FoodDrop = "rbxassetid://9120898894",
	WaterDrop = "rbxassetid://9117558678",
	EatFood = "rbxassetid://134938643932555",
	DrinkWater = "rbxassetid://134938643932555",

	-- Lever (intentionally loud — alerts the monster)
	LeverPull = "rbxassetid://119741178791414",

	-- Item pickup (any category)
	ItemPickup = "rbxassetid://134602992766192",

	-- Survival feedback
	DarkEnter = "rbxassetid://9120697982",
	DarkWarning = "rbxassetid://1014740409",
	HungerWarning = "rbxassetid://90681938651301",
}

-- ─────────────────────────────────────────────────────────────
--  ONE-SHOT SPATIAL SOUND
-- ─────────────────────────────────────────────────────────────

function SoundManager.playAt(soundId: string, position: Vector3, volume: number?, maxDist: number?)
	if not soundId or soundId == "rbxassetid://0" or soundId == "" then
		return
	end

	local anchor = Instance.new("Part")
	anchor.Name = "SFX_Anchor"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.1, 0.1, 0.1)
	anchor.Position = position
	anchor.Parent = workspace

	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Volume = volume or 0.8
	sound.RollOffMaxDistance = maxDist or 50
	sound.RollOffMinDistance = 5
	sound.RollOffMode = Enum.RollOffMode.Linear
	sound.Parent = anchor
	sound:Play()

	sound.Ended:Once(function()
		anchor:Destroy()
	end)

	-- Safety cleanup in case Ended never fires (invalid asset, etc.)
	task.delay(10, function()
		if anchor.Parent then
			anchor:Destroy()
		end
	end)
end

-- ─────────────────────────────────────────────────────────────
--  NAMED WRAPPERS
-- ─────────────────────────────────────────────────────────────

function SoundManager.coalDrop(position: Vector3)
	SoundManager.playAt(SoundManager.Ids.CoalDrop, position, 0.65, 35)
end

function SoundManager.coalIntoFireplace(position: Vector3)
	SoundManager.playAt(SoundManager.Ids.CoalFireplace, position, 1.0, 45)
end

function SoundManager.boulderHit(position: Vector3)
	SoundManager.playAt(SoundManager.Ids.BoulderHit, position, 0.9, 45)
end

function SoundManager.foodDrop(position: Vector3)
	SoundManager.playAt(SoundManager.Ids.FoodDrop, position, 0.5, 25)
end

function SoundManager.waterDrop(position: Vector3)
	SoundManager.playAt(SoundManager.Ids.WaterDrop, position, 0.5, 25)
end

function SoundManager.eatFood(position: Vector3)
	SoundManager.playAt(SoundManager.Ids.EatFood, position, 0.7, 20)
end

function SoundManager.drinkWater(position: Vector3)
	SoundManager.playAt(SoundManager.Ids.DrinkWater, position, 0.7, 20)
end

function SoundManager.leverPull(position: Vector3)
	SoundManager.playAt(SoundManager.Ids.LeverPull, position, 1.0, 60)
end

function SoundManager.itemPickup(position: Vector3)
	SoundManager.playAt(SoundManager.Ids.ItemPickup, position, 0.8, 30)
end

function SoundManager.itemDrop(position: Vector3)
	SoundManager.playAt(SoundManager.Ids.FoodDrop, position, 0.45, 20)
end

function SoundManager.darkEnter(position: Vector3)
	SoundManager.playAt(SoundManager.Ids.DarkEnter, position, 0.7, 18)
end

function SoundManager.darkWarning(position: Vector3)
	SoundManager.playAt(SoundManager.Ids.DarkWarning, position, 0.9, 18)
end

function SoundManager.hungerWarning(position: Vector3)
	SoundManager.playAt(SoundManager.Ids.HungerWarning, position, 0.7, 18)
end

-- ─────────────────────────────────────────────────────────────
--  MONSTER SOUND CONTROLLER
--
--  Usage:
--    local sounds = SoundManager.new(monsterModel)
--    sounds:onStateChange("CHASE", true)
--    sounds:playHitSounds()
--
--  Required Sound children inside SoulDragger > HumanoidRootPart:
--    FootstepSFX   (Looped = true in Studio)
--    RoarSFX
--    BiteSFX
--    JumpscareSFX
--    AfterJumpscareEndSFX
--    HeadCutSFX
--  Optional (on the root Model):
--    Spotted_SFX
-- ─────────────────────────────────────────────────────────────

local MonsterSounds = {}
MonsterSounds.__index = MonsterSounds

function SoundManager.new(monster: Model)
	local self = setmetatable({}, MonsterSounds)
	local hrp = monster:FindFirstChild("HumanoidRootPart")

	self._sfx = {
		Roar = hrp and hrp:FindFirstChild("RoarSFX"),
		Footstep = hrp and hrp:FindFirstChild("FootstepSFX"),
		Bite = hrp and hrp:FindFirstChild("BiteSFX"),
		Jumpscare = hrp and hrp:FindFirstChild("JumpscareSFX"),
		AfterJump = hrp and hrp:FindFirstChild("AfterJumpscareEndSFX"),
		HeadCut = hrp and hrp:FindFirstChild("HeadCutSFX"),
		Spotted = monster:FindFirstChild("Spotted_SFX"),
	}

	self._lastState = ""
	self._roarCD = 0

	return self
end

function MonsterSounds:_play(name: string)
	local s = self._sfx[name]
	if s and s:IsA("Sound") then
		s:Play()
	end
end

function MonsterSounds:_stop(name: string)
	local s = self._sfx[name]
	if s and s:IsA("Sound") and s.IsPlaying then
		s:Stop()
	end
end

function MonsterSounds:onStateChange(newState: string, isChasing: boolean)
	if newState == self._lastState then
		return
	end
	self._lastState = newState

	local footstep = self._sfx.Footstep

	if newState == "IDLE" then
		if footstep then
			-- Suppress footsteps in idle if the creator flagged them chase-only
			local chaseOnly = footstep:FindFirstChild("PlayOnlyWhenChasing")
			if chaseOnly and chaseOnly:IsA("BoolValue") and chaseOnly.Value then
				self:_stop("Footstep")
			else
				footstep.PlaybackSpeed = 0.75
				footstep.Volume = 0.5
				if not footstep.IsPlaying then
					footstep:Play()
				end
			end
		end
	elseif newState == "CHASE" then
		if footstep then
			footstep.PlaybackSpeed = 1.55
			footstep.Volume = 1.0
			if not footstep.IsPlaying then
				footstep:Play()
			end
		end
		-- Roar on first detection, then on a cooldown
		if os.clock() > self._roarCD then
			self._roarCD = os.clock() + 12
			self:_play("Roar")
		end
		self:_play("Spotted")
	elseif newState == "CATCH" then
		self:_stop("Footstep")
		self:_stop("Roar")
		self:_play("Jumpscare")

		local jSFX = self._sfx.Jumpscare
		if jSFX then
			jSFX.Ended:Once(function()
				self:_play("AfterJump")
			end)
		else
			task.delay(1.5, function()
				self:_play("AfterJump")
			end)
		end
	end
end

-- Called right after a player is caught (during _beginStrike)
function MonsterSounds:playHitSounds()
	self:_play("Bite")
	task.delay(0.35, function()
		self:_play("HeadCut")
	end)
end

return SoundManager
