--[[
    EnemyDatabase.lua
    Enemy definitions with easy-to-configure behavior system

    ============================================================================
    ENEMY CREATION GUIDE
    ============================================================================

    To create a new enemy, copy this template and adjust values:

    MyEnemy = {
        -- IDENTITY
        Name = "My Enemy",
        Zone = "Beach",                 -- Beach, Midlands, or Godlands
        Type = "Enemy",                 -- "Enemy" (regular) or "Boss"

        -- STATS
        MaxHP = 100,
        Defense = 5,
        XPReward = 20,

        -- MOVEMENT
        Movement = {
            Speed = 12,                 -- Base movement speed (studs/sec)
            ChaseSpeed = 14,            -- Speed when actively chasing (nil = use Speed)
            Behavior = "Chase",         -- "Chase", "Orbit", or "Wander"
            OrbitRadius = 20,           -- For Orbit behavior: distance to maintain
            StopRange = 3,              -- Stop moving when this close to player
            AggroRange = 30,            -- Start chasing when player is within this range
            LeashRange = 50,            -- Stop chasing if player goes beyond this
        },

        -- CHARGE ATTACK (optional - set to nil or omit to disable)
        Charge = {
            Enabled = true,
            Speed = 40,                 -- Charge speed (very fast burst)
            Duration = 0.5,             -- How long the charge lasts (seconds)
            Cooldown = 5,               -- Time between charges (seconds)
            WarningTime = 0.3,          -- Telegraph time before charge (seconds)
            Range = 25,                 -- Only charge if player within this range
        },

        -- ATTACKS
        Attack = {
            Pattern = "SingleShot",     -- SingleShot, Burst, Ring, Shotgun, Spiral
            Damage = 20,
            Cooldown = 1.5,
            Range = 25,                 -- Attack when player is within this range
            ProjectileSpeed = 45,
            ProjectileColor = Color3.fromRGB(255, 0, 0),

            -- For Burst pattern:
            BurstCount = 3,
            BurstDelay = 0.2,

            -- For Shotgun pattern:
            ShotgunSpread = 30,
            ProjectileCount = 3,

            -- For Ring/Spiral pattern:
            ProjectileCount = 8,
        },

        -- LOOT
        LootTable = "Beach_Common",

        -- VISUALS
        Size = Vector3.new(4, 5, 2),
        Color = Color3.fromRGB(255, 100, 100),
    },

    ============================================================================
]]

local EnemyDatabase = {}

--============================================================================
-- BEHAVIOR TYPES
--============================================================================
EnemyDatabase.Behaviors = {
    Chase = "Chase",        -- Run at player
    Orbit = "Orbit",        -- Circle around player at distance
    Wander = "Wander",      -- Random movement (idle only)
}

--============================================================================
-- ATTACK PATTERNS
--============================================================================
EnemyDatabase.AttackPatterns = {
    SingleShot = "SingleShot",
    Burst = "Burst",
    Ring = "Ring",
    Shotgun = "Shotgun",
    Spiral = "Spiral",
}

