-- =============================================================
--  SoundManager.luau  (ModuleScript)
--
--  Two responsibilities:
--
--  1. SoundManager.playAt() + named wrapper functions
--     One-shot spatial sounds for world events. Roblox replicates
--     Sound:Play() on a server Part → all clients hear it in 3D.
--
--  2. SoundManager.new(monster) → MonsterSounds
--     Drives SFX inside SoulDragger based on AI state changes.
--     Called by MonsterAI.server.luau and DuplicationSystem.luau.
--
--  NOT handled here:
--    • FireplaceCrackle / AmbientLoop  → SoundService, auto-plays
--    • Player footsteps / breathing / heartbeat → PlayerNoise.client.luau
--
--  Survival feedback sounds (dark zone, hunger) are played at the
--  player's world position so all nearby players can hear them. If
--  you want per-player-only sounds, route those through a RemoteEvent
--  to the specific client instead of using playAt().
--
--  PLACEHOLDER IDs:
--    Entries marked rbxassetid://0 need real asset IDs.
--    The comment on each line describes what to search for.
-- =============================================================

local SoundManager = {}

-- ─────────────────────────────────────────────────────────────
--  SOUND IDs
-- ─────────────────────────────────────────────────────────────

SoundManager.Ids = {

	-- ── Coal ─────────────────────────────────────────────────
	-- Coal hits any surface (floor, wall, fireplace edge, etc.)
	CoalDrop = "rbxassetid://9125869797",

	-- Coal successfully lands inside the fireplace
	CoalFireplace = "rbxassetid://128344217763318",

	-- ── Boulder ──────────────────────────────────────────────
	-- Boulder lands / collides after being thrown.
	-- Ideally heavier than CoalDrop; search: "stone impact crash"
	BoulderHit = "rbxassetid://9125869797",

	-- ── Food & Drink ─────────────────────────────────────────
	-- Carrot or meat hits the floor; search: "food drop thud soft"
	FoodDrop = "rbxassetid://9120898894",

	-- Waterbottle hits the floor; search: "plastic bottle drop"
	WaterDrop = "rbxassetid://9117558678",

	-- Player eats food (carrot / meat); search: "eating crunch bite"
	EatFood = "rbxassetid://134938643932555",

	-- Player drinks water; search: "gulp drink water"
	DrinkWater = "rbxassetid://134938643932555",

	-- ── Lever ────────────────────────────────────────────────
	-- Intentionally loud — generates a large noise event for the monster
	LeverPull = "rbxassetid://119741178791414",

	-- ── Item Pickup ──────────────────────────────────────────
	-- Picking up ANY item (coal, food, water, boulder…)
	ItemPickup = "rbxassetid://134602992766192",

	-- ── Survival feedback ────────────────────────────────────
	-- Player steps into a dark zone; search: "horror whoosh dark ambient"
	DarkEnter = "rbxassetid://9120697982",

	-- Dark timer reaching critical; search: "horror sting short"
	DarkWarning = "rbxassetid://1014740409",

	-- Hunger dropping critically low; search: "stomach growl grumble"
	HungerWarning = "rbxassetid://90681938651301",
}

-- ─────────────────────────────────────────────────────────────
--  ONE-SHOT SPATIAL SOUND
--  Creates a temporary invisible Part at `position`, plays a Sound
--  on it, then destroys everything when the sound ends.
-- ─────────────────────────────────────────────────────────────

function SoundManager.playAt(
	soundId: string,
	position: Vector3,
	volume: number?, -- default 0.8
	maxDist: number? -- default 50 studs
)
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
	-- Safety cleanup in case Ended never fires (e.g. invalid asset ID)
	task.delay(10, function()
		if anchor.Parent then
			anchor:Destroy()
		end
	end)
end

-- ─────────────────────────────────────────────────────────────
--  NAMED WRAPPERS
--  Keep one wrapper per semantic event so callers never hardcode
--  IDs or volumes and renaming only requires touching this file.
-- ─────────────────────────────────────────────────────────────

-- Coal --------------------------------------------------------

-- Coal hits any surface (floor, wall, dropped from hand, etc.)
function SoundManager.coalDrop(position: Vector3)
	SoundManager.playAt(SoundManager.Ids.CoalDrop, position, 0.65, 35)
end

-- Coal successfully deposited into the fireplace
function SoundManager.coalIntoFireplace(position: Vector3)
	SoundManager.playAt(SoundManager.Ids.CoalFireplace, position, 1.0, 45)
end

-- Boulder -----------------------------------------------------

-- Boulder lands or collides after a throw
function SoundManager.boulderHit(position: Vector3)
	SoundManager.playAt(SoundManager.Ids.BoulderHit, position, 0.9, 45)
end

-- Food & Drink ------------------------------------------------

-- Carrot or meat hits the floor
function SoundManager.foodDrop(position: Vector3)
	SoundManager.playAt(SoundManager.Ids.FoodDrop, position, 0.5, 25)
end

-- Waterbottle hits the floor
function SoundManager.waterDrop(position: Vector3)
	SoundManager.playAt(SoundManager.Ids.WaterDrop, position, 0.5, 25)
