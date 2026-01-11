--[[
    NexusBuilder.lua
    Creates the physical Nexus hub area

    The Nexus is the safe spawn zone where players:
    - Spawn when entering the game
    - Access portals to Realms, Vault, Pet Yard
    - Trade and socialize safely
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)

local NexusBuilder = {}

-- Nexus visual settings
local FLOOR_COLOR = Color3.fromRGB(60, 60, 70)
local FLOOR_MATERIAL = Enum.Material.SmoothPlastic
local WALL_COLOR = Color3.fromRGB(40, 40, 50)
local ACCENT_COLOR = Color3.fromRGB(100, 80, 180)  -- Purple accent

local nexusFolder = nil

--============================================================================
-- HELPER FUNCTIONS
--============================================================================

local function createPart(properties)
    local part = Instance.new("Part")
    part.Anchored = true
    part.CanCollide = properties.CanCollide ~= false
    part.CastShadow = properties.CastShadow ~= false
    part.Color = properties.Color or FLOOR_COLOR
    part.Material = properties.Material or FLOOR_MATERIAL
    part.Size = properties.Size or Vector3.new(4, 1, 4)
    part.CFrame = properties.CFrame or CFrame.new(0, 0, 0)
    part.Name = properties.Name or "NexusPart"
    part.Parent = properties.Parent or nexusFolder
    return part
end

--============================================================================
-- NEXUS CONSTRUCTION
--============================================================================

function NexusBuilder.BuildNexus()
    local center = Constants.Nexus.CENTER
    local radius = Constants.Nexus.FLOOR_RADIUS

    -- Create folder for all Nexus parts
    nexusFolder = Instance.new("Folder")
    nexusFolder.Name = "Nexus"
    nexusFolder.Parent = workspace

    -- Main circular floor (using a cylinder)
    local floor = Instance.new("Part")
    floor.Name = "NexusFloor"
    floor.Shape = Enum.PartType.Cylinder
    floor.Anchored = true
    floor.CanCollide = true
    floor.Size = Vector3.new(4, radius * 2, radius * 2)  -- Cylinder: Height, Diameter, Diameter
    floor.CFrame = CFrame.new(center) * CFrame.Angles(0, 0, math.rad(90))
    floor.Color = FLOOR_COLOR
    floor.Material = FLOOR_MATERIAL
    floor.TopSurface = Enum.SurfaceType.Smooth
    floor.BottomSurface = Enum.SurfaceType.Smooth
    floor.Parent = nexusFolder

    -- Outer ring accent
    local outerRing = Instance.new("Part")
    outerRing.Name = "OuterRing"
    outerRing.Shape = Enum.PartType.Cylinder
    outerRing.Anchored = true
    outerRing.CanCollide = true
    outerRing.Size = Vector3.new(2, (radius + 8) * 2, (radius + 8) * 2)
    outerRing.CFrame = CFrame.new(center + Vector3.new(0, -1.5, 0)) * CFrame.Angles(0, 0, math.rad(90))
    outerRing.Color = ACCENT_COLOR
    outerRing.Material = Enum.Material.Neon
    outerRing.Transparency = 0.3
    outerRing.Parent = nexusFolder

    -- Center platform (raised area)
    local centerPlatform = Instance.new("Part")
    centerPlatform.Name = "CenterPlatform"
    centerPlatform.Shape = Enum.PartType.Cylinder
    centerPlatform.Anchored = true
    centerPlatform.CanCollide = true
    centerPlatform.Size = Vector3.new(1, 30, 30)
    centerPlatform.CFrame = CFrame.new(center + Vector3.new(0, 0.5, 0)) * CFrame.Angles(0, 0, math.rad(90))
    centerPlatform.Color = Color3.fromRGB(80, 80, 90)
    centerPlatform.Material = FLOOR_MATERIAL
    centerPlatform.Parent = nexusFolder

    -- Spawn point marker (decorative)
    local spawnMarker = Instance.new("Part")
    spawnMarker.Name = "SpawnMarker"
    spawnMarker.Shape = Enum.PartType.Cylinder
    spawnMarker.Anchored = true
    spawnMarker.CanCollide = false
    spawnMarker.Size = Vector3.new(0.2, 10, 10)
    spawnMarker.CFrame = CFrame.new(center + Vector3.new(0, 0.6, 0)) * CFrame.Angles(0, 0, math.rad(90))
    spawnMarker.Color = Color3.fromRGB(150, 200, 255)
    spawnMarker.Material = Enum.Material.Neon
    spawnMarker.Transparency = 0.5
    spawnMarker.Parent = nexusFolder

    -- Build portal pedestals
    NexusBuilder.BuildPortalPedestals()

    -- Add ambient lighting
    NexusBuilder.AddLighting()

    -- Add invisible walls at edge to prevent falling off
    NexusBuilder.AddBoundaryWalls()

    print("[NexusBuilder] Nexus built at " .. tostring(center))
end

function NexusBuilder.BuildPortalPedestals()
    local center = Constants.Nexus.CENTER

    -- Realm Portal pedestal (North)
    local realmPos = center + Constants.Nexus.REALM_PORTAL_OFFSET
    NexusBuilder.CreatePedestal(realmPos, "RealmPortalPedestal", ACCENT_COLOR)

    -- Vault Portal pedestal (Southwest)
    local vaultPos = center + Constants.Nexus.VAULT_PORTAL_OFFSET
    NexusBuilder.CreatePedestal(vaultPos, "VaultPortalPedestal", Color3.fromRGB(255, 200, 50))

    -- Pet Yard Portal pedestal (Southeast)
    local petPos = center + Constants.Nexus.PET_YARD_PORTAL_OFFSET
    NexusBuilder.CreatePedestal(petPos, "PetYardPortalPedestal", Color3.fromRGB(100, 200, 100))
end

function NexusBuilder.CreatePedestal(position, name, accentColor)
    -- Base platform
    local pedestal = Instance.new("Part")
    pedestal.Name = name
    pedestal.Shape = Enum.PartType.Cylinder
    pedestal.Anchored = true
    pedestal.CanCollide = true
    pedestal.Size = Vector3.new(2, 20, 20)
    pedestal.CFrame = CFrame.new(position + Vector3.new(0, 1, 0)) * CFrame.Angles(0, 0, math.rad(90))
    pedestal.Color = Color3.fromRGB(50, 50, 60)
    pedestal.Material = FLOOR_MATERIAL
    pedestal.Parent = nexusFolder

    -- Glowing ring around pedestal
    local ring = Instance.new("Part")
    ring.Name = name .. "Ring"
    ring.Shape = Enum.PartType.Cylinder
    ring.Anchored = true
    ring.CanCollide = false
    ring.Size = Vector3.new(0.5, 22, 22)
    ring.CFrame = CFrame.new(position + Vector3.new(0, 2.1, 0)) * CFrame.Angles(0, 0, math.rad(90))
    ring.Color = accentColor
    ring.Material = Enum.Material.Neon
    ring.Transparency = 0.3
    ring.Parent = nexusFolder
end

function NexusBuilder.AddLighting()
    local center = Constants.Nexus.CENTER

    -- Central overhead light
    local mainLight = Instance.new("PointLight")
    mainLight.Name = "NexusMainLight"
    mainLight.Brightness = 2
    mainLight.Range = 150
    mainLight.Color = Color3.fromRGB(200, 200, 255)

    local lightPart = Instance.new("Part")
    lightPart.Name = "MainLightSource"
    lightPart.Anchored = true
    lightPart.CanCollide = false
    lightPart.Transparency = 1
    lightPart.Size = Vector3.new(1, 1, 1)
    lightPart.CFrame = CFrame.new(center + Vector3.new(0, 50, 0))
    lightPart.Parent = nexusFolder
    mainLight.Parent = lightPart

    -- Portal area lights
    local portalOffsets = {
        Constants.Nexus.REALM_PORTAL_OFFSET,
        Constants.Nexus.VAULT_PORTAL_OFFSET,
        Constants.Nexus.PET_YARD_PORTAL_OFFSET,
    }

    for i, offset in ipairs(portalOffsets) do
        local portalLight = Instance.new("PointLight")
        portalLight.Name = "PortalLight" .. i
        portalLight.Brightness = 1
        portalLight.Range = 30
        portalLight.Color = Color3.fromRGB(180, 150, 255)

        local portalLightPart = Instance.new("Part")
        portalLightPart.Name = "PortalLightSource" .. i
        portalLightPart.Anchored = true
        portalLightPart.CanCollide = false
        portalLightPart.Transparency = 1
        portalLightPart.Size = Vector3.new(1, 1, 1)
        portalLightPart.CFrame = CFrame.new(center + offset + Vector3.new(0, 20, 0))
        portalLightPart.Parent = nexusFolder
        portalLight.Parent = portalLightPart
    end
end

function NexusBuilder.AddBoundaryWalls()
    local center = Constants.Nexus.CENTER
    local radius = Constants.Nexus.FLOOR_RADIUS + 10

    -- Create invisible wall cylinder around the nexus
    -- Using 8 wall segments around the perimeter
    local wallHeight = 50
    local wallThickness = 4
    local segments = 16

    for i = 1, segments do
        local angle = (i - 1) * (2 * math.pi / segments)
        local x = center.X + math.cos(angle) * radius
        local z = center.Z + math.sin(angle) * radius

        local wall = Instance.new("Part")
        wall.Name = "BoundaryWall" .. i
        wall.Anchored = true
        wall.CanCollide = true
        wall.Transparency = 1  -- Invisible
        wall.Size = Vector3.new(wallThickness, wallHeight, radius * 2 * math.pi / segments + 2)
        wall.CFrame = CFrame.new(x, center.Y + wallHeight / 2, z) * CFrame.Angles(0, angle + math.pi / 2, 0)
        wall.Parent = nexusFolder
    end
end

--============================================================================
-- INITIALIZATION
--============================================================================

function NexusBuilder.Init()
    NexusBuilder.BuildNexus()
    print("[NexusBuilder] Initialized")
end

return NexusBuilder
