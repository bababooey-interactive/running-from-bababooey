local Workspace = game:GetService("Workspace")
local ServerStorage = game:GetService("ServerStorage")
local Players = game:GetService("Players")

-- ============================================================
-- CONFIG
-- ============================================================

local TILE_SIZE = 16

local MAP_WIDTH = 15
local MAP_HEIGHT = 18

local MAIN_HALL_WIDTH = 3
local MAIN_HALL_LENGTH = 13

local WALL_SCALE = 5
local WALL_Y_OFFSET = 5

local CEILING_SCALE = 4
local CEILING_Y_OFFSET = 12

local PROP_SCALE = 3
local FIREPLACE_SCALE = 4
local CONVEYOR_SCALE = 4

local FLOOR_HEIGHT = 1

local SIDE_BRANCH_CHANCE = 0.85
local SIDE_BRANCH_MIN_LENGTH = 3
local SIDE_BRANCH_MAX_LENGTH = 5

local PROP_CHANCE = 0.18
local RUBBLE_CHANCE = 0.22
local SHORT_WALL_CHANCE = 0.12

local CONVEYOR_SPEED = 35

-- ============================================================
-- ASSETS
-- ============================================================

local MapPieces = ServerStorage
	:WaitForChild("Assets")
	:WaitForChild("MapPieces")

local WallsFolder = MapPieces:WaitForChild("Walls")
local CeilingsFolder = MapPieces:WaitForChild("Ceilings")
local PropsFolder = MapPieces:WaitForChild("Props")
local SpecialFolder = MapPieces:FindFirstChild("Special")

local WallStraight = WallsFolder:WaitForChild("wall_straight")
local WallCorner = WallsFolder:FindFirstChild("wall_corner_90")
local WallEndCap = WallsFolder:FindFirstChild("wall_end_cap")
local WallPillar = WallsFolder:FindFirstChild("wall_pillar")
local WallShort = WallsFolder:FindFirstChild("wall_short")

local CeilingFlat = CeilingsFolder:WaitForChild("ceiling_flat")
local CeilingArch = CeilingsFolder:FindFirstChild("ceiling_arch")
local CeilingCrack = CeilingsFolder:FindFirstChild("ceiling_crack")
local CeilingStalactite = CeilingsFolder:FindFirstChild("Ceiling_Stalactite_Group")

local BoulderLarge = PropsFolder:FindFirstChild("boulder_large")
local BoulderMedium = PropsFolder:FindFirstChild("boulder_medium")
local BoulderSmall = PropsFolder:FindFirstChild("boulder_small")
local FloorRubble = PropsFolder:FindFirstChild("Floor_Rubble_Group")
local FireplaceAsset = PropsFolder:FindFirstChild("old_fireplace_prop")

local ConveyorAsset = nil

if SpecialFolder then
	ConveyorAsset = SpecialFolder:FindFirstChild("conveyor")
end

-- fallback kalau conveyor belum dipindah ke Special
if not ConveyorAsset then
	ConveyorAsset = PropsFolder:FindFirstChild("conveyor")
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
-- TILE TYPES
-- ============================================================

local Tile = {
	WALL = 0,
	FLOOR = 1,
	SPAWN = 2,
	CONVEYOR = 3,
	FIREPLACE = 4,
}

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
	return Vector3.new(
		(col - 1) * TILE_SIZE,
		0,
		(row - 1) * TILE_SIZE
	)
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
	return tileType == Tile.FLOOR
		or tileType == Tile.SPAWN
		or tileType == Tile.CONVEYOR
		or tileType == Tile.FIREPLACE
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

	local startRow = MAP_HEIGHT - 2
	local endRow = math.max(3, startRow - MAIN_HALL_LENGTH + 1)

	for row = endRow, startRow do
		for col = hallLeft, hallRight do
			setTile(grid, col, row, Tile.FLOOR)
		end

		setTile(grid, centerCol, row, Tile.CONVEYOR)
	end

	setTile(grid, centerCol, startRow, Tile.SPAWN)
	setTile(grid, centerCol, endRow - 1, Tile.FIREPLACE)

	return {
		centerCol = centerCol,
		hallLeft = hallLeft,
		hallRight = hallRight,
		startRow = startRow,
		endRow = endRow,
		spawnCol = centerCol,
		spawnRow = startRow,
		fireplaceCol = centerCol,
		fireplaceRow = endRow - 1,
	}