end

-- Player eats food (carrot / meat)
function SoundManager.eatFood(position: Vector3)
	SoundManager.playAt(SoundManager.Ids.EatFood, position, 0.7, 20)
end

-- Player drinks water
function SoundManager.drinkWater(position: Vector3)
	SoundManager.playAt(SoundManager.Ids.DrinkWater, position, 0.7, 20)
end

-- Lever -------------------------------------------------------

-- Lever pulled — loud on purpose to alert the monster
function SoundManager.leverPull(position: Vector3)
	SoundManager.playAt(SoundManager.Ids.LeverPull, position, 1.0, 60)
end

-- Items -------------------------------------------------------

-- Any item picked up off the ground
function SoundManager.itemPickup(position: Vector3)
	SoundManager.playAt(SoundManager.Ids.ItemPickup, position, 0.8, 30)
end

-- Generic light drop fallback (for future item categories)
function SoundManager.itemDrop(position: Vector3)
	SoundManager.playAt(SoundManager.Ids.FoodDrop, position, 0.45, 20)
end

-- Survival feedback -------------------------------------------
-- These play at the player's world position. Nearby players can
-- also hear them, which adds atmosphere in co-op. To make them
-- strictly private, fire a RemoteEvent to that client instead.

-- Player enters a dark zone for the first time
function SoundManager.darkEnter(position: Vector3)
	SoundManager.playAt(SoundManager.Ids.DarkEnter, position, 0.7, 18)
end

-- Dark timer reaching a warning threshold (10 s, then 5 s)
function SoundManager.darkWarning(position: Vector3)
	SoundManager.playAt(SoundManager.Ids.DarkWarning, position, 0.9, 18)
end

-- Hunger dropping to a warning threshold (30 %, then 10 %)
function SoundManager.hungerWarning(position: Vector3)
	SoundManager.playAt(SoundManager.Ids.HungerWarning, position, 0.7, 18)
end

-- ─────────────────────────────────────────────────────────────
--  MONSTER SOUND CONTROLLER
--  SoundManager.new(monster) returns a MonsterSounds object.
--  MonsterAI and DuplicationSystem call :onStateChange() and
--  :playHitSounds() as the monster's state changes.
--
--  All Sound instances must already exist inside
--  SoulDragger > HumanoidRootPart in Studio. Set their SoundId
--  there; this module only calls :Play() / :Stop() on them.
-- ─────────────────────────────────────────────────────────────

local MonsterSounds = {}
MonsterSounds.__index = MonsterSounds

function SoundManager.new(monster: Model)
	local self = setmetatable({}, MonsterSounds)
	local hrp = monster:FindFirstChild("HumanoidRootPart")

	self._m = {
		Roar = hrp and hrp:FindFirstChild("RoarSFX"),
		-- search: "monster roar horror", "creature growl"

		Footstep = hrp and hrp:FindFirstChild("FootstepSFX"),
		-- search: "heavy stone footstep monster" — set Looped = true in Studio

		Bite = hrp and hrp:FindFirstChild("BiteSFX"),
		-- search: "monster bite snap", "creature chomp"

		Jumpscare = hrp and hrp:FindFirstChild("JumpscareSFX"),
		-- search: "horror jumpscare sting", "horror stinger"

		AfterJump = hrp and hrp:FindFirstChild("AfterJumpscareEndSFX"),
		-- search: "horror exhale heavy", "monster breathe out"

		HeadCut = hrp and hrp:FindFirstChild("HeadCutSFX"),
		-- search: "impact wet flesh", "horror hit impact"

		Spotted = monster:FindFirstChild("Spotted_SFX"),
		-- search: "horror alert sting short"
	}

	self._lastState = ""
	self._roarCD = 0 -- prevents roar spam on rapid re-detects

	return self
end

function MonsterSounds:_play(name: string)
	local s = self._m[name]
	if s and s:IsA("Sound") then
		s:Play()
	end
end

function MonsterSounds:_stop(name: string)
	local s = self._m[name]
	if s and s:IsA("Sound") and s.IsPlaying then
		s:Stop()
	end
end

function MonsterSounds:onStateChange(newState: string, _isChasing: boolean)
	if newState == self._lastState then
		return
	end
	self._lastState = newState

	local footstep = self._m.Footstep

	if newState == "IDLE" then
		if footstep then
			local onlyChase = footstep:FindFirstChild("PlayOnlyWhenChasing")
			local restrict = onlyChase and onlyChase:IsA("BoolValue") and onlyChase.Value
			if restrict then
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
		if os.clock() > self._roarCD then
			self._roarCD = os.clock() + 12
			self:_play("Roar")
		end
		self:_play("Spotted")
	elseif newState == "CATCH" then
		self:_stop("Footstep")
		self:_stop("Roar")
		self:_play("Jumpscare")
		local jSFX = self._m.Jumpscare
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

-- Called from beginStrike after a player is caught
function MonsterSounds:playHitSounds()
	self:_play("Bite")
	task.delay(0.35, function()
		self:_play("HeadCut")
	end)
end

return SoundManager
