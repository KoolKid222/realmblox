--[[
    Constants.lua
    All game constants and configuration values
]]

local Constants = {}

-- Unit System (1 unit = 1 tile, like RotMG)
-- At max zoom (height 50), visible area is roughly 9 units from center to edge
-- So wizard staff (9 * 0.9 = ~8 units range) reaches 90% to edge
Constants.STUDS_PER_UNIT = 4      -- 1 game unit = 4 studs
Constants.UNITS_VISIBLE = 9       -- Units visible from center to edge at max zoom

-- Helper to convert units to studs
function Constants.UnitsToStuds(units)
    return units * Constants.STUDS_PER_UNIT
end

-- Helper to convert studs to units
function Constants.StudsToUnits(studs)
    return studs / Constants.STUDS_PER_UNIT
end

-- Player Stats
-- NOTE: Actual stat values, growth, and caps are defined per-class in ClassDatabase.lua
-- These are just fallback defaults
Constants.Stats = {
    -- All 8 RotMG stats
    STAT_NAMES = {"HP", "MP", "Attack", "Defense", "Speed", "Dexterity", "Vitality", "Wisdom"},
}

-- Leveling (RotMG XP System)
-- Formula: XP for level N = 50 + (N-2) * 100
-- Total XP to level 20: 18,050
-- XP Caps: 10% regular enemies, 20% bosses
-- Default enemy XP: MaxHP / 10
Constants.Leveling = {
    MAX_LEVEL = 20,
    TOTAL_XP_TO_MAX = 18050,  -- Welcome Back Gift amount in RotMG
}

-- Combat (RotMG Formulas - see Utilities.lua for implementations)
-- ATT: FinalDamage = WeaponDamage * (0.5 + ATT/50)
--      At 0 ATT = 50%, at 50 ATT = 100%, at 75 ATT = 150%
-- DEF: DamageTaken = max(RawDamage - DEF, RawDamage * 0.15)
--      Defense reduces damage but can't go below 15% of raw
-- DEX: APS = 1.5 + 6.5 * (DEX/75)
--      At 0 DEX = 1.5 shots/sec, at 75 DEX = 8 shots/sec
-- SPD: WalkSpeed = 12 + (SPD * 0.2)
--      At 0 SPD = 12 studs/sec, at 50 SPD = 22 studs/sec
Constants.Combat = {
    MIN_DAMAGE_FLOOR = 0.15,        -- Damage can't be reduced below 15% of raw damage
}

-- Hitbox System (RotMG-style - smaller than visuals for "graze" mechanic)
-- All collision checks use 2D distance (X, Z) ignoring Y axis
-- Hitboxes are cylinders extending infinitely on Y axis
Constants.Hitbox = {
    PLAYER_RADIUS = 0.5,            -- Player hitbox radius (studs) - smaller than visual
    PROJECTILE_RADIUS = 0.75,       -- Enemy projectile hitbox radius (studs)
                                    -- Visual size = 1.5, hitbox radius = 0.75 (matches visual)
    ENEMY_HITBOX_SCALE = 0.4,       -- Default: 40% of visual size = 80% of radius
    -- Enemy hitboxes are defined per-enemy in EnemyDatabase.HitboxRadius
    -- Formula: 2D distance < (PlayerRadius + ProjectileRadius) = 0.5 + 0.75 = 1.25 studs
}

-- Projectiles
Constants.Projectile = {
    DEFAULT_SPEED = 16,             -- Studs per second (4 units/sec)
    DEFAULT_LIFETIME = 2.0,         -- Seconds
    DEFAULT_SIZE = Vector3.new(1, 1, 2),
    POOL_SIZE = 200,                -- Pre-allocated projectiles
}

-- Zones
Constants.Zones = {
    BEACH = "Beach",
    LOWLANDS = "Lowlands",
    MIDLANDS = "Midlands",
    GODLANDS = "Godlands",
}

-- Zone difficulty multipliers
Constants.ZoneDifficulty = {
    Beach = {enemyLevel = 0, lootTier = 0},
    Lowlands = {enemyLevel = 3, lootTier = 1},
    Midlands = {enemyLevel = 7, lootTier = 2},
    Godlands = {enemyLevel = 12, lootTier = 3},
}

-- Spawning (in game units)
Constants.Spawning = {
    SPAWN_RADIUS = 15,              -- Spawn enemies within this range of players (units)
    DESPAWN_RADIUS = 40,            -- Remove enemies beyond this range (units)
    AGGRO_RANGE = 8,                -- Enemy aggro range (units)
    CHASE_RANGE = 12,               -- Stop chasing beyond this (units)
}

-- Inventory
Constants.Inventory = {
    BACKPACK_SLOTS = 8,
    MAX_HP_POTIONS = 6,
    MAX_MP_POTIONS = 6,
}

-- Item Rarities
Constants.Rarity = {
    COMMON = {name = "Common", color = Color3.fromRGB(255, 255, 255)},
    UNCOMMON = {name = "Uncommon", color = Color3.fromRGB(0, 255, 0)},
    RARE = {name = "Rare", color = Color3.fromRGB(0, 150, 255)},
    EPIC = {name = "Epic", color = Color3.fromRGB(150, 0, 255)},
    LEGENDARY = {name = "Legendary", color = Color3.fromRGB(255, 165, 0)},
}

-- Regeneration (RotMG Vital Combat System)
-- Out of Combat: Full regen rate
-- In Combat: Reduced regen rate (~25% of normal)
-- Combat Timer: 7 seconds after taking/dealing damage
-- VIT reduces in-combat duration
Constants.Regen = {
    -- HP Regeneration: HP/s = BASE + (VIT * VIT_MULTIPLIER)
    HP_BASE = 1,                    -- Base HP/s at 0 VIT
    HP_VIT_MULTIPLIER = 0.24,       -- Each VIT adds 0.24 HP/s

    -- MP Regeneration: MP/s = BASE + (WIS * WIS_MULTIPLIER)
    MP_BASE = 0.5,                  -- Base MP/s at 0 WIS
    MP_WIS_MULTIPLIER = 0.12,       -- Each WIS adds 0.12 MP/s

    -- Combat State
    IN_COMBAT_MULTIPLIER = 0.25,    -- Regen is 25% when in combat
    COMBAT_DURATION = 7,            -- Seconds of "in combat" after damage
    VIT_COMBAT_REDUCTION = 0.04,    -- Each VIT reduces combat duration by 0.04s
    MIN_COMBAT_DURATION = 1,        -- Minimum in-combat time (even with max VIT)

    -- Update Rate
    TICK_RATE = 0.5,                -- Update regen every 0.5 seconds
}

-- Movement (RotMG SPD formula applied in Utilities.GetWalkSpeed)
-- WalkSpeed = 12 + (SPD * 0.2)
Constants.Movement = {
    BASE_WALK_SPEED = 12,           -- Roblox studs/sec at 0 SPD
    SPD_MULTIPLIER = 0.2,           -- Each SPD point adds 0.2 studs/sec

    -- Movement Validation (anti-cheat)
    VALIDATION_INTERVAL = 0.1,      -- Check every 100ms
    SPEED_TOLERANCE = 1.5,          -- 50% buffer for latency
    TELEPORT_THRESHOLD = 60,        -- Studs - instant flag
    VIOLATION_THRESHOLD = 5,        -- Violations before rubberband
    RUBBERBAND_COOLDOWN = 0.5,      -- Seconds between rubberbands
    SPAWN_GRACE_PERIOD = 2.0,       -- Seconds after spawn before validation
}

-- DataStore
Constants.DataStore = {
    STORE_NAME = "RealmBlox_PlayerData",
    AUTO_SAVE_INTERVAL = 60,        -- Seconds
    DATA_VERSION = 3,               -- Synced with ProfileManager template version
}

-- Nexus (Safe Hub Zone) - Located far from the Realm island
Constants.Nexus = {
    CENTER = Vector3.new(5000, 10, 5000),      -- Nexus center (far from realm)
    SPAWN_OFFSET = Vector3.new(0, 3, 0),       -- Player spawn offset from center
    SAFE_RADIUS = 150,                         -- Entire Nexus is safe
    FLOOR_RADIUS = 120,                        -- Physical floor size

    -- Portal positions (relative offsets from CENTER)
    REALM_PORTAL_OFFSET = Vector3.new(0, 0, -40),    -- North side - to enter realm
    VAULT_PORTAL_OFFSET = Vector3.new(-35, 0, 20),   -- Southwest - personal vault
    PET_YARD_PORTAL_OFFSET = Vector3.new(35, 0, 20), -- Southeast - pet storage

    -- Where players appear when entering the Realm (Beach biome)
    REALM_SPAWN_POS = Vector3.new(350, 10, 350),

    PORTAL_INTERACT_RADIUS = 10,               -- Distance to show "Press E" prompt
}

-- Vault (Personal Storage Room) - Simple grid layout
-- Chests are flat glowing floor squares (golden = unlocked, dark = locked)
Constants.Vault = {
    CENTER = Vector3.new(6000, 10, 5000),      -- Vault room center (separate from Nexus)
    SPAWN_OFFSET = Vector3.new(0, 3, -20),     -- Player spawns near back (portal behind)
    FLOOR_SIZE = Vector3.new(120, 1, 100),     -- Room dimensions (flatter floor)

    -- Checkered floor settings
    TILE_SIZE = 8,                              -- Size of each floor tile
    TILE_COLOR_1 = Color3.fromRGB(65, 65, 75),  -- Dark grey tile
    TILE_COLOR_2 = Color3.fromRGB(85, 85, 95),  -- Light grey tile

    -- Chest grid layout (in front of spawn)
    -- Grid: 7 columns x 4 rows = 28 chests visible
    CHEST_GRID = {
        startOffset = Vector3.new(-36, 0, 0),  -- Start position relative to center
        columns = 7,                            -- Chests per row
        rows = 4,                               -- Number of rows
        spacingX = 12,                          -- Horizontal spacing between chests
        spacingZ = 12,                          -- Vertical spacing between rows
    },

    MAX_VISIBLE_CHESTS = 28,
    MAX_CHESTS = 80,                           -- Total chests possible (additional unlock later)

    -- Special storage positions (relative to center)
    POTION_VAULT_POS = Vector3.new(-50, 0, 20),  -- Left side, in chest area
    GIFT_CHEST_POS = Vector3.new(50, 0, 20),     -- Right side, in chest area

    -- Exit portal back to Nexus (behind spawn point)
    EXIT_PORTAL_POS = Vector3.new(0, 0, -40),    -- Behind where player spawns

    -- Chest interaction (walk-over detection on flat floor squares)
    CHEST_INTERACT_RADIUS = 5,                   -- Radius for walk-over detection
    CHEST_SIZE = Vector3.new(8, 0.3, 8),         -- Flat floor square (X, height, Z)
    SLOTS_PER_CHEST = 8,                         -- Items per chest
}

return Constants
