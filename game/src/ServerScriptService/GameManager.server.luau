-- =============================================================
--  GameManager.server.luau
--  Orkestrator utama: init TaskSystem + SurvivalSystem
--  Path: game/src/ServerScriptService/GameManager.server.luau
--
--  Cara kerja:
--  1. Baca level + rules dari TeleportData (dikirim lobby)
--  2. Init TaskSystem (counter + task objects)
--  3. Init SurvivalSystem (hanya rules yang aktif)
--
--  PERUBAHAN (Gilang):
--  - getSessionData() sekarang RANDOM, bukan hardcode lagi.
--    Level N -> random pick N rules unik dari Constants.RULES_POOL.
--    Level kelipatan NIGHTMARE_EVERY_N_LEVELS -> pakai Constants.NIGHTMARE_RULES.
--    Level > jumlah pool unik (8) -> semua 8 rule aktif + MONSTER_DUPLICATE
--    di-stack tambahan (sesuai catatan "Level 9+: rule_duplicate mulai stack"
--    di Constants.luau).
-- =============================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local TaskSystem = require(script.Parent.TaskSystem)
local SurvivalSystem = require(script.Parent.SurvivalSystem)
local MapGenerator = require(script.Parent.MapGenerator)

-- ─────────────────────────────────────────────
--  RANDOM RULE PICKER
--  Pick `count` rule unik dari Constants.RULES_POOL (no-repeat).
--  GARANSI: Minimal 1 rule sensor (HEAR/SEE/SMELL) akan terpilih
--  agar monster tidak buta/tuli di level-level awal.
-- ─────────────────────────────────────────────
local function pickRandomRules(count: number): { string }
	local pool = table.clone(Constants.RULES_POOL)
	local picked = {}

	count = math.min(count, #pool)
	if count <= 0 then
		return picked
	end

	-- 1. Definisikan rule yang termasuk "Sense" (Indera)
	local senses = {
		Constants.Rules.MONSTER_HEAR,
		Constants.Rules.MONSTER_SEE,
		Constants.Rules.MONSTER_SMELL,
	}

	-- 2. Cari sense apa saja yang tersedia di dalam pool saat ini
	local availableSenses = {}
	for _, rule in ipairs(pool) do
		if table.find(senses, rule) then
			table.insert(availableSenses, rule)
		end
	end

	-- 3. Paksa pilih 1 sense secara acak sebagai rule pertama
	if #availableSenses > 0 then
		local forcedSense = availableSenses[math.random(1, #availableSenses)]
		table.insert(picked, forcedSense)

		-- Hapus dari pool agar tidak terpilih dua kali
		local poolIndex = table.find(pool, forcedSense)
		if poolIndex then
			table.remove(pool, poolIndex)
		end

		-- Kurangi jatah pick karena kita sudah ambil 1
		count = count - 1
	end

	-- 4. Pilih sisanya secara acak dari sisa pool (bisa jadi dapat sense tambahan)
	for _ = 1, count do
		local index = math.random(1, #pool)
		table.insert(picked, pool[index])
		table.remove(pool, index)
	end

	return picked
end

-- ─────────────────────────────────────────────
--  Hitung berapa kali MONSTER_DUPLICATE harus "stack" di level tinggi.
--  Level 9  -> +1 stack tambahan (selain yang mungkin sudah ke-pick normal)
--  Level 17 -> +2 stack tambahan, dst (tiap +8 level di atas 8, +1 stack)
--  Catatan: ini interpretasi dari comment Constants.luau ("level 9+:
--  rule_duplicate mulai stack (2x, 4x, 8x monster)"). Sesuaikan formula
--  ini kalau Arkan punya definisi pasti berapa banyak stack per level.
-- ─────────────────────────────────────────────
local function getDuplicateStackCount(level: number): number
	local poolSize = #Constants.RULES_POOL -- 8

	if level <= poolSize then
		return 0
	end

	return math.floor((level - poolSize - 1) / poolSize) + 1
end

-- ─────────────────────────────────────────────
--  Generate rules berdasarkan level.
--  - Level kelipatan NIGHTMARE_EVERY_N_LEVELS -> Nightmare combo (fixed)
--  - Level <= jumlah pool (8) -> random pick N rule unik
--  - Level > 8 -> semua rule aktif + MONSTER_DUPLICATE di-stack
--    (ditambahkan sebagai entry duplikat di list, supaya SurvivalSystem/
--    MonsterAI yang nge-loop rules bisa lihat "monster_duplicate" lebih
--    dari sekali kalau mereka memang count occurrence-nya)
-- ─────────────────────────────────────────────
local function generateRulesForLevel(level: number): { string }
	if Constants.NIGHTMARE_EVERY_N_LEVELS > 0 and level % Constants.NIGHTMARE_EVERY_N_LEVELS == 0 then
		return table.clone(Constants.NIGHTMARE_RULES)
	end

	if level <= #Constants.RULES_POOL then
		return pickRandomRules(level)
	end

	-- Level 9+: semua rule unik aktif + stack tambahan untuk duplicate
	local rules = table.clone(Constants.RULES_POOL)
	local extraStacks = getDuplicateStackCount(level)

	for _ = 1, extraStacks do
		table.insert(rules, Constants.Rules.MONSTER_DUPLICATE)
	end

	return rules
end

-- ─────────────────────────────────────────────
--  Baca TeleportData yang dikirim lobby
--  Format: { level = number, rules = {string}, mode = string }
--
--  Fallback: level 1, rules di-random dari pool (bukan hardcode lagi)
-- ─────────────────────────────────────────────
-- 1. Pass 'firstPlayer' into the function and fix the rules assignment
local function getSessionData(firstPlayer: Player) --: { level: number, rules: { string }, mode: string }
	if firstPlayer then
		local joinData = firstPlayer:GetJoinData()
		local teleportData = joinData and joinData.TeleportData
		if teleportData and teleportData.level then
			local targetLevel = teleportData.level
			return {
				level = targetLevel,
				-- FIX: If lobby didn't send custom rules, generate them based on the level!
				rules = (teleportData.rules and #teleportData.rules > 0) and teleportData.rules
					or generateRulesForLevel(targetLevel),
				mode = teleportData.mode or Constants.GameMode.REGULAR,
			}
		end
	end

	-- ── DEFAULT SESSION (untuk testing tanpa lobby) ──
	local level = 1
	return {
		level = level,
		rules = generateRulesForLevel(level),
		mode = Constants.GameMode.REGULAR,
	}
end

-- ─────────────────────────────────────────────
--  Alternatif: terima data via ObjectValue di ServerStorage
--  Lobby bisa set value sebelum teleport.
--  Uncomment jika pakai pendekatan ini:
-- ─────────────────────────────────────────────
--[[
local function getSessionDataFromStorage()
    local ss   = game:GetService("ServerStorage")
    local data = ss:FindFirstChild("SessionData")
    if not data then return getSessionData() end

    local level  = data:FindFirstChild("Level")
    local mode   = data:FindFirstChild("Mode")
    local ruleList = data:FindFirstChild("Rules")

    local rules = {}
    if ruleList then
        for _, v in ipairs(ruleList:GetChildren()) do
            table.insert(rules, v.Value)
        end
    end

    -- Kalau lobby tidak kirim rules eksplisit, fallback ke random:
    if #rules == 0 then
        rules = generateRulesForLevel(level and level.Value or 1)
    end

    return {
        level = level and level.Value or 1,
        rules = rules,
        mode  = mode and mode.Value or Constants.GameMode.REGULAR,
    }
end
]]

-- ─────────────────────────────────────────────
--  Main init
-- ─────────────────────────────────────────────
math.randomseed(os.time())

local firstPlayer = Players:GetPlayers()[1] or Players.PlayerAdded:Wait()

task.wait() -- yield one heartbeat so MonsterAI can connect its ServerMapGenerated listener

local session = getSessionData(firstPlayer) -- FIX: Pass firstPlayer here

print(
	string.format(
		"[GameManager] Sesi dimulai — Level: %d | Mode: %s | Rules: %s",
		session.level,
		session.mode,
		table.concat(session.rules, ", ")
	)
)

-- ─────────────────────────────────────────────
--  1. SessionInfo + RulesBindable DULU
--     MonsterAI.server.luau melakukan WaitForChild("RulesBindable", 5)
--     SEBELUM ia connect listener ServerMapGenerated.
--     Kalau kita generate map sebelum RulesBindable ada, MonsterAI
--     masih tertahan 5 detik → event map sudah terlewat.
-- ─────────────────────────────────────────────
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RE_RulesActivated = Remotes:WaitForChild("RulesActivated")

local sessionInfo = Instance.new("Folder")
sessionInfo.Name = "SessionInfo"
sessionInfo.Parent = ReplicatedStorage

local levelVal = Instance.new("IntValue")
levelVal.Name = "Level"
levelVal.Value = session.level
levelVal.Parent = sessionInfo

local modeVal = Instance.new("StringValue")
modeVal.Name = "Mode"
modeVal.Value = session.mode
modeVal.Parent = sessionInfo

local rulesFolder = Instance.new("Folder")
rulesFolder.Name = "ActiveRules"
rulesFolder.Parent = sessionInfo

for i, rule in ipairs(session.rules) do
	local v = Instance.new("StringValue")
	v.Name = rule .. "_" .. i
	v.Value = rule
	v.Parent = rulesFolder
end

RE_RulesActivated:FireAllClients(session.rules)

local RulesBindable = Remotes:FindFirstChild("RulesBindable")
if RulesBindable and not RulesBindable:IsA("BindableEvent") then
	warn("[GameManager] Instance 'RulesBindable' ditemukan tapi bukan BindableEvent, akan dibuat ulang.")
	RulesBindable:Destroy()
	RulesBindable = nil
end
if not RulesBindable then
	RulesBindable = Instance.new("BindableEvent")
	RulesBindable.Name = "RulesBindable"
	RulesBindable.Parent = Remotes
end
RulesBindable:Fire(session.rules)

-- ─────────────────────────────────────────────
--  2. Yield satu heartbeat
--     RulesBindable baru di-parent → MonsterAI di-queue untuk resume.
--     Tapi MonsterAI baru benar-benar jalan setelah kita yield.
--     Selama heartbeat ini MonsterAI: dapat RulesBindable, baca
--     SessionInfo, lalu connect mapBE.Event — siap menerima event map.
-- ─────────────────────────────────────────────
task.wait()

-- ─────────────────────────────────────────────
--  3. Generate map — MonsterAI listener sudah terpasang
-- ─────────────────────────────────────────────
MapGenerator.generateMap(session.level)

-- ─────────────────────────────────────────────
--  4. Init systems (setelah map ada di workspace)
-- ─────────────────────────────────────────────
TaskSystem.init(session.level)
SurvivalSystem.init(session.rules)
