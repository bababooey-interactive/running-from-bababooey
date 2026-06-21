-- =============================================================
--  SoundManager.luau  (ModuleScript — Day 8-9)
--
--  Two parts:
--  1. MonsterSounds: wraps SFX inside SoulDragger > HumanoidRootPart.
--     Triggered by MonsterAI state changes.
--  2. SoundManager.playAt(): one-shot spatial sounds for world
--     events (coal drop, lever pull, etc.). Roblox auto-replicates
--     Sound:Play() on server for workspace parts — clients hear it.
--
--  AMBIENT HORROR (background loop):
--    Don't put it here. In Studio, add a Sound to SoundService
--    (not workspace), set Looped = true, Volume ~0.4, then set
--    SoundId. It will play automatically for all clients.
--    Search Roblox Creator Store: "horror ambience loop"
--
--  PLAYER SOUNDS (footstep, breathing):
--    Handled client-side in PlayerNoise.client.luau.
--    Add Sound instances to the character or StarterCharacterScripts.
-- =============================================================

local SoundManager = {}

-- ─────────────────────────────────────────────────────────────
--  WORLD SOUND IDs
--  Fill these in with rbxassetid://XXXXXX after uploading.
--  Used by SoundManager.playAt() for task/interaction sounds.
-- ─────────────────────────────────────────────────────────────

SoundManager.Ids = {
    -- Coal
    CoalDrop        = "rbxassetid://0",  -- soft stone thud (search: "rock drop")
    CoalThrowHit    = "rbxassetid://0",  -- heavier impact + slight echo (search: "stone impact wall")
    CoalFireplace   = "rbxassetid://0",  -- whoosh + crackle (search: "fire whoosh crackle")

    -- Lever (loud — intentional per design)
    LeverPull       = "rbxassetid://0",  -- heavy mechanical clunk (search: "industrial lever switch")

    -- Battery
    BatteryInsert   = "rbxassetid://0",  -- soft electrical click (search: "battery click insert")

    -- Item pickup
    ItemPickup      = "rbxassetid://0",  -- light tap (search: "item pickup ui click")

    -- Fireplace (ambient, placed on the fireplace part itself)
    FireplaceCrackle = "rbxassetid://0", -- looped fire crackle (search: "campfire crackle loop")
}

-- ─────────────────────────────────────────────────────────────
--  ONE-SHOT WORLD SOUND
--  Creates a temporary invisible part at `position`, attaches
--  a Sound to it, plays it, then destroys everything on Ended.
--  Roblox replicates Sound:Play() from server → all clients hear it.
-- ─────────────────────────────────────────────────────────────

function SoundManager.playAt(
    soundId  : string,
    position : Vector3,
    volume   : number?,     -- default 0.8
    maxDist  : number?      -- default 50 studs (how far the sound travels)
)
    if not soundId or soundId == "rbxassetid://0" or soundId == "" then return end

    local anchor      = Instance.new("Part")
    anchor.Name       = "SFX_Anchor"
    anchor.Anchored   = true
    anchor.CanCollide = false
    anchor.CanQuery   = false
    anchor.Transparency = 1
    anchor.Size       = Vector3.new(0.1, 0.1, 0.1)
    anchor.Position   = position
    anchor.Parent     = workspace

    local sound                  = Instance.new("Sound")
    sound.SoundId                = soundId
    sound.Volume                 = volume or 0.8
    sound.RollOffMaxDistance     = maxDist or 50
    sound.RollOffMinDistance     = 5
    sound.RollOffMode            = Enum.RollOffMode.Linear
    sound.Parent                 = anchor
    sound:Play()

    sound.Ended:Once(function()
        anchor:Destroy()
    end)
    -- Safety cleanup in case Ended never fires (e.g. ID is invalid)
    task.delay(10, function()
        if anchor.Parent then anchor:Destroy() end
    end)
end

-- Convenience wrappers so TaskSystem doesn't need to know sound IDs
function SoundManager.coalDrop(position: Vector3)
    SoundManager.playAt(SoundManager.Ids.CoalDrop, position, 0.65, 35)
end
function SoundManager.coalThrowHit(position: Vector3)
    SoundManager.playAt(SoundManager.Ids.CoalThrowHit, position, 0.85, 40)
end
function SoundManager.coalIntoFireplace(position: Vector3)
    SoundManager.playAt(SoundManager.Ids.CoalFireplace, position, 1.0, 45)
