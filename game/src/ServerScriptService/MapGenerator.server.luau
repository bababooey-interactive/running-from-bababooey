local Workspace = game:GetService("Workspace")
local ServerStorage = game:GetService("ServerStorage")

local TILE_SIZE = 16
local MAP_WIDTH = 8
local MAP_HEIGHT = 8
local WALL_SCALE = 5
local WALL_Y_OFFSET = 6
--local WALL_HEIGHT = 12
--local WALL_THICKNESS = 2
local CEILING_SCALE = 4
local CEILING_Y_OFFSET = 12

local directions = {
	N = { dx = 0, dz = -1, opposite = "S" },
	E = { dx = 1, dz = 0, opposite = "W" },
	S = { dx = 0, dz = 1, opposite = "N" },
	W = { dx = -1, dz = 0, opposite = "E" },
}

local MapPieces = ServerStorage
	:WaitForChild("Assets")
	:WaitForChild("MapPieces")

local CeilingFlat = MapPieces
	:WaitForChild("Ceilings")
	:WaitForChild("ceiling_flat")

local CeilingArch = MapPieces
    :WaitForChild("Ceilings")
    :WaitForChild("ceiling_arch")

local CeilingCrack = MapPieces
    :WaitForChild("Ceilings")
    :WaitForChild("ceiling_crack")

local WallStraight = MapPieces
	:WaitForChild("Walls")
	:WaitForChild("wall_straight")

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

local function createPart(name, size, cframe, color)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Anchored = true
	part.Color = color
	part.Material = Enum.Material.Slate
	part.Parent = nil

	return part
end

local function gridToWorld(x, z)
	return Vector3.new(
		x * TILE_SIZE,
		0,
		z * TILE_SIZE
	)
end

local function createGrid()
	local grid = {}

	for x = 1, MAP_WIDTH do
		grid[x] = {}

		for z = 1, MAP_HEIGHT do
			grid[x][z] = {
				Visited = false,
				Walls = {
					N = true,
					E = true,
					S = true,
					W = true,
				}
			}
		end
	end

	return grid
end

local function shuffle(list)
	for i = #list, 2, -1 do
		local j = math.random(1, i)
		list[i], list[j] = list[j], list[i]
	end

	return list
end

local function generateMaze(grid)
	local function visit(x, z)
		grid[x][z].Visited = true

		local dirNames = { "N", "E", "S", "W" }
		shuffle(dirNames)

		for _, dirName in ipairs(dirNames) do
			local dir = directions[dirName]
			local nx = x + dir.dx
			local nz = z + dir.dz

			local insideMap =
				nx >= 1 and nx <= MAP_WIDTH and
				nz >= 1 and nz <= MAP_HEIGHT

			if insideMap and not grid[nx][nz].Visited then
				grid[x][z].Walls[dirName] = false
				grid[nx][nz].Walls[dir.opposite] = false

				visit(nx, nz)
			end
		end
	end

	visit(1, 1)
end

local function placeFloor(mapFolder, x, z)
	local pos = gridToWorld(x - 1, z - 1)

	local floor = createPart(
		"Floor",
		Vector3.new(TILE_SIZE, 1, TILE_SIZE),
		CFrame.new(pos),
		Color3.fromRGB(65, 65, 65)
	)

	floor.Parent = mapFolder
end

local function setPhysicsSafe(object)
	if object:IsA("BasePart") then
		object.Anchored = true
		object.CanCollide = true
		object.CanTouch = true
		object.CanQuery = true
	end

	for _, descendant in ipairs(object:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = true
			descendant.CanTouch = true
			descendant.CanQuery = true
		end
	end
end

local function cloneAsset(template, parent, cframe, scale)
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

    setPhysicsSafe(clone)

	return clone
end

local function placeWall(mapFolder, x, z, dirName)
	local basePos = gridToWorld(x - 1, z - 1)
	local wallPos
	local rotationY = 0

	if dirName == "N" then
		wallPos = basePos + Vector3.new(0, WALL_Y_OFFSET, -TILE_SIZE / 2)
		rotationY = 0
	elseif dirName == "S" then
		wallPos = basePos + Vector3.new(0, WALL_Y_OFFSET, TILE_SIZE / 2)
		rotationY = 180
	elseif dirName == "E" then
		wallPos = basePos + Vector3.new(TILE_SIZE / 2, WALL_Y_OFFSET, 0)
		rotationY = 90
	elseif dirName == "W" then
		wallPos = basePos + Vector3.new(-TILE_SIZE / 2, WALL_Y_OFFSET, 0)
		rotationY = 270
	end

	cloneAsset(
		WallStraight,
		mapFolder,
		CFrame.new(wallPos) * CFrame.Angles(0, math.rad(rotationY), 0),
        WALL_SCALE
	)
end

local ceilingOptions = { 
    CeilingFlat, 
    CeilingArch, 
    CeilingCrack 
}

local function placeCeiling(mapFolder, x, z)
	local basePos = gridToWorld(x - 1, z - 1)

	local ceilingPos = basePos + Vector3.new(
		0,
		CEILING_Y_OFFSET,
		0
	)

    local selectedCeiling = ceilingOptions[math.random(3, #ceilingOptions)]

    local randomRotation = math.random(0, 3) * 90

	cloneAsset(
		selectedCeiling,
		mapFolder,
		CFrame.new(ceilingPos) * CFrame.Angles(0, math.rad(randomRotation), 0),
		CEILING_SCALE
	)
end

local function placeRandomProp(mapFolder, x, z)
	if math.random() > 0.15 then
		return
	end

	-- Jangan spawn prop di titik awal
	if x == 1 and z == 1 then
		return
	end

	local basePos = gridToWorld(x - 1, z - 1)

	local prop = createPart(
		"Mock_Boulder",
		Vector3.new(4, 4, 4),
		CFrame.new(basePos + Vector3.new(
			math.random(-4, 4),
			2,
			math.random(-4, 4)
		)),
		Color3.fromRGB(90, 80, 70)
	)

	prop.Shape = Enum.PartType.Ball
	prop.Parent = mapFolder
end

local function generateMap()
	local mapFolder = clearOldMap()
	local grid = createGrid()

	generateMaze(grid)

	for x = 1, MAP_WIDTH do
		for z = 1, MAP_HEIGHT do
			placeFloor(mapFolder, x, z)
			placeRandomProp(mapFolder, x, z)
            placeCeiling(mapFolder, x, z)

			local cell = grid[x][z]

			for dirName, hasWall in pairs(cell.Walls) do
				if hasWall then
					placeWall(mapFolder, x, z, dirName)
				end
			end
		end
	end

	print("Maze generated!")
end

generateMap()