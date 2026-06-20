--[[
	RoomManager.lua
	Author: Gilang

	Tanggung jawab:
	- Menangani 3 plate difficulty (Easy/Medium/Hard) di lobby.
	- Mengelompokkan player jadi 1 room (single atau coop) berdasarkan
	  siapa saja yang menyentuh plate yang sama dalam window waktu join.
	- Memanggil RulesRandomizer untuk generate & broadcast rules.
	- Trigger MapGenerator untuk room tersebut.
	- Teleport player dari lobby ke room saat semua siap.

	CARA SETUP DI STUDIO:
	1. Buat 3 Part di Workspace, taruh di lobby, namai bebas (mis. "Plate_Easy").
	2. Set Attribute "Difficulty" di tiap Part = "Easy" / "Medium" / "Hard".
	3. Taruh Part-Part itu di dalam folder Workspace.Lobby.DifficultyPlates
	   (folder ini akan otomatis dicari, sesuaikan path di JOIN_PLATES_PATH
	   kalau struktur folder Anda beda).
]]

local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local RulesRandomizer = require(ServerScriptService:WaitForChild("RulesRandomizer"))

-- ============================================================
-- CONFIG
-- ============================================================

-- Path ke folder berisi 3 Part plate difficulty. Sesuaikan kalau struktur beda.
local PLATES_FOLDER_PATH = { "Lobby", "DifficultyPlates" }

-- Berapa lama (detik) window untuk player lain ikut gabung room yang sama
-- setelah player pertama menyentuh plate, sebelum room dikunci & game mulai.
local JOIN_WINDOW_SECONDS = 10

-- Posisi teleport sementara untuk room (TODO: sesuaikan / pakai banyak
-- titik kalau nanti ada banyak room aktif sekaligus secara paralel)
local ROOM_TELEPORT_POSITION = Vector3.new(0, 10, 0)

-- ============================================================
-- REMOTES
-- ============================================================

local RoomCountdownEvent = Remotes:FindFirstChild("RoomCountdown")
if not RoomCountdownEvent then
	RoomCountdownEvent = Instance.new("RemoteEvent")
	RoomCountdownEvent.Name = "RoomCountdown"
	RoomCountdownEvent.Parent = Remotes
end

local RoomStartingEvent = Remotes:FindFirstChild("RoomStarting")
if not RoomStartingEvent then
	RoomStartingEvent = Instance.new("RemoteEvent")
	RoomStartingEvent.Name = "RoomStarting"
	RoomStartingEvent.Parent = Remotes
end

-- ============================================================
-- STATE
-- ============================================================

-- playersInQueue[difficulty] = {
--     players = {player1, player2, ...},
--     countdownStartedAt = os.clock(),
--     locked = false,
-- }
local pendingRooms = {}

-- Supaya 1 player gak ke-detect masuk plate berkali-kali tiap frame Touched
local playersOnCooldown = {}

-- ============================================================
-- HELPERS
-- ============================================================

local function getPlatesFolder()
	local current = Workspace

	for _, name in ipairs(PLATES_FOLDER_PATH) do
		current = current:WaitForChild(name)
	end

	return current
end

local function getPlayerFromPart(part)
	local character = part.Parent

	if not character then
		return nil
	end

	return Players:GetPlayerFromCharacter(character)
end

local function removePlayerFromAllPending(player)
	for _, roomData in pairs(pendingRooms) do
		for i = #roomData.players, 1, -1 do
			if roomData.players[i] == player then
				table.remove(roomData.players, i)
			end
		end
	end
end

-- ============================================================
-- ROOM START (generate rules, generate map, teleport)
-- ============================================================

