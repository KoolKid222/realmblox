--[[
    Utilities.lua
    Common helper functions used across client and server
]]

local Constants = require(script.Parent.Constants)

local Utilities = {}

--============================================================================
-- ROTMG XP SYSTEM (Exact values from RotMG)
-- Source: https://www.realmeye.com/wiki/experience-and-fame
--
-- XP Formula: XP needed for level N = 50 + (N-2) * 100
-- Level 1→2:  50 XP
-- Level 2→3:  150 XP
-- Level 3→4:  250 XP
-- ...
-- Level 19→20: 1850 XP
-- Total to 20: 18,050 XP
--
-- XP Caps:
-- - Regular enemies: capped at 10% of XP needed for next level
-- - Quest/Boss enemies: capped at 20% of XP needed for next level
--============================================================================

-- Calculate XP required to reach a specific level (RotMG formula)
function Utilities.GetXPForLevel(level)
    if level <= 1 then return 0 end
    -- RotMG formula: 50 + (level - 2) * 100
    return 50 + (level - 2) * 100
end

-- Calculate total XP needed from level 1 to target level
function Utilities.GetTotalXPForLevel(level)
    if level <= 1 then return 0 end
    -- Sum of arithmetic sequence: n/2 * (first + last)
    -- For levels 2 to N: sum of 50, 150, 250, ... , (50 + (N-2)*100)
    local n = level - 1  -- Number of level-ups needed
    local firstXP = 50
    local lastXP = 50 + (level - 2) * 100
    return math.floor(n * (firstXP + lastXP) / 2)
end

-- Calculate level from current total XP
function Utilities.GetLevelFromXP(totalXP)
    local level = 1
    local xpNeeded = 0

    while level < Constants.Leveling.MAX_LEVEL do
        local nextLevelXP = Utilities.GetXPForLevel(level + 1)
        if totalXP < xpNeeded + nextLevelXP then
            break
        end
        xpNeeded = xpNeeded + nextLevelXP
        level = level + 1
    end

    return level, totalXP - xpNeeded  -- Returns level and XP progress into current level
end

-- Cap XP reward based on player level (RotMG mechanic)
-- Regular enemies: 10% of XP needed for next level
-- Quest/Boss enemies: 20% of XP needed for next level
function Utilities.CapXPReward(baseXP, playerLevel, isBossOrQuest)
    if playerLevel >= Constants.Leveling.MAX_LEVEL then
        return 0  -- No XP at max level
    end

    local xpForNextLevel = Utilities.GetXPForLevel(playerLevel + 1)
    local maxXP

    if isBossOrQuest then
        maxXP = math.floor(xpForNextLevel * 0.20)  -- 20% cap for bosses
    else
        maxXP = math.floor(xpForNextLevel * 0.10)  -- 10% cap for regular enemies
    end

    return math.min(baseXP, maxXP)
end

-- Calculate base XP for an enemy (RotMG formula: HP / 10)
function Utilities.GetEnemyBaseXP(maxHP, specifiedXP)
    if specifiedXP and specifiedXP > 0 then
        return specifiedXP
    end
    -- RotMG default: HP / 10
    return math.floor(maxHP / 10)
end

--============================================================================
-- ROTMG STAT FORMULAS (Exact values from RotMG source code)
-- Source: Player.as - MIN/MAX constants
--============================================================================

-- RotMG Constants (from Player.as)
local ROTMG = {
    MIN_ATTACK_FREQ = 0.0015,   -- 1.5 APS at 0 DEX
    MAX_ATTACK_FREQ = 0.008,    -- 8 APS at 75 DEX
    MIN_ATTACK_MULT = 0.5,      -- 50% damage at 0 ATK
    MAX_ATTACK_MULT = 2.0,      -- 200% damage at 75 ATK
    MIN_MOVE_SPEED = 0.004,     -- Min move speed
    MAX_MOVE_SPEED = 0.0096,    -- Max move speed at 75 SPD
    STAT_CAP = 75,              -- Max stat value for calculations
}

-- ATT Formula (exact RotMG: attackMultiplier())
-- Formula: MIN_ATTACK_MULT + (attack/75) * (MAX_ATTACK_MULT - MIN_ATTACK_MULT)
-- At 0 ATK = 0.5x damage (50%)
-- At 75 ATK = 2.0x damage (200%)
function Utilities.GetDamageMult(attack)
    local t = math.min(attack, ROTMG.STAT_CAP) / ROTMG.STAT_CAP
    return ROTMG.MIN_ATTACK_MULT + t * (ROTMG.MAX_ATTACK_MULT - ROTMG.MIN_ATTACK_MULT)
end

-- DEF Formula (exact RotMG: damageWithDefense())
-- Minimum damage floor = (damage * 3) / 20 = 15% of raw damage
-- Final damage = max(minDamage, damage - defense)
function Utilities.CalculateDamageTaken(rawDamage, defense)
    local minDamage = math.floor((rawDamage * 3) / 20)  -- 15% floor (exact RotMG)
    return math.max(minDamage, rawDamage - defense)
