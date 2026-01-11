--[[
    BiomeCache.lua
    Pre-computes and caches all biome colors for the entire map.

    Called ONCE at game startup to eliminate runtime noise calculations.
    Minimap can then do instant O(1) lookups instead of expensive Perlin noise.

    Performance:
    - Cache size: 1000x1000 = 1,000,000 cells
    - Memory: ~1MB (1 byte per cell for biome index)
    - Generation: ~2-3 seconds at startup (with yielding)
    - Runtime lookup: O(1) - two array accesses
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BiomeCache = {}

--============================================================================
-- CONFIGURATION
--============================================================================

local MAP_RADIUS = 2000                 -- From WorldGen.MAP_RADIUS
local CACHE_RESOLUTION = 4              -- Studs per cache cell (matches TILE_SIZE)

-- Calculate cache dimensions
-- Map spans from -MAP_RADIUS to +MAP_RADIUS = 4000 studs
-- At CACHE_RESOLUTION studs per cell = 1000 x 1000 cache
local CACHE_SIZE = math.floor(MAP_RADIUS * 2 / CACHE_RESOLUTION)  -- 1000

-- The cache: 2D array of biome indices (1-5)
local biomeCache = {}  -- biomeCache[x][z] = biomeIndex

-- Flag to track if cache is ready
local cacheReady = false

--============================================================================
-- BIOME COLOR LOOKUP (Pre-computed for instant access)
--============================================================================

-- Biome index mapping for compact storage
local BIOME_INDICES = {
    DeepWater = 1,
    Beach = 2,
    Lowlands = 3,
    Highlands = 4,
    Godlands = 5,
}

-- Pre-computed biome colors (indexed by biome index)
-- These match BiomeData.lua colors exactly
local BIOME_COLORS = {
    [1] = Color3.fromRGB(20, 50, 80),     -- DeepWater: Dark blue ocean
    [2] = Color3.fromRGB(230, 210, 140),  -- Beach: Sandy yellow
    [3] = Color3.fromRGB(120, 180, 80),   -- Lowlands: Light green grass
    [4] = Color3.fromRGB(60, 120, 50),    -- Highlands: Dark green forest
    [5] = Color3.fromRGB(200, 200, 210),  -- Godlands: White/grey snow
}

-- Default color for out-of-bounds or errors
local DEFAULT_COLOR = BIOME_COLORS[1]

--============================================================================
-- COORDINATE CONVERSION
--============================================================================

-- Convert world position to cache index
function BiomeCache.WorldToCache(worldX, worldZ)
    local cacheX = math.floor((worldX + MAP_RADIUS) / CACHE_RESOLUTION)
    local cacheZ = math.floor((worldZ + MAP_RADIUS) / CACHE_RESOLUTION)
    return math.clamp(cacheX, 0, CACHE_SIZE - 1), math.clamp(cacheZ, 0, CACHE_SIZE - 1)
end

--============================================================================
-- CACHE LOOKUP (O(1) - use this for minimap)
--============================================================================

-- Get cached biome color at world position
-- Returns Color3 instantly (no noise calculations)
function BiomeCache.GetBiomeColor(worldX, worldZ)
    if not cacheReady then
        return DEFAULT_COLOR
    end

    local cacheX, cacheZ = BiomeCache.WorldToCache(worldX, worldZ)
    local row = biomeCache[cacheX]
    if not row then
        return DEFAULT_COLOR
    end

    local biomeIndex = row[cacheZ]
    return BIOME_COLORS[biomeIndex] or DEFAULT_COLOR
end

-- Get cached biome index at world position (1-5)
function BiomeCache.GetBiomeIndex(worldX, worldZ)
    if not cacheReady then
        return 1
    end

    local cacheX, cacheZ = BiomeCache.WorldToCache(worldX, worldZ)
    local row = biomeCache[cacheX]
    if not row then
        return 1
    end

    return row[cacheZ] or 1
end

-- Check if cache is ready
function BiomeCache.IsReady()
    return cacheReady
end

--============================================================================
-- CACHE GENERATION (Call once at startup)
--============================================================================

-- Generate the entire biome cache
-- This is called ONCE at game startup
-- Takes ~2-3 seconds but eliminates all runtime noise calculations
function BiomeCache.Generate(WorldGen)
    if cacheReady then
        print("[BiomeCache] Cache already generated, skipping")
        return
    end

    print("[BiomeCache] Generating biome cache...")
    local startTime = tick()

    local cellsGenerated = 0
    local totalCells = CACHE_SIZE * CACHE_SIZE

    for x = 0, CACHE_SIZE - 1 do
        biomeCache[x] = {}

        for z = 0, CACHE_SIZE - 1 do
            -- Convert cache coords to world coords
            local worldX = (x * CACHE_RESOLUTION) - MAP_RADIUS
            local worldZ = (z * CACHE_RESOLUTION) - MAP_RADIUS

            -- Get biome using WorldGen (this is the expensive part)
            local biome = WorldGen.GetBiome(worldX, worldZ)

            -- Store only the biome index (1 byte instead of full object)
            biomeCache[x][z] = BIOME_INDICES[biome.Name] or 1

            cellsGenerated = cellsGenerated + 1
        end

        -- Yield every 50 rows to prevent timeout and allow other code to run
        if x % 50 == 0 then
            task.wait()
            -- Progress update every 200 rows
            if x % 200 == 0 and x > 0 then
                local progress = math.floor((x / CACHE_SIZE) * 100)
                print(string.format("[BiomeCache] Progress: %d%% (%d/%d rows)",
                    progress, x, CACHE_SIZE))
            end
        end
    end

    cacheReady = true

    local elapsed = tick() - startTime
    print(string.format("[BiomeCache] Generated %dx%d cache (%d cells) in %.2f seconds",
        CACHE_SIZE, CACHE_SIZE, totalCells, elapsed))

    return true
end

--============================================================================
-- UTILITY FUNCTIONS
--============================================================================

-- Get cache statistics
function BiomeCache.GetStats()
    return {
        CacheSize = CACHE_SIZE,
        Resolution = CACHE_RESOLUTION,
        MapRadius = MAP_RADIUS,
        TotalCells = CACHE_SIZE * CACHE_SIZE,
        Ready = cacheReady,
    }
end

-- Get biome name from index
function BiomeCache.GetBiomeName(index)
    local names = {"DeepWater", "Beach", "Lowlands", "Highlands", "Godlands"}
    return names[index] or "Unknown"
end

return BiomeCache