--============================================================================
-- HELPER: Create enemy with defaults
--============================================================================
local function CreateEnemy(config)
    -- Apply defaults for missing values
    local size = config.Size or Vector3.new(4, 5, 2)

    local enemy = {
        Name = config.Name or "Unknown Enemy",
        Zone = config.Zone or "Beach",
        Type = config.Type or "Enemy",  -- "Enemy" or "Boss"

        MaxHP = config.MaxHP or 100,
        Defense = config.Defense or 0,
        XPReward = config.XPReward or 10,

        LootTable = config.LootTable or "Beach_Common",
        Size = size,
        Color = config.Color or Color3.fromRGB(255, 100, 100),

        -- Hitbox radius (RotMG-style: smaller than visual for "graze" mechanic)
        -- Default: 80% of visual radius (40% of diameter)
        -- 2D cylinder collision ignoring Y axis
        HitboxRadius = config.HitboxRadius or (math.max(size.X, size.Z) * 0.4),
    }

    -- Movement defaults
    local mv = config.Movement or {}
    enemy.Speed = mv.Speed or 12
    enemy.ChaseSpeed = mv.ChaseSpeed or enemy.Speed
    enemy.Behavior = mv.Behavior or "Chase"
    enemy.OrbitRadius = mv.OrbitRadius or 20
    enemy.StopRange = mv.StopRange or 3
    enemy.AggroRange = mv.AggroRange or 30
    enemy.ChaseRange = mv.LeashRange or mv.ChaseRange or 50  -- LeashRange is more descriptive

    -- Charge behavior
    if config.Charge and config.Charge.Enabled then
        enemy.CanCharge = true
        enemy.ChargeSpeed = config.Charge.Speed or 40
        enemy.ChargeDuration = config.Charge.Duration or 0.5
        enemy.ChargeCooldown = config.Charge.Cooldown or 5
        enemy.ChargeWarning = config.Charge.WarningTime or 0.3
        enemy.ChargeRange = config.Charge.Range or 25
    else
        enemy.CanCharge = false
    end

    -- Attack defaults
    local atk = config.Attack or {}
    enemy.AttackPattern = atk.Pattern or "SingleShot"
    enemy.AttackDamage = atk.Damage or 15
    enemy.AttackCooldown = atk.Cooldown or 1.5
    enemy.AttackRange = atk.Range or (enemy.AggroRange * 0.8)
    enemy.ProjectileSpeed = atk.ProjectileSpeed or 45
    enemy.ProjectileColor = atk.ProjectileColor or Color3.fromRGB(255, 100, 100)

    -- Pattern-specific
    enemy.BurstCount = atk.BurstCount or 3
    enemy.BurstDelay = atk.BurstDelay or 0.2
    enemy.ShotgunSpread = atk.ShotgunSpread or 30
    enemy.ProjectileCount = atk.ProjectileCount or 8

    -- Boss scaling
    if enemy.Type == "Boss" then
        enemy.IsBoss = true
        -- Bosses are larger and more threatening
        if not config.Size then
            enemy.Size = enemy.Size * 1.5
            -- Recalculate hitbox for scaled boss size (if not explicitly set)
            if not config.HitboxRadius then
                enemy.HitboxRadius = math.max(enemy.Size.X, enemy.Size.Z) * 0.4
            end
        end
    else
        enemy.IsBoss = false
    end

    -- God flag (Godlands enemies can drop stat potions)
    if config.IsGod ~= nil then
        enemy.IsGod = config.IsGod
    else
        -- Auto-set IsGod for Godlands zone enemies
        enemy.IsGod = (enemy.Zone == "Godlands")
    end

    -- Soulbound damage threshold (% of max HP needed to qualify for soulbound loot)
    -- Lower threshold = easier to qualify
    if config.SoulboundThreshold then
        enemy.SoulboundThreshold = config.SoulboundThreshold
    elseif enemy.IsBoss then
        enemy.SoulboundThreshold = 0.10  -- 10% for bosses (easier due to high HP)
    elseif enemy.IsGod then
        enemy.SoulboundThreshold = 0.18  -- 18% for gods (RotMG standard)
    else
        enemy.SoulboundThreshold = 0.15  -- 15% for regular enemies
    end

    return enemy
end

--============================================================================
-- ENEMY DEFINITIONS
--============================================================================
EnemyDatabase.Enemies = {

    --========================================================================
    -- TEST/DEBUG ENEMIES
    --========================================================================

    Dummy = CreateEnemy({
        Name = "Training Dummy",
        Zone = "Beach",
        Type = "Enemy",

        MaxHP = 100000,          -- Very high HP for extended testing
        Defense = 0,             -- No defense so damage numbers are clear
        XPReward = 0,            -- No XP reward

        Movement = {
            Speed = 0,           -- Doesn't move
            Behavior = "Wander",
            AggroRange = 0,      -- Never aggros
            LeashRange = 0,
        },

        Attack = {
            Pattern = "SingleShot",
            Damage = 0,          -- Doesn't attack
            Cooldown = 999,      -- Never attacks
            Range = 0,
        },

        LootTable = nil,         -- No loot
        Size = Vector3.new(6, 8, 6),
        Color = Color3.fromRGB(150, 150, 150),  -- Gray dummy
    }),

    --========================================================================
    -- BEACH ENEMIES (Easy - Chase behavior, low damage)
    --========================================================================

    Pirate = CreateEnemy({
        Name = "Pirate",
        Zone = "Beach",
        Type = "Enemy",

        MaxHP = 50,
        Defense = 0,
        XPReward = 10,

        Movement = {
            Speed = 12,
            ChaseSpeed = 14,            -- Slightly faster when chasing
            Behavior = "Chase",
            StopRange = 4,
            AggroRange = 25,
            LeashRange = 40,
        },

        Attack = {
            Pattern = "SingleShot",
            Damage = 15,
            Cooldown = 1.5,
            ProjectileSpeed = 40,
            ProjectileColor = Color3.fromRGB(139, 69, 19),
        },

        LootTable = "Beach_Common",
        Size = Vector3.new(4, 5, 2),
        Color = Color3.fromRGB(139, 90, 43),
    }),

    PirateCaptain = CreateEnemy({
        Name = "Pirate Captain",
        Zone = "Beach",
        Type = "Enemy",

        MaxHP = 150,
        Defense = 5,
        XPReward = 40,

        Movement = {
            Speed = 10,
            ChaseSpeed = 12,
            Behavior = "Chase",
            StopRange = 5,
            AggroRange = 30,
            LeashRange = 50,
        },

        -- Captain charges at players!
        Charge = {
            Enabled = true,
            Speed = 35,
            Duration = 0.6,
            Cooldown = 6,
            WarningTime = 0.4,
            Range = 20,
        },

        Attack = {
            Pattern = "Burst",
            Damage = 20,
            Cooldown = 2.0,
            BurstCount = 3,
            BurstDelay = 0.2,
            ProjectileSpeed = 45,
            ProjectileColor = Color3.fromRGB(139, 69, 19),
        },

        LootTable = "Beach_Rare",
        Size = Vector3.new(5, 6, 2),
        Color = Color3.fromRGB(100, 60, 30),
    }),

    Crab = CreateEnemy({
        Name = "Crab",
        Zone = "Beach",
        Type = "Enemy",

        MaxHP = 30,
        Defense = 5,
        XPReward = 8,

        Movement = {
            Speed = 14,
            ChaseSpeed = 18,            -- Fast little crab
            Behavior = "Chase",
            StopRange = 2,
            AggroRange = 15,
            LeashRange = 25,
        },

        Attack = {
            Pattern = "SingleShot",
            Damage = 10,
            Cooldown = 1.0,
            ProjectileSpeed = 50,
            ProjectileColor = Color3.fromRGB(255, 100, 100),
        },

        LootTable = "Beach_Common",
        Size = Vector3.new(3, 2, 4),
        Color = Color3.fromRGB(255, 100, 80),
    }),

    Snake = CreateEnemy({
        Name = "Snake",
        Zone = "Beach",
        Type = "Enemy",

        MaxHP = 25,
        Defense = 0,
        XPReward = 6,

        Movement = {
            Speed = 16,
            ChaseSpeed = 20,            -- Very fast when chasing
            Behavior = "Chase",
            StopRange = 2,
            AggroRange = 20,
            LeashRange = 35,
        },

        -- Snakes do quick lunges
        Charge = {
            Enabled = true,
            Speed = 45,
            Duration = 0.3,
            Cooldown = 3,
            WarningTime = 0.2,
            Range = 12,
        },

        Attack = {
            Pattern = "SingleShot",
            Damage = 8,
            Cooldown = 0.8,
            ProjectileSpeed = 55,
            ProjectileColor = Color3.fromRGB(0, 200, 0),
        },

        LootTable = "Beach_Common",
        Size = Vector3.new(2, 1, 5),
        Color = Color3.fromRGB(50, 150, 50),
    }),

    --========================================================================
    -- MIDLANDS ENEMIES (Medium - More aggressive, some charges)
    --========================================================================

    Goblin = CreateEnemy({
        Name = "Goblin",
        Zone = "Midlands",
        Type = "Enemy",

        MaxHP = 100,
        Defense = 5,
        XPReward = 25,

        Movement = {
            Speed = 14,
            ChaseSpeed = 16,
            Behavior = "Chase",
            StopRange = 4,
            AggroRange = 30,
            LeashRange = 50,
        },

        Attack = {
            Pattern = "SingleShot",
            Damage = 25,
            Cooldown = 1.2,
            ProjectileSpeed = 50,
            ProjectileColor = Color3.fromRGB(0, 255, 0),
        },

        LootTable = "Midlands_Common",
        Size = Vector3.new(3, 4, 2),
        Color = Color3.fromRGB(50, 180, 50),
    }),

    Orc = CreateEnemy({
        Name = "Orc",
        Zone = "Midlands",
        Type = "Enemy",

        MaxHP = 200,
        Defense = 10,
        XPReward = 40,

        Movement = {
            Speed = 10,
            ChaseSpeed = 12,
            Behavior = "Chase",
            StopRange = 5,
            AggroRange = 25,
            LeashRange = 45,
        },

        -- Orcs charge frequently!
        Charge = {
            Enabled = true,
            Speed = 30,
            Duration = 0.8,
            Cooldown = 4,
            WarningTime = 0.5,
            Range = 18,
        },

        Attack = {
            Pattern = "Shotgun",
            Damage = 30,
            Cooldown = 2.0,
            ShotgunSpread = 30,
            ProjectileCount = 3,
            ProjectileSpeed = 45,
            ProjectileColor = Color3.fromRGB(100, 200, 100),
        },

        LootTable = "Midlands_Common",
        Size = Vector3.new(5, 7, 3),
        Color = Color3.fromRGB(80, 120, 80),
    }),

    DarkElf = CreateEnemy({
        Name = "Dark Elf",
        Zone = "Midlands",
        Type = "Enemy",

        MaxHP = 120,
        Defense = 3,
        XPReward = 35,

        Movement = {
            Speed = 16,
            ChaseSpeed = 18,
            Behavior = "Chase",
            StopRange = 6,              -- Keeps distance, ranged attacker
            AggroRange = 35,
            LeashRange = 55,
        },

        Attack = {
            Pattern = "Burst",
            Damage = 20,
            Cooldown = 1.5,
            BurstCount = 2,
            BurstDelay = 0.15,
            ProjectileSpeed = 60,
            ProjectileColor = Color3.fromRGB(100, 0, 150),
        },

        LootTable = "Midlands_Rare",
        Size = Vector3.new(3, 6, 2),
        Color = Color3.fromRGB(60, 30, 80),
    }),

    --========================================================================
    -- GODLANDS ENEMIES (Hard - Orbit behavior, dangerous attacks)
    --========================================================================

    MedusaConstruct = CreateEnemy({
        Name = "Medusa Construct",
        Zone = "Godlands",
        Type = "Enemy",

        MaxHP = 500,
        Defense = 20,
        XPReward = 100,

        Movement = {
            Speed = 12,
            ChaseSpeed = 14,
            Behavior = "Orbit",         -- Circles player
            OrbitRadius = 18,
            StopRange = 10,
            AggroRange = 40,
            LeashRange = 60,
        },

        Attack = {
            Pattern = "Ring",
            Damage = 50,
            Cooldown = 2.0,
            ProjectileCount = 8,
            ProjectileSpeed = 40,
            ProjectileColor = Color3.fromRGB(0, 255, 100),
        },

        LootTable = "Godlands_God",
        Size = Vector3.new(6, 7, 6),
        Color = Color3.fromRGB(100, 255, 150),
    }),

    WhiteDemon = CreateEnemy({
        Name = "White Demon",
        Zone = "Godlands",
        Type = "Enemy",

        MaxHP = 450,
        Defense = 15,
        XPReward = 90,

        Movement = {
            Speed = 14,
            ChaseSpeed = 16,
            Behavior = "Orbit",
            OrbitRadius = 20,
            StopRange = 12,
            AggroRange = 35,
            LeashRange = 55,
        },

        -- White Demons charge occasionally
        Charge = {
            Enabled = true,
            Speed = 50,
            Duration = 0.4,
            Cooldown = 8,
            WarningTime = 0.3,
            Range = 25,
        },

        Attack = {
            Pattern = "Shotgun",
            Damage = 60,
            Cooldown = 1.8,
            ShotgunSpread = 45,
            ProjectileCount = 5,
            ProjectileSpeed = 50,
            ProjectileColor = Color3.fromRGB(255, 255, 255),
        },

        LootTable = "Godlands_God",
        Size = Vector3.new(6, 8, 3),
        Color = Color3.fromRGB(240, 240, 255),
    }),

    FlyingBrain = CreateEnemy({
        Name = "Flying Brain",
        Zone = "Godlands",
        Type = "Enemy",

        MaxHP = 400,
        Defense = 10,
        XPReward = 85,

        Movement = {
            Speed = 16,
            ChaseSpeed = 18,
            Behavior = "Orbit",
            OrbitRadius = 16,           -- Closer orbit
            StopRange = 8,
            AggroRange = 40,
            LeashRange = 60,
        },

        Attack = {
            Pattern = "Spiral",
            Damage = 45,
            Cooldown = 2.5,
            ProjectileCount = 12,
            ProjectileSpeed = 35,
            ProjectileColor = Color3.fromRGB(255, 100, 200),
        },

        LootTable = "Godlands_God",
        Size = Vector3.new(5, 5, 5),
        Color = Color3.fromRGB(255, 150, 200),
    }),

    Beholder = CreateEnemy({
        Name = "Beholder",
        Zone = "Godlands",
        Type = "Enemy",

        MaxHP = 600,
        Defense = 25,
        XPReward = 120,

        Movement = {
            Speed = 10,
            ChaseSpeed = 12,
            Behavior = "Orbit",
            OrbitRadius = 22,           -- Wide orbit
            StopRange = 15,
            AggroRange = 45,
            LeashRange = 65,
        },

        Attack = {
            Pattern = "Ring",
            Damage = 70,
            Cooldown = 3.0,
            ProjectileCount = 12,
            ProjectileSpeed = 45,
            ProjectileColor = Color3.fromRGB(255, 0, 0),
        },

        LootTable = "Godlands_God",
        Size = Vector3.new(7, 7, 7),
        Color = Color3.fromRGB(150, 50, 50),
    }),

    --========================================================================
    -- BOSS EXAMPLE
    --========================================================================

    BeachBoss = CreateEnemy({
        Name = "Dreadpirate",
        Zone = "Beach",
        Type = "Boss",                  -- Boss type = larger, more dangerous

        MaxHP = 2000,
        Defense = 15,
        XPReward = 500,

        Movement = {
            Speed = 8,
            ChaseSpeed = 12,
            Behavior = "Orbit",
            OrbitRadius = 25,
            StopRange = 15,
            AggroRange = 50,
            LeashRange = 80,
        },

        -- Boss charges frequently and dangerously
        Charge = {
            Enabled = true,
            Speed = 60,
            Duration = 1.0,
            Cooldown = 5,
            WarningTime = 0.8,          -- More warning for boss charge
            Range = 35,
        },

        Attack = {
            Pattern = "Ring",
            Damage = 80,
            Cooldown = 2.5,
            ProjectileCount = 16,
            ProjectileSpeed = 50,
            ProjectileColor = Color3.fromRGB(100, 50, 0),
        },

        LootTable = "Boss_Common",      -- Boss loot table with stat pots and white bags
        Size = Vector3.new(8, 10, 4),
        Color = Color3.fromRGB(50, 30, 20),
    }),
}