end

-- Full damage calculation: weapon damage -> ATT multiplier -> DEF reduction
function Utilities.CalculateDamage(weaponDamage, attackerAttack, defenderDefense)
    local attackMult = Utilities.GetDamageMult(attackerAttack)
    local rawDamage = weaponDamage * attackMult
    local finalDamage = Utilities.CalculateDamageTaken(rawDamage, defenderDefense)
    return math.floor(finalDamage)
end

-- SPD Formula (exact RotMG: getMoveSpeed())
-- Formula: MIN_MOVE_SPEED + (speed/75) * (MAX_MOVE_SPEED - MIN_MOVE_SPEED)
-- Converted to Roblox WalkSpeed (multiply by ~4000 for studs/sec equivalent)
function Utilities.GetWalkSpeed(speed)
    local t = math.min(speed, ROTMG.STAT_CAP) / ROTMG.STAT_CAP
    local rotmgSpeed = ROTMG.MIN_MOVE_SPEED + t * (ROTMG.MAX_MOVE_SPEED - ROTMG.MIN_MOVE_SPEED)
    -- Convert RotMG units to Roblox WalkSpeed (scaled for feel)
    -- RotMG 0.004-0.0096 maps to roughly 12-27 studs/sec
    return 12 + (rotmgSpeed - ROTMG.MIN_MOVE_SPEED) / (ROTMG.MAX_MOVE_SPEED - ROTMG.MIN_MOVE_SPEED) * 15
end

-- DEX Formula (exact RotMG: attackFrequency())
-- Formula: MIN_ATTACK_FREQ + (dexterity/75) * (MAX_ATTACK_FREQ - MIN_ATTACK_FREQ)
-- Returns cooldown in seconds between shots
-- At 0 DEX = 1.5 APS (0.667 sec cooldown)
-- At 75 DEX = 8 APS (0.125 sec cooldown)
function Utilities.GetAttackCooldown(dexterity, weaponBaseRate)
    local t = math.min(dexterity, ROTMG.STAT_CAP) / ROTMG.STAT_CAP
    local attackFreq = ROTMG.MIN_ATTACK_FREQ + t * (ROTMG.MAX_ATTACK_FREQ - ROTMG.MIN_ATTACK_FREQ)

    -- Convert to APS then to cooldown
    local attacksPerSecond = attackFreq * 1000  -- RotMG uses per-millisecond, we need per-second

    -- Weapon rate modifier
    local weaponMult = weaponBaseRate or 1.0
    attacksPerSecond = attacksPerSecond * weaponMult

    return 1 / attacksPerSecond
end

-- VIT Formula (HP Regeneration)
-- Returns HP restored per second
function Utilities.GetHPRegen(vitality)
    local BASE_HP_REGEN = 1
    return BASE_HP_REGEN + (vitality * 0.12)
end

-- WIS Formula (MP Regeneration)
-- Returns MP restored per second
function Utilities.GetMPRegen(wisdom)
    local BASE_MP_REGEN = 0.5
    return BASE_MP_REGEN + (wisdom * 0.06)
end

--============================================================================
-- LEGACY/HELPER FUNCTIONS
--============================================================================

-- Deep copy a table
function Utilities.DeepCopy(original)
    local copy = {}
    for key, value in pairs(original) do
        if type(value) == "table" then
            copy[key] = Utilities.DeepCopy(value)
        else
            copy[key] = value
        end
    end
    return copy
end

-- Weighted random selection
function Utilities.WeightedRandom(items)
    -- items = {{item = X, weight = 10}, {item = Y, weight = 5}, ...}
    local totalWeight = 0
    for _, entry in ipairs(items) do
        totalWeight = totalWeight + entry.weight
    end

    local roll = math.random() * totalWeight
    local cumulative = 0

    for _, entry in ipairs(items) do
        cumulative = cumulative + entry.weight
        if roll <= cumulative then
            return entry.item or entry
        end
    end

    return items[#items].item or items[#items]
end

-- Generate a unique ID
function Utilities.GenerateUID()
    return game:GetService("HttpService"):GenerateGUID(false)
end

-- Clamp a value between min and max
function Utilities.Clamp(value, min, max)
    return math.max(min, math.min(max, value))
end

-- Linear interpolation
function Utilities.Lerp(a, b, t)
    return a + (b - a) * t
end

-- Distance between two Vector3 positions (ignoring Y)
function Utilities.HorizontalDistance(pos1, pos2)
    local dx = pos1.X - pos2.X
    local dz = pos1.Z - pos2.Z
    return math.sqrt(dx * dx + dz * dz)
end

-- Get direction from one position to another (normalized, horizontal only)
function Utilities.GetDirection(from, to)
    local direction = Vector3.new(to.X - from.X, 0, to.Z - from.Z)
    if direction.Magnitude > 0 then
        return direction.Unit
    end
    return Vector3.new(0, 0, 1)  -- Default forward
end

return Utilities