end

local function carveSideBranch(grid, startCol, startRow, direction)
	local length = math.random(SIDE_BRANCH_MIN_LENGTH, SIDE_BRANCH_MAX_LENGTH)

	local col = startCol
	local row = startRow

	for i = 1, length do
		col += direction

		if not isInsideGrid(col, row) then
			break
		end

		setTile(grid, col, row, Tile.FLOOR)

		if i >= 2 and math.random() < 0.35 then
			local turn = if math.random() < 0.5 then -1 else 1
			local nextRow = row + turn

			if isInsideGrid(col, nextRow) then
				row = nextRow
				setTile(grid, col, row, Tile.FLOOR)
			end
		end
	end
end

local function carveRandomSideCorridors(grid, hallInfo)
	for row = hallInfo.endRow + 2, hallInfo.startRow - 2, 2 do
		if math.random() < SIDE_BRANCH_CHANCE then
			carveSideBranch(grid, hallInfo.hallLeft - 1, row, -1)
		end

		if math.random() < SIDE_BRANCH_CHANCE then
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

	if WallShort and math.random() < SHORT_WALL_CHANCE then
		selectedWall = WallShort
		scale = WALL_SCALE
	end

	cloneAsset(
		selectedWall,
		mapFolder,
		CFrame.new(wallPos) * CFrame.Angles(0, math.rad(dir.rotation), 0),
		scale,
		true
	)
end

local function placeDecorativeWallDetails(mapFolder, grid, col, row)
	local tileType = getTile(grid, col, row)

	if not isWalkable(tileType) then
		return
	end

	local basePos = gridToWorld(col, row)

	if shouldUsePillar(grid, col, row) then
		cloneAsset(
			WallPillar,
			mapFolder,
			CFrame.new(basePos + Vector3.new(0, WALL_Y_OFFSET, 0)),
			WALL_SCALE,
			true
		)
	end

	if shouldUseEndCap(grid, col, row) then
		cloneAsset(
			WallEndCap,
			mapFolder,
			CFrame.new(basePos + Vector3.new(0, WALL_Y_OFFSET, 0)),
			WALL_SCALE,
			true
		)
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
-- FLOOR, CEILING, CONVEYOR, PROPS
-- ============================================================

local function placeFloor(mapFolder, col, row, tileType)
	local pos = gridToWorld(col, row)

	local color = Color3.fromRGB(60, 60, 60)
	local material = Enum.Material.Slate

	if tileType == Tile.SPAWN then
		color = Color3.fromRGB(60, 90, 60)
	elseif tileType == Tile.FIREPLACE then
		color = Color3.fromRGB(90, 55, 35)
	elseif tileType == Tile.CONVEYOR then
		color = Color3.fromRGB(35, 40, 50)
		material = Enum.Material.Metal
	end

	local floor = createPart(
		"Floor",
		Vector3.new(TILE_SIZE, FLOOR_HEIGHT, TILE_SIZE),
		CFrame.new(pos),
		color,
		material
	)

	floor.Parent = mapFolder
end

