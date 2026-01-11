--[[
    Main.client.lua
    Client entry point - initializes all client systems
]]

-- print("\!\!\! Client Main.client.lua starting !!!")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local player = Players.LocalPlayer

-- Wait for shared modules
local Shared = ReplicatedStorage:WaitForChild("Shared")

-- Load shared modules
local Remotes = require(Shared:WaitForChild("Remotes"))
local Constants = require(Shared:WaitForChild("Constants"))
local WorldGen = require(Shared:WaitForChild("WorldGen"))
local BiomeCache = require(Shared:WaitForChild("BiomeCache"))

-- Initialize remotes (waits for server to create them)
Remotes.Init()

-- Generate biome cache for minimap (one-time cost, enables instant lookups)
-- print("[Main] Generating biome cache for minimap...")
BiomeCache.Generate(WorldGen)
-- print("[Main] Biome cache ready!")

-- Load client controllers (they auto-initialize)
local Controllers = script.Parent:WaitForChild("Controllers")
local CombatController = require(Controllers:WaitForChild("CombatController"))
local EnemyVisuals = require(Controllers:WaitForChild("EnemyVisuals"))
local ProjectileRenderer = require(Controllers:WaitForChild("ProjectileRenderer"))
local ProjectileVisuals = require(Controllers:WaitForChild("ProjectileVisuals"))  -- Enemy projectile hit detection
local DamageNumbers = require(Controllers:WaitForChild("DamageNumbers"))
local InventoryController = require(Controllers:WaitForChild("InventoryController"))
local LootVisuals = require(Controllers:WaitForChild("LootVisuals"))
local PortalController = require(Controllers:WaitForChild("PortalController"))
local MapRenderer = require(Controllers:WaitForChild("MapRenderer"))
local VaultController = require(Controllers:WaitForChild("VaultController"))
-- HUD is now in StarterGui (src/ui/HUDController.client.lua)
-- CharacterSelect and DeathScreen are also in src/ui/

-- Initialize controllers
MapRenderer.Init()         -- Initialize terrain first
ProjectileRenderer.Init()  -- Initialize first (CombatController uses it)
ProjectileVisuals.Init()   -- Enemy projectile visuals + client-side hit detection
CombatController.Init()
EnemyVisuals.Init()
DamageNumbers.Init()
InventoryController.Init()  -- Initialize inventory after HUD
LootVisuals.Init()  -- Initialize loot visuals
PortalController.Init()  -- Initialize portal interaction
VaultController.Init()  -- Initialize vault chest interaction

-- Tell server we're ready
Remotes.Events.PlayerReady:FireServer()

print("=================================")
print("  REALM BLOX Client Ready!")
print("  Beta 0.0.1")
print("=================================")
