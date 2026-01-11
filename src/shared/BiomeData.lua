--[[
    BiomeData.lua
    Defines biome thresholds, colors, and properties for RotMG-style island generation

    Biome Bands (based on elevation 0.0 - 1.0):
    - Deep Water (< 0.2): Ocean border, impassable
    - Beach (0.2 - 0.3): Safe spawn zone
    - Lowlands (0.3 - 0.55): Beginner enemies
    - Highlands (0.55 - 0.8): Mid-tier enemies
    - Godlands (> 0.8): Center, highest danger
]]

local BiomeData = {}

--============================================================================
-- BIOME DEFINITIONS
--============================================================================

BiomeData.Biomes = {
    DeepWater = {
        Name = "DeepWater",
        DisplayName = "Deep Water",
        MinElevation = 0,
        MaxElevation = 0.2,
        Color = Color3.fromRGB(20, 50, 80),      -- Dark blue ocean
        Material = Enum.Material.Water,
        Walkable = false,
        SpawnEnemies = false,
        EnemyLevel = 0,
        LootTier = 0,
    },

    Beach = {
        Name = "Beach",
        DisplayName = "Beach",
        MinElevation = 0.2,
        MaxElevation = 0.3,
        Color = Color3.fromRGB(230, 210, 140),   -- Sandy yellow
        Material = Enum.Material.Sand,
        Walkable = true,
        SpawnEnemies = false,                    -- Safe zone
        EnemyLevel = 0,
        LootTier = 0,
        IsSpawnZone = true,                      -- Players spawn here
    },

    Lowlands = {
        Name = "Lowlands",
        DisplayName = "Lowlands",
        MinElevation = 0.3,
        MaxElevation = 0.55,
        Color = Color3.fromRGB(120, 180, 80),    -- Light green grass
        Material = Enum.Material.Grass,
        Walkable = true,
        SpawnEnemies = true,
        EnemyLevel = 1,                          -- Level 1-5 enemies
        LootTier = 1,
        EnemyTypes = {"Pirate", "PirateCaptain", "Snake", "Scorpion"},
    },

    Highlands = {
        Name = "Highlands",
        DisplayName = "Highlands",
        MinElevation = 0.55,
        MaxElevation = 0.8,
        Color = Color3.fromRGB(60, 120, 50),     -- Dark green forest
        Material = Enum.Material.LeafyGrass,
        Walkable = true,
        SpawnEnemies = true,
        EnemyLevel = 5,                          -- Level 5-10 enemies
        LootTier = 2,
        EnemyTypes = {"Elf", "Dwarf", "Hobbit", "Orc"},
    },

    Godlands = {
        Name = "Godlands",
        DisplayName = "Godlands",
        MinElevation = 0.8,
        MaxElevation = 1.0,
        Color = Color3.fromRGB(200, 200, 210),   -- White/grey snow
        Material = Enum.Material.Snow,
        Walkable = true,
        SpawnEnemies = true,
        EnemyLevel = 12,                         -- Level 12-20 enemies (Gods)
        LootTier = 3,
        EnemyTypes = {"MedusaGod", "DjinnGod", "LeviathanGod", "BeholderGod", "FlyingBrainGod", "SlimeGod", "GhostGod", "SpriteGod"},
    },
}

-- Ordered list for elevation lookup (sorted by MinElevation)
BiomeData.BiomeOrder = {"DeepWater", "Beach", "Lowlands", "Highlands", "Godlands"}

--============================================================================
-- HELPER FUNCTIONS
--============================================================================

-- Get biome data from elevation value (0.0 - 1.0)
function BiomeData.GetBiomeFromElevation(elevation)
    -- Clamp elevation
    elevation = math.clamp(elevation, 0, 1)

    -- Find matching biome
    for _, biomeName in ipairs(BiomeData.BiomeOrder) do
        local biome = BiomeData.Biomes[biomeName]
        if elevation >= biome.MinElevation and elevation < biome.MaxElevation then
            return biome
        end
    end

    -- Default to Godlands if exactly 1.0
    return BiomeData.Biomes.Godlands
end

-- Get biome by name
function BiomeData.GetBiome(name)
    return BiomeData.Biomes[name]
end

-- Check if a biome is walkable
function BiomeData.IsWalkable(biomeName)
    local biome = BiomeData.Biomes[biomeName]
    return biome and biome.Walkable or false
end

-- Check if enemies can spawn in a biome
function BiomeData.CanSpawnEnemies(biomeName)
    local biome = BiomeData.Biomes[biomeName]
    return biome and biome.SpawnEnemies or false
end

-- Get enemy types for a biome
function BiomeData.GetEnemyTypes(biomeName)
    local biome = BiomeData.Biomes[biomeName]
    return biome and biome.EnemyTypes or {}
end

-- Get all spawn zone biomes
function BiomeData.GetSpawnZoneBiomes()
    local spawnBiomes = {}
    for name, biome in pairs(BiomeData.Biomes) do
        if biome.IsSpawnZone then
            table.insert(spawnBiomes, biome)
        end
    end
    return spawnBiomes
end

return BiomeData