--============================================================================
-- ZONE SPAWN TABLES
--============================================================================
EnemyDatabase.ZoneSpawns = {
    Beach = {
        {Enemy = "Pirate", Weight = 40},
        {Enemy = "PirateCaptain", Weight = 10},
        {Enemy = "Crab", Weight = 30},
        {Enemy = "Snake", Weight = 20},
    },

    Midlands = {
        {Enemy = "Goblin", Weight = 40},
        {Enemy = "Orc", Weight = 30},
        {Enemy = "DarkElf", Weight = 30},
    },

    Godlands = {
        {Enemy = "MedusaConstruct", Weight = 25},
        {Enemy = "WhiteDemon", Weight = 25},
        {Enemy = "FlyingBrain", Weight = 25},
        {Enemy = "Beholder", Weight = 25},
    },
}

--============================================================================
-- ZONE CONFIGURATION
--============================================================================
EnemyDatabase.ZoneConfig = {
    Beach = {
        MaxEnemies = 30,
        SpawnRate = 1.5,
        EnemyLevelBonus = 0,
    },

    Midlands = {
        MaxEnemies = 40,
        SpawnRate = 1.0,
        EnemyLevelBonus = 5,
    },

    Godlands = {
        MaxEnemies = 50,
        SpawnRate = 0.8,
        EnemyLevelBonus = 10,
    },
}