local function startRoom(difficulty, playersInRoom)
	-- Filter player yang mungkin sudah disconnect selama countdown
	local validPlayers = {}

	for _, player in ipairs(playersInRoom) do
		if player and player.Parent then
			table.insert(validPlayers, player)
		end
	end

	if #validPlayers == 0 then
		return
	end

	print(string.format(
		"[RoomManager] Starting room | Difficulty: %s | Players: %d",
		difficulty,
		#validPlayers
	))

	-- 1. Generate & broadcast rules (RulesRandomizer sudah handle
	--    RemoteEvent ke client + BindableEvent ke Arkan/Julian)
	local rules = RulesRandomizer.GenerateAndBroadcast(difficulty, validPlayers)

	-- 2. Beri tahu client bahwa room dimulai (dipakai LocalScript UI buat
	--    transisi dari lobby ke layar in-game + munculkan popup rules)
	for _, player in ipairs(validPlayers) do
		RoomStartingEvent:FireClient(player, rules)
	end

	-- 3. Teleport player ke room
	--    TODO: kalau nanti banyak room paralel, ganti ROOM_TELEPORT_POSITION
	--    jadi posisi unik per room (mis. offset berdasarkan room id)
	for _, player in ipairs(validPlayers) do
		local character = player.Character

		if character then
			character:PivotTo(CFrame.new(ROOM_TELEPORT_POSITION))
		end
	end

	-- 4. Trigger MapGenerator untuk room ini.
	--    MapGenerator.lua saat ini jalan otomatis di awal (task.wait(2) lalu
	--    generateMap()). Kalau mau RoomManager yang trigger manual, ubah
	--    MapGenerator.lua supaya generateMap() di-expose sebagai module
	--    function, lalu panggil di sini. Untuk sekarang kita asumsikan
	--    map sudah/akan di-generate terpisah oleh Gilang sendiri saat
	--    runtime testing.
end

-- ============================================================
-- PLATE TOUCH HANDLER
-- ============================================================

local function onPlateTouched(plate, difficulty)
	return function(hit)
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

		-- Kalau player lagi pending di room/difficulty lain, pindahkan dia
		removePlayerFromAllPending(player)

		local roomData = pendingRooms[difficulty]

		if not roomData or roomData.locked then
			-- Buat antrian baru untuk difficulty ini
			roomData = {
				players = {},
				countdownStartedAt = os.clock(),
				locked = false,
			}
			pendingRooms[difficulty] = roomData
		end

		table.insert(roomData.players, player)

		print(string.format(
			"[RoomManager] %s joined %s queue (%d player(s) waiting)",
			player.Name,
			difficulty,
			#roomData.players
		))

		-- Broadcast countdown info ke semua player di queue ini, biar UI
		-- bisa nampilin "Starting in X seconds... (N players)"
		for _, p in ipairs(roomData.players) do
			RoomCountdownEvent:FireClient(p, {
				difficulty = difficulty,
				secondsLeft = JOIN_WINDOW_SECONDS,
				playerCount = #roomData.players,
			})
		end

		-- Player pertama yang masuk plate ini yang menentukan kapan
		-- countdown berakhir & room di-lock.
		if #roomData.players == 1 then
			task.delay(JOIN_WINDOW_SECONDS, function()
				if roomData.locked then
					return
				end

				roomData.locked = true
				pendingRooms[difficulty] = nil

				startRoom(difficulty, roomData.players)
			end)
		end
	end
end

-- ============================================================
-- SETUP PLATES
-- ============================================================

local function setupPlates()
	local platesFolder = getPlatesFolder()

	for _, plate in ipairs(platesFolder:GetChildren()) do
		if plate:IsA("BasePart") then
			local difficulty = plate:GetAttribute("Difficulty")

			if not difficulty then
				warn("[RoomManager] Plate tanpa Attribute 'Difficulty':", plate:GetFullName())
			else
				plate.Touched:Connect(onPlateTouched(plate, difficulty))
				print("[RoomManager] Plate terdaftar:", plate.Name, "->", difficulty)
			end
		end
	end
end

-- ============================================================
-- CLEANUP ON LEAVE
-- ============================================================

Players.PlayerRemoving:Connect(function(player)
	removePlayerFromAllPending(player)
	playersOnCooldown[player] = nil
end)

-- ============================================================
-- INIT
-- ============================================================

setupPlates()