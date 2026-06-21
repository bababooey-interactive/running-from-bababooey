-- =============================================================
--  LobbyRoomManager.server.luau
--  Author: Gilang
--  Path: lobby/src/ServerScriptService/LobbyRoomManager.server.luau
--
--  Tanggung jawab:
--  - Handle 2 plate fisik (Solo / Coop) di lobby
--  - Solo: player pilih level sendiri, langsung jalan (skip voting)
--  - Coop: 1 room tunggal (belum multi-room), player join, vote level,
--    ready-up, begitu SEMUA ready -> StartingGame -> teleport bareng
--  - Implementasi server-side dari RemoteEvents.luau yang sudah ada
--
--  CARA SETUP DI STUDIO:
--  1. Buat 2 Part di Workspace > Lobby > ModePlates (folder baru,
--     sesuaikan MODE_PLATES_PATH kalau struktur Anda beda).
--  2. Set Attribute "RoomMode" di tiap Part = "SOLO" atau "COOP".
-- =============================================================

local Workspace         = game:GetService("Workspace")
local Players            = game:GetService("Players")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local TeleportService    = game:GetService("TeleportService")
local HttpService        = game:GetService("HttpService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Types      = require(ReplicatedStorage.Shared.Types) -- hanya untuk dokumentasi/referensi tipe

local PlayerProgressStore = require(script.Parent.PlayerProgressStore)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local function R(name: string): RemoteEvent
    return Remotes:WaitForChild(name) :: RemoteEvent
end

local RE = {
    RoomListUpdated       = R("RoomListUpdated"),
    RoomStateUpdated      = R("RoomStateUpdated"),
    CreateRoom            = R("CreateRoom"),
    JoinRoom              = R("JoinRoom"),
    LeaveRoom             = R("LeaveRoom"),
    PlayerReadyUp         = R("PlayerReadyUp"),
    VoteForLevel          = R("VoteForLevel"),
    VoteResultUpdated     = R("VoteResultUpdated"),
    StartingGame          = R("StartingGame"),
    PlayerProgressLoaded  = R("PlayerProgressLoaded"),
}

-- ============================================================
-- CONFIG
-- ============================================================

local MODE_PLATES_PATH = { "Lobby", "ModePlates" } -- Workspace.Lobby.ModePlates

local STARTING_GAME_COUNTDOWN = 5 -- detik, jeda sebelum teleport beneran terjadi

-- ============================================================
-- STATE
-- ============================================================

-- Progress player sekarang dikelola PlayerProgressStore.luau (DataStore
-- + cache in-memory selama sesi). Tidak ada state lokal di sini lagi.

-- Room Coop TUNGGAL (belum multi-room, sesuai kesepakatan).
-- nil kalau belum ada room aktif.
local coopRoom: {
    id: string,
    hostName: string,
    gameMode: string,
    roomMode: string,
    players: { Player },
    votes: { [string]: number }, -- [playerName] = votedLevel
    readyPlayers: { [string]: boolean },
    maxLevel: number,
    locked: boolean, -- true setelah StartingGame di-fire, supaya tidak diproses dobel
}? = nil

-- ============================================================
-- HELPERS: PROGRESS
-- ============================================================

-- Wrapper tipis: progress sesungguhnya dikelola PlayerProgressStore
-- (DataStore + cache). Nama fungsi dipertahankan supaya pemanggil di
-- bawah tidak perlu diubah satu-satu.
local function getOrInitProgress(player: Player)
    return PlayerProgressStore.Load(player)
end

local function sendProgressToPlayer(player: Player)
    -- Sebelum kirim ke client, cek dulu apakah player ini baru saja
    -- balik dari Game Place (menang/kalah) dan apply hasilnya, supaya
    -- unlockedLevel yang dikirim sudah ter-update.
    local joinData = player:GetJoinData()
    local teleportData = joinData and joinData.TeleportData

    if teleportData then
        PlayerProgressStore.ApplyMatchResult(player, teleportData)
    end

    local progress = getOrInitProgress(player)
    RE.PlayerProgressLoaded:FireClient(player, progress)
end

-- ============================================================
-- HELPERS: ROOM (COOP)
-- ============================================================

local function buildRoomInfo()
    if not coopRoom then
        return nil
    end

    -- Hitung winningLevel sementara (vote terbanyak, tie -> level lebih rendah)
    local tally: { [number]: number } = {}
    for _, level in pairs(coopRoom.votes) do
        tally[level] = (tally[level] or 0) + 1
    end

    local winningLevel = 1
    local bestCount = -1
    for level, count in pairs(tally) do
        if count > bestCount or (count == bestCount and level < winningLevel) then
            bestCount = count
            winningLevel = level
        end
    end

    local readyCount = 0
    for _ in pairs(coopRoom.readyPlayers) do
        readyCount += 1
    end

    return {
        id            = coopRoom.id,
        hostName      = coopRoom.hostName,
        gameMode      = coopRoom.gameMode,
        roomMode      = coopRoom.roomMode,
        selectedLevel = winningLevel,
        maxLevel      = coopRoom.maxLevel,
        playerCount   = #coopRoom.players,
        maxPlayers    = 8, -- TODO: sesuaikan limit coop sebenarnya
        readyCount    = readyCount,
    }
end

local function broadcastRoomState()
    if not coopRoom then
        return
    end

    local info = buildRoomInfo()

    for _, player in ipairs(coopRoom.players) do
        RE.RoomStateUpdated:FireClient(player, info)
    end

    -- RoomListUpdated: karena cuma 1 room, kirim list isinya 1 item saja
    -- (atau kosong kalau room sudah tidak ada). Broadcast ke semua orang
    -- di lobby (bukan cuma yang di room), supaya UI "room list" konsisten.
    local list = coopRoom and { info } or {}

    for _, player in ipairs(Players:GetPlayers()) do
        RE.RoomListUpdated:FireClient(player, list)
    end
end

local function broadcastVoteResult()
    if not coopRoom then
        return
    end

    local info = buildRoomInfo()

    for _, player in ipairs(coopRoom.players) do
        RE.VoteResultUpdated:FireClient(player, {
            votes         = coopRoom.votes,
            winningLevel  = info.selectedLevel,
            timeRemaining = 0, -- tidak pakai countdown durasi, selesai saat semua ready
        })
    end
end

local function getOrCreateCoopRoom(host: Player)
    if coopRoom and not coopRoom.locked then
        return coopRoom
    end

    local hostProgress = getOrInitProgress(host)

    coopRoom = {
        id            = HttpService:GenerateGUID(false),
        hostName      = host.Name,
        gameMode      = Constants.GameMode.REGULAR,
        roomMode      = "COOP",
        players       = {},
        votes         = {},
        readyPlayers  = {},
        maxLevel      = hostProgress.unlockedLevel,
        locked        = false,
    }

    return coopRoom
end

local function addPlayerToCoopRoom(player: Player)
    local room = getOrCreateCoopRoom(player)

    for _, existing in ipairs(room.players) do
        if existing == player then
            return -- sudah di room
        end
    end

    table.insert(room.players, player)

    -- maxLevel room = level unlock TERENDAH di antara anggota (supaya adil,
    -- tidak ada yang vote level yang belum di-unlock anggota lain)
    local progress = getOrInitProgress(player)
    room.maxLevel = math.min(room.maxLevel, progress.unlockedLevel)

    print(string.format("[LobbyRoomManager] %s join Coop room (%d player sekarang)", player.Name, #room.players))

    broadcastRoomState()
end

local function removePlayerFromCoopRoom(player: Player)
    if not coopRoom then
        return
    end

    for i = #coopRoom.players, 1, -1 do
        if coopRoom.players[i] == player then
            table.remove(coopRoom.players, i)
        end
    end

    coopRoom.votes[player.Name] = nil
    coopRoom.readyPlayers[player.Name] = nil

    print(string.format("[LobbyRoomManager] %s keluar dari Coop room (%d player tersisa)", player.Name, #coopRoom.players))

    if #coopRoom.players == 0 then
        coopRoom = nil
        print("[LobbyRoomManager] Coop room dibubarkan (kosong).")
    else
        broadcastRoomState()
        broadcastVoteResult()
    end
end

-- ============================================================
-- TELEPORT
-- ============================================================

-- Bungkus teleport dengan pcall + cek PlaceId, supaya bisa ditest
-- sebelum Place benar-benar dipublish (Constants.GAME_PLACE_ID = 0
-- berarti belum di-setup, jadi di-skip dengan print, bukan error).
local function teleportPlayersToGame(players: { Player }, level: number, gameMode: string, roomId: string)
    if Constants.GAME_PLACE_ID == 0 then
        warn(string.format(
            "[LobbyRoomManager] GAME_PLACE_ID belum di-set (masih 0). Teleport DI-SKIP. " ..
            "Akan teleport %d player ke level %d (%s) begitu Place sudah dipublish & ID diisi.",
            #players, level, gameMode
        ))
        return
    end

    local teleportOptions = Instance.new("TeleportOptions")
    teleportOptions:SetTeleportData({
        level  = level,
        mode   = gameMode,
        roomId = roomId,
    })

    local ok, err = pcall(function()
        TeleportService:TeleportAsync(Constants.GAME_PLACE_ID, players, teleportOptions)
    end)

    if not ok then
        warn("[LobbyRoomManager] Teleport gagal:", err)
    end
end

local function beginStartingGameSequence(players: { Player }, level: number, gameMode: string, roomId: string)
    for _, player in ipairs(players) do
        RE.StartingGame:FireClient(player, level, gameMode, STARTING_GAME_COUNTDOWN)
    end

    task.delay(STARTING_GAME_COUNTDOWN, function()
        teleportPlayersToGame(players, level, gameMode, roomId)
    end)
end

-- ============================================================
-- SOLO FLOW
-- ============================================================

-- Dipanggil saat player pilih level di mode Solo (lihat LevelSelectUI).
-- Solo skip voting & ready-up sepenuhnya, langsung gas.
local function startSoloGame(player: Player, level: number)
    local progress = getOrInitProgress(player)
    level = math.clamp(level, 1, progress.unlockedLevel)

    print(string.format("[LobbyRoomManager] %s mulai SOLO di level %d", player.Name, level))

    local roomId = HttpService:GenerateGUID(false)
    beginStartingGameSequence({ player }, level, Constants.GameMode.REGULAR, roomId)
end

-- ============================================================
-- REMOTE EVENT HANDLERS
-- ============================================================

RE.CreateRoom.OnServerEvent:Connect(function(player, gameMode: string, roomMode: string)
    if roomMode == "SOLO" then
        -- Solo tidak benar-benar butuh "room" persisten, tapi tetap
        -- terima event ini untuk konsistensi API. Level dipilih lewat
        -- VoteForLevel di bawah (langsung dianggap final untuk Solo).
        return
    end

    addPlayerToCoopRoom(player)
end)

RE.JoinRoom.OnServerEvent:Connect(function(player, roomId: string)
    -- Karena cuma 1 room Coop, roomId di sini diabaikan validasinya
    -- (cukup join room Coop yang ada/baru). Kalau nanti multi-room,
    -- roomId dipakai untuk cari room yang tepat.
    addPlayerToCoopRoom(player)
end)

RE.LeaveRoom.OnServerEvent:Connect(function(player)
    removePlayerFromCoopRoom(player)
end)

RE.VoteForLevel.OnServerEvent:Connect(function(player, votedLevel: number)
    -- ── SOLO: vote langsung jadi keputusan final, tidak masuk coopRoom ──
    local isInCoopRoom = false

    if coopRoom then
        for _, p in ipairs(coopRoom.players) do
            if p == player then
                isInCoopRoom = true
                break
            end
        end
    end

    if not isInCoopRoom then
        startSoloGame(player, votedLevel)
        return
    end

    -- ── COOP: simpan vote, broadcast hasil ──
    local progress = getOrInitProgress(player)
    votedLevel = math.clamp(votedLevel, 1, math.min(progress.unlockedLevel, coopRoom.maxLevel))

    coopRoom.votes[player.Name] = votedLevel
    print(string.format("[LobbyRoomManager] %s vote level %d (Coop)", player.Name, votedLevel))

    broadcastVoteResult()
end)

RE.PlayerReadyUp.OnServerEvent:Connect(function(player)
    if not coopRoom or coopRoom.locked then
        return
    end

    local isInRoom = false
    for _, p in ipairs(coopRoom.players) do
        if p == player then
            isInRoom = true
            break
        end
    end

    if not isInRoom then
        return
    end

    -- Player harus sudah vote sebelum bisa ready (biar winningLevel valid)
    if not coopRoom.votes[player.Name] then
        warn(string.format("[LobbyRoomManager] %s coba ready tanpa vote dulu, diabaikan.", player.Name))
        return
    end

    coopRoom.readyPlayers[player.Name] = true
    print(string.format("[LobbyRoomManager] %s ready (%d/%d)", player.Name, (function()
        local c = 0
        for _ in pairs(coopRoom.readyPlayers) do c += 1 end
        return c
    end)(), #coopRoom.players))

    broadcastRoomState()

    -- ── Cek apakah SEMUA player di room sudah ready ──
    local allReady = true
    for _, p in ipairs(coopRoom.players) do
        if not coopRoom.readyPlayers[p.Name] then
            allReady = false
            break
        end
    end

    if allReady and #coopRoom.players > 0 then
        coopRoom.locked = true

        local info = buildRoomInfo()
        local playersSnapshot = table.clone(coopRoom.players)
        local roomId = coopRoom.id

        print(string.format(
            "[LobbyRoomManager] Semua ready di Coop room! Level %d, %d player. Memulai countdown.",
            info.selectedLevel, #playersSnapshot
        ))

        beginStartingGameSequence(playersSnapshot, info.selectedLevel, coopRoom.gameMode, roomId)

        -- Bersihkan room SETELAH countdown selesai, biar room baru bisa
        -- terbentuk untuk player lain yang masih di lobby.
        task.delay(STARTING_GAME_COUNTDOWN + 1, function()
            if coopRoom and coopRoom.id == roomId then
                coopRoom = nil
                broadcastRoomState()
            end
        end)
    end
end)

-- ============================================================
-- PLATE TOUCH HANDLER
-- ============================================================

local playersOnCooldown: { [Player]: boolean } = {}

local function getPlayerFromPart(part: BasePart): Player?
    local character = part.Parent
    if not character then
        return nil
    end
    return Players:GetPlayerFromCharacter(character)
end

local function onPlateTouched(roomMode: string)
    return function(hit: BasePart)
        local player = getPlayerFromPart(hit)
        if not player then
            return
        end

        if playersOnCooldown[player] then
            return
        end

        playersOnCooldown[player] = true
        task.delay(1, function()
            playersOnCooldown[player] = nil
        end)

        if roomMode == "COOP" then
            addPlayerToCoopRoom(player)
        end

        -- Untuk SOLO, plate cuma trigger UI level-select (lihat
        -- LevelSelectUI.client.luau) — server tidak perlu lakukan
        -- apa-apa di sini selain memastikan player TIDAK sedang di
        -- coop room (kalau iya, keluarkan dulu).
        if roomMode == "SOLO" then
            removePlayerFromCoopRoom(player)
        end

        -- Beri tahu client mode apa yang dipilih, supaya LevelSelectUI
        -- tahu mau tampilkan UI Solo atau Coop.
        local progress = getOrInitProgress(player)
        local maxLevel = progress.unlockedLevel

        if roomMode == "COOP" and coopRoom then
            maxLevel = coopRoom.maxLevel
        end

        RE.RoomStateUpdated:FireClient(player, {
            id            = roomMode == "COOP" and coopRoom and coopRoom.id or "SOLO_" .. player.UserId,
            hostName      = player.Name,
            gameMode      = Constants.GameMode.REGULAR,
            roomMode      = roomMode,
            selectedLevel = 1,
            maxLevel      = maxLevel,
            playerCount   = roomMode == "COOP" and coopRoom and #coopRoom.players or 1,
            maxPlayers    = 8,
            readyCount    = 0,
        })
    end
end

local function setupPlates()
    local current = Workspace
    for _, name in ipairs(MODE_PLATES_PATH) do
        current = current:WaitForChild(name)
    end

    for _, plate in ipairs(current:GetChildren()) do
        if plate:IsA("BasePart") then
            local roomMode = plate:GetAttribute("RoomMode")

            if roomMode ~= "SOLO" and roomMode ~= "COOP" then
                warn("[LobbyRoomManager] Plate dengan Attribute 'RoomMode' tidak valid:", plate:GetFullName())
            else
                plate.Touched:Connect(onPlateTouched(roomMode))
                print("[LobbyRoomManager] Plate terdaftar:", plate.Name, "->", roomMode)
            end
        end
    end
end

-- ============================================================
-- PLAYER LIFECYCLE
-- ============================================================

Players.PlayerAdded:Connect(function(player)
    sendProgressToPlayer(player)
end)

Players.PlayerRemoving:Connect(function(player)
    removePlayerFromCoopRoom(player)
    playersOnCooldown[player] = nil
end)

for _, player in ipairs(Players:GetPlayers()) do
    sendProgressToPlayer(player)
end

-- ============================================================
-- INIT
-- ============================================================

setupPlates()