end
function SoundManager.leverPull(position: Vector3)
    -- Lever is intentionally loud — generates significant noise event
    SoundManager.playAt(SoundManager.Ids.LeverPull, position, 1.0, 60)
end
function SoundManager.batteryInsert(position: Vector3)
    SoundManager.playAt(SoundManager.Ids.BatteryInsert, position, 0.6, 30)
end

-- ─────────────────────────────────────────────────────────────
--  MONSTER SOUND CONTROLLER
--  SoundManager.new(monster) returns an object that MonsterAI
--  calls to drive the monster's own SFX.
-- ─────────────────────────────────────────────────────────────

local MonsterSounds = {}
MonsterSounds.__index = MonsterSounds

function SoundManager.new(monster: Model)
    local self    = setmetatable({}, MonsterSounds)
    local hrp     = monster:FindFirstChild("HumanoidRootPart")

    -- ── Bind to existing Sound instances in the model ────────
    -- These should already be in SoulDragger > HumanoidRootPart.
    -- Set their SoundId in Studio Properties.
    self._m = {
        Roar      = hrp and hrp:FindFirstChild("RoarSFX"),
        --[[ search: "monster roar horror", "creature growl" ]]

        Footstep  = hrp and hrp:FindFirstChild("FootstepSFX"),
        --[[ search: "heavy stone footstep monster" — set Looped=true ]]

        Bite      = hrp and hrp:FindFirstChild("BiteSFX"),
        --[[ search: "monster bite snap", "creature chomp"   ]]

        Jumpscare = hrp and hrp:FindFirstChild("JumpscareSFX"),
        --[[ search: "horror jumpscare sting", "horror stinger" ]]

        AfterJump = hrp and hrp:FindFirstChild("AfterJumpscarEndSFX"),
        --[[ search: "horror exhale heavy", "monster breathe out" ]]

        HeadCut   = hrp and hrp:FindFirstChild("HeadCutSFX"),
        --[[ search: "impact wet flesh", "horror hit impact" ]]

        Spotted   = monster:FindFirstChild("Spotted_SFX"),
        --[[ search: "horror alert sting short"              ]]
    }

    self._lastState = ""
    self._roarCD    = 0   -- prevents roar spamming on rapid re-detects

    return self
end

function MonsterSounds:_play(name: string)
    local s = self._m[name]
    if s and s:IsA("Sound") then s:Play() end
end

function MonsterSounds:_stop(name: string)
    local s = self._m[name]
    if s and s:IsA("Sound") and s.IsPlaying then s:Stop() end
end

-- ── State transitions ─────────────────────────────────────────

function MonsterSounds:onStateChange(newState: string, isChasing: boolean)
    if newState == self._lastState then return end
    self._lastState = newState

    local footstep = self._m.Footstep

    if newState == "IDLE" then
        -- Slow/quiet footsteps — or stop if PlayOnlyWhenChasing
        if footstep then
            local onlyChase = footstep:FindFirstChild("PlayOnlyWhenChasing")
            local restrict  = onlyChase and onlyChase:IsA("BoolValue") and onlyChase.Value
            if restrict then
                self:_stop("Footstep")
            else
                footstep.PlaybackSpeed = 0.75
                footstep.Volume        = 0.5
                if not footstep.IsPlaying then footstep:Play() end
            end
        end

    elseif newState == "CHASE" then
        -- Fast heavy footsteps
        if footstep then
            footstep.PlaybackSpeed = 1.55
            footstep.Volume        = 1.0
            if not footstep.IsPlaying then footstep:Play() end
        end
        -- Roar once at chase start (cooldown = 12 seconds)
        if os.clock() > self._roarCD then
            self._roarCD = os.clock() + 12
            self:_play("Roar")
        end
        -- "Spotted" sting
        self:_play("Spotted")

    elseif newState == "CATCH" then
        -- Kill movement sounds instantly
        self:_stop("Footstep")
        self:_stop("Roar")
        -- Jumpscare audio
        self:_play("Jumpscare")
        -- AfterJump plays when Jumpscare track finishes
        local jSFX = self._m.Jumpscare
        if jSFX then
            jSFX.Ended:Once(function() self:_play("AfterJump") end)
        else
            task.delay(1.5, function() self:_play("AfterJump") end)
        end
    end
end

-- ── Called from beginStrike after player is caught ────────────

function MonsterSounds:playHitSounds()
    self:_play("Bite")
    task.delay(0.35, function()
        self:_play("HeadCut")
    end)
end

return SoundManager
