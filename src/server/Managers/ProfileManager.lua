--[[
    ProfileManager.lua
    Wrapper around ProfileService for session-locked data persistence

    Features:
    - Session locking (prevents dupes from multiple server access)
    - Auto-save with conflict resolution
    - Graceful shutdown handling
    - Data reconciliation (merges defaults with existing data)

    Usage:
        local ProfileManager = require(path.to.ProfileManager)
        ProfileManager.Init()

        -- Get player's profile (returns nil if not loaded)
        local profile = ProfileManager.GetProfile(player)
        if profile then
            profile.Data.Characters[1].Level = 5
            -- Auto-saves periodically, or call profile:Save() for immediate save
        end
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- Load ProfileService
local ProfileService = require(script.Parent.Parent.Lib.ProfileService)

local ProfileManager = {}

--============================================================================
-- CONFIGURATION
--============================================================================

local PROFILE_STORE_NAME = "RealmBlox_PlayerData_v4"
local KICK_MESSAGE_SESSION_LOCK = "Your data is being used on another server. Please wait a moment and rejoin."
local KICK_MESSAGE_LOAD_FAIL = "Failed to load your data. Please rejoin."

--============================================================================
-- DATA TEMPLATE (Default structure for new players)
-- ProfileService will reconcile this with existing data automatically
--============================================================================

local PROFILE_TEMPLATE = {
    Version = 4,

    -- Character slots (permadeath - characters can be deleted)
    Characters = {},

    -- Account-wide vault storage (RotMG-style)
    Vault = {
        -- Array of vault chests, each chest holds up to 8 items
        -- Chests[1] is always unlocked by default
        -- Each chest is: {Item1, Item2, ..., Item8} where each item is itemId or false
        Chests = {
            {false, false, false, false, false, false, false, false},  -- Chest 1 (free)
        },
        UnlockedChestCount = 1,  -- How many chests the player has unlocked
        MaxChests = 80,          -- Maximum purchasable chests

        -- Potion Vault (special storage for stat potions only)
        -- Stores: {itemId = count} for each potion type
        PotionVault = {},
        PotionVaultCapacity = 16,  -- Starting capacity, upgradable to 256

        -- Gift Chest (unlimited capacity, for rewards/gifts)
        GiftChest = {},
    },

    -- Account statistics (persists across character deaths)
    AccountStats = {
        TotalFame = 0,
        HighestLevelReached = 0,
        TotalDeaths = 0,
        EnemiesKilled = 0,
    },

    -- Unlocked classes (start with Wizard)
    UnlockedClasses = {"Wizard"},

    -- Currency
    Currency = {
        RealmGold = 0,  -- Premium currency
        Fame = 0,       -- Earned from gameplay
    },

    -- Settings
    Settings = {
        MusicVolume = 0.5,
        SFXVolume = 0.8,
    },
}

--============================================================================
-- PROFILE STORE
--============================================================================

local ProfileStore = ProfileService.GetProfileStore(PROFILE_STORE_NAME, PROFILE_TEMPLATE)

-- Active profiles cache
local Profiles = {}  -- [Player] = Profile

--============================================================================
-- PROFILE LOADING
--============================================================================

local function onPlayerAdded(player)
    -- Load profile with session locking
    local profile = ProfileStore:LoadProfileAsync("Player_" .. player.UserId)

    if profile then
        -- Profile loaded successfully
        profile:AddUserId(player.UserId)  -- GDPR compliance
        profile:Reconcile()  -- Merge with template (adds missing fields)

        -- Handle session lock steal (another server took over)
        profile:ListenToRelease(function()
            Profiles[player] = nil
            -- Kick player if they're still in game
            if player:IsDescendantOf(Players) then
                player:Kick(KICK_MESSAGE_SESSION_LOCK)
            end
        end)

        -- Check if player is still in game (might have left during load)
        if player:IsDescendantOf(Players) then
            Profiles[player] = profile
            print("[ProfileManager] Loaded profile for " .. player.Name)
        else
            -- Player left during load, release profile
            profile:Release()
        end
    else
        -- Failed to load profile (DataStore issues or session locked elsewhere)
        if player:IsDescendantOf(Players) then
            player:Kick(KICK_MESSAGE_LOAD_FAIL)
        end
        warn("[ProfileManager] Failed to load profile for " .. player.Name)
    end
end

local function onPlayerRemoving(player)
    local profile = Profiles[player]
    if profile then
        profile:Release()  -- Releases session lock and saves
        Profiles[player] = nil
        print("[ProfileManager] Released profile for " .. player.Name)
    end
end

--============================================================================
-- PUBLIC API
--============================================================================

-- Get a player's profile (returns nil if not loaded yet)
function ProfileManager.GetProfile(player)
    return Profiles[player]
end

-- Get profile data directly (convenience function)
function ProfileManager.GetData(player)
    local profile = Profiles[player]
    if profile then
        return profile.Data
    end
    return nil
end

-- Check if profile is loaded
function ProfileManager.IsLoaded(player)
    return Profiles[player] ~= nil
end

-- Wait for profile to load (with timeout)
function ProfileManager.WaitForProfile(player, timeout)
    timeout = timeout or 10
    local startTime = tick()

    while not Profiles[player] do
        if tick() - startTime > timeout then
            return nil  -- Timeout
        end
        if not player:IsDescendantOf(Players) then
            return nil  -- Player left
        end
        task.wait(0.1)
    end

    return Profiles[player]
end

-- Force save a player's profile (normally auto-saves)
function ProfileManager.SaveProfile(player)
    local profile = Profiles[player]
    if profile then
        -- ProfileService doesn't have a manual Save() - it auto-saves
        -- But we can trigger an update by marking data as changed
        profile.Data._LastSave = tick()
        return true
    end
    return false
end

-- Get all active profiles (for admin/debug)
function ProfileManager.GetAllProfiles()
    return Profiles
end

--============================================================================
-- DATA MIGRATION
--============================================================================

-- Called after profile load to migrate old data formats
local function migrateData(profile)
    local data = profile.Data

    -- Migration from Version 2 to Version 3
    if data.Version == 2 then
        -- Add any new fields that were added in v3
        if not data.Settings then
            data.Settings = {
                MusicVolume = 0.5,
                SFXVolume = 0.8,
            }
        end
        data.Version = 3
        print("[ProfileManager] Migrated data from v2 to v3")
    end

    -- Migration from Version 3 to Version 4 (Vault system)
    if data.Version == 3 then
        -- Expand Vault from simple table to full RotMG-style vault
        local oldVault = data.Vault or {}
        data.Vault = {
            Chests = {
                {false, false, false, false, false, false, false, false},  -- Chest 1 (free)
            },
            UnlockedChestCount = 1,
            MaxChests = 80,
            PotionVault = {},
            PotionVaultCapacity = 16,
            GiftChest = {},
        }

        -- Migrate any existing vault items to first chest
        local slotIndex = 1
        for _, item in pairs(oldVault) do
            if slotIndex <= 8 and item then
                data.Vault.Chests[1][slotIndex] = item
                slotIndex = slotIndex + 1
            end
        end

        -- Add Currency if missing
        if not data.Currency then
            data.Currency = {
                RealmGold = 0,
                Fame = 0,
            }
        end

        data.Version = 4
        print("[ProfileManager] Migrated data from v3 to v4 (Vault system)")
    end

    -- Future migrations go here
    -- if data.Version == 4 then ... end
end

--============================================================================
-- INITIALIZATION
--============================================================================

function ProfileManager.Init()
    -- Handle players already in game (in case of late initialization)
    for _, player in ipairs(Players:GetPlayers()) do
        task.spawn(onPlayerAdded, player)
    end

    -- Handle new players
    Players.PlayerAdded:Connect(onPlayerAdded)

    -- Handle players leaving
    Players.PlayerRemoving:Connect(onPlayerRemoving)

    -- Handle server shutdown (ensure all profiles are saved)
    game:BindToClose(function()
        print("[ProfileManager] Server shutting down, releasing all profiles...")

        -- Release all profiles (triggers save)
        for player, profile in pairs(Profiles) do
            profile:Release()
        end

        -- Wait a moment for saves to complete
        task.wait(2)
    end)

    print("[ProfileManager] Initialized with ProfileService")
end

return ProfileManager