local function placeCeiling(mapFolder, col, row, tileType)
	local basePos = gridToWorld(col, row)

	local selectedCeiling = CeilingFlat

	if tileType == Tile.CONVEYOR and CeilingArch then
		selectedCeiling = CeilingArch
	elseif math.random() < 0.18 and CeilingCrack then
		selectedCeiling = CeilingCrack
	elseif math.random() < 0.12 and CeilingStalactite then
		selectedCeiling = CeilingStalactite
	else
		selectedCeiling = CeilingOptions[math.random(1, #CeilingOptions)]
	end

	local ceilingPos = basePos + Vector3.new(0, CEILING_Y_OFFSET, 0)
	local rotation = math.random(0, 3) * 90

	cloneAsset(
		selectedCeiling,
		mapFolder,
		CFrame.new(ceilingPos) * CFrame.Angles(0, math.rad(rotation), 0),
		CEILING_SCALE,
		false
	)
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

	local directionToFireplace = Vector3.new(0, 0, -1)

	zone.Touched:Connect(function(hit)
		if not hit:IsA("BasePart") then
			return
		end

		local isCoal =
			hit.Name == "coal"
			or hit.Name == "Coal"
			or hit.Name:lower():find("coal") ~= nil

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
		cloneAsset(
			ConveyorAsset,
			mapFolder,
			CFrame.new(basePos + Vector3.new(0, 0.75, 0)),
			CONVEYOR_SCALE,
			false
		)
	else
		local conveyor = createPart(
			"Conveyor_Visual",
			Vector3.new(TILE_SIZE * 0.75, 0.2, TILE_SIZE * 0.95),
			CFrame.new(basePos + Vector3.new(0, 0.65, 0)),
			Color3.fromRGB(50, 70, 110),
			Enum.Material.Metal
		)

		conveyor.CanCollide = false
		conveyor.Parent = mapFolder
	end

	createConveyorZone(mapFolder, col, row, hallInfo)
end

local function placeRandomProp(mapFolder, col, row, tileType)
	if tileType == Tile.SPAWN or tileType == Tile.CONVEYOR or tileType == Tile.FIREPLACE then
		return
	end

	local basePos = gridToWorld(col, row)

	if FloorRubble and math.random() < RUBBLE_CHANCE then
		cloneAsset(
			FloorRubble,
			mapFolder,
			CFrame.new(basePos + Vector3.new(math.random(-3, 3), 0.5, math.random(-3, 3))) * CFrame.Angles(0, math.rad(math.random(0, 359)), 0),
			2,
			false
		)
	end

	if #BoulderOptions > 0 and math.random() < PROP_CHANCE then
		local selected = BoulderOptions[math.random(1, #BoulderOptions)]

		cloneAsset(
			selected,
			mapFolder,
			CFrame.new(basePos + Vector3.new(math.random(-4, 4), 2, math.random(-4, 4))) * CFrame.Angles(0, math.rad(math.random(0, 359)), 0),
			PROP_SCALE,
			true
		)
	end
end

local function placeFireplace(mapFolder, hallInfo)
	local basePos = gridToWorld(hallInfo.fireplaceCol, hallInfo.fireplaceRow)

	if FireplaceAsset then
		cloneAsset(
			FireplaceAsset,
			mapFolder,
			CFrame.new(basePos + Vector3.new(0, 1, 0)) * CFrame.Angles(0, math.rad(180), 0),
			FIREPLACE_SCALE,
			true
		)
	else
		local fireplaceMock = createPart(
			"Mock_Fireplace",
			Vector3.new(TILE_SIZE, 7, 3),
			CFrame.new(basePos + Vector3.new(0, 3.5, 0)),
			Color3.fromRGB(100, 50, 25),
			Enum.Material.Brick
		)

		fireplaceMock.Parent = mapFolder
	end
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

local function generateMap()
	math.randomseed(os.time())

	local mapFolder = clearOldMap()
	local grid, hallInfo = buildLayout()

	for row = 1, MAP_HEIGHT do
		for col = 1, MAP_WIDTH do
			local tileType = grid[row][col]

			if isWalkable(tileType) then
				placeFloor(mapFolder, col, row, tileType)

				if tileType == Tile.CONVEYOR then
					placeConveyorVisual(mapFolder, col, row, hallInfo)
				end

				placeCeiling(mapFolder, col, row, tileType)
				placeWallsAroundFloor(mapFolder, grid, col, row)
				placeRandomProp(mapFolder, col, row, tileType)
			end
		end
	end

	placeFireplace(mapFolder, hallInfo)
	movePlayersToSpawn(hallInfo)

	print("Generated fixed main hall with randomized side corridors and conveyor.")
end

generateMap()