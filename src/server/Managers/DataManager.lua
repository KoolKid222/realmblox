--[[
    DataManager.lua
    Wrapper around ProfileManager for backward compatibility

    Now uses ProfileService (via ProfileManager) for:
    - Session locking (prevents dupes)
    - Auto-save (handled automatically)
    - Graceful shutdown
    - Data reconciliation

    The old raw DataStore code has been replaced with ProfileManager calls.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local ClassDatabase = require(Shared.ClassDatabase)

-- ProfileManager handles all the heavy lifting now
local ProfileManager = require(script.Parent.ProfileManager)

local DataManager = {}

local isStudio = RunService:IsStudio()

--============================================================================
-- PROFILE DATA ACCESS
-- These functions provide backward compatibility with the old API
--============================================================================

-- Load player data (waits for ProfileManager to load the profile)
function DataManager.LoadPlayerData(player)
    -- Wait for profile to load (ProfileManager handles the actual loading)
    local profile = ProfileManager.WaitForProfile(player, 15)

    if not profile then
        warn("[DataManager] Failed to load profile for " .. player.Name)
        return nil
    end

    local data = profile.Data

    print("[DataManager] Loaded data for " .. player.Name .. " Version=" .. tostring(data.Version))

    -- Run migration if needed
    if data.Version and data.Version < Constants.DataStore.DATA_VERSION then
        DataManager.MigrateData(data)
    end

    -- ALWAYS validate character stats (ensure no characters have missing/broken stats)
    DataManager.ValidateCharacterStats(data)

    print("[DataManager] Loaded data for " .. player.Name .. " with " .. #data.Characters .. " character(s)")
    return data
end

-- Save player data (ProfileService auto-saves, but this can trigger immediate save)
function DataManager.SavePlayerData(player, data)
    -- ProfileService handles saving automatically
    -- This function exists for backward compatibility
    local profile = ProfileManager.GetProfile(player)

    if not profile then
        warn("[DataManager] No profile to save for " .. player.Name)
        return false
    end

    -- Data is already in profile.Data (same reference), so it's already "saved"
    -- ProfileService will persist it automatically
    print("[DataManager] Data marked for save: " .. player.Name .. " (ProfileService will auto-save)")
    return true
end

-- Get player data without loading (returns nil if not loaded yet)
function DataManager.GetPlayerData(player)
    return ProfileManager.GetData(player)
end

-- Check if player data is loaded
function DataManager.IsLoaded(player)
    return ProfileManager.IsLoaded(player)
end

--============================================================================
-- CHARACTER STATS VALIDATION
-- Ensures all characters have valid stats (runs on every load)
--============================================================================

function DataManager.ValidateCharacterStats(data)
    if not data.Characters then return end

    for i, character in ipairs(data.Characters) do
        local needsStats = false
        local reason = ""

        if not character.Stats then
            needsStats = true
            reason = "Stats is nil"
        elseif type(character.Stats) ~= "table" then
            needsStats = true
            reason = "Stats is not a table"
        elseif not character.Stats.HP or character.Stats.HP == 0 then
            needsStats = true
            reason = "Stats.HP is nil or 0"
        elseif not character.Stats.Attack then
            needsStats = true
            reason = "Stats.Attack is nil"
        end

        if needsStats then
            warn("[DataManager] ValidateCharacterStats: Character " .. i .. " needs stats fix - " .. reason)
            local baseStats = ClassDatabase.GetBaseStats(character.Class or "Wizard")
            if baseStats then
                character.Stats = baseStats
                character.CurrentHP = character.CurrentHP or baseStats.HP
                character.CurrentMP = character.CurrentMP or baseStats.MP
                print("[DataManager] Fixed stats for character " .. i .. " (" .. tostring(character.Class) .. ")")
                print("  HP=" .. baseStats.HP .. ", Attack=" .. baseStats.Attack .. ", Dexterity=" .. baseStats.Dexterity)
            else
                warn("[DataManager] Could not get base stats for class: " .. tostring(character.Class))
            end
        else
            print("[DataManager] Character " .. i .. " stats OK: HP=" .. character.Stats.HP .. ", Attack=" .. character.Stats.Attack)
        end
    end
end

--============================================================================
-- DATA MIGRATION
-- Migrates old data formats to the current version
--============================================================================

function DataManager.MigrateData(data)
    local oldVersion = data.Version or 0
    print("[DataManager] Migrating data from version " .. oldVersion .. " to " .. Constants.DataStore.DATA_VERSION)

    -- Ensure all required fields exist
    data.Characters = data.Characters or {}
    data.Vault = data.Vault or {}
    data.AccountStats = data.AccountStats or {
        TotalFame = 0,
        HighestLevelReached = 1,
        TotalDeaths = 0,
        EnemiesKilled = 0,
    }
    data.UnlockedClasses = data.UnlockedClasses or ClassDatabase.GetDefaultUnlockedClasses()

    -- Migrate character stats if needed (old format -> new format)
    for _, character in ipairs(data.Characters) do
        if character.Stats then
            -- Check if stats are in old format (direct MaxHP, MaxMP) or missing values
            if not character.Stats.HP or character.Stats.HP == 0 then
                -- Get fresh base stats for this class
                local baseStats = ClassDatabase.GetBaseStats(character.Class or "Wizard")
                if baseStats then
                    character.Stats = baseStats
                    character.CurrentHP = baseStats.HP
                    character.CurrentMP = baseStats.MP
                    print("[DataManager] Migrated stats for character: " .. tostring(character.Class))
                end
            end
        else
            -- No stats at all, create fresh
            local baseStats = ClassDatabase.GetBaseStats(character.Class or "Wizard")
            if baseStats then
                character.Stats = baseStats
                character.CurrentHP = baseStats.HP
                character.CurrentMP = baseStats.MP
            end
        end

        -- Ensure StatBonuses exists (for stat potions)
        if not character.StatBonuses then
            character.StatBonuses = {
                HP = 0, MP = 0,
                Attack = 0, Defense = 0,
                Speed = 0, Dexterity = 0,
                Vitality = 0, Wisdom = 0,
            }
        end
    end

    -- Update version
    data.Version = Constants.DataStore.DATA_VERSION

    return data
end

--============================================================================
-- AUTO-SAVE (Deprecated - ProfileService handles this)
-- These functions exist for backward compatibility but do nothing
--============================================================================

function DataManager.StartAutoSave(player, getData)
    -- ProfileService handles auto-saving automatically
    -- This function exists for backward compatibility
    print("[DataManager] Auto-save handled by ProfileService for " .. player.Name)
end

function DataManager.StopAutoSave(player)
    -- ProfileService handles this automatically
end

--============================================================================
-- INITIALIZATION
--============================================================================

function DataManager.Init()
    -- Initialize ProfileManager first (it handles ProfileService setup)
    ProfileManager.Init()

    print("[DataManager] Initialized (using ProfileService for session-locked persistence)")
end

return DataManager
