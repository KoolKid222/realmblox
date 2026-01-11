--[[
    MapRenderer.lua
    Client-side chunk-based terrain rendering for RotMG-style island

    Features:
    - Chunks load/unload based on player position
    - Deep Water tiles are NOT rendered (optimization)
    - Single water plane covers the ocean
    - Biome colors from BiomeData
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local WorldGen = require(Shared.WorldGen)
local BiomeData = require(Shared.BiomeData)

local player = Players.LocalPlayer

local MapRenderer = {}

--============================================================================
-- CONFIGURATION
--============================================================================

local RENDER_DISTANCE = 400             -- Studs around player to render
local UPDATE_INTERVAL = 0.5             -- Seconds between chunk updates
local TILES_PER_FRAME = 50              -- Max tiles to create per frame (prevents lag spikes)

-- Part pooling (much smaller with greedy meshing - typically ~200-500 parts per chunk instead of 4096)
local POOL_SIZE = 1000                  -- Pre-allocated parts (greedy meshing reduces count by 80-90%)
local partPool = {}                     -- Array of {part = Part, inUse = bool}
local partToIndex = {}                  -- Quick lookup: part -> index in partPool
local partPoolIndex = 1

--============================================================================
-- CONTAINERS
--============================================================================

local terrainContainer = nil
local waterPlane = nil
local loadedChunks = {}                 -- [chunkKey] = {parts = {}, loaded = true}
local chunkLoadQueue = {}               -- Chunks waiting to be loaded

--============================================================================
-- PART POOLING
--============================================================================

local function initializePool()
    for i = 1, POOL_SIZE do
        local part = Instance.new("Part")
        part.Name = "TerrainTile"
        part.Anchored = true
        part.CanCollide = true
        part.CastShadow = false
        part.TopSurface = Enum.SurfaceType.Smooth
        part.BottomSurface = Enum.SurfaceType.Smooth
        part.Size = Vector3.new(WorldGen.TILE_SIZE, 1, WorldGen.TILE_SIZE)
        part.Position = Vector3.new(0, -1000, 0)  -- Hidden
        part.Parent = terrainContainer

        partPool[i] = {part = part, inUse = false}
        partToIndex[part] = i  -- Quick lookup
    end
end

local function getPooledPart()
    -- Find available part in pool (start from last used index for better cache locality)
    local poolSize = #partPool
    for i = 1, poolSize do
        local idx = ((partPoolIndex + i - 2) % poolSize) + 1
        if not partPool[idx].inUse then
            partPool[idx].inUse = true
            partPoolIndex = idx + 1
            return partPool[idx].part
        end
    end

    -- Pool exhausted, create new part
    local part = Instance.new("Part")
    part.Name = "TerrainTile"
    part.Anchored = true
    part.CanCollide = true
    part.CastShadow = false
    part.TopSurface = Enum.SurfaceType.Smooth
    part.BottomSurface = Enum.SurfaceType.Smooth
    part.Size = Vector3.new(WorldGen.TILE_SIZE, 1, WorldGen.TILE_SIZE)
    part.Parent = terrainContainer

    local poolEntry = {part = part, inUse = true}
    table.insert(partPool, poolEntry)
    partToIndex[part] = #partPool  -- Add to lookup

    return part
end

local function returnPooledPart(part)
    -- O(1) lookup instead of O(n) linear search
    local idx = partToIndex[part]
    if idx and partPool[idx] then
        partPool[idx].inUse = false
        part.Position = Vector3.new(0, -1000, 0)  -- Hide
    end
end

--============================================================================
-- WATER PLANE
--============================================================================

local function createWaterPlane()
    if waterPlane then return end

    waterPlane = Instance.new("Part")
    waterPlane.Name = "OceanPlane"
    waterPlane.Anchored = true
    waterPlane.CanCollide = false
    waterPlane.CastShadow = false
    waterPlane.Material = Enum.Material.Water
    waterPlane.Color = Color3.fromRGB(30, 70, 120)
    waterPlane.Transparency = 0.3
    waterPlane.Size = Vector3.new(WorldGen.MAP_RADIUS * 3, 1, WorldGen.MAP_RADIUS * 3)
    waterPlane.Position = Vector3.new(0, -1.5, 0)  -- Just below flat ground (Y=0)
    waterPlane.Parent = terrainContainer
end

--============================================================================
-- INVISIBLE WALLS (Ocean Boundary)
--============================================================================

local function createOceanBoundary()
    local wallHeight = 50
    local wallThickness = 10
    local radius = WorldGen.MAP_RADIUS + 50

    -- Create 4 walls forming a square boundary
    local walls = {
        {pos = Vector3.new(radius, wallHeight/2, 0), size = Vector3.new(wallThickness, wallHeight, radius * 2)},
        {pos = Vector3.new(-radius, wallHeight/2, 0), size = Vector3.new(wallThickness, wallHeight, radius * 2)},
        {pos = Vector3.new(0, wallHeight/2, radius), size = Vector3.new(radius * 2, wallHeight, wallThickness)},
        {pos = Vector3.new(0, wallHeight/2, -radius), size = Vector3.new(radius * 2, wallHeight, wallThickness)},
    }

    for i, wallData in ipairs(walls) do
        local wall = Instance.new("Part")
        wall.Name = "OceanWall_" .. i
        wall.Anchored = true
        wall.CanCollide = true
        wall.Transparency = 1  -- Invisible
        wall.Size = wallData.size
        wall.Position = wallData.pos
        wall.Parent = terrainContainer
    end
end

--============================================================================
-- GREEDY MESHING
-- Combines adjacent tiles of the same biome into larger rectangles
-- Reduces part count by 80-90%
--============================================================================

local function greedyMesh(biomeGrid, chunkSize)
    local visited = {}
    for x = 0, chunkSize - 1 do
        visited[x] = {}
        for z = 0, chunkSize - 1 do
            visited[x][z] = false
        end
    end

    local rectangles = {}

    for startX = 0, chunkSize - 1 do
        for startZ = 0, chunkSize - 1 do
            if not visited[startX][startZ] and biomeGrid[startX][startZ] then
                local biomeName = biomeGrid[startX][startZ].Name

                -- Skip DeepWater
                if biomeName ~= "DeepWater" then
                    -- Find max width (expand right)
                    local width = 1
                    while startX + width < chunkSize
                          and biomeGrid[startX + width][startZ]
                          and biomeGrid[startX + width][startZ].Name == biomeName
                          and not visited[startX + width][startZ] do
                        width = width + 1
                    end

                    -- Find max height (expand down) for the entire width
                    local height = 1
                    local canExpand = true
                    while canExpand and startZ + height < chunkSize do
                        -- Check if entire row matches
                        for dx = 0, width - 1 do
                            local checkX = startX + dx
                            local checkZ = startZ + height
                            if not biomeGrid[checkX][checkZ]
                               or biomeGrid[checkX][checkZ].Name ~= biomeName
                               or visited[checkX][checkZ] then
                                canExpand = false
                                break
                            end
                        end
                        if canExpand then
                            height = height + 1
                        end
                    end

                    -- Mark all cells in this rectangle as visited
                    for dx = 0, width - 1 do
                        for dz = 0, height - 1 do
                            visited[startX + dx][startZ + dz] = true
                        end
                    end

                    -- Store the rectangle
                    table.insert(rectangles, {
                        x = startX,
                        z = startZ,
                        width = width,
                        height = height,
                        biome = biomeGrid[startX][startZ],
                    })
                else
                    -- Mark DeepWater as visited but don't create rectangle
                    visited[startX][startZ] = true
                end
            end
        end
    end

    return rectangles
end

--============================================================================
-- CHUNK LOADING
--============================================================================

local function loadChunk(chunkX, chunkZ)
    local chunkKey = WorldGen.GetChunkKey(chunkX, chunkZ)

    -- Already loaded?
    if loadedChunks[chunkKey] then return end

    -- Mark as loading
    loadedChunks[chunkKey] = {parts = {}, loaded = false}

    -- Get world position of chunk corner
    local worldX, worldZ = WorldGen.GetChunkWorldPos(chunkX, chunkZ)

    -- Build biome grid for this chunk
    local biomeGrid = {}
    for tx = 0, WorldGen.CHUNK_SIZE - 1 do
        biomeGrid[tx] = {}
        for tz = 0, WorldGen.CHUNK_SIZE - 1 do
            local x = worldX + tx * WorldGen.TILE_SIZE
            local z = worldZ + tz * WorldGen.TILE_SIZE
            biomeGrid[tx][tz] = WorldGen.GetBiome(x, z)
        end
    end

    -- Apply greedy meshing to get merged rectangles
    local rectangles = greedyMesh(biomeGrid, WorldGen.CHUNK_SIZE)

    -- Convert rectangles to world-space merged tiles
    local mergedTiles = {}
    for _, rect in ipairs(rectangles) do
        local tileX = worldX + rect.x * WorldGen.TILE_SIZE
        local tileZ = worldZ + rect.z * WorldGen.TILE_SIZE
        local tileWidth = rect.width * WorldGen.TILE_SIZE
        local tileHeight = rect.height * WorldGen.TILE_SIZE

        -- Center position of the merged tile
        local centerX = tileX + tileWidth / 2 - WorldGen.TILE_SIZE / 2
        local centerZ = tileZ + tileHeight / 2 - WorldGen.TILE_SIZE / 2

        table.insert(mergedTiles, {
            x = centerX,
            y = 0,  -- Flat terrain
            z = centerZ,
            width = tileWidth,
            height = tileHeight,
            biome = rect.biome,
        })
    end

    -- Add to load queue
    table.insert(chunkLoadQueue, {
        key = chunkKey,
        tiles = mergedTiles,
        index = 1,
    })
end

local function unloadChunk(chunkKey)
    local chunk = loadedChunks[chunkKey]
    if not chunk then return end

    -- Return all parts to pool
    for _, part in ipairs(chunk.parts) do
        returnPooledPart(part)
    end

    loadedChunks[chunkKey] = nil
end

-- Process chunk load queue (spread across frames)
local MERGED_TILES_PER_FRAME = 20  -- Fewer tiles needed since they're larger

local function processChunkQueue()
    if #chunkLoadQueue == 0 then return end

    local tilesThisFrame = 0
    local toRemove = {}

    for i, chunkData in ipairs(chunkLoadQueue) do
        local chunk = loadedChunks[chunkData.key]
        if not chunk then
            -- Chunk was unloaded, skip
            table.insert(toRemove, i)
            continue
        end

        -- Process merged tiles
        while chunkData.index <= #chunkData.tiles and tilesThisFrame < MERGED_TILES_PER_FRAME do
            local tile = chunkData.tiles[chunkData.index]

            -- Create merged tile part
            local part = getPooledPart()
            part.Position = Vector3.new(tile.x, tile.y, tile.z)
            part.Color = tile.biome.Color
            part.Material = tile.biome.Material
            part.CanCollide = tile.biome.Walkable

            -- Merged tile size (width x 1 x height)
            part.Size = Vector3.new(tile.width, 1, tile.height)

            table.insert(chunk.parts, part)
            chunkData.index = chunkData.index + 1
            tilesThisFrame = tilesThisFrame + 1
        end

        -- Check if chunk is fully loaded
        if chunkData.index > #chunkData.tiles then
            chunk.loaded = true
            table.insert(toRemove, i)
        end

        if tilesThisFrame >= MERGED_TILES_PER_FRAME then
            break
        end
    end

    -- Remove completed chunks from queue (in reverse order)
    table.sort(toRemove, function(a, b) return a > b end)
    for _, idx in ipairs(toRemove) do
        table.remove(chunkLoadQueue, idx)
    end
end

--============================================================================
-- CHUNK MANAGEMENT
--============================================================================

local function updateChunks()
    local character = player.Character
    if not character then return end

    local rootPart = character:FindFirstChild("HumanoidRootPart")
    if not rootPart then return end

    local playerPos = rootPart.Position

    -- Get chunks that should be loaded
    local neededChunks = WorldGen.GetChunksInRadius(playerPos.X, playerPos.Z, RENDER_DISTANCE)
    local neededKeys = {}
    for _, chunk in ipairs(neededChunks) do
        neededKeys[chunk.key] = true
        if not loadedChunks[chunk.key] then
            loadChunk(chunk.x, chunk.z)
        end
    end

    -- Unload chunks that are too far
    for chunkKey, _ in pairs(loadedChunks) do
        if not neededKeys[chunkKey] then
            unloadChunk(chunkKey)
        end
    end
end

--============================================================================
-- DEBUG / STATS
--============================================================================

function MapRenderer.GetStats()
    local loadedCount = 0
    local partCount = 0
    local queueCount = #chunkLoadQueue

    for _, chunk in pairs(loadedChunks) do
        loadedCount = loadedCount + 1
        partCount = partCount + #chunk.parts
    end

    return {
        LoadedChunks = loadedCount,
        TotalParts = partCount,
        QueuedChunks = queueCount,
        PoolSize = #partPool,
    }
end

--============================================================================
-- INITIALIZATION
--============================================================================

function MapRenderer.Init()
    print("[MapRenderer] Initializing...")

    -- Create terrain container
    terrainContainer = workspace:FindFirstChild("Terrain")
    if not terrainContainer then
        terrainContainer = Instance.new("Folder")
        terrainContainer.Name = "Terrain"
        terrainContainer.Parent = workspace
    end

    -- Clear any existing terrain
    for _, child in ipairs(terrainContainer:GetChildren()) do
        if child:IsA("BasePart") then
            child:Destroy()
        end
    end

    -- Initialize part pool
    initializePool()

    -- Create water plane
    createWaterPlane()

    -- Create ocean boundary walls
    createOceanBoundary()

    -- Start chunk update loop
    local lastUpdate = 0
    RunService.Heartbeat:Connect(function()
        -- Process chunk load queue every frame
        processChunkQueue()

        -- Update chunks periodically
        local now = tick()
        if now - lastUpdate >= UPDATE_INTERVAL then
            lastUpdate = now
            updateChunks()
        end
    end)

    -- Initial load
    task.defer(function()
        updateChunks()
    end)

    print("[MapRenderer] Initialized with Greedy Meshing")
    print(string.format("  Map Radius: %d studs", WorldGen.MAP_RADIUS))
    print(string.format("  Tile Size: %d studs", WorldGen.TILE_SIZE))
    print(string.format("  Chunk Size: %dx%d tiles (%d studs)",
        WorldGen.CHUNK_SIZE, WorldGen.CHUNK_SIZE, WorldGen.CHUNK_STUDS))
    print(string.format("  Render Distance: %d studs", RENDER_DISTANCE))
    print("  Greedy Meshing: ENABLED (80-90% part reduction)")
end

return MapRenderer
