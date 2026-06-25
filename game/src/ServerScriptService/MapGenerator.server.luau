-- =============================================================
--  MapGenerator.server.luau  (v3 — Constants-driven, level-aware)
--  Author: Gilang
--
--  PERUBAHAN BESAR dari versi sebelumnya:
--  - SEMUA ukuran (TILE_SIZE, lebar map, panjang hall) sekarang
--    diambil dari Constants.luau, BUKAN hardcode lokal lagi.
--    Ini WAJIB supaya grid yang di-generate cocok dengan asumsi
--    MonsterAI.lua (worldToTile pakai Constants.TILE_SIZE) dan
--    TaskSystem/SurvivalSystem (scaling per level).
--  - Map & main hall sekarang scaling sesuai level (lihat
--    Constants.MAP_GROWTH_PER_LEVEL, MAIN_HALL_LENGTH_PER_LEVEL).
--  - Tambah: TaskObjects (coal & lever), Lighting (lantern wajib di
--    main hall), DarkZones (otomatis dari area tidak ter-cover
--    lantern), FoodItems (carrot, meat & waterbottle tersebar).
--
--  CARA PEMANGGILAN:
--  generateMap(level) sekarang terima parameter level (number).
--  Dipanggil dari GameManager.server.luau SETELAH session.level
--  diketahui (lihat catatan di akhir file).
-- =============================================================

local Workspace = game:GetService("Workspace")
local ServerStorage = game:GetService("ServerStorage")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Constants)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local MapGeneratedEvent = Remotes:WaitForChild("MapGenerated")

-- Server-to-Server BindableEvent (dipakai MonsterAI)
local ServerMapBindable = ReplicatedStorage:FindFirstChild("ServerMapGenerated")
if not ServerMapBindable then
	ServerMapBindable = Instance.new("BindableEvent")
	ServerMapBindable.Name = "ServerMapGenerated"
	ServerMapBindable.Parent = ReplicatedStorage
end

-- ============================================================
-- CONFIG — SEKARANG DARI Constants.luau
-- ============================================================

local TILE_SIZE = Constants.TILE_SIZE -- 8 (BUKAN 16 lagi)

-- Ukuran map & main hall di-resolve PER LEVEL, lihat resolveLevelConfig()
-- di bawah. Tidak ada lagi MAP_WIDTH/MAP_HEIGHT konstan di top-level.

-- WALL_SCALE dihitung dari ukuran ASLI asset wall_straight
-- (4.03 x 2.97 x 0.32 studs, dicek via GetBoundingBox), supaya lebar
-- hasil scale PAS dengan TILE_SIZE (8 studs) -- tidak menjorok ke tile
-- sebelah. Sebelumnya WALL_SCALE=5 dirancang untuk TILE_SIZE=16 lama,
-- menyebabkan wall jadi 2.5x lebih lebar dari tile setelah migrasi ke
-- TILE_SIZE=8, sehingga menutup celah akses ke labirin.
-- Konsekuensi: tinggi wall jadi ~5.89 studs (bukan persis WALL_HEIGHT
-- 8 studs), karena ScaleTo() itu uniform scale (X/Y/Z bareng). Ini
-- prioritas yang disengaja -- wall TERLALU LEBAR jauh lebih berbahaya
-- (blokir jalur) daripada wall sedikit lebih pendek dari ceiling.
local WALL_SCALE = TILE_SIZE / 4.034626007080078 -- ≈ 1.983
local WALL_Y_OFFSET = (2.969966411590576 * WALL_SCALE) / 2 -- setengah tinggi wall HASIL scale, bukan Constants.WALL_HEIGHT/2

local CEILING_SCALE = 4
local CEILING_Y_OFFSET = Constants.WALL_HEIGHT - 8

-- FLOOR_SCALE dihitung dari ukuran asli floor_flat (4.03 x 0.43 x 4.01
-- studs, dicek via GetBoundingBox), sama persis polanya dengan
-- WALL_SCALE -- supaya lebar X/Z pas TILE_SIZE (8 studs).
local FLOOR_SCALE = TILE_SIZE / 4.025826454162598 -- ≈ 1.991
local FLOOR_THICKNESS = 0.4282493591308594 * FLOOR_SCALE -- ≈ 0.853 studs (ketebalan HASIL scale)

local PROP_SCALE = 1.5
local FOOD_SCALE = 1.5
local COAL_SCALE = 2
local LEVER_SCALE = 5
local FIREPLACE_SCALE = 7
local CONVEYOR_SCALE = 4
local LANTERN_SCALE = 2
local DARKZONE_SCALE = 1 -- dark zone model dipakai apa adanya, tanpa scale up

local FLOOR_HEIGHT = 1

local SIDE_BRANCH_CHANCE = 0.85
local SIDE_BRANCH_MIN_LENGTH = 3
local SIDE_BRANCH_MAX_LENGTH = 5

local PROP_CHANCE = 0.45
local BOULDERLARGE_CHANCE = 0.50
--local SHORT_WALL_CHANCE = 0.12
local FOOD_CHANCE = 0.3 -- chance per tile floor biasa muncul food item
local LANTERN_CHANCE = 0.4 -- chance per tile floor biasa muncul lantern (selain main hall)

local CONVEYOR_SPEED = Constants.CONVEYOR_SPEED

local PROP_SAFE_MARGIN = 3 -- offset maksimum dari pusat tile (stud), TILE_SIZE skrg 8

-- Lantern: ditempatkan di SEMUA tile main hall, dan tersebar di labirin
-- sebelum dark zone dihitung. LANTERN_LIGHT_RADIUS dipakai untuk
-- menentukan tile mana yang "tercover cahaya" saat menghitung dark zone.
-- local LANTERN_MAZE_SPACING = 4 -- coba taruh lantern tiap N tile di labirin (jarak grid kasar)
local LANTERN_SPACING = 4 -- jarak lantern di map 
local LANTERN_LIGHT_RADIUS_TILES = 2 -- radius cover cahaya dalam satuan TILE (bukan stud) awalnya 2.2

-- ============================================================
-- LEVEL CONFIG (scaling, sesuai Types.LevelConfig)
-- ============================================================

