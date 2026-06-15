
-- =============================================================
--  SensorSystem.luau  (ModuleScript — Day 4-6)
--  Monster perception: Hearing (active), Smell/Vision (stubs for Day 7)
--
--  require() dari MonsterAI.server.luau (server-side only)
--  Semua data noise disimpan di sini, tidak replikasi ke client.
-- =============================================================

local Constants = require(game.ReplicatedStorage.Shared.Constants)

local SensorSystem = {}

-- ─────────────────────────────────────────────
--  NOISE EVENT STORE
--  Diisi oleh server saat menerima PlayerMakeNoise RemoteEvent
--  atau saat player selesaikan task (coal drop, lever pull, dst.)
-- ─────────────────────────────────────────────

type NoiseEvent = {
	player   : Player,
	position : Vector3,
	level    : number,   -- 0..1, besar = lebih keras
	expireAt : number,   -- os.clock() saat noise expire
}

local noiseEvents : {NoiseEvent} = {}
local NOISE_LIFETIME = 3.5   -- detik sebelum noise event expired

-- ─────────────────────────────────────────────
--  PUBLIC: tambah noise event baru
--  Dipanggil dari MonsterAI saat menerima PlayerMakeNoise
-- ─────────────────────────────────────────────

function SensorSystem.AddNoise(player : Player, position : Vector3, level : number)
	table.insert(noiseEvents, {
		player   = player,
		position = position,
		level    = math.clamp(level, 0, 1),
		expireAt = os.clock() + NOISE_LIFETIME,
	})
end

-- ─────────────────────────────────────────────
--  INTERNAL: hapus noise yang sudah expired
-- ─────────────────────────────────────────────

local function cleanNoise()
	local now = os.clock()
	for i = #noiseEvents, 1, -1 do
		if now >= noiseEvents[i].expireAt then
			table.remove(noiseEvents, i)
		end
	end
end

-- ─────────────────────────────────────────────
--  HEARING CHECK
--  Returns noise event terkuat dalam radius, atau nil.
--  Rule MONSTER_HEAR harus aktif.
-- ─────────────────────────────────────────────

function SensorSystem.CheckHearing(
	monsterPos  : Vector3,
	activeRules : {string}
) : NoiseEvent?

	if not table.find(activeRules, Constants.Rules.MONSTER_HEAR) then
		return nil
	end

	cleanNoise()

	local hearRadius = Constants.MONSTER_HEAR_RADIUS
	local bestEvent  : NoiseEvent? = nil
	local bestScore  = 0

	for _, event in ipairs(noiseEvents) do
		local dist = (monsterPos - event.position).Magnitude
		if dist <= hearRadius then
			-- Score: lebih keras + lebih dekat = lebih prioritas
			local score = event.level * (1 - dist / hearRadius)
			if score > bestScore then
				bestScore = score
				bestEvent = event
			end
		end
	end

	return bestEvent
end

-- ─────────────────────────────────────────────
--  SMELL CHECK  (Day 7 — stub)
-- ─────────────────────────────────────────────

function SensorSystem.CheckSmell(
    monsterPos  : Vector3,
    players     : {Player},
    activeRules : {string}
) : Player?

    if not table.find(activeRules, Constants.Rules.MONSTER_SMELL) then return nil end

    local closestPlayer = nil
    local closestDist = Constants.MONSTER_SMELL_RADIUS

    for _, player in ipairs(players) do
        local char = player.Character
        if not char then continue end
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if not hrp then continue end

        local dist = (monsterPos - hrp.Position).Magnitude
        if dist <= closestDist then
            closestDist = dist
            closestPlayer = player
        end
    end

    return closestPlayer
end
-- ─────────────────────────────────────────────
--  VISION CHECK  (Day 7 — stub)
-- ─────────────────────────────────────────────

function SensorSystem.CheckVision(
	monster     : Model,
	monsterPos  : Vector3,
	players     : {Player},
	activeRules : {string}
) : Player?

	if not table.find(activeRules, Constants.Rules.MONSTER_SEE) then
		return nil
	end
	-- Implementation: Day 7 (raycast + lit area check)
	return nil
end

-- ─────────────────────────────────────────────
--  AWARENESS LEVEL  (0..1, per player)
--  Dipakai untuk update UI indicator milik player.
--  0 = monster tidak tahu keberadaan player
--  1 = monster sangat fokus ke player ini
-- ─────────────────────────────────────────────

function SensorSystem.GetAwarenessForPlayer(
	monsterPos  : Vector3,
	monster     : Model,
	player      : Player,
	activeRules : {string},
	isChasing   : boolean,
	chaseTarget : Player?
) : number

	local char = player.Character
	if not char then return 0 end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then return 0 end

	-- Kalau monster sedang CHASE dan target adalah player ini → full awareness
	if isChasing and chaseTarget == player then
		return 1.0
	end

	local playerPos  = hrp.Position
	local awareness  = 0

	-- Kontribusi HEARING: cek apakah ada noise event dari player ini dekat monster
	if table.find(activeRules, Constants.Rules.MONSTER_HEAR) then
		cleanNoise()
		for _, event in ipairs(noiseEvents) do
			if event.player ~= player then continue end
			local dist = (monsterPos - event.position).Magnitude
			if dist <= Constants.MONSTER_HEAR_RADIUS then
				local contribution = event.level * (1 - dist / Constants.MONSTER_HEAR_RADIUS)
				awareness = math.max(awareness, contribution * 0.85)
			end
		end
	end

	-- Kontribusi SMELL
	if table.find(activeRules, Constants.Rules.MONSTER_SMELL) then
		local dist = (monsterPos - playerPos).Magnitude
		if dist <= Constants.MONSTER_SMELL_RADIUS then
			local contribution = (1 - dist / Constants.MONSTER_SMELL_RADIUS) * 0.7
			awareness = math.max(awareness, contribution)
		end
	end

	-- Kontribusi VISION (cone check saja, raycast di Day 7)
    if table.find(activeRules, Constants.Rules.MONSTER_SEE) then
        local rootPart = monster:FindFirstChild("rb") or monster.PrimaryPart
        if rootPart then
            local dir  = (playerPos - monsterPos)
            local dist = dir.Magnitude
            if dist <= Constants.MONSTER_VISION_RANGE then
                if dist < 0.1 then
                    -- Prevent NaN error if distance is exactly 0
                    awareness = 1
                else
                    local cosAngle  = rootPart.CFrame.LookVector:Dot(dir.Unit)
                    local halfAngle = math.rad(Constants.MONSTER_VISION_ANGLE)
                    if cosAngle >= math.cos(halfAngle) then
                        local contribution = (1 - dist / Constants.MONSTER_VISION_RANGE) * cosAngle
                        awareness = math.max(awareness, contribution)
                    end
                end
            end
        end
    end

	return math.clamp(awareness, 0, 1)
end

-- ─────────────────────────────────────────────
--  NOISE LEVEL PROXY
--  Dipakai MonsterAI untuk kirim "noise level player" ke UI
--  (berapa keras player saat ini dari sudut pandang noise store)
-- ─────────────────────────────────────────────

function SensorSystem.GetRecentNoiseForPlayer(player : Player) : number
	cleanNoise()
	local highest = 0
	for _, event in ipairs(noiseEvents) do
		if event.player == player then
			highest = math.max(highest, event.level)
		end
	end
	return highest
end

return SensorSystem
