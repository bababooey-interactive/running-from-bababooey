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

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService   = game:GetService("TeleportService")

local Constants      = require(ReplicatedStorage.Shared.Constants)
local TaskSystem     = require(script.Parent.TaskSystem)
local SurvivalSystem = require(script.Parent.SurvivalSystem)

-- ─────────────────────────────────────────────
--  RANDOM RULE PICKER
--  Pick `count` rule unik dari Constants.RULES_POOL (no-repeat).
--  Kalau count >= jumlah pool, return semua pool apa adanya.
-- ─────────────────────────────────────────────
local function pickRandomRules(count: number): {string}
    local pool = table.clone(Constants.RULES_POOL)
    local picked = {}

    count = math.min(count, #pool)

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
local function generateRulesForLevel(level: number): {string}
    if Constants.NIGHTMARE_EVERY_N_LEVELS > 0
        and level % Constants.NIGHTMARE_EVERY_N_LEVELS == 0
    then
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
local function getSessionData(): {level: number, rules: {string}, mode: string}
    -- Ambil dari player pertama yang masuk
    local firstPlayer = Players:GetPlayers()[1]
    if firstPlayer then
        local ok, data = pcall(function()
            return TeleportService:GetLocalPlayerTeleportData()
        end)
        -- Note: GetLocalPlayerTeleportData hanya tersedia di LocalScript.
        -- Untuk server, gunakan pendekatan via DataStore atau BindableEvent dari lobby.
        -- Sementara fallback ke default di bawah:
    end

    -- ── DEFAULT SESSION (untuk testing tanpa lobby) ──
    -- TODO: ganti level di sini untuk testing manual level berapa pun
    local level = 10

    return {
        level = level,
        rules = generateRulesForLevel(level),
        mode  = Constants.GameMode.REGULAR,
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

local session = getSessionData()

print(string.format(
    "[GameManager] Sesi dimulai — Level: %d | Mode: %s | Rules: %s",
    session.level,
    session.mode,
    table.concat(session.rules, ", ")
))

-- Init task system dulu (task objects di-hook)
TaskSystem.init(session.level)

-- Init survival system (hanya rules yang aktif)
SurvivalSystem.init(session.rules)

-- ─────────────────────────────────────────────
--  Expose session info ke ReplicatedStorage
--  agar client bisa tahu rules mana yang aktif
-- ─────────────────────────────────────────────
local sessionInfo = Instance.new("Folder")
sessionInfo.Name   = "SessionInfo"
sessionInfo.Parent = ReplicatedStorage

local levelVal = Instance.new("IntValue")
levelVal.Name   = "Level"
levelVal.Value  = session.level
levelVal.Parent = sessionInfo

local modeVal = Instance.new("StringValue")
modeVal.Name   = "Mode"
modeVal.Value  = session.mode
modeVal.Parent = sessionInfo

local rulesFolder = Instance.new("Folder")
rulesFolder.Name   = "ActiveRules"
rulesFolder.Parent = sessionInfo

for i, rule in ipairs(session.rules) do
    local v = Instance.new("StringValue")
    -- Name dibuat unik (rule .. index) supaya MONSTER_DUPLICATE yang
    -- di-stack lebih dari sekali tidak saling menimpa di bawah Folder
    -- yang sama (2 child tidak boleh nama sama persis kalau mau
    -- di-:GetChildren() dengan aman satu-satu).
    v.Name   = rule .. "_" .. i
    v.Value  = rule
    v.Parent = rulesFolder
end

-- ─────────────────────────────────────────────
--  Broadcast rules ke CLIENT lewat RemoteEvent "RulesActivated"
--  (sudah dibuat oleh RemoteSetup.server.luau, comment di situ:
--  "server→all: active rules list" — jadi ini memang sudah
--  direncanakan tim, kita tinggal pakai).
--
--  PENTING: RemoteSetup.server.luau HARUS jalan duluan sebelum
--  GameManager (urutan di ServerScriptService biasanya alfabetis,
--  "GameManager" < "RemoteSetup" secara abjad — kalau Studio jalanin
--  alfabetis, ini bisa salah urutan! Cek Script Order kalau error
--  "infinite yield" muncul di WaitForChild di bawah ini).
-- ─────────────────────────────────────────────
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RE_RulesActivated = Remotes:WaitForChild("RulesActivated")

RE_RulesActivated:FireAllClients(session.rules)

-- ─────────────────────────────────────────────
--  RulesBindable (BindableEvent, Server -> Server)
--
--  Untuk script SERVER lain (mis. MonsterAI.server.luau) yang butuh
--  rules begitu sesi mulai. RemoteEvent "RulesActivated" di atas itu
--  cuma untuk Server -> Client, TIDAK bisa di-:Connect() dari server
--  lain (server tidak punya .OnClientEvent). Makanya tetap disediakan
--  BindableEvent terpisah ini khusus untuk kebutuhan server -> server.
--
--  CATATAN PENTING: nama-nya "RulesBindable", BUKAN "RulesActivated".
--  "RulesActivated" sudah dipakai sebagai RemoteEvent (lihat di atas).
--  RemoteEvent dan BindableEvent itu beda class — RemoteEvent tidak
--  punya method :Fire() (cuma :FireServer()/:FireClient()/dst), jadi
--  kalau nama dipakai sama, FindFirstChild akan nemu RemoteEvent itu
--  dan crash saat dipanggil :Fire(). Makanya dipakai nama unik di sini.
--
--  Payload: array of string (session.rules), SAMA PERSIS isinya
--  dengan ReplicatedStorage.SessionInfo.ActiveRules (cuma beda
--  bentuk: ini array biasa, bukan Folder of StringValue).
--
--  Cara pakai di MonsterAI.server.luau (tinggal sambungkan sendiri):
--    local Remotes = ReplicatedStorage:WaitForChild("Remotes")
--    Remotes:WaitForChild("RulesBindable").Event:Connect(function(rules)
--        activeRules = rules
--    end)
--
--  Catatan: event ini di-fire SEKALI saat GameManager init (server
--  start). Kalau script lain baru listen SETELAH fire ini terjadi,
--  mereka akan miss event-nya — dalam kasus itu, baca langsung dari
--  ReplicatedStorage.SessionInfo.ActiveRules sebagai fallback.
-- ─────────────────────────────────────────────
local RulesBindable = Remotes:FindFirstChild("RulesBindable")

-- Validasi tipe: kalau somehow ada instance lama dengan nama ini tapi
-- bukan BindableEvent (mis. sisa RemoteEvent dari percobaan lain),
-- buang dan buat ulang yang benar, daripada crash diam-diam.
if RulesBindable and not RulesBindable:IsA("BindableEvent") then
    warn("[GameManager] Instance 'RulesBindable' ditemukan tapi bukan BindableEvent, akan dibuat ulang.")
    RulesBindable:Destroy()
    RulesBindable = nil
end

if not RulesBindable then
    RulesBindable = Instance.new("BindableEvent")
    RulesBindable.Name   = "RulesBindable"
    RulesBindable.Parent = Remotes
end

RulesBindable:Fire(session.rules)