local function resolveLevelConfig(level: number)
	level = math.max(1, level or 1)

	local mapCols =
		math.min(Constants.MAP_COLS_BASE + (level - 1) * Constants.MAP_GROWTH_PER_LEVEL, Constants.MAP_MAX_COLS)
	local mapRows =
		math.min(Constants.MAP_ROWS_BASE + (level - 1) * Constants.MAP_GROWTH_PER_LEVEL, Constants.MAP_MAX_ROWS)

	local mainHallLength = Constants.MAIN_HALL_LENGTH_BASE + level * Constants.MAIN_HALL_LENGTH_PER_LEVEL

	-- Hall tidak boleh lebih panjang dari tinggi map (sisakan ruang
	-- untuk dinding atas/bawah)
	mainHallLength = math.min(mainHallLength, mapRows - 4)

	local monsterSpeed =
		math.min(Constants.MONSTER_SPEED_BASE + level * Constants.MONSTER_SPEED_PER_LEVEL, Constants.MONSTER_SPEED_MAX)

	local isNightmare = Constants.NIGHTMARE_EVERY_N_LEVELS > 0 and level % Constants.NIGHTMARE_EVERY_N_LEVELS == 0

	return {
		level = level,
		ruleCount = math.min(level, #Constants.RULES_POOL),
		mapCols = mapCols,
		mapRows = mapRows,
		mainHallLen = mainHallLength,
		monsterSpeed = monsterSpeed,
		isNightmare = isNightmare,
	}
end

-- Diisi di awal generateMap(), dipakai semua fungsi di bawah lewat
-- closure (gantikan MAP_WIDTH/MAP_HEIGHT/MAIN_HALL_LENGTH konstan lama)
local MAP_WIDTH = Constants.MAP_COLS_BASE
local MAP_HEIGHT = Constants.MAP_ROWS_BASE
local MAIN_HALL_WIDTH = Constants.MAIN_HALL_WIDTH
local MAIN_HALL_LENGTH = Constants.MAIN_HALL_LENGTH_BASE

-- ============================================================
-- ASSETS
-- ============================================================

local Assets = ServerStorage:WaitForChild("Assets")
local MapPieces = Assets:WaitForChild("MapPieces")

local WallsFolder = MapPieces:WaitForChild("Walls")
local CeilingsFolder = MapPieces:WaitForChild("Ceilings")
local FloorsFolder = MapPieces:WaitForChild("Floors")
local PropsFolder = MapPieces:WaitForChild("Props")
local SpecialFolder = MapPieces:FindFirstChild("Special")
local TaskObjectsFolder = MapPieces:WaitForChild("TaskObjects")
local LightingFolder = MapPieces:WaitForChild("Lighting")
local DarkZonesFolder = MapPieces:WaitForChild("DarkZones")
local FoodItemsFolder = MapPieces:WaitForChild("FoodItems")

local WallStraight = WallsFolder:WaitForChild("wall_straight")
local WallCorner = WallsFolder:FindFirstChild("wall_corner_90")
-- local WallEndCap = WallsFolder:FindFirstChild("wall_end_cap")
-- local WallPillar = WallsFolder:FindFirstChild("wall_pillar")
-- local WallShort = WallsFolder:FindFirstChild("wall_short")

local CeilingFlat = CeilingsFolder:WaitForChild("ceiling_flat")
local CeilingArch = CeilingsFolder:FindFirstChild("ceiling_arch")
local CeilingCrack = CeilingsFolder:FindFirstChild("ceiling_crack")
local CeilingStalactite = CeilingsFolder:FindFirstChild("Ceiling_Stalactite_Group")

local FloorFlat = FloorsFolder:WaitForChild("floor_flat")
local FloorCrack = FloorsFolder:FindFirstChild("floor_crack")

local BoulderLarge = PropsFolder:FindFirstChild("boulder_large")
local BoulderMedium = PropsFolder:FindFirstChild("boulder_medium")
local BoulderSmall = PropsFolder:FindFirstChild("boulder_small")
local FloorRubble = PropsFolder:FindFirstChild("Floor_Rubble_Group")
local FireplaceAsset = PropsFolder:FindFirstChild("old_fireplace_prop")

local ConveyorAsset = nil
if SpecialFolder then
	ConveyorAsset = SpecialFolder:FindFirstChild("conveyor")
end
if not ConveyorAsset then
	ConveyorAsset = PropsFolder:FindFirstChild("conveyor")
end

-- ── Task Objects: Coal (5 varian) & Lever ──
local CoalFolder = TaskObjectsFolder:WaitForChild("Coal")
local LeverFolder = TaskObjectsFolder:WaitForChild("Lever")

local CoalOptions = {}
for _, child in ipairs(CoalFolder:GetChildren()) do
	table.insert(CoalOptions, child)
end

local LeverAsset = LeverFolder:FindFirstChild("lever_box")

-- ── Lighting: Lantern ──
local LanternAsset = LightingFolder:WaitForChild("lantern")

-- ── Dark Zones: 3 varian sesuai bentuk tile ──
local DarkZoneAlley = DarkZonesFolder:WaitForChild("DarkZone_Alley") -- lorong sempit 1 tile
local DarkZoneCorridor = DarkZonesFolder:WaitForChild("DarkZone_Corridor") -- lorong biasa
local DarkZoneRoom = DarkZonesFolder:WaitForChild("DarkZone_Room") -- ruangan/persimpangan lebar

-- ── Food Items ── 
-- — simpan scale asli tiap item supaya ScaleTo tidak
-- override scale manual yang sudah diset di Studio (mis. waterbottle = 0.01)
local FoodOptions = {}
for _, child in ipairs(FoodItemsFolder:GetChildren()) do
    -- Simpan scale asli sebagai Attribute supaya bisa dibaca saat spawn
    local currentScale = 1
    if child:IsA("Model") then
        -- Model punya Scale di bawah Pivot
        currentScale = child:GetScale()
    end
    child:SetAttribute("OriginalScale", currentScale)
    table.insert(FoodOptions, child)
end

local BoulderOptions = {}
if BoulderSmall then
	table.insert(BoulderOptions, BoulderSmall)
end
if BoulderMedium then
	table.insert(BoulderOptions, BoulderMedium)
end
if BoulderLarge then
	table.insert(BoulderOptions, BoulderLarge)
end
if FloorRubble then
	table.insert(BoulderOptions, FloorRubble)
end

local CeilingOptions = { CeilingFlat }
if CeilingArch then
	table.insert(CeilingOptions, CeilingArch)
end
if CeilingCrack then
	table.insert(CeilingOptions, CeilingCrack)
end
if CeilingStalactite then
	table.insert(CeilingOptions, CeilingStalactite)
end

-- ============================================================
-- TILE TYPES (pakai Constants.Tile, BUKAN enum lokal lagi)
-- ============================================================

local Tile = Constants.Tile
-- Constants.Tile cuma punya WALL/FLOOR/SPAWN/CONVEYOR. SPAWN dipakai
-- sebagai penanda titik spawn (sama seperti sebelumnya). FIREPLACE
-- dan task-object placement TIDAK butuh tile type baru — itu murni
-- penempatan OBJEK di atas tile FLOOR/CONVEYOR yang sudah ada, jadi
-- kita tetap pakai 1 flag tambahan lokal khusus fireplace di hallInfo
-- (bukan tile type terpisah), supaya tidak nambah Tile enum yang harus
-- disinkronkan ulang ke Types.luau/Constants.luau milik tim.
local FIREPLACE_TILE_MARKER = -1 -- internal sentinel, lihat carveMainHall

local directions = {
	N = { dx = 0, dz = -1, rotation = 0 },
	E = { dx = 1, dz = 0, rotation = 90 },
	S = { dx = 0, dz = 1, rotation = 180 },
	W = { dx = -1, dz = 0, rotation = 270 },
}

-- ============================================================
-- BASIC HELPERS
-- ============================================================

local function clearOldMap()
	local oldMap = Workspace:FindFirstChild("GeneratedMap")
	if oldMap then
		oldMap:Destroy()
	end

	local folder = Instance.new("Folder")
	folder.Name = "GeneratedMap"
	folder.Parent = Workspace

	return folder
end

local function gridToWorld(col, row)
	return Vector3.new((col - 1) * TILE_SIZE, 0, (row - 1) * TILE_SIZE)
end

local function isInsideGrid(col, row)
	return col >= 1 and col <= MAP_WIDTH and row >= 1 and row <= MAP_HEIGHT
end

local function createGrid()
	local grid = {}
	for row = 1, MAP_HEIGHT do
		grid[row] = {}
		for col = 1, MAP_WIDTH do
			grid[row][col] = Tile.WALL
		end
	end
	return grid
end

local function setTile(grid, col, row, tileType)
	if isInsideGrid(col, row) then
		grid[row][col] = tileType
	end
end

local function getTile(grid, col, row)
	if not isInsideGrid(col, row) then
		return Tile.WALL
	end
	return grid[row][col]
end

local function isWalkable(tileType)
	return tileType == Tile.FLOOR or tileType == Tile.SPAWN or tileType == Tile.CONVEYOR
end

local function createPart(name, size, cframe, color, material)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Anchored = true
	part.CanCollide = true
	part.Color = color
	part.Material = material or Enum.Material.Slate
	part.Parent = nil
	return part
end

local function setPhysicsSafe(object, canCollide)
	if canCollide == nil then
		canCollide = true
	end

	-- If this is our lantern, do NOT anchor it! Let gravity work.
	if object.Name == "lantern" or object.Name == "Lantern_Model" then
		return
	end

	if object:IsA("BasePart") then
		object.Anchored = true
		object.CanCollide = canCollide
		object.CanTouch = true
		object.CanQuery = true
	end

	for _, descendant in ipairs(object:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = canCollide
			descendant.CanTouch = true
			descendant.CanQuery = true
		end
	end
end

local function cloneAsset(template, parent, cframe, scale, canCollide)
	local clone = template:Clone()
	clone.Parent = parent

	scale = scale or 1

	if clone:IsA("Model") then
		clone:ScaleTo(scale)
		clone:PivotTo(cframe)
	elseif clone:IsA("BasePart") then
		clone.Size = clone.Size * scale
		clone.CFrame = cframe
	else
		warn("Asset bukan Model atau BasePart:", clone.Name)
	end

	setPhysicsSafe(clone, canCollide)

	return clone
end

-- ============================================================
-- LAYOUT GENERATION
-- ============================================================

local function carveMainHall(grid)
	local centerCol = math.ceil(MAP_WIDTH / 2)
	local hallLeft = centerCol - math.floor(MAIN_HALL_WIDTH / 2)
	local hallRight = hallLeft + MAIN_HALL_WIDTH - 1

	local startRow = MAP_HEIGHT - 3
	local endRow = math.max(2, startRow - MAIN_HALL_LENGTH)

	for row = endRow + 1, startRow do
		for col = hallLeft, hallRight do
			setTile(grid, col, row, Tile.FLOOR)
		end
		setTile(grid, centerCol, row, Tile.CONVEYOR)
	end

	-- floor di sekeliling fireplace, selebar hall
	for col = hallLeft, hallRight do
		setTile(grid, col, endRow, Tile.FLOOR)
	end

	setTile(grid, centerCol, startRow, Tile.SPAWN)

	return {
		centerCol = centerCol,
		hallLeft = hallLeft,
		hallRight = hallRight,
		startRow = startRow,
		endRow = endRow,
		spawnCol = centerCol,
		spawnRow = startRow,
		fireplaceCol = centerCol,
		fireplaceRow = endRow, -- fireplace tetap di endRow, TANPA tile type khusus
	}
end

local function carveSideBranch(grid, startCol, startRow, direction)
	local length = math.random(SIDE_BRANCH_MIN_LENGTH, SIDE_BRANCH_MAX_LENGTH)
	local col, row = startCol, startRow

	for i = 1, length do
		col += direction
		if not isInsideGrid(col, row) then
			break
		end

		setTile(grid, col, row, Tile.FLOOR)

		if math.random() < 0.35 then
			local turn = math.random(0, 1) == 0 and -1 or 1
			row += turn

			if isInsideGrid(col, row) then
				setTile(grid, col, row, Tile.FLOOR)
			end
		end
	end
end

local function carveRandomSideCorridors(grid, hallInfo)
	for row = hallInfo.endRow + 2, hallInfo.startRow - 2, 2 do
		if math.random() < SIDE_BRANCH_CHANCE then
			setTile(grid, hallInfo.hallLeft - 1, row, Tile.FLOOR)
			carveSideBranch(grid, hallInfo.hallLeft - 1, row, -1)
		end

		if math.random() < SIDE_BRANCH_CHANCE then
			setTile(grid, hallInfo.hallRight + 1, row, Tile.FLOOR)
			carveSideBranch(grid, hallInfo.hallRight + 1, row, 1)
		end
	end
end

local function buildLayout()
	local grid = createGrid()
	local hallInfo = carveMainHall(grid)
	carveRandomSideCorridors(grid, hallInfo)
	return grid, hallInfo
end

-- ============================================================
-- (BERSAMBUNG DI PESAN BERIKUTNYA: wall logic, floor/ceiling/conveyor,
--  task objects, lantern, dark zones, food items, generateMap)
-- ============================================================
-- ============================================================
-- WALL LOGIC
-- ============================================================

local function countWallNeighbors(grid, col, row)
	local count = 0
	for _, dir in pairs(directions) do
		local neighborTile = getTile(grid, col + dir.dx, row + dir.dz)
		if not isWalkable(neighborTile) then
			count += 1
		end
	end
	return count
end

local function countWalkableNeighbors(grid, col, row)
	local count = 0
	for _, dir in pairs(directions) do
		local neighborTile = getTile(grid, col + dir.dx, row + dir.dz)
		if isWalkable(neighborTile) then
			count += 1
		end
	end
	return count
end

-- Dipakai juga oleh dark zone classification (Alley/Corridor/Room)
local function getWalkableNeighborCount(grid, col, row)
	return countWalkableNeighbors(grid, col, row)
end

local function shouldUseEndCap(grid, col, row)
	return WallEndCap and countWalkableNeighbors(grid, col, row) == 1
end

local function shouldUsePillar(grid, col, row)
	return WallPillar and countWallNeighbors(grid, col, row) >= 3
end

local function placeWall(mapFolder, col, row, dirName)
	local basePos = gridToWorld(col, row)
	local dir = directions[dirName]

	local wallPos
	if dirName == "N" then
		wallPos = basePos + Vector3.new(0, WALL_Y_OFFSET, -TILE_SIZE / 2)
	elseif dirName == "S" then
		wallPos = basePos + Vector3.new(0, WALL_Y_OFFSET, TILE_SIZE / 2)
	elseif dirName == "E" then
		wallPos = basePos + Vector3.new(TILE_SIZE / 2, WALL_Y_OFFSET, 0)
	elseif dirName == "W" then
		wallPos = basePos + Vector3.new(-TILE_SIZE / 2, WALL_Y_OFFSET, 0)
	end

	local selectedWall = WallStraight
	local scale = WALL_SCALE

	--if WallShort and math.random() < SHORT_WALL_CHANCE then
	--	selectedWall = WallShort
	--	scale = WALL_SCALE
	--end

	local wallClone = cloneAsset(
		selectedWall,
		mapFolder,
		CFrame.new(wallPos) * CFrame.Angles(0, math.rad(dir.rotation), 0),
		scale,
		true
	)

	-- Koreksi tinggi: ScaleTo() di atas bikin tinggi cuma ~5.89 stud
	-- (lebar sudah pas TILE_SIZE, tapi tinggi ikut keskalakan sama rata).
	-- Stretch ULANG cuma sumbu Y biar nyampe Constants.WALL_HEIGHT,
	-- tanpa ubah lebar/ketebalan yang sudah pas.
	if wallClone then
		local currentCFrame, currentSize = wallClone:GetBoundingBox()
		local currentHeight = currentSize.Y
		local heightScaleFactor = Constants.WALL_HEIGHT / currentHeight

		-- ScaleTo() lagi tapi cuma pakai faktor TINGGI -- ini akan
		-- ikut membesarkan X/Z juga (ScaleTo selalu uniform), jadi
		-- TIDAK dipakai di sini. Sebagai gantinya, pakai pendekatan
		-- resize manual per-Part (lebih rumit tapi presisi):

		for _, part in ipairs(wallClone:GetDescendants()) do
			if part:IsA("BasePart") then
				local oldSize = part.Size
				local WALL_OVERLAP = 0.15
				part.Size = Vector3.new(oldSize.X + WALL_OVERLAP, oldSize.Y * heightScaleFactor, oldSize.Z + WALL_OVERLAP)
			end
		end

		-- Setelah resize manual, posisi tiap part RELATIF terhadap pivot
		-- model bisa sedikit bergeser (karena resize biasanya dari tengah
		-- part itu sendiri, bukan dari pivot model). Re-pivot ke posisi
		-- target supaya wall tetap presisi di tile-nya:
		wallClone:PivotTo(CFrame.new(wallPos) * CFrame.Angles(0, math.rad(dir.rotation), 0))
	end
end

local function placeDecorativeWallDetails(mapFolder, grid, col, row)
	local tileType = getTile(grid, col, row)
	if not isWalkable(tileType) then
		return
	end

	local basePos = gridToWorld(col, row)

	if shouldUsePillar(grid, col, row) then
		cloneAsset(WallPillar, mapFolder, CFrame.new(basePos + Vector3.new(0, WALL_Y_OFFSET, 0)), WALL_SCALE, true)
	end

	if shouldUseEndCap(grid, col, row) then
		cloneAsset(WallEndCap, mapFolder, CFrame.new(basePos + Vector3.new(0, WALL_Y_OFFSET, 0)), WALL_SCALE, true)
	end
end

local function placeWallsAroundFloor(mapFolder, grid, col, row)
	for dirName, dir in pairs(directions) do
		local neighborCol = col + dir.dx
		local neighborRow = row + dir.dz
		local neighborTile = getTile(grid, neighborCol, neighborRow)

		if not isWalkable(neighborTile) then
			placeWall(mapFolder, col, row, dirName)
		end
	end

	placeDecorativeWallDetails(mapFolder, grid, col, row)
end

-- ============================================================
-- FLOOR, CEILING, CONVEYOR
-- ============================================================

local function placeFloor(mapFolder, col, row, tileType, hallInfo)
	local pos = gridToWorld(col, row)

	local isFireplaceTile = hallInfo and col == hallInfo.fireplaceCol and row == hallInfo.fireplaceRow

	-- Pilih varian floor (sama logic seperti ceiling: kebanyakan flat,
	-- sesekali crack untuk variasi visual)
	local selectedFloor = FloorFlat
	if FloorCrack and math.random() < 0.1 then
		selectedFloor = FloorCrack
	end

	-- Floor di-clone TANPA scale tambahan (asumsikan sudah didesain
	-- pas TILE_SIZE, sama seperti ceiling). Kalau ternyata floor_flat
	-- ukurannya beda dari ceiling_flat, perlu dicek GetBoundingBox()
	-- dulu seperti kasus wall/darkzone sebelumnya.
	local clone = cloneAsset(
		selectedFloor,
		mapFolder,
		CFrame.new(pos + Vector3.new(0, FLOOR_THICKNESS / 2, 0)),
		FLOOR_SCALE, -- pakai scale yang sama dengan ceiling, karena ini hasil duplikat ceiling
		true
	)

	-- Setelah cloneAsset, besarkan sedikit supaya tepi-tepi antar tile saling
	-- overlap dan tidak ada celah visual
	if clone then
		-- Tambah TILE_OVERLAP ke X dan Z supaya gap antar tile tertutup
		-- Y (ketebalan) tidak perlu diubah
		local TILE_OVERLAP = 0.15 -- stud, sesuaikan kalau masih ada celah
		for _, part in ipairs(clone:GetDescendants()) do
			if part:IsA("BasePart") then
				part.Size = Vector3.new(
					part.Size.X + TILE_OVERLAP,
					part.Size.Y,
					part.Size.Z + TILE_OVERLAP
				)
			end
		end
	end

	-- Pewarnaan khusus per tile type (spawn/conveyor/fireplace) --
	-- TIDAK BISA lagi pakai .Color kalau asset floor pakai banyak
	-- Part/texture custom. Kalau mau tetap ada pembedaan warna visual,
	-- perlu loop descendants & set Color tiap BasePart (lihat catatan
	-- di bawah).
end

local function placeCeiling(mapFolder, col, row, tileType)
	local basePos = gridToWorld(col, row)
	local selectedCeiling = CeilingFlat
	local heightOffset = CEILING_Y_OFFSET

	if tileType == Tile.CONVEYOR then
		if CeilingArch then
			selectedCeiling = CeilingArch
			heightOffset = CEILING_Y_OFFSET + 2
		end
	elseif math.random() < 0.1 then
		if CeilingCrack then
			selectedCeiling = CeilingCrack
		end
	end

	local ceilingPos = basePos + Vector3.new(0, heightOffset, 0)

	cloneAsset(selectedCeiling, mapFolder, CFrame.new(ceilingPos), CEILING_SCALE, true)
end

local function createConveyorZone(mapFolder, col, row, hallInfo)
	local basePos = gridToWorld(col, row)

	local zone = createPart(
		"ConveyorZone",
		Vector3.new(TILE_SIZE * 0.85, 2, TILE_SIZE * 0.85),
		CFrame.new(basePos + Vector3.new(0, 2, 0)),
		Color3.fromRGB(0, 120, 255),
		Enum.Material.Neon
	)

	zone.Transparency = 1
	zone.CanCollide = false
	zone.CanTouch = true
	zone.Parent = mapFolder

	local fireplacePos = gridToWorld(hallInfo.fireplaceCol, hallInfo.fireplaceRow)
	local directionToFireplace = (fireplacePos - basePos)

	-- Guard: kalau zone ini PERSIS di tile fireplace, Unit vector akan
	-- NaN (magnitude 0). Pakai vector nol saja dalam kasus itu.
	if directionToFireplace.Magnitude > 0.01 then
		directionToFireplace = directionToFireplace.Unit
	else
		directionToFireplace = Vector3.new(0, 0, 0)
	end

	zone.Touched:Connect(function(hit)
		if not hit:IsA("BasePart") then
			return
		end

		local isCoal = hit.Name == "coal" or hit.Name == "Coal" or hit.Name:lower():find("coal") ~= nil

		if not isCoal then
			return
		end

		if hit.Anchored then
			hit.Anchored = false
		end

		hit.AssemblyLinearVelocity = directionToFireplace * CONVEYOR_SPEED
	end)
end

local function placeConveyorVisual(mapFolder, col, row, hallInfo)
	local basePos = gridToWorld(col, row)

	if ConveyorAsset then
		cloneAsset(ConveyorAsset, mapFolder, CFrame.new(basePos + Vector3.new(0, 0.75 + 0.75, 0)), CONVEYOR_SCALE, true)
	else
		local conveyor = createPart(
			"Conveyor_Visual",
			Vector3.new(TILE_SIZE * 0.75, 0.2, TILE_SIZE * 0.95),
			CFrame.new(basePos + Vector3.new(0, 0.65 + 0.75, 0)),
			Color3.fromRGB(50, 70, 110),
			Enum.Material.Metal
		)
		conveyor.CanCollide = true
		conveyor.Parent = mapFolder
	end

	createConveyorZone(mapFolder, col, row, hallInfo)
end

-- ============================================================
-- (BERSAMBUNG: props, task objects, lantern, dark zone, food items)
-- ============================================================
-- ============================================================
-- PROPS (boulder, rubble) — sama seperti sebelumnya
-- ============================================================

local function getSafePropOffset(grid, col, row, maxOffset)
	local offsetX = math.random(-maxOffset, maxOffset)
	local offsetZ = math.random(-maxOffset, maxOffset)

	if offsetX ~= 0 then
		local neighborCol = col + (offsetX > 0 and 1 or -1)
		if not isWalkable(getTile(grid, neighborCol, row)) then
			offsetX = 0
		end
	end

	if offsetZ ~= 0 then
		local neighborRow = row + (offsetZ > 0 and 1 or -1)
		if not isWalkable(getTile(grid, col, neighborRow)) then
			offsetZ = 0
		end
	end

	return Vector3.new(offsetX, 0, offsetZ)
end

-- Tile yang sudah "dipakai" objek lain (task object/lantern/food) di
-- sesi generate ini, supaya prop acak tidak nimpa objek penting itu.
-- [row][col] = true kalau sudah occupied.
local occupiedTiles = {}

local function markOccupied(col, row)
	occupiedTiles[row] = occupiedTiles[row] or {}
	occupiedTiles[row][col] = true
end

local function isOccupied(col, row)
	return occupiedTiles[row] and occupiedTiles[row][col] == true
end

local function placeRandomProp(mapFolder, grid, col, row, tileType, hallInfo)
	if tileType == Tile.SPAWN or tileType == Tile.CONVEYOR then
		return
	end

	if hallInfo and col == hallInfo.fireplaceCol and row == hallInfo.fireplaceRow then
		return
	end

	if isOccupied(col, row) then
		return
	end

	local basePos = gridToWorld(col, row)

	if BoulderOptions[BoulderLarge] and math.random() < BOULDERLARGE then
		local offset = getSafePropOffset(grid, col, row, PROP_SAFE_MARGIN)
		cloneAsset(
			BoulderLarge,
			mapFolder,
			CFrame.new(basePos + offset + Vector3.new(0, FLOOR_THICKNESS, 0)) * CFrame.Angles(0, math.rad(math.random(0, 359)), 0),
			PROP_SCALE,
			true
		)
	end

	if #BoulderOptions > 0 and math.random() < PROP_CHANCE then
		-- Spawn 2-3 prop per tile (acak)
		local propCount = math.random(2, 3)
		for _ = 1, propCount do
			local selected = BoulderOptions[math.random(1, #BoulderOptions)]
			-- Tiap prop dapat offset acak SENDIRI supaya tidak numpuk
			-- persis di titik yang sama. Pakai safe margin yang lebih
			-- kecil (2 stud) supaya masih dalam 1 tile meski ada beberapa.
			local offsetX = math.random(-2, 2)
			local offsetZ = math.random(-2, 2)
			cloneAsset(
				selected,
				mapFolder,
				CFrame.new(basePos + Vector3.new(offsetX, FLOOR_THICKNESS, offsetZ))
					* CFrame.Angles(
						0,
						math.rad(math.random(0, 359)),
						0
					),
				PROP_SCALE,
				true
			)
		end
	end
end

-- ============================================================
-- FIREPLACE
-- ============================================================

local function placeFireplace(mapFolder, hallInfo)
	local basePos = gridToWorld(hallInfo.fireplaceCol, hallInfo.fireplaceRow)

	local fireplaceCFrame = CFrame.new(basePos + Vector3.new(0, 1, 0)) * CFrame.Angles(0, math.rad(180), 0)

	if FireplaceAsset then
		cloneAsset(FireplaceAsset, mapFolder, fireplaceCFrame, FIREPLACE_SCALE, true)
	else
		local fireplaceMock = createPart(
			"Mock_Fireplace",
			Vector3.new(TILE_SIZE, 7, 3),
			CFrame.new(basePos + Vector3.new(0, FLOOR_THICKNESS, 0)),
			Color3.fromRGB(100, 50, 25),
			Enum.Material.Brick
		)
		fireplaceMock.Parent = mapFolder
	end

	placeWall(mapFolder, hallInfo.fireplaceCol, hallInfo.fireplaceRow, "N")
	markOccupied(hallInfo.fireplaceCol, hallInfo.fireplaceRow)
end

-- ============================================================
-- TASK OBJECTS: COAL & LEVER
--
-- Konvensi WAJIB (dibaca TaskSystem.lua Aang):
--   - Attribute "TaskType" = "coal" | "lever" | "battery"
--   - Attribute "TaskId"   = string unik
--   - Ditaruh di Workspace.TaskObjects (folder TERPISAH dari
--     GeneratedMap, karena TaskSystem scan dari Workspace langsung,
--     bukan dari dalam GeneratedMap)
--   - ProximityPrompt di-auto-create oleh TaskSystem.lua sendiri kalau
--     belum ada, jadi TIDAK perlu kita buat manual di sini.
--
-- Catatan: "battery" tidak punya asset yang dikirim ke saya, jadi
-- TIDAK di-generate di sini. Kalau asset battery sudah ada, tinggal
-- tambah folder TaskObjects.Battery + panggil placeTaskObjects dengan
-- pola yang sama seperti coal/lever.
-- ============================================================

local function getOrCreateTaskObjectsFolder()
	local folder = Workspace:FindFirstChild("TaskObjects")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "TaskObjects"
		folder.Parent = Workspace
	end
	return folder
end

-- Kumpulkan semua tile floor/conveyor "biasa" (bukan spawn, bukan
-- fireplace) yang valid untuk ditaruh objek (task/lantern/food).
local function collectPlaceableTiles(grid, hallInfo)
	local tiles = {}

	for row = 1, MAP_HEIGHT do
		for col = 1, MAP_WIDTH do
			local tileType = getTile(grid, col, row)

			if isWalkable(tileType) and tileType ~= Tile.SPAWN then
				local isFireplaceTile = col == hallInfo.fireplaceCol and row == hallInfo.fireplaceRow

				if not isFireplaceTile then
					table.insert(tiles, { col = col, row = row })
				end
			end
		end
	end

	return tiles
end

-- Fisher-Yates shuffle sederhana
local function shuffleTiles(tiles)
	for i = #tiles, 2, -1 do
		local j = math.random(1, i)
		tiles[i], tiles[j] = tiles[j], tiles[i]
	end
end

local function placeCoalObjects(taskFolder, placeableTiles, level)
	if #CoalOptions == 0 then
		warn("[MapGenerator] Tidak ada asset coal di TaskObjects.Coal, coal di-skip.")
		return
	end

	local extra = math.max(0, level - 1) * Constants.TASK_ADD_PER_LEVEL
	local coalCount = math.min(Constants.TASK_COAL_COUNT + extra, #placeableTiles, #CoalOptions * 3)
	-- batas #CoalOptions*3 cuma jaga-jaga supaya tidak nyoba taruh ribuan
	-- coal kalau level sangat tinggi & tile placeable banyak sekali

	for i = 1, coalCount do
		local tileEntry = table.remove(placeableTiles) -- ambil dari belakang (sudah di-shuffle)
		if not tileEntry then
			break
		end

		local selected = CoalOptions[math.random(1, #CoalOptions)]
		local basePos = gridToWorld(tileEntry.col, tileEntry.row)

		local clone = cloneAsset(
			selected,
			taskFolder,
			CFrame.new(basePos + Vector3.new(0, FLOOR_THICKNESS, 0)) * CFrame.Angles(0, math.rad(math.random(0, 359)), 0),
			COAL_SCALE,
			true
		)

		clone:SetAttribute("TaskType", "coal")
		clone:SetAttribute("TaskId", string.format("Coal_%02d", i))

		markOccupied(tileEntry.col, tileEntry.row)
	end
end

local function placeLeverObjects(taskFolder, placeableTiles, level)
	if not LeverAsset then
		warn("[MapGenerator] Asset lever_box tidak ditemukan di TaskObjects.Lever, lever di-skip.")
		return
	end

	local extra = math.max(0, level - 1) * Constants.TASK_ADD_PER_LEVEL
	local leverCount = math.min(Constants.TASK_LEVER_COUNT + extra, #placeableTiles)

	for i = 1, leverCount do
		local tileEntry = table.remove(placeableTiles)
		if not tileEntry then
			break
		end

		local basePos = gridToWorld(tileEntry.col, tileEntry.row)

		local clone = cloneAsset(
			LeverAsset,
			taskFolder,
			CFrame.new(basePos + Vector3.new(0, FLOOR_THICKNESS, 0)) * CFrame.Angles(0, math.rad(math.random(0, 359)), 0),
			LEVER_SCALE,
			true
		)

		clone:SetAttribute("TaskType", "lever")
		clone:SetAttribute("TaskId", string.format("Lever_%02d", i))

		markOccupied(tileEntry.col, tileEntry.row)
	end
end

-- ============================================================
-- LANTERN — wajib di SEMUA tile main hall + tersebar di labirin
-- ============================================================

-- litTiles: set tile yang akan ter-cover cahaya, dipakai nanti untuk
-- menentukan dark zone. [row][col] = true
local litTiles = {}

function markLitAround(col, row, radiusTiles)
	local r = math.ceil(radiusTiles)

	for dRow = -r, r do
		for dCol = -r, r do
			local dist = math.sqrt(dCol ^ 2 + dRow ^ 2)
			if dist <= radiusTiles then
				local c, rr = col + dCol, row + dRow
				if isInsideGrid(c, rr) then
					litTiles[rr] = litTiles[rr] or {}
					litTiles[rr][c] = true
				end
			end
		end
	end
end

local function placeLantern(mapFolder, col, row)
	local basePos = gridToWorld(col, row)

	-- Lantern ditempel di atas lantai
	-- fallback ke tengah tile kalau tidak ada referensi dinding.
	-- Untuk simplicity & supaya konsisten, kita taruh di tengah tile
	-- dengan offset Y mengikuti tinggi wall.
	cloneAsset(
		LanternAsset,
		mapFolder,
		CFrame.new(basePos + Vector3.new(0, FLOOR_THICKNESS, 0)),
		LANTERN_SCALE,
		false
	)

	markLitAround(col, row, LANTERN_LIGHT_RADIUS_TILES)
	markOccupied(col, row)
end

local function placeLanterns(mapFolder, grid, hallInfo)
	-- Pastikan baris terakhir hall (dekat spawn) & baris fireplace tetap
	-- ke-cover cahaya walau tidak kena step LANTERN_HALL_SPACING persis
	-- (mis. kalau hall length tidak habis dibagi spacing-nya).
	markLitAround(hallInfo.centerCol, hallInfo.startRow, LANTERN_LIGHT_RADIUS_TILES)

	local spawnCol = hallInfo.spawnCol
	local spawnRow = hallInfo.spawnRow

	-- Kita cek dulu apakah koordinatnya walkable
	if isInsideGrid(spawnCol + 1, spawnRow) and isWalkable(getTile(grid, spawnCol + 1, spawnRow)) then
		placeLantern(mapFolder, spawnCol + 1, spawnRow)
		markLitAround(spawnCol + 1, spawnRow, LANTERN_LIGHT_RADIUS_TILES)
	end

	-- 3. Taruh lantern di sekitar FIREPLACE (misal: di baris sebelum fireplace, row + 1)
	local fpCol = hallInfo.fireplaceCol
	local fpRow = hallInfo.fireplaceRow
	
	-- Atau menaruh di tile sebelah kiri fireplace
	if isInsideGrid(fpCol - 1, fpRow) and isWalkable(getTile(grid, fpCol - 1, fpRow)) then
		placeLantern(mapFolder, fpCol - 1, fpRow)
		markLitAround(fpCol - 1, fpRow, LANTERN_LIGHT_RADIUS_TILES)
	end
	
	markLitAround(fpCol, fpRow, LANTERN_LIGHT_RADIUS_TILES)

	-- 1. Main hall: lantern HANYA di sisi KIRI & KANAN,
	-- berselang tiap LANTERN_HALL_SPACING tile -- BUKAN memenuhi semua
	-- kolom lebar hall (itu bikin berdempetan, lihat histori perbaikan).
	-- for row = hallInfo.endRow, hallInfo.startRow do
	--	local isFireplaceTile = row == hallInfo.fireplaceRo
	--	if isFireplaceTile then
	--		-- Area fireplace tetap ditandai lit (fireplace = sumber
	--		-- cahaya visualnya sendiri secara estetika), tanpa lantern
	--		-- fisik tambahan di situ.
	--		markLitAround(hallInfo.centerCol, row, LANTERN_LIGHT_RADIUS_TILES)
	--	else
	--		--for _, col in ipairs({ hallInfo.hallLeft, hallInfo.hallRight }) do
	--			local tileType = getTile(grid, col, row)
	--		--	if isWalkable(tileType) and not isOccupied(col, row) then
	--		--		placeLantern(mapFolder, col, row)
	--		--	end
	--		--end
	--		if isWalkable(tileType) and not isOccupied(col, row) then
	--			-- deket spwan
	--			local spawnPos = gridToWorld(hallInfo.spawnCol, hallInfo.spawnRow)
	--			placeLantern(mapFolder, spawnPos + Vector3.new(4, FLOOR_THICKNESS, 0))
--
	--			-- deket fireplace
	--			local firePos = gridToWorld(hallInfo.fireplaceCol, hallInfo.fireplaceRow)
	--			placeLantern(mapFolder, firePos + Vector3.new(-4, FLOOR_THICKNESS, 0))
	--		end
	--	end
	--end

	-- 2. Labirin: tersebar tiap LANTERN_MAZE_SPACING tile (kasar),
	-- hanya di tile yang valid & belum occupied.
	for row = 1, MAP_HEIGHT do
		for col = 1, MAP_WIDTH, LANTERN_SPACING do
			local tileType = getTile(grid, col, row)
			local isInHall = col >= hallInfo.hallLeft
				and col <= hallInfo.hallRight
				and row >= hallInfo.endRow
				and row <= hallInfo.startRow

			if isWalkable(tileType) and not isInHall and not isOccupied(col, row) then
				if LanternAsset and math.random() < LANTERN_CHANCE then
					placeLantern(mapFolder, col, row)
					markLitAround(col, row, LANTERN_LIGHT_RADIUS_TILES)
				end
			end
		end
	end
end

-- ============================================================
-- DARK ZONES — otomatis dari tile yang TIDAK ter-cover lantern
-- ============================================================

local function isTileLit(col, row)
	return litTiles[row] and litTiles[row][col] == true
end

-- Pilih varian dark zone sesuai bentuk tile:
-- - 1 walkable neighbor / sangat sempit -> Alley
-- - 2 walkable neighbor (lorong lurus/belokan) -> Corridor
-- - 3+ walkable neighbor (persimpangan/ruangan) -> Room
local function selectDarkZoneVariant(grid, col, row)
	local neighborCount = getWalkableNeighborCount(grid, col, row)

	if neighborCount <= 1 then
		return DarkZoneAlley
	elseif neighborCount == 2 then
		return DarkZoneCorridor
	else
		return DarkZoneRoom
	end
end

local function getOrCreateDarkZonesFolder()
	local folder = Workspace:FindFirstChild("DarkZones")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "DarkZones"
		folder.Parent = Workspace
	end
	return folder
end

local function placeDarkZones(grid, hallInfo)
	local darkZonesFolder = getOrCreateDarkZonesFolder()

	for row = 1, MAP_HEIGHT do
		for col = 1, MAP_WIDTH do
			local tileType = getTile(grid, col, row)

			if isWalkable(tileType) and not isTileLit(col, row) then
				local variant = selectDarkZoneVariant(grid, col, row)
				local basePos = gridToWorld(col, row)

				local clone = cloneAsset(
					variant,
					darkZonesFolder,
					CFrame.new(basePos + Vector3.new(0, 6, 0)),
					1, -- scale 1, karena kita resize manual di bawah
					false
				)

				-- Paksa lebar X & Z dark zone supaya SELALU pas TILE_SIZE (8 studs),
				-- biar nutup penuh lebar lorong/hall tanpa celah, terlepas dari ukuran
				-- asli tiap varian (Alley/Corridor/Room beda-beda). Tinggi (Y) TIDAK
				-- diubah karena offset 5 stud sudah pas untuk tinggi asli 10 stud.
				if clone then
					local darkZoneHeight = Constants.WALL_HEIGHT - 8 -- 10 stud
					clone.Size = Vector3.new(TILE_SIZE, darkZoneHeight, TILE_SIZE)
					clone.CFrame = CFrame.new(basePos + Vector3.new(0, darkZoneHeight / 2, 0))
				end

				clone:SetAttribute("IsDarkZone", true)

				-- SurvivalSystem.lua baca dark zone lewat BasePart dengan
				-- Attribute IsDarkZone, dan cek posisi pakai bounding box
				-- (CFrame:PointToObjectSpace + Size/2). Kalau variant-nya
				-- Model (bukan BasePart tunggal), kita perlu pastikan ada
				-- 1 BasePart representatif dengan Size mencakup 1 tile,
				-- supaya deteksi SurvivalSystem tetap akurat.
				if clone:IsA("Model") then
					local primary = clone.PrimaryPart or clone:FindFirstChildWhichIsA("BasePart")
					if primary then
						-- Set ukuran logis 1 tile penuh untuk deteksi,
						-- TANPA mengubah ukuran visual asli (pakai part
						-- transparan terpisah khusus untuk hit-test).
						local hitBox = Instance.new("Part")
						hitBox.Name = "DarkZoneTrigger"
						hitBox.Size = Vector3.new(TILE_SIZE, Constants.WALL_HEIGHT, TILE_SIZE)
						hitBox.CFrame = CFrame.new(basePos + Vector3.new(0, Constants.WALL_HEIGHT / 2, 0))
						hitBox.Transparency = 1
						hitBox.CanCollide = false
						hitBox.CanTouch = false
						hitBox.CanQuery = false
						hitBox.Anchored = true
						hitBox:SetAttribute("IsDarkZone", true)
						hitBox.Parent = darkZonesFolder
					end
				end
			end
		end
	end
end

-- ============================================================
-- FOOD ITEMS — tersebar acak (terkait PLAYER_HUNGER)
-- ============================================================

local function getOrCreateFoodItemsFolder()
	local folder = Workspace:FindFirstChild("FoodItems")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "FoodItems"
		folder.Parent = Workspace
	end
	return folder
end

-- NOTE: SurvivalSystem.lua Aang cuma punya RE_EatFood.OnServerEvent yang
-- terima (player) tanpa validasi item apa yang dimakan -- artinya logic
-- "item mana yang fire EatFood" ada di SISI LAIN (kemungkinan LocalScript
-- per food item, atau ProximityPrompt + client script terpisah yang
-- BELUM saya lihat). Saya auto-buat ProximityPrompt sederhana yang fire
-- EatFood ke server, TAPI ini perlu dikonfirmasi/disesuaikan dengan
-- Aang/Julian supaya tidak dobel-implementasi.
--local function hookFoodItem(foodModel)
--	local prompt = foodModel:FindFirstChildOfClass("ProximityPrompt")
--		or foodModel:FindFirstChild("ProximityPrompt", true)

--	if not prompt then
--		local targetPart = foodModel:IsA("Model")
--			and (foodModel.PrimaryPart or foodModel:FindFirstChildWhichIsA("BasePart"))
--			or foodModel

--		if targetPart then
--			prompt = Instance.new("ProximityPrompt")
--			prompt.ActionText = "Eat"
--			prompt.ObjectText = foodModel.Name
--			prompt.HoldDuration = 0.5
--			prompt.MaxActivationDistance = 8
--			prompt.Parent = targetPart
--		end
--	end

--	if prompt then
--		local Remotes = ReplicatedStorage:WaitForChild("Remotes")
--		local RE_EatFood = Remotes:WaitForChild("EatFood")

--		prompt.Triggered:Connect(function(player)
--			RE_EatFood:FireServer()
--			foodModel:Destroy() -- food item habis sekali pakai
--		end)
--	end
--end

local function placeFoodItems(grid, hallInfo)
	if #FoodOptions == 0 then
		return
	end

	local foodFolder = getOrCreateFoodItemsFolder()

	for row = 1, MAP_HEIGHT do
		for col = 1, MAP_WIDTH do
			local tileType = getTile(grid, col, row)
			local isFireplaceTile = col == hallInfo.fireplaceCol and row == hallInfo.fireplaceRow

			if
				isWalkable(tileType)
				and tileType ~= Tile.SPAWN
				and not isFireplaceTile
				and not isOccupied(col, row)
				and math.random() < FOOD_CHANCE
			then
				local selected = FoodOptions[math.random(1, #FoodOptions)]
				local basePos = gridToWorld(col, row)
				local offset = getSafePropOffset(grid, col, row, PROP_SAFE_MARGIN)

				-- Hitung scale final = scale asli asset × FOOD_SCALE
				-- Ini mempertahankan scale manual yang sudah diset di Studio
				-- (mis. waterbottle 0.01) dan hanya mengalikannya, bukan override.
				local originalScale = selected:GetAttribute("OriginalScale") or 1
				local finalscale = originalScale * FOOD_SCALE

				local clone = cloneAsset(
					selected,
					foodFolder,
					CFrame.new(basePos + offset + Vector3.new(0, FLOOR_THICKNESS, 0))
						* CFrame.Angles(0, math.rad(math.random(0, 359)), 0),
					finalscale,
					false
				)

				--hookFoodItem(clone)
				clone:SetAttribute("ItemCategory", "food")
				markOccupied(col, row)
			end
		end
	end
end

-- ============================================================
-- (BERSAMBUNG: movePlayersToSpawn, generateMap final)
-- ============================================================
-- ============================================================
-- SPAWN
-- ============================================================

local function updateSpawnLocation(hallInfo)
    -- Cari SpawnLocation yang sudah ada di Workspace (bukan di dalam
    -- GeneratedMap folder), pindahkan ke posisi spawn map yang benar.
    -- Kalau tidak ada, buat baru.
    local spawnPos = gridToWorld(hallInfo.spawnCol, hallInfo.spawnRow)

    local spawnLocation = Workspace:FindFirstChildOfClass("SpawnLocation")
    if not spawnLocation then
        spawnLocation = Instance.new("SpawnLocation")
        spawnLocation.Size = Vector3.new(TILE_SIZE, 1, TILE_SIZE)
        spawnLocation.Anchored = true
        spawnLocation.CanCollide = true
        spawnLocation.Transparency = 1 -- tidak terlihat
        spawnLocation.Name = "MapSpawnLocation"
        spawnLocation.Parent = Workspace
    end

    -- Taruh di permukaan floor (Y = ketebalan floor)
    spawnLocation.CFrame = CFrame.new(
        spawnPos.X,
        FLOOR_THICKNESS,
        spawnPos.Z
    )
end

local function movePlayersToSpawn(hallInfo)
	local spawnPos = gridToWorld(hallInfo.spawnCol, hallInfo.spawnRow) + Vector3.new(0, 5, 0)

	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		if character then
			character:PivotTo(CFrame.new(spawnPos))
		end
	end
end

-- ============================================================
-- GENERATE
-- ============================================================

local MapGenerator = {}

-- generateMap(level): level (number, default 1) menentukan ukuran map,
-- panjang main hall, dan jumlah coal/lever (scaling sesuai Constants).
function MapGenerator.generateMap(level: number?)
	level = level or 1
	math.randomseed(os.time())

	-- Reset state per-generate (occupied tiles & lit tiles HARUS fresh,
	-- supaya generate kedua/ketiga tidak ke-pollute data lama)
	occupiedTiles = {}
	litTiles = {}

	-- Resolve ukuran map & hall sesuai level, lalu OVERRIDE closure vars
	local levelConfig = resolveLevelConfig(level)
	MAP_WIDTH = levelConfig.mapCols
	MAP_HEIGHT = levelConfig.mapRows
	MAIN_HALL_LENGTH = levelConfig.mainHallLen

	local mapFolder = clearOldMap()

	-- Bersihkan folder task/darkzone/food lama dari run sebelumnya
	-- (folder ini di Workspace langsung, BUKAN di dalam GeneratedMap,
	-- jadi clearOldMap() tidak otomatis bersihkan ini)
	local oldTaskFolder = Workspace:FindFirstChild("TaskObjects")
	if oldTaskFolder then
		oldTaskFolder:Destroy()
	end

	local oldDarkZonesFolder = Workspace:FindFirstChild("DarkZones")
	if oldDarkZonesFolder then
		oldDarkZonesFolder:Destroy()
	end

	local oldFoodFolder = Workspace:FindFirstChild("FoodItems")
	if oldFoodFolder then
		oldFoodFolder:Destroy()
	end

	local grid, hallInfo = buildLayout()
	updateSpawnLocation(hallInfo)

	-- ── Lantern DULU (sebelum dark zone, supaya litTiles ke-set) ──
	placeLanterns(mapFolder, grid, hallInfo)

	-- ── Floor, ceiling, wall, props ──
	for row = 1, MAP_HEIGHT do
		for col = 1, MAP_WIDTH do
			local tileType = grid[row][col]

			if isWalkable(tileType) then
				placeFloor(mapFolder, col, row, tileType, hallInfo)

				local isFireplaceTile = col == hallInfo.fireplaceCol and row == hallInfo.fireplaceRow

				-- Tile fireplace WAJIB dapat conveyor visual (supaya tidak
				-- "mengambang", lihat histori perbaikan sebelumnya), dan
				-- tile CONVEYOR biasa juga dapat. Gabungkan jadi satu
				-- kondisi supaya TIDAK terpanggil 2x kalau kebetulan tile
				-- fireplace itu sendiri tileType-nya == Tile.CONVEYOR.
				if tileType == Tile.CONVEYOR or isFireplaceTile then
					placeConveyorVisual(mapFolder, col, row, hallInfo)
				end

				placeCeiling(mapFolder, col, row, tileType)
				placeWallsAroundFloor(mapFolder, grid, col, row)
			end
		end
	end

	placeFireplace(mapFolder, hallInfo)

	-- ── Task Objects (coal & lever) ──
	local taskFolder = getOrCreateTaskObjectsFolder()
	local placeableTiles = collectPlaceableTiles(grid, hallInfo)
	shuffleTiles(placeableTiles)

	placeCoalObjects(taskFolder, placeableTiles, level)
	placeLeverObjects(taskFolder, placeableTiles, level)

	-- ── Dark Zones (setelah lantern selesai, pakai litTiles) ──
	placeDarkZones(grid, hallInfo)

	-- ── Food Items ──
	placeFoodItems(grid, hallInfo)

	-- ── Props acak (boulder/rubble) — TERAKHIR, supaya markOccupied
	-- dari task/lantern/food sudah lengkap dan prop tidak menimpa objek
	-- penting ──
	for row = 1, MAP_HEIGHT do
		for col = 1, MAP_WIDTH do
			local tileType = grid[row][col]
			if isWalkable(tileType) then
				placeRandomProp(mapFolder, grid, col, row, tileType, hallInfo)
			end
		end
	end

	movePlayersToSpawn(hallInfo)

	print(
		string.format(
			"[MapGenerator] Level %d generated. Map %dx%d, hall length %d, nightmare=%s",
			level,
			MAP_WIDTH,
			MAP_HEIGHT,
			MAIN_HALL_LENGTH,
			tostring(levelConfig.isNightmare)
		)
	)

	-- 1. RemoteEvent untuk Julian punya Minimap (Server -> Client)
	MapGeneratedEvent:FireAllClients(grid, hallInfo)

	-- 2. BindableEvent untuk Arkan punya Monster (Server -> Server)
	ServerMapBindable:Fire(grid, hallInfo)

	return grid, hallInfo
end

-- ============================================================
-- AUTO-RUN (sementara, untuk testing tanpa GameManager)
--
-- TODO: setelah GameManager.server.luau dipastikan jalan duluan dan
-- panggil MapGenerator.generateMap(session.level) secara eksplisit,
-- HAPUS blok auto-run ini supaya map tidak ke-generate 2x (sekali
-- otomatis di sini, sekali lagi dipanggil GameManager).
--
-- Cara GameManager manggil nanti (require, bukan auto-run):
--   local MapGenerator = require(ServerScriptService.MapGenerator)
--   MapGenerator.generateMap(session.level)
-- ============================================================

task.wait(2)
MapGenerator.generateMap(level==10)

return MapGenerator
