--[[
    Main.server.lua
    Server entry point - initializes all systems

    RESILIENT INITIALIZATION:
    Each manager is initialized in a protected call (pcall) so that
    one failing manager doesn't prevent others from starting.
]]

print("!!! Server Main.server.lua starting !!!")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")

-- NOTE: We keep CharacterAutoLoads = true (default) because setting it to false
-- prevents StarterGui LocalScripts from running in some cases.
-- Instead, we destroy the auto-spawned character in PlayerManager if no character is selected.

-- Wait for shared modules to be available
local Shared = ReplicatedStorage:WaitForChild("Shared")

-- Load shared modules
local Remotes = require(Shared:WaitForChild("Remotes"))
local Constants = require(Shared:WaitForChild("Constants"))

-- Initialize remotes first (creates them for clients to use)
local remotesOk, remotesErr = pcall(function()
    Remotes.Init()
end)
if not remotesOk then
    warn("[Main] CRITICAL: Remotes.Init() failed:", remotesErr)
end

-- Load server managers
local Server = ServerScriptService:WaitForChild("Server")
local Managers = Server:WaitForChild("Managers")

local DataManager = require(Managers:WaitForChild("DataManager"))
local PlayerManager = require(Managers:WaitForChild("PlayerManager"))
local CombatManager = require(Managers:WaitForChild("CombatManager"))
local ProjectileManager = require(Managers:WaitForChild("ProjectileManager"))
local EnemyManager = require(Managers:WaitForChild("EnemyManager"))
local LootManager = require(Managers:WaitForChild("LootManager"))
local PortalManager = require(Managers:WaitForChild("PortalManager"))
local RegenManager = require(Managers:WaitForChild("RegenManager"))
local NexusBuilder = require(Managers:WaitForChild("NexusBuilder"))
local VaultBuilder = require(Managers:WaitForChild("VaultBuilder"))
local VaultManager = require(Managers:WaitForChild("VaultManager"))

--============================================================================
-- PROTECTED INITIALIZATION HELPER
--============================================================================

local function safeInit(managerName, initFunc)
    local success, err = pcall(initFunc)
    if success then
        print("[Main] ✓", managerName, "initialized")
    else
        warn("[Main] ✗", managerName, "FAILED:", err)
    end
    return success
end

--============================================================================
-- INITIALIZE ALL MANAGERS (with fault isolation)
--============================================================================

print("[Main] Beginning manager initialization...")

-- Critical managers (order matters)
safeInit("DataManager", DataManager.Init)
safeInit("NexusBuilder", NexusBuilder.Init)  -- Build Nexus before players spawn
safeInit("VaultBuilder", VaultBuilder.Init)  -- Build Vault room
safeInit("PlayerManager", PlayerManager.Init)
safeInit("VaultManager", VaultManager.Init)  -- Vault storage operations

-- Combat systems (isolated so portal still works if combat fails)
safeInit("CombatManager", CombatManager.Init)
safeInit("ProjectileManager", ProjectileManager.Init)  -- Client-auth hit detection handler
safeInit("EnemyManager", EnemyManager.Init)
safeInit("LootManager", LootManager.Init)

-- Portal and utility systems
safeInit("PortalManager", PortalManager.Init)
safeInit("RegenManager", RegenManager.Init)  -- HP/MP regeneration (Vital Combat)

print("=================================")
print("  REALM BLOX Server Started!")
print("  Beta 0.0.1")
print("=================================")
