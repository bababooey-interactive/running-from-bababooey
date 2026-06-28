-- =============================================================
--  MinimapUI.client.luau
--  Minimap dinamis dari grid yang di-generate MapGenerator
--  Path: game/src/StarterPlayer/StarterPlayerScripts/MinimapUI.client.luau
--
--  Cara kerja:
--  1. Terima grid (2D array) dari RemoteEvent "MapGenerated"
--  2. Buat Frame kecil per tile (tile walkable saja yang dirender)
--  3. Fog of war: tile hidden sampai player mendekat (radius REVEAL_RADIUS)
--  4. Dot player (putih) update tiap Heartbeat
--  5. Dot monster (merah) update dari RemoteEvent "MonsterPosition"
--
--  Catatan tile types (dari Constants.luau):
--    0 = WALL   → tidak dirender (background minimap = warna wall)
--    1 = FLOOR  → abu gelap
--    2 = SPAWN  → sama dengan floor (spawn tidak perlu warna khusus)
--    3 = CONVEYOR → biru gelap
--  Fireplace tile → oranye (dicek dari hallInfo.fireplaceCol/Row)
-- =============================================================

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")

local Constants = require(ReplicatedStorage.Shared.Constants)

local Remotes            = ReplicatedStorage:WaitForChild("Remotes")
local RE_MapGenerated    = Remotes:WaitForChild("MapGenerated")
local RE_MonsterPosition = Remotes:WaitForChild("MonsterPosition")

local LocalPlayer = Players.LocalPlayer
local PlayerGui   = LocalPlayer:WaitForChild("PlayerGui")

-- ─────────────────────────────────────────────
--  CONFIG
-- ─────────────────────────────────────────────

local TILE_PX       = 7      -- ukuran 1 tile dalam pixel di minimap (naik dari 4)
local MINIMAP_SIZE  = 220    -- lebar & tinggi minimap (pixel) — square (naik dari 160)
local REVEAL_RADIUS = 6      -- tile radius yang di-reveal di sekitar player (naik dari 5)
local UPDATE_HZ     = 0.08   -- interval update posisi dot (detik)
local MAP_OFFSET_X  = 12     -- jarak dari kiri layar
local MAP_OFFSET_Y  = 52     -- jarak dari atas layar (di bawah Roblox buttons)

-- Warna tile (revealed)
local COLOR = {
    FLOOR     = Color3.fromRGB(70,  72,  82),
    CONVEYOR  = Color3.fromRGB(40,  60, 110),
    FIREPLACE = Color3.fromRGB(200, 100,  30),
    SPAWN     = Color3.fromRGB(70,  72,  82),  -- sama dengan floor
    FOG       = Color3.fromRGB(18,  18,  22),  -- tile belum dikunjungi
    PLAYER    = Color3.fromRGB(240, 240, 240),
    MONSTER   = Color3.fromRGB(210,  45,  45),
    BG        = Color3.fromRGB(12,  12,  16),  -- background (wall)
    BORDER    = Color3.fromRGB(55,  55,  70),
}

-- ─────────────────────────────────────────────
--  STATE
-- ─────────────────────────────────────────────

local grid: {{number}}   = {}
local hallInfo: any      = nil
local gridRows           = 0
local gridCols           = 0
local tileFrames: {{Frame?}} = {}   -- [row][col] = Frame | nil (wall tidak punya frame)
local revealed: {{boolean}}  = {}   -- [row][col] = true kalau sudah di-reveal

-- Posisi offset supaya minimap di-center di dalam viewport
-- (diisi saat grid diterima)
local viewOffsetCol = 0   -- col pertama yang ter-visible di minimap
local viewOffsetRow = 0   -- row pertama yang ter-visible di minimap

-- ─────────────────────────────────────────────
--  BUILD MINIMAP GUI (container saja, tile diisi nanti)
-- ─────────────────────────────────────────────

local screenGui = Instance.new("ScreenGui")
screenGui.Name           = "MinimapGui"
screenGui.ResetOnSpawn   = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.IgnoreGuiInset = false
screenGui.Enabled        = false   -- aktif setelah map diterima
screenGui.Parent         = PlayerGui

-- Outer container (border + background)
local mapContainer = Instance.new("Frame")
mapContainer.Name                  = "MapContainer"
mapContainer.Position              = UDim2.new(0, MAP_OFFSET_X, 0, MAP_OFFSET_Y)
mapContainer.Size                  = UDim2.new(0, MINIMAP_SIZE + 4, 0, MINIMAP_SIZE + 4)  -- 224x224
mapContainer.BackgroundColor3      = COLOR.BORDER
mapContainer.BorderSizePixel       = 0
mapContainer.Parent                = screenGui

local containerCorner = Instance.new("UICorner")
containerCorner.CornerRadius = UDim.new(0, 6)
containerCorner.Parent       = mapContainer

-- Inner viewport (area render tile)
local mapViewport = Instance.new("Frame")
mapViewport.Name             = "MapViewport"
mapViewport.Position         = UDim2.new(0, 2, 0, 2)
mapViewport.Size             = UDim2.new(0, MINIMAP_SIZE, 0, MINIMAP_SIZE)
mapViewport.BackgroundColor3 = COLOR.BG
mapViewport.BorderSizePixel  = 0
mapViewport.ClipsDescendants = true   -- tile di luar batas tidak terlihat
mapViewport.Parent           = mapContainer

local viewportCorner = Instance.new("UICorner")
viewportCorner.CornerRadius = UDim.new(0, 4)
viewportCorner.Parent       = mapViewport

-- Label "MINIMAP" kecil di atas container
local mapLabel = Instance.new("TextLabel")
mapLabel.Name                  = "MapLabel"
mapLabel.AnchorPoint           = Vector2.new(0, 1)
mapLabel.Position              = UDim2.new(0, 0, 0, -2)
mapLabel.Size                  = UDim2.new(0, 80, 0, 14)
mapLabel.BackgroundTransparency = 1
mapLabel.TextColor3             = Color3.fromRGB(100, 100, 120)
mapLabel.TextSize               = 10
mapLabel.Font                   = Enum.Font.GothamBold
mapLabel.TextXAlignment         = Enum.TextXAlignment.Left
mapLabel.Text                   = "MINIMAP"
mapLabel.Parent                 = mapContainer

-- ── Dot player ──────────────────────────────
local playerDot = Instance.new("Frame")
playerDot.Name             = "PlayerDot"
playerDot.Size             = UDim2.new(0, 6, 0, 6)
playerDot.AnchorPoint      = Vector2.new(0.5, 0.5)
playerDot.BackgroundColor3 = COLOR.PLAYER
playerDot.BorderSizePixel  = 0
playerDot.ZIndex           = 10
playerDot.Visible          = false
playerDot.Parent           = mapViewport

local playerDotCorner = Instance.new("UICorner")
playerDotCorner.CornerRadius = UDim.new(1, 0)
playerDotCorner.Parent       = playerDot

-- Player direction triangle (garis kecil menunjuk arah)
local playerDir = Instance.new("Frame")
playerDir.Name             = "PlayerDir"
playerDir.Size             = UDim2.new(0, 2, 0, 5)
playerDir.AnchorPoint      = Vector2.new(0.5, 1)
playerDir.BackgroundColor3 = COLOR.PLAYER
playerDir.BorderSizePixel  = 0
playerDir.ZIndex           = 10
playerDir.Visible          = false
playerDir.Parent           = mapViewport

-- ── Dot monster (hingga 4 clone) ────────────
local MAX_MONSTERS = 4
local monsterDots: {Frame} = {}

for i = 1, MAX_MONSTERS do
    local dot = Instance.new("Frame")
    dot.Name             = "MonsterDot_" .. i
    dot.Size             = UDim2.new(0, 6, 0, 6)
    dot.AnchorPoint      = Vector2.new(0.5, 0.5)
    dot.BackgroundColor3 = COLOR.MONSTER
    dot.BorderSizePixel  = 0
    dot.ZIndex           = 9
    dot.Visible          = false
    dot.Parent           = mapViewport

    local dotCorner = Instance.new("UICorner")
    dotCorner.CornerRadius = UDim.new(1, 0)
    dotCorner.Parent       = dot

    monsterDots[i] = dot
end

-- ─────────────────────────────────────────────
--  KONVERSI: world position → minimap pixel
--
--  MapGenerator: gridToWorld(col, row) = Vector3((col-1)*TILE_SIZE, 0, (row-1)*TILE_SIZE)
--  Jadi: col = pos.X / TILE_SIZE + 1
--        row = pos.Z / TILE_SIZE + 1
--
--  Minimap di-scroll supaya player selalu di tengah.
--  viewOffsetCol / viewOffsetRow = tile pojok kiri atas minimap saat ini.
-- ─────────────────────────────────────────────

local TILE_SIZE_WORLD = Constants.TILE_SIZE  -- 8 studs per tile

local function worldToTileF(pos: Vector3): (number, number)
    -- Mengembalikan posisi tile dalam float (bukan integer),
    -- supaya dot bisa bergerak smooth di antara tile.
    local col = pos.X / TILE_SIZE_WORLD + 1
    local row = pos.Z / TILE_SIZE_WORLD + 1
    return col, row
end

local function tileToMinimapPx(tileCol: number, tileRow: number): (number, number)
    -- Konversi koordinat tile ke pixel dalam mapViewport.
    -- viewOffsetCol/Row adalah tile mana yang ada di sudut kiri atas minimap.
    local px = (tileCol - viewOffsetCol) * TILE_PX
    local py = (tileRow - viewOffsetRow) * TILE_PX
    return px, py
end

local function updateViewOffset(playerCol: number, playerRow: number)
    -- Geser offset supaya player selalu di tengah minimap.
    local halfTiles = (MINIMAP_SIZE / TILE_PX) / 2
    viewOffsetCol = playerCol - halfTiles
    viewOffsetRow = playerRow - halfTiles
end

-- ─────────────────────────────────────────────
--  REVEAL TILES DI SEKITAR POSISI PLAYER
-- ─────────────────────────────────────────────

local function revealAround(centerCol: number, centerRow: number)
    local cCol = math.round(centerCol)
    local cRow = math.round(centerRow)

    for dr = -REVEAL_RADIUS, REVEAL_RADIUS do
        for dc = -REVEAL_RADIUS, REVEAL_RADIUS do
            -- Lingkaran, bukan kotak
            if dc * dc + dr * dr > REVEAL_RADIUS * REVEAL_RADIUS then
                continue
            end

            local r = cRow + dr
            local c = cCol + dc

            if r < 1 or r > gridRows or c < 1 or c > gridCols then
                continue
            end

            if revealed[r] and revealed[r][c] then
                continue  -- sudah di-reveal, skip
            end

            revealed[r] = revealed[r] or {}
            revealed[r][c] = true

            -- Tampilkan frame tile (kalau ada — wall tidak punya frame)
            local frame = tileFrames[r] and tileFrames[r][c]
            if frame then
                frame.BackgroundTransparency = 0
            end
        end
    end
end

-- ─────────────────────────────────────────────
--  UPDATE POSISI TILES DI MINIMAP
--  (dipanggil tiap kali viewOffset berubah — saat player bergerak)
-- ─────────────────────────────────────────────

local function repositionAllTiles()
    for row = 1, gridRows do
        for col = 1, gridCols do
            local frame = tileFrames[row] and tileFrames[row][col]
            if not frame then continue end

            local px, py = tileToMinimapPx(col, row)
            frame.Position = UDim2.new(0, px, 0, py)
        end
    end
end

-- ─────────────────────────────────────────────
--  BUILD TILE FRAMES DARI GRID
-- ─────────────────────────────────────────────

local function isFireplaceTile(col, row)
    if not hallInfo then return false end
    return col == hallInfo.fireplaceCol and row == hallInfo.fireplaceRow
end

local function getTileColor(col, row, tileType)
    if isFireplaceTile(col, row) then
        return COLOR.FIREPLACE
    end
    if tileType == Constants.Tile.CONVEYOR then
        return COLOR.CONVEYOR
    end
    return COLOR.FLOOR  -- FLOOR dan SPAWN sama
end

local function buildTileFrames()
    -- Bersihkan tile lama kalau ada (re-generate)
    for _, child in ipairs(mapViewport:GetChildren()) do
        if child.Name == "Tile" then
            child:Destroy()
        end
    end
    tileFrames = {}
    revealed   = {}

    for row = 1, gridRows do
        tileFrames[row] = {}
        for col = 1, gridCols do
            local tileType = grid[row][col]

            -- WALL tidak dirender (background = COLOR.BG)
            if tileType == Constants.Tile.WALL then
                continue
            end

            local px, py = tileToMinimapPx(col, row)

            local frame = Instance.new("Frame")
            frame.Name                 = "Tile"
            frame.Size                 = UDim2.new(0, TILE_PX, 0, TILE_PX)
            frame.Position             = UDim2.new(0, px, 0, py)
            frame.BackgroundColor3     = getTileColor(col, row, tileType)
            frame.BackgroundTransparency = 1   -- fog: semua mulai tersembunyi
            frame.BorderSizePixel      = 0
            frame.ZIndex               = 2
            frame.Parent               = mapViewport

            tileFrames[row][col] = frame
        end
    end
end

-- ─────────────────────────────────────────────
--  INIT MAP (dipanggil dari RE_MapGenerated)
-- ─────────────────────────────────────────────

local function initMap(receivedGrid: {{number}}, receivedHallInfo: any)
    grid     = receivedGrid
    hallInfo = receivedHallInfo

    gridRows = #grid
    gridCols = gridRows > 0 and #grid[1] or 0

    if gridRows == 0 or gridCols == 0 then
        warn("[MinimapUI] Grid kosong, minimap tidak ditampilkan.")
        return
    end

    -- Set view offset awal ke spawn
    local spawnCol = receivedHallInfo.spawnCol or math.ceil(gridCols / 2)
    local spawnRow = receivedHallInfo.spawnRow or gridRows
    updateViewOffset(spawnCol, spawnRow)

    buildTileFrames()

    -- Reveal area spawn di awal
    revealAround(spawnCol, spawnRow)

    screenGui.Enabled  = true
    playerDot.Visible  = true
    playerDir.Visible  = true

    print(string.format("[MinimapUI] Map %dx%d dirender. Spawn: (%d,%d)",
        gridCols, gridRows, spawnCol, spawnRow))
end

-- ─────────────────────────────────────────────
--  UPDATE LOOP — posisi dot player
-- ─────────────────────────────────────────────

local lastUpdateTime = 0

RunService.Heartbeat:Connect(function()
    if not screenGui.Enabled then return end

    local now = os.clock()
    if now - lastUpdateTime < UPDATE_HZ then return end
    lastUpdateTime = now

    local character = LocalPlayer.Character
    if not character then return end
    local hrp = character:FindFirstChild("HumanoidRootPart")
    if not hrp then return end

    local col, row = worldToTileF(hrp.Position)

    -- Update fog of war (reveal di sekitar posisi sekarang)
    revealAround(col, row)

    -- Geser semua tile supaya player di tengah
    updateViewOffset(col, row)
    repositionAllTiles()

    -- Posisi dot player = selalu tengah minimap
    local centerPx = MINIMAP_SIZE / 2
    playerDot.Position = UDim2.new(0, centerPx, 0, centerPx)

    -- Arah player (rotasi kasar berdasarkan LookVector)
    -- FIX: hapus negasi — -look.X dan -look.Z membalik arah 180°
    local look = hrp.CFrame.LookVector
    local angleDeg = math.deg(math.atan2(look.X, look.Z))

    -- Rotasi indicator arah (geser ke atas dari center dot)
    local RAD   = math.rad(angleDeg)
    local DIST  = 7  -- jarak dari pusat dot (pixel)
    local dirPx = centerPx + math.sin(RAD) * DIST
    local dirPy = centerPx + math.cos(RAD) * DIST  -- FIX: + bukan - (maju = bawah di grid)
    playerDir.Position = UDim2.new(0, dirPx, 0, dirPy)
end)

-- ─────────────────────────────────────────────
--  UPDATE DOT MONSTER
--  Payload: { position: Vector3, state: string, monsterIndex: number }
-- ─────────────────────────────────────────────

-- Track posisi tiap monster (index → Vector3)
local monsterPositions: {[number]: Vector3} = {}

RE_MonsterPosition.OnClientEvent:Connect(function(data)
    if not screenGui.Enabled then return end
    if not data or not data.position then return end

    local idx = data.monsterIndex or 1
    if idx < 1 or idx > MAX_MONSTERS then return end

    monsterPositions[idx] = data.position

    -- Update dot monster sesuai posisi relatif terhadap view offset saat ini
    local mCol, mRow = worldToTileF(data.position)
    local px, py = tileToMinimapPx(mCol, mRow)

    local dot = monsterDots[idx]
    dot.Position = UDim2.new(0, px, 0, py)

    -- Warna: merah terang kalau CHASE, merah redup kalau IDLE
    if data.state == "CHASE" or data.state == "CATCH" then
        dot.BackgroundColor3 = Color3.fromRGB(255, 50, 50)
        dot.Size             = UDim2.new(0, 7, 0, 7)  -- sedikit lebih besar saat chase
    else
        dot.BackgroundColor3 = Color3.fromRGB(140, 40, 40)
        dot.Size             = UDim2.new(0, 5, 0, 5)
    end

    -- Hanya tampilkan dot kalau tile monster sudah ter-reveal
    -- (player belum lihat area itu = tidak tahu monster ada di sana)
    local revRow = math.round(mRow)
    local revCol = math.round(mCol)
    local isRevealed = revealed[revRow] and revealed[revRow][revCol]
    dot.Visible = isRevealed == true
end)

-- ─────────────────────────────────────────────
--  TERIMA MAP DARI SERVER
-- ─────────────────────────────────────────────

RE_MapGenerated.OnClientEvent:Connect(function(receivedGrid, receivedHallInfo)
    initMap(receivedGrid, receivedHallInfo)
end)

print("[MinimapUI] Menunggu map dari server...")
