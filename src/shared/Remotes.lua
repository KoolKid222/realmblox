--[[
    Remotes.lua
    Central definition and access for all RemoteEvents/Functions

    RESILIENT REMOTE FACTORY:
    - Falls back from UnreliableRemoteEvent to RemoteEvent if instantiation fails
    - Provides GetRemote() helper with built-in waiting
    - Includes payload size debugging for unreliable events

    Usage:
        local Remotes = require(path.to.Remotes)

        -- Server:
        Remotes.Events.PlayerDamaged:FireClient(player, data)

        -- Client:
        Remotes.Events.PlayerDamaged.OnClientEvent:Connect(handler)

        -- Safe access with waiting:
        local remote = Remotes.GetRemote("PlayerHitEnemy")
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

local Remotes = {}

-- Initialization state
Remotes.IsReady = false
Remotes.ReadyEvent = Instance.new("BindableEvent")

-- Define all remote events
Remotes.EventNames = {
    -- Server → Client
    "DamageNumber",       -- Show floating damage text
    "EnemySpawn",         -- Create enemy visual on client
    "EnemyUpdate",        -- Update enemy position/state
    "EnemyDeath",         -- Enemy died, play death FX
    "ProjectileSpawn",    -- Create projectile visual
    "ProjectileHit",      -- Projectile hit, destroy visual early
    "ProjectileBatch",    -- Batch projectile spawns (optimization)
    "PlayerDeath",        -- Show death screen
    "LootDrop",           -- Show loot bag
    "LootPickup",         -- Item picked up
    "LootBagContents",    -- Response to GetBagContents request
    "StatUpdate",         -- HP/MP/XP/Stats changed
    "InventoryUpdate",    -- Inventory changed (full inventory sync)
    "InventoryError",     -- Error message (swap failed, pickup failed, etc.)
    "Notification",       -- General notification message
    "LevelUp",            -- Player leveled up
    "ZoneChanged",        -- Player entered new zone

    -- Client → Server
    "FireWeapon",         -- Player fired weapon (aim direction)
    "PlayerHitEnemy",     -- Client reports hitting enemy (client-auth projectiles)
    "PlayerHitByProjectile", -- Client reports being hit by enemy projectile (client-auth)
    "UseAbility",         -- Player used class ability
    "RequestLoot",        -- Player wants to pick up loot
    "GetBagContents",     -- Request loot bag contents (for late arrivals)
    "SwapInventory",      -- Swap items between two slots (RotMG InvSwap)
    "DropItem",           -- Player dropping item from slot
    "EquipItem",          -- Swap equipment (legacy)
    "UsePotion",          -- HP/MP potion consumed
    "UseStatPotion",      -- Stat potion consumed (permanent stat boost)
    "PlayerReady",        -- Client finished loading
    "ToggleGodmode",      -- Debug: toggle invincibility
    "AdminCommand",       -- Admin panel commands

    -- Gameplay Loop Events
    "EnterPortal",        -- Client → Server: Request to enter a portal
    "ReturnToCharSelect", -- Client → Server: Player wants to return to character select
    "ShowCharacterSelect",-- Server → Client: Show character selection screen
    "HideCharacterSelect",-- Server → Client: Hide character selection, show HUD

    -- Loading Screen
    "ShowLoading",        -- Server → Client: Show loading screen with message
    "HideLoading",        -- Server → Client: Hide loading screen

    -- Vault System
    "OpenVaultChest",     -- Client → Server: Request to open a vault chest
    "CloseVaultChest",    -- Client → Server: Close vault chest UI
    "VaultChestOpened",   -- Server → Client: Chest contents response
    "VaultChestClosed",   -- Server → Client: Vault chest UI should close
    "VaultChestUpdated",  -- Server → Client: Chest contents changed
    "VaultDeposit",       -- Client → Server: Deposit item into vault
    "VaultWithdraw",      -- Client → Server: Withdraw item from vault
    "VaultSwap",          -- Client → Server: Swap items within vault chest
    "UnlockVaultChest",   -- Client → Server: Unlock a new vault chest
    "VaultChestUnlocked", -- Server → Client: Chest was unlocked
    "GetVaultData",       -- Client → Server: Request full vault data
    "VaultDataResponse",  -- Server → Client: Full vault data response
}

-- Unreliable remote events (for high-frequency, non-critical updates)
-- These use UDP-like delivery: faster but may drop packets
-- NOTE: If UnreliableRemoteEvent fails to instantiate, falls back to RemoteEvent
Remotes.UnreliableEventNames = {
    "ProjectileSync",     -- Batch projectile position updates (can drop)
    "EnemyPositionSync",  -- Batch enemy position updates (can drop)
    "PlayerHitBatch",     -- Batched hit reports (can tolerate some loss)
}

-- Define all remote functions
Remotes.FunctionNames = {
    "GetCharacterList",   -- Fetch available characters
    "CreateCharacter",    -- Make new character
    "SelectCharacter",    -- Enter game with character
    "GetPlayerData",      -- Get current player data
}

-- Storage for created remotes
Remotes.Events = {}
Remotes.UnreliableEvents = {}
Remotes.Functions = {}

-- Track which "unreliable" events fell back to reliable
Remotes.FallbackEvents = {}

--============================================================================
-- PAYLOAD SIZE DEBUGGING (for unreliable events)
--============================================================================

local UNRELIABLE_PAYLOAD_LIMIT = 900  -- bytes
local DEBUG_PAYLOAD_SIZE = false  -- Set to true to enable warnings

-- Estimate payload size (rough approximation)
local function estimatePayloadSize(data)
    local success, encoded = pcall(function()
        return HttpService:JSONEncode(data)
    end)
    if success then
        return #encoded
    end
    return 0
end

-- Wrapper for firing unreliable events with size checking
function Remotes.FireUnreliableWithSizeCheck(eventName, ...)
    local remote = Remotes.UnreliableEvents[eventName]
    if not remote then
        warn("[Remotes] UnreliableEvent not found:", eventName)
        return false
    end

    if DEBUG_PAYLOAD_SIZE then
        local args = {...}
        local totalSize = 0
        for _, arg in ipairs(args) do
            if type(arg) == "table" then
                totalSize = totalSize + estimatePayloadSize(arg)
            end
        end

        if totalSize > UNRELIABLE_PAYLOAD_LIMIT * 0.8 then
            warn("[Remotes] WARNING: Payload for", eventName, "is", totalSize,
                "bytes (limit:", UNRELIABLE_PAYLOAD_LIMIT, ")")
        end
    end

    return true
end

--============================================================================
-- RESILIENT REMOTE FACTORY
--============================================================================

-- Try to create UnreliableRemoteEvent, fall back to RemoteEvent if it fails
local function createUnreliableOrFallback(name, parent)
    -- First, try UnreliableRemoteEvent
    local success, remote = pcall(function()
        local r = Instance.new("UnreliableRemoteEvent")
        r.Name = name
        r.Parent = parent
        return r
    end)

    if success and remote then
        return remote, false  -- false = did not fall back
    end

    -- Fallback to regular RemoteEvent
    warn("[Remotes] UnreliableRemoteEvent failed for", name, "- falling back to RemoteEvent")
    local fallbackRemote = Instance.new("RemoteEvent")
    fallbackRemote.Name = name
    fallbackRemote.Parent = parent
    return fallbackRemote, true  -- true = fell back
end

--============================================================================
-- SAFE REMOTE ACCESS
--============================================================================

-- Get a remote with optional waiting (use this for safe access)
function Remotes.GetRemote(eventName, timeout)
    timeout = timeout or 5

    -- Already have it?
    if Remotes.Events[eventName] then
        return Remotes.Events[eventName]
    end

    -- Wait for ready if not initialized yet
    if not Remotes.IsReady then
        local startTime = tick()
        while not Remotes.IsReady and (tick() - startTime) < timeout do
            task.wait(0.1)
        end
    end

    return Remotes.Events[eventName]
end

-- Get unreliable remote (or its fallback)
function Remotes.GetUnreliableRemote(eventName, timeout)
    timeout = timeout or 5

    if Remotes.UnreliableEvents[eventName] then
        return Remotes.UnreliableEvents[eventName]
    end

    if not Remotes.IsReady then
        local startTime = tick()
        while not Remotes.IsReady and (tick() - startTime) < timeout do
            task.wait(0.1)
        end
    end

    return Remotes.UnreliableEvents[eventName]
end

-- Wait until remotes are ready
function Remotes.WaitForReady(timeout)
    timeout = timeout or 10
    if Remotes.IsReady then return true end

    local startTime = tick()
    while not Remotes.IsReady and (tick() - startTime) < timeout do
        task.wait(0.1)
    end

    return Remotes.IsReady
end

--============================================================================
-- INITIALIZATION
--============================================================================

function Remotes.Init()
    local remotesFolder = ReplicatedStorage:FindFirstChild("Remotes")

    if RunService:IsServer() then
        -- Server: Create the folder and remotes
        if not remotesFolder then
            remotesFolder = Instance.new("Folder")
            remotesFolder.Name = "Remotes"
            remotesFolder.Parent = ReplicatedStorage
        end

        local eventsFolder = remotesFolder:FindFirstChild("Events")
        if not eventsFolder then
            eventsFolder = Instance.new("Folder")
            eventsFolder.Name = "Events"
            eventsFolder.Parent = remotesFolder
        end

        local functionsFolder = remotesFolder:FindFirstChild("Functions")
        if not functionsFolder then
            functionsFolder = Instance.new("Folder")
            functionsFolder.Name = "Functions"
            functionsFolder.Parent = remotesFolder
        end

        -- Create RemoteEvents
        for _, eventName in ipairs(Remotes.EventNames) do
            local remote = eventsFolder:FindFirstChild(eventName)
            if not remote then
                remote = Instance.new("RemoteEvent")
                remote.Name = eventName
                remote.Parent = eventsFolder
            end
            Remotes.Events[eventName] = remote
        end

        -- Create UnreliableRemoteEvents (with fallback)
        local unreliableFolder = remotesFolder:FindFirstChild("Unreliable")
        if not unreliableFolder then
            unreliableFolder = Instance.new("Folder")
            unreliableFolder.Name = "Unreliable"
            unreliableFolder.Parent = remotesFolder
        end

        for _, eventName in ipairs(Remotes.UnreliableEventNames) do
            local remote = unreliableFolder:FindFirstChild(eventName)
            local didFallback = false

            if not remote then
                remote, didFallback = createUnreliableOrFallback(eventName, unreliableFolder)
            end

            Remotes.UnreliableEvents[eventName] = remote
            if didFallback then
                Remotes.FallbackEvents[eventName] = true
            end
        end

        -- Create RemoteFunctions
        for _, funcName in ipairs(Remotes.FunctionNames) do
            local remote = functionsFolder:FindFirstChild(funcName)
            if not remote then
                remote = Instance.new("RemoteFunction")
                remote.Name = funcName
                remote.Parent = functionsFolder
            end
            Remotes.Functions[funcName] = remote
        end

        -- Mark as ready
        Remotes.IsReady = true
        Remotes.ReadyEvent:Fire()

        print("[Remotes] Server remotes initialized")
        if next(Remotes.FallbackEvents) then
            warn("[Remotes] Fallback events:", table.concat(
                (function() local t = {} for k in pairs(Remotes.FallbackEvents) do table.insert(t, k) end return t end)(),
                ", "
            ))
        end

    else
        -- Client: Wait for the folder and remotes
        remotesFolder = ReplicatedStorage:WaitForChild("Remotes", 10)
        if not remotesFolder then
            warn("[Remotes] Could not find Remotes folder!")
            return
        end

        local eventsFolder = remotesFolder:WaitForChild("Events", 5)
        local functionsFolder = remotesFolder:WaitForChild("Functions", 5)

        if not eventsFolder then
            warn("[Remotes] Could not find Events folder!")
            return
        end

        -- Get RemoteEvents
        for _, eventName in ipairs(Remotes.EventNames) do
            local remote = eventsFolder:WaitForChild(eventName, 5)
            if remote then
                Remotes.Events[eventName] = remote
            else
                warn("[Remotes] Missing event:", eventName)
            end
        end

        -- Get UnreliableRemoteEvents (or their fallbacks)
        local unreliableFolder = remotesFolder:WaitForChild("Unreliable", 5)
        if unreliableFolder then
            for _, eventName in ipairs(Remotes.UnreliableEventNames) do
                local remote = unreliableFolder:WaitForChild(eventName, 5)
                if remote then
                    Remotes.UnreliableEvents[eventName] = remote
                else
                    warn("[Remotes] Missing unreliable event:", eventName)
                end
            end
        else
            warn("[Remotes] Unreliable folder not found")
        end

        -- Get RemoteFunctions
        if functionsFolder then
            for _, funcName in ipairs(Remotes.FunctionNames) do
                local remote = functionsFolder:WaitForChild(funcName, 5)
                if remote then
                    Remotes.Functions[funcName] = remote
                else
                    warn("[Remotes] Missing function:", funcName)
                end
            end
        end

        -- Mark as ready
        Remotes.IsReady = true
        Remotes.ReadyEvent:Fire()

        print("[Remotes] Client remotes initialized")
    end
end

return Remotes
