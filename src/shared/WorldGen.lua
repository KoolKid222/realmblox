--[[
    WorldGen.lua
    RotMG-style finite island generation using Perlin Noise + Radial Mask

    Core Formula:
    Elevation = PerlinNoise(x, z) - (DistanceFromCenter / MapRadius)

    This creates a natural island shape where:
    - Center = High elevation (Godlands)
    - Edges = Low elevation (Deep Water)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BiomeData = require(Shared.BiomeData)

local WorldGen = {}

--============================================================================
-- WORLD CONSTANTS
--============================================================================

WorldGen.MAP_RADIUS = 2000              -- Island radius in studs
WorldGen.MAP_CENTER = Vector3.new(0, 0, 0)  -- World center

-- Perlin noise settings
WorldGen.NOISE_SCALE = 0.003            -- Lower = larger features
WorldGen.NOISE_OCTAVES = 4              -- More octaves = more detail
WorldGen.NOISE_PERSISTENCE = 0.5        -- How much each octave contributes
WorldGen.NOISE_SEED = 12345             -- Random seed for consistent generation

-- Terrain settings
WorldGen.TILE_SIZE = 4                  -- Size of each terrain tile (studs)
WorldGen.WATER_LEVEL = -2               -- Y position of water plane (below baseplate)

-- Chunk settings (for MapRenderer)
WorldGen.CHUNK_SIZE = 64                -- Tiles per chunk side (64x64 = 4096 tiles)
WorldGen.CHUNK_STUDS = WorldGen.CHUNK_SIZE * WorldGen.TILE_SIZE  -- 256 studs per chunk

--============================================================================
-- NOISE GENERATION
--============================================================================

-- Multi-octave Perlin noise for more natural terrain
local function fractalNoise(x, z, octaves, persistence, scale, seed)
    local total = 0
    local frequency = scale
    local amplitude = 1
    local maxValue = 0

    for i = 1, octaves do
        -- Use math.noise (Roblox's Perlin noise implementation)
        local noiseValue = math.noise(x * frequency + seed, z * frequency + seed, seed * 0.5)
        total = total + noiseValue * amplitude

        maxValue = maxValue + amplitude
        amplitude = amplitude * persistence
        frequency = frequency * 2
    end

    -- Normalize to 0-1 range
    return (total / maxValue + 1) / 2
end

--============================================================================
-- ELEVATION CALCULATION
--============================================================================

-- Calculate raw elevation at world position (returns 0.0 - 1.0)
function WorldGen.GetElevation(x, z)
    -- Calculate distance from center
    local dx = x - WorldGen.MAP_CENTER.X
    local dz = z - WorldGen.MAP_CENTER.Z
    local distanceFromCenter = math.sqrt(dx * dx + dz * dz)

    -- Radial falloff (0 at center, 1 at edge)
    local radialFalloff = distanceFromCenter / WorldGen.MAP_RADIUS

    -- Get Perlin noise value (0-1)
    local noiseValue = fractalNoise(
        x, z,
        WorldGen.NOISE_OCTAVES,
        WorldGen.NOISE_PERSISTENCE,
        WorldGen.NOISE_SCALE,
        WorldGen.NOISE_SEED
    )

    -- Apply radial mask: noise - falloff
    -- This makes center high (Godlands) and edges low (Ocean)
    local elevation = noiseValue - radialFalloff

    -- Add slight noise variation to the falloff for more organic coastlines
    local coastNoise = math.noise(x * 0.01, z * 0.01, WorldGen.NOISE_SEED * 2) * 0.1
    elevation = elevation + coastNoise

    -- Clamp to valid range
    return math.clamp(elevation, 0, 1)
end

-- Get terrain height (Y position) at world position
-- RotMG-style: COMPLETELY FLAT - all walkable tiles at Y=0
function WorldGen.GetTerrainHeight(x, z)
    local biome = WorldGen.GetBiome(x, z)

    -- Deep water is slightly below to create visual distinction
    if biome.Name == "DeepWater" then
        return -1
    end

    -- ALL walkable terrain is flat at Y=0
    return 0
end

--============================================================================
-- BIOME LOOKUP
--============================================================================

-- Get biome at world position
function WorldGen.GetBiome(x, z)
    local elevation = WorldGen.GetElevation(x, z)
    return BiomeData.GetBiomeFromElevation(elevation)
end

-- Get biome name at world position
function WorldGen.GetBiomeName(x, z)
    local biome = WorldGen.GetBiome(x, z)
    return biome and biome.Name or "DeepWater"
end

-- Check if position is walkable
function WorldGen.IsWalkable(x, z)
    local biome = WorldGen.GetBiome(x, z)
    return biome and biome.Walkable or false
end

-- Check if position is within map bounds
function WorldGen.IsInBounds(x, z)
    local dx = x - WorldGen.MAP_CENTER.X
    local dz = z - WorldGen.MAP_CENTER.Z
    local distance = math.sqrt(dx * dx + dz * dz)
    return distance <= WorldGen.MAP_RADIUS * 1.1  -- Slight buffer
end

--============================================================================
-- SPAWN POINT GENERATION
--============================================================================

-- Find a valid spawn point in the Beach biome
function WorldGen.GetSpawnPoint()
    local maxAttempts = 1000
    local attempts = 0

    -- Search for a Beach tile
    -- With formula: elevation = noise - (dist/radius), Beach (0.2-0.3) is at ~20-35% radius
    -- noise averages ~0.5, so for elevation 0.25: 0.5 - dist/2000 = 0.25 → dist = 500
    while attempts < maxAttempts do
        -- Random angle and distance from center
        local angle = math.random() * math.pi * 2
        -- Beach is at ~20-35% of map radius (where elevation ~0.2-0.3)
        local minDist = WorldGen.MAP_RADIUS * 0.20
        local maxDist = WorldGen.MAP_RADIUS * 0.40
        local distance = minDist + math.random() * (maxDist - minDist)

        local x = WorldGen.MAP_CENTER.X + math.cos(angle) * distance
        local z = WorldGen.MAP_CENTER.Z + math.sin(angle) * distance

        -- Snap to tile grid
        x = math.floor(x / WorldGen.TILE_SIZE) * WorldGen.TILE_SIZE
        z = math.floor(z / WorldGen.TILE_SIZE) * WorldGen.TILE_SIZE

        -- Check if this is Beach (or any walkable biome for now)
        local biome = WorldGen.GetBiome(x, z)
        local elevation = WorldGen.GetElevation(x, z)

        -- Debug: Print what we're finding
        if attempts < 5 then
            print(string.format("[WorldGen] Search attempt %d: x=%.0f, z=%.0f, dist=%.0f, elevation=%.3f, biome=%s",
                attempts, x, z, distance, elevation, biome and biome.Name or "nil"))
        end

        if biome and biome.Walkable then
            local y = 3  -- Spawn above flat ground (Y=0)
            print(string.format("[WorldGen] SPAWN: x=%.0f, z=%.0f, y=%.0f, biome=%s, elevation=%.3f",
                x, z, y, biome.Name, elevation))
            return Vector3.new(x, y, z)
        end

        attempts = attempts + 1
    end

    -- Fallback: Search in a grid pattern
    local searchRadius = WorldGen.MAP_RADIUS * 0.8
    local step = WorldGen.TILE_SIZE * 10

    for x = -searchRadius, searchRadius, step do
        for z = -searchRadius, searchRadius, step do
            local biome = WorldGen.GetBiome(x, z)
            if biome and biome.Name == "Beach" then
                local y = WorldGen.GetTerrainHeight(x, z) + 3
                return Vector3.new(x, y, z)
            end
        end
    end

    -- Ultimate fallback: center of map (should never happen)
    warn("[WorldGen] Could not find walkable spawn point, using center")
    return Vector3.new(0, 3, 0)  -- Flat ground at Y=0, spawn at Y=3
end

-- Get multiple spawn points (for variety)
function WorldGen.GetSpawnPoints(count)
    local points = {}
    local maxAttempts = count * 10
    local attempts = 0

    while #points < count and attempts < maxAttempts do
        local point = WorldGen.GetSpawnPoint()

        -- Check it's not too close to existing points
        local valid = true
        for _, existing in ipairs(points) do
            if (point - existing).Magnitude < 50 then
                valid = false
                break
            end
        end

        if valid then
            table.insert(points, point)
        end

        attempts = attempts + 1
    end

    return points
end

--============================================================================
-- CHUNK HELPERS
--============================================================================

-- Get chunk coordinates from world position
function WorldGen.GetChunkCoords(x, z)
    local chunkX = math.floor(x / WorldGen.CHUNK_STUDS)
    local chunkZ = math.floor(z / WorldGen.CHUNK_STUDS)
    return chunkX, chunkZ
end

-- Get world position from chunk coordinates (top-left corner)
function WorldGen.GetChunkWorldPos(chunkX, chunkZ)
    return chunkX * WorldGen.CHUNK_STUDS, chunkZ * WorldGen.CHUNK_STUDS
end

-- Get chunk key string for storage
function WorldGen.GetChunkKey(chunkX, chunkZ)
    return chunkX .. "," .. chunkZ
end

-- Get all chunk coordinates needed for a given render distance
function WorldGen.GetChunksInRadius(centerX, centerZ, renderDistance)
    local centerChunkX, centerChunkZ = WorldGen.GetChunkCoords(centerX, centerZ)
    local chunkRadius = math.ceil(renderDistance / WorldGen.CHUNK_STUDS)

    local chunks = {}
    for cx = centerChunkX - chunkRadius, centerChunkX + chunkRadius do
        for cz = centerChunkZ - chunkRadius, centerChunkZ + chunkRadius do
            table.insert(chunks, {x = cx, z = cz, key = WorldGen.GetChunkKey(cx, cz)})
        end
    end

    return chunks
end

--============================================================================
-- ENEMY SPAWN HELPERS
--============================================================================

-- Get valid enemy spawn position near a player
function WorldGen.GetEnemySpawnPosition(playerX, playerZ, minDist, maxDist)
    local maxAttempts = 20

    for _ = 1, maxAttempts do
        local angle = math.random() * math.pi * 2
        local distance = minDist + math.random() * (maxDist - minDist)

        local x = playerX + math.cos(angle) * distance
        local z = playerZ + math.sin(angle) * distance

        -- Check if valid spawn location
        local biome = WorldGen.GetBiome(x, z)
        if biome and biome.SpawnEnemies then
            local y = WorldGen.GetTerrainHeight(x, z) + 2
            return Vector3.new(x, y, z), biome
        end
    end

    return nil, nil
end

-- Get biome-appropriate enemies for a position
function WorldGen.GetEnemiesForPosition(x, z)
    local biome = WorldGen.GetBiome(x, z)
    if biome and biome.EnemyTypes then
        return biome.EnemyTypes, biome.EnemyLevel
    end
    return {}, 0
end

return WorldGen
