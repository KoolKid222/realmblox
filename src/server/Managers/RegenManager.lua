--[[
    RegenManager.lua
    Handles HP/MP regeneration using RotMG Vital Combat system

    Formulas (RotMG):
    - Out of Combat HP/s = 1 + 0.24 × VIT
    - Out of Combat MP/s = 0.5 + 0.12 × WIS
    - In Combat: Regeneration reduced to 25% of normal
    - Combat Timer: 7 seconds after taking/dealing damage
    - VIT reduces in-combat duration (0.04s per VIT point)
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local Remotes = require(Shared.Remotes)
local LazyLoader = require(Shared.LazyLoader)

-- Lazy load managers using LazyLoader utility
local getPlayerManager = LazyLoader.create(script.Parent, "PlayerManager")

local RegenManager = {}

-- Track combat state per player
-- [player] = { LastCombatTime = tick(), InCombat = false }
RegenManager.CombatState = {}

-- Accumulated regen (for fractional HP/MP between ticks)
-- [player] = { HP = 0.0, MP = 0.0 }
RegenManager.RegenAccumulator = {}

--============================================================================
-- COMBAT STATE TRACKING
--============================================================================

-- Called when player takes damage (from PlayerManager.DamagePlayer)
function RegenManager.OnPlayerTookDamage(player)
    if not RegenManager.CombatState[player] then
        RegenManager.CombatState[player] = {}
    end
    RegenManager.CombatState[player].LastCombatTime = tick()
    RegenManager.CombatState[player].InCombat = true
end

-- Called when player deals damage (from hit detection)
function RegenManager.OnPlayerDealtDamage(player)
    if not RegenManager.CombatState[player] then
        RegenManager.CombatState[player] = {}
    end
    RegenManager.CombatState[player].LastCombatTime = tick()
    RegenManager.CombatState[player].InCombat = true
end

-- Check if player is currently in combat
function RegenManager.IsInCombat(player)
    local state = RegenManager.CombatState[player]
    if not state or not state.LastCombatTime then
        return false
    end

    -- Get player's VIT to calculate combat duration
    local PM = getPlayerManager()
    local effectiveStats = PM.GetEffectiveStats(player)
    local vit = effectiveStats and effectiveStats.Vitality or 0

    -- Calculate combat duration (reduced by VIT)
    local baseDuration = Constants.Regen.COMBAT_DURATION
    local vitReduction = vit * Constants.Regen.VIT_COMBAT_REDUCTION
    local combatDuration = math.max(Constants.Regen.MIN_COMBAT_DURATION, baseDuration - vitReduction)

    -- Check if still in combat
    local timeSinceCombat = tick() - state.LastCombatTime
    local inCombat = timeSinceCombat < combatDuration

    -- Update state
    state.InCombat = inCombat

    return inCombat
end

-- Get combat duration remaining (for UI display if needed)
function RegenManager.GetCombatTimeRemaining(player)
    local state = RegenManager.CombatState[player]
    if not state or not state.LastCombatTime then
        return 0
    end

    local PM = getPlayerManager()
    local effectiveStats = PM.GetEffectiveStats(player)
    local vit = effectiveStats and effectiveStats.Vitality or 0

    local baseDuration = Constants.Regen.COMBAT_DURATION
    local vitReduction = vit * Constants.Regen.VIT_COMBAT_REDUCTION
    local combatDuration = math.max(Constants.Regen.MIN_COMBAT_DURATION, baseDuration - vitReduction)

    local timeSinceCombat = tick() - state.LastCombatTime
    return math.max(0, combatDuration - timeSinceCombat)
end

--============================================================================
-- REGENERATION CALCULATIONS
--============================================================================

-- Calculate HP regen per second based on VIT and combat state
local function calculateHPRegen(vit, inCombat)
    local baseRegen = Constants.Regen.HP_BASE + (vit * Constants.Regen.HP_VIT_MULTIPLIER)

    if inCombat then
        return baseRegen * Constants.Regen.IN_COMBAT_MULTIPLIER
    end

    return baseRegen
end

-- Calculate MP regen per second based on WIS and combat state
local function calculateMPRegen(wis, inCombat)
    local baseRegen = Constants.Regen.MP_BASE + (wis * Constants.Regen.MP_WIS_MULTIPLIER)

    if inCombat then
        return baseRegen * Constants.Regen.IN_COMBAT_MULTIPLIER
    end

    return baseRegen
end

--============================================================================
-- REGEN TICK
--============================================================================

local function applyRegen()
    local PM = getPlayerManager()
    local tickRate = Constants.Regen.TICK_RATE

    for _, player in ipairs(Players:GetPlayers()) do
        local charData = PM.ActiveCharacters[player]
        if not charData then continue end

        local effectiveStats = PM.GetEffectiveStats(player)
        if not effectiveStats then continue end

        -- Initialize accumulator
        if not RegenManager.RegenAccumulator[player] then
            RegenManager.RegenAccumulator[player] = { HP = 0, MP = 0 }
        end
        local accumulator = RegenManager.RegenAccumulator[player]

        -- Check combat state
        local inCombat = RegenManager.IsInCombat(player)

        -- Calculate regen for this tick
        local hpRegenPerSec = calculateHPRegen(effectiveStats.Vitality or 0, inCombat)
        local mpRegenPerSec = calculateMPRegen(effectiveStats.Wisdom or 0, inCombat)

        local hpRegen = hpRegenPerSec * tickRate
        local mpRegen = mpRegenPerSec * tickRate

        -- Accumulate fractional regen
        accumulator.HP = accumulator.HP + hpRegen
        accumulator.MP = accumulator.MP + mpRegen

        -- Apply whole numbers only
        local hpToAdd = math.floor(accumulator.HP)
        local mpToAdd = math.floor(accumulator.MP)

        -- Keep remainder for next tick
        accumulator.HP = accumulator.HP - hpToAdd
        accumulator.MP = accumulator.MP - mpToAdd

        -- Check if regen is needed
        local needsHPRegen = hpToAdd > 0 and charData.CurrentHP < effectiveStats.MaxHP
        local needsMPRegen = mpToAdd > 0 and charData.CurrentMP < effectiveStats.MaxMP

        if not needsHPRegen and not needsMPRegen then
            continue
        end

        -- Apply HP regen
        local hpChanged = false
        if needsHPRegen then
            local oldHP = charData.CurrentHP
            charData.CurrentHP = math.min(effectiveStats.MaxHP, charData.CurrentHP + hpToAdd)
            hpChanged = charData.CurrentHP ~= oldHP
        end

        -- Apply MP regen
        local mpChanged = false
        if needsMPRegen then
            local oldMP = charData.CurrentMP
            charData.CurrentMP = math.min(effectiveStats.MaxMP, charData.CurrentMP + mpToAdd)
            mpChanged = charData.CurrentMP ~= oldMP
        end

        -- Update character attributes for instant client feedback
        if player.Character and (hpChanged or mpChanged) then
            if hpChanged then
                player.Character:SetAttribute("CurrentHP", charData.CurrentHP)
            end
            if mpChanged then
                player.Character:SetAttribute("CurrentMP", charData.CurrentMP)
            end

            -- Send stat update to client
            Remotes.Events.StatUpdate:FireClient(player, {
                CurrentHP = charData.CurrentHP,
                MaxHP = effectiveStats.MaxHP,
                CurrentMP = charData.CurrentMP,
                MaxMP = effectiveStats.MaxMP,
            })
        end
    end
end

--============================================================================
-- INITIALIZATION
--============================================================================

function RegenManager.Init()
    -- Start regen tick loop
    task.spawn(function()
        while true do
            task.wait(Constants.Regen.TICK_RATE)
            applyRegen()
        end
    end)

    -- Cleanup on player leave
    Players.PlayerRemoving:Connect(function(player)
        RegenManager.CombatState[player] = nil
        RegenManager.RegenAccumulator[player] = nil
    end)

    print("[RegenManager] Initialized (Vital Combat system)")
    print(string.format("  HP Regen: %.1f + %.2f*VIT per second", Constants.Regen.HP_BASE, Constants.Regen.HP_VIT_MULTIPLIER))
    print(string.format("  MP Regen: %.1f + %.2f*WIS per second", Constants.Regen.MP_BASE, Constants.Regen.MP_WIS_MULTIPLIER))
    print(string.format("  In-Combat: %.0f%% regen, %.1fs duration", Constants.Regen.IN_COMBAT_MULTIPLIER * 100, Constants.Regen.COMBAT_DURATION))
end

return RegenManager
