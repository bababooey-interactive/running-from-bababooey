--[[
	PlayerProgressStore.luau  (ModuleScript)
	Author: Gilang
	Path: lobby/src/ServerScriptService/PlayerProgressStore.luau

	Tanggung jawab:
	- Load/save Types.PlayerProgress { unlockedLevel, highestEndless }
	  pakai DataStoreService.
	- Baca TeleportData saat player balik dari Game Place (hasil
	  menang/kalah), update progress sesuai itu.

	KONTRAK TeleportData dari Game Place (PERLU DISEPAKATI DENGAN AANG):
	Saat Aang teleport player balik ke Constants.LOBBY_PLACE_ID,
	sertakan TeleportData dengan bentuk:

	    {
	        won          = true / false,
	        levelPlayed  = number,  -- level yang baru saja dimainkan
	        mode         = "REGULAR" / "ENDLESS",
	    }

	Cara Aang kirim (dari Game Place, sebelum/saat teleport):
	    local TeleportOptions = Instance.new("TeleportOptions")
	    TeleportOptions:SetTeleportData({
	        won = true,
	        levelPlayed = currentLevel,
	        mode = Constants.GameMode.REGULAR,
	    })
	    TeleportService:TeleportAsync(Constants.LOBBY_PLACE_ID, players, TeleportOptions)

	Kalau Aang pakai Teleport() biasa (bukan TeleportAsync + TeleportOptions),
	bisa juga lewat TeleportService:Teleport(placeId, player, teleportData).
	Module ini baca dari player:GetJoinData().TeleportData, yang akan
	terisi otomatis dari kedua cara itu.
]]

local Players          = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")

local ProgressStore = DataStoreService:GetDataStore("PlayerProgress_v1")

local PlayerProgressStore = {}

-- ============================================================
-- DEFAULT
-- ============================================================

local function getDefaultProgress()
	return {
		unlockedLevel  = 1, -- player baru mulai dari level 1, BUKAN langsung 10
		highestEndless = 0,
	}
end

-- In-memory cache, supaya tidak perlu DataStore call berulang-ulang
-- selama sesi lobby berlangsung. [UserId] = PlayerProgress
local cache: { [number]: { unlockedLevel: number, highestEndless: number } } = {}

-- ============================================================
-- LOAD
-- ============================================================

function PlayerProgressStore.Load(player: Player)
	if cache[player.UserId] then
		return cache[player.UserId]
	end

	local key = "Player_" .. player.UserId
	local progress = nil

	local ok, result = pcall(function()
		return ProgressStore:GetAsync(key)
	end)

	if ok and result then
		progress = result
	else
		if not ok then
			warn(string.format(
				"[PlayerProgressStore] Gagal GetAsync untuk %s: %s. Pakai default.",
				player.Name, tostring(result)
			))
		end
		progress = getDefaultProgress()
	end

	-- Jaga-jaga field baru yang belum ada di data lama (migrasi ringan)
	progress.unlockedLevel  = progress.unlockedLevel or 1
	progress.highestEndless = progress.highestEndless or 0

	cache[player.UserId] = progress
	return progress
end

-- ============================================================
-- SAVE
-- ============================================================

function PlayerProgressStore.Save(player: Player)
	local progress = cache[player.UserId]
	if not progress then
		return
	end

	local key = "Player_" .. player.UserId

	local ok, err = pcall(function()
		ProgressStore:UpdateAsync(key, function(old)
			-- Jangan pernah turunkan progress yang sudah tersimpan
			-- (mis. kalau ada 2 server nyimpen hampir bersamaan).
			if old then
				return {
					unlockedLevel  = math.max(old.unlockedLevel or 1, progress.unlockedLevel),
					highestEndless = math.max(old.highestEndless or 0, progress.highestEndless),
				}
			end
			return progress
		end)
	end)

	if not ok then
		warn(string.format("[PlayerProgressStore] Gagal save progress %s: %s", player.Name, tostring(err)))
	end
end

-- ============================================================
-- UPDATE DARI HASIL MATCH (dipanggil saat player balik dari Game Place)
-- ============================================================

-- applyMatchResult: update progress berdasarkan TeleportData dari Game Place.
-- Aman dipanggil walau teleportData nil/kosong (mis. player join lobby
-- biasa tanpa baru saja main) — dalam kasus itu tidak melakukan apa-apa.
function PlayerProgressStore.ApplyMatchResult(player: Player, teleportData: any)
	if not teleportData or type(teleportData) ~= "table" then
		return
	end

	local progress = PlayerProgressStore.Load(player)

	if teleportData.won and teleportData.levelPlayed then
		if teleportData.mode == "ENDLESS" then
			progress.highestEndless = math.max(progress.highestEndless, teleportData.levelPlayed)
		else
			-- REGULAR: menang level N -> unlock level N+1
			progress.unlockedLevel = math.max(progress.unlockedLevel, teleportData.levelPlayed + 1)
		end

		print(string.format(
			"[PlayerProgressStore] %s menang level %d (%s) -> unlockedLevel=%d, highestEndless=%d",
			player.Name, teleportData.levelPlayed, tostring(teleportData.mode),
			progress.unlockedLevel, progress.highestEndless
		))
	end

	-- Simpan langsung begitu ada update dari hasil match (jangan tunggu
	-- player leave, supaya kalau Studio/server crash progress tidak hilang)
	PlayerProgressStore.Save(player)
end

-- ============================================================
-- LIFECYCLE
-- ============================================================

Players.PlayerRemoving:Connect(function(player)
	PlayerProgressStore.Save(player)
	cache[player.UserId] = nil
end)

-- Auto-save berkala (jaga-jaga server crash tanpa sempat PlayerRemoving)
task.spawn(function()
	while true do
		task.wait(120) -- tiap 2 menit
		for _, player in ipairs(Players:GetPlayers()) do
			if cache[player.UserId] then
				PlayerProgressStore.Save(player)
			end
		end
	end
end)

return PlayerProgressStore
