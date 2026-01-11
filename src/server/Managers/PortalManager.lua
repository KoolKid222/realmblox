--[[
    PortalManager.lua
    Handles portal teleportation between zones

    Portal Types:
    - Realm Portal: Nexus -> Realm (Beach zone)
    - Nexus Portal: Realm -> Nexus (return home)
    - Vault Portal: Nexus -> Personal Vault (placeholder)
    - Pet Yard Portal: Nexus -> Pet Yard (placeholder)

    Future:
    - Dungeon portals
    - Guild hall portals
    - etc.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local Remotes = require(Shared.Remotes)

-- Lazy load MovementValidator
local MovementValidator
local function getMovementValidator()
    if not MovementValidator then
        MovementValidator = require(script.Parent.MovementValidator)
    end
    return MovementValidator
end

local PortalManager = {}

-- Helper to get absolute position from offset
local function getNexusPortalPos(offset)
    return Constants.Nexus.CENTER + offset
end

--============================================================================
-- PORTAL DEFINITIONS
--============================================================================

PortalManager.Portals = {
    -- Nexus -> Realm (Beach)
    RealmPortal = {
        Name = "Realm Portal",
        Position = getNexusPortalPos(Constants.Nexus.REALM_PORTAL_OFFSET),
        Destination = Constants.Nexus.REALM_SPAWN_POS,
        DestinationZone = "Beach",
        InteractRadius = Constants.Nexus.PORTAL_INTERACT_RADIUS,
        Type = "realm",
        Color = Color3.fromRGB(150, 80, 255),  -- Purple
    },

    -- Realm -> Nexus (return home) - spawned dynamically in realm
    NexusPortal = {
        Name = "Nexus Portal",
        Position = Constants.Nexus.REALM_SPAWN_POS + Vector3.new(0, 0, -20),  -- Near realm spawn
        Destination = Constants.Nexus.CENTER + Constants.Nexus.SPAWN_OFFSET,
        DestinationZone = "Nexus",
        InteractRadius = Constants.Nexus.PORTAL_INTERACT_RADIUS,
        Type = "nexus",
        Color = Color3.fromRGB(100, 200, 255),  -- Cyan
    },

    -- Nexus -> Vault
    VaultPortal = {
        Name = "Vault",
        Position = getNexusPortalPos(Constants.Nexus.VAULT_PORTAL_OFFSET),
        Destination = Constants.Vault.CENTER + Constants.Vault.SPAWN_OFFSET,
        DestinationZone = "Vault",
        InteractRadius = Constants.Nexus.PORTAL_INTERACT_RADIUS,
        Type = "vault",
        Color = Color3.fromRGB(255, 200, 50),  -- Gold
        FacingDirection = Vector3.new(0, 0, 1),  -- Face +Z (towards chests)
    },

    -- Vault -> Nexus (exit portal in vault room)
    VaultExitPortal = {
        Name = "Exit to Nexus",
        Position = Constants.Vault.CENTER + Constants.Vault.EXIT_PORTAL_POS,
        Destination = Constants.Nexus.CENTER + Constants.Nexus.SPAWN_OFFSET,
        DestinationZone = "Nexus",
        InteractRadius = Constants.Nexus.PORTAL_INTERACT_RADIUS,
        Type = "nexus",
        Color = Color3.fromRGB(100, 200, 255),  -- Cyan
    },

    -- Nexus -> Pet Yard (placeholder)
    PetYardPortal = {
        Name = "Pet Yard",
        Position = getNexusPortalPos(Constants.Nexus.PET_YARD_PORTAL_OFFSET),
        Destination = nil,  -- Not implemented yet
        DestinationZone = "PetYard",
        InteractRadius = Constants.Nexus.PORTAL_INTERACT_RADIUS,
        Type = "petyard",
        Color = Color3.fromRGB(100, 200, 100),  -- Green
        Disabled = true,  -- Not yet implemented
    },
}

--============================================================================
-- PORTAL TELEPORTATION
--============================================================================

function PortalManager.TeleportPlayer(player, portalName)
    local portal = PortalManager.Portals[portalName]
    if not portal then
        warn("[PortalManager] Unknown portal: " .. tostring(portalName))
        return false, "Unknown portal"
    end

    -- Check if portal is disabled (not yet implemented)
    if portal.Disabled then
        return false, "Coming soon!"
    end

    -- Check if portal has a destination
    if not portal.Destination then
        return false, "Portal not available"
    end

    local character = player.Character
    if not character then
        return false, "No character"
    end

    local rootPart = character:FindFirstChild("HumanoidRootPart")
    if not rootPart then
        return false, "No character"
    end

    -- Check if player is near the portal
    local playerPos = rootPart.Position
    local portalPos = portal.Position
    local dist = (Vector3.new(playerPos.X, 0, playerPos.Z) - Vector3.new(portalPos.X, 0, portalPos.Z)).Magnitude

    if dist > portal.InteractRadius then
        warn("[PortalManager] Player " .. player.Name .. " too far from portal: " .. dist)
        return false, "Too far from portal"
    end

    -- Grant movement immunity before teleport
    getMovementValidator().GrantImmunity(player, 1.5)

    -- Teleport to destination with optional facing direction
    if portal.FacingDirection then
        local lookAt = portal.Destination + portal.FacingDirection
        rootPart.CFrame = CFrame.lookAt(portal.Destination, lookAt)
    else
        rootPart.CFrame = CFrame.new(portal.Destination)
    end

    -- Notify client of new zone (forces immediate zone indicator update)
    -- This is needed because client position may have replication delay
    task.defer(function()
        Remotes.Events.ZoneChanged:FireClient(player, {
            Zone = portal.DestinationZone or "Unknown",
            Position = portal.Destination,
        })
    end)

    -- print("[PortalManager] " .. player.Name .. " entered " .. portal.Name .. " -> " .. tostring(portal.Destination))

    return true
end

-- Check if player is near any portal
function PortalManager.GetNearbyPortal(player)
    local character = player.Character
    if not character then
        return nil
    end

    local rootPart = character:FindFirstChild("HumanoidRootPart")
    if not rootPart then
        return nil
    end

    local playerPos = rootPart.Position

    for portalName, portal in pairs(PortalManager.Portals) do
        local portalPos = portal.Position
        local dist = (Vector3.new(playerPos.X, 0, playerPos.Z) - Vector3.new(portalPos.X, 0, portalPos.Z)).Magnitude

        if dist <= portal.InteractRadius then
            return portalName, portal
        end
    end

    return nil
end

--============================================================================
-- INITIALIZATION
--============================================================================

function PortalManager.Init()
    -- Wait for Remotes to be ready (prevents race condition)
    if not Remotes.IsReady then
        Remotes.WaitForReady(5)
    end

    -- Handle portal entry requests (with safe access)
    local enterPortalRemote = Remotes.GetRemote("EnterPortal", 5)
    if enterPortalRemote then
        enterPortalRemote.OnServerEvent:Connect(function(player, portalName)
            -- Default to RealmPortal if not specified
            portalName = portalName or "RealmPortal"

            local success, errorMsg = PortalManager.TeleportPlayer(player, portalName)

            if not success then
                -- Notify client of failure with specific message
                local notificationRemote = Remotes.Events.Notification
                if notificationRemote then
                    notificationRemote:FireClient(player, {
                        Message = errorMsg or "Cannot enter portal",
                        Type = "error"
                    })
                end
            end
        end)
    else
        warn("[PortalManager] CRITICAL: EnterPortal remote not found!")
    end

    -- Count active portals
    local portalCount = 0
    local activeCount = 0
    for _, portal in pairs(PortalManager.Portals) do
        portalCount = portalCount + 1
        if not portal.Disabled then
            activeCount = activeCount + 1
        end
    end
    print("[PortalManager] Initialized with", activeCount, "/", portalCount, "active portal(s)")
end

return PortalManager