--============================================================================
-- API FUNCTIONS
-- Note: Loot tables are in ItemDatabase.lua (not duplicated here)
--============================================================================

function EnemyDatabase.GetEnemy(enemyName)
    return EnemyDatabase.Enemies[enemyName]
end

function EnemyDatabase.GetRandomEnemyForZone(zoneName)
    local spawns = EnemyDatabase.ZoneSpawns[zoneName]
    if not spawns then
        warn("[EnemyDatabase] No spawns found for zone: " .. tostring(zoneName))
        return nil
    end

    local totalWeight = 0
    for _, entry in ipairs(spawns) do
        totalWeight = totalWeight + entry.Weight
    end

    if totalWeight <= 0 then
        warn("[EnemyDatabase] Total weight is 0 for zone: " .. zoneName)
        return nil
    end

    local roll = math.random() * totalWeight
    local cumulative = 0

    for _, entry in ipairs(spawns) do
        cumulative = cumulative + entry.Weight
        if roll <= cumulative then
            local enemy = EnemyDatabase.Enemies[entry.Enemy]
            if not enemy then
                warn("[EnemyDatabase] Enemy not found: " .. tostring(entry.Enemy))
            end
            return enemy
        end
    end

    return nil
end

-- Debug: Verify enemies were created at module load
local enemyCount = 0
for name, enemy in pairs(EnemyDatabase.Enemies) do
    enemyCount = enemyCount + 1
end
print("[EnemyDatabase] Loaded " .. enemyCount .. " enemy definitions")

return EnemyDatabase
