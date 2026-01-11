--[[
    PortalController.lua
    Client-side portal visuals and interaction

    Features:
    - Renders portal visuals (spinning effect) for all portal types
    - Shows "Press E to Enter" prompt when nearby
    - Handles E key press to enter portal
    - Supports different portal colors and labels
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local Remotes = require(Shared.Remotes)

local PortalController = {}

--============================================================================
-- PORTAL CONFIGURATION
--============================================================================

local PORTAL_RADIUS = 5
local PORTAL_HEIGHT = 12
local ROTATION_SPEED = 60  -- Degrees per second

-- Portal definitions (matches server PortalManager)
local PORTAL_DEFS = {
    RealmPortal = {
        Name = "REALM PORTAL",
        Offset = Constants.Nexus.REALM_PORTAL_OFFSET,
        Color = Color3.fromRGB(150, 80, 255),  -- Purple
        GlowColor = Color3.fromRGB(200, 120, 255),
        InNexus = true,
    },
    NexusPortal = {
        Name = "NEXUS",
        Position = Constants.Nexus.REALM_SPAWN_POS + Vector3.new(0, 0, -20),
        Color = Color3.fromRGB(100, 200, 255),  -- Cyan
        GlowColor = Color3.fromRGB(150, 230, 255),
        InNexus = false,
    },
    VaultPortal = {
        Name = "VAULT",
        Offset = Constants.Nexus.VAULT_PORTAL_OFFSET,
        Color = Color3.fromRGB(255, 200, 50),  -- Gold
        GlowColor = Color3.fromRGB(255, 230, 100),
        InNexus = true,
    },
    VaultExitPortal = {
        Name = "EXIT TO NEXUS",
        Position = nil,  -- Will be set dynamically from Constants
        Color = Color3.fromRGB(100, 200, 255),  -- Cyan
        GlowColor = Color3.fromRGB(150, 230, 255),
        InNexus = false,
        InVault = true,
    },
    PetYardPortal = {
        Name = "PET YARD",
        Offset = Constants.Nexus.PET_YARD_PORTAL_OFFSET,
        Color = Color3.fromRGB(100, 200, 100),  -- Green
        GlowColor = Color3.fromRGB(150, 255, 150),
        InNexus = true,
        Disabled = true,
        DisabledText = "Coming Soon",
    },
}

--============================================================================
-- STATE
--============================================================================

local portalVisuals = {}
local nearbyPortal = nil
local promptGui = nil
local promptText = nil
local promptStroke = nil

--============================================================================
-- HELPER FUNCTIONS
--============================================================================

local function getPortalPosition(portalDef)
    if portalDef.Position then
        return portalDef.Position
    elseif portalDef.InVault then
        -- Vault exit portal position
        return Constants.Vault.CENTER + Constants.Vault.EXIT_PORTAL_POS
    elseif portalDef.Offset then
        return Constants.Nexus.CENTER + portalDef.Offset
    end
    return Vector3.new(0, 0, 0)
end

--============================================================================
-- CREATE PORTAL VISUAL
--============================================================================

local function createPortalVisual(portalKey, portalDef)
    local position = getPortalPosition(portalDef)
    local color = portalDef.Color
    local glowColor = portalDef.GlowColor or color

    -- Container part
    local container = Instance.new("Part")
    container.Name = "Portal_" .. portalKey
    container.Size = Vector3.new(1, 1, 1)
    container.Position = position
    container.Anchored = true
    container.CanCollide = false
    container.Transparency = 1
    container.Parent = workspace

    -- Outer ring (torus-like effect using cylinder)
    local outerRing = Instance.new("Part")
    outerRing.Name = "OuterRing"
    outerRing.Shape = Enum.PartType.Cylinder
    outerRing.Size = Vector3.new(1, PORTAL_RADIUS * 2, PORTAL_RADIUS * 2)
    outerRing.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))
    outerRing.Anchored = true
    outerRing.CanCollide = false
    outerRing.Material = Enum.Material.Neon
    outerRing.Color = color
    outerRing.Transparency = portalDef.Disabled and 0.6 or 0.3
    outerRing.Parent = container

    -- Inner glow disc
    local innerDisc = Instance.new("Part")
    innerDisc.Name = "InnerDisc"
    innerDisc.Shape = Enum.PartType.Cylinder
    innerDisc.Size = Vector3.new(0.5, PORTAL_RADIUS * 1.8, PORTAL_RADIUS * 1.8)
    innerDisc.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))
    innerDisc.Anchored = true
    innerDisc.CanCollide = false
    innerDisc.Material = Enum.Material.Neon
    innerDisc.Color = glowColor
    innerDisc.Transparency = portalDef.Disabled and 0.8 or 0.5
    innerDisc.Parent = container

    -- Particle effect
    local particles = Instance.new("ParticleEmitter")
    particles.Name = "PortalParticles"
    particles.Color = ColorSequence.new(color)
    particles.LightEmission = 0.5
    particles.Size = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.5),
        NumberSequenceKeypoint.new(1, 0),
    })
    particles.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0),
        NumberSequenceKeypoint.new(1, 1),
    })
    particles.Lifetime = NumberRange.new(1, 2)
    particles.Rate = portalDef.Disabled and 5 or 20
    particles.Speed = NumberRange.new(2, 5)
    particles.SpreadAngle = Vector2.new(180, 180)
    particles.Parent = outerRing

    -- Point light
    local light = Instance.new("PointLight")
    light.Name = "PortalLight"
    light.Color = color
    light.Brightness = portalDef.Disabled and 1 or 2
    light.Range = 15
    light.Parent = outerRing

    -- Billboard label above portal
    local billboard = Instance.new("BillboardGui")
    billboard.Name = "PortalLabel"
    billboard.Size = UDim2.new(0, 150, 0, 50)
    billboard.StudsOffset = Vector3.new(0, PORTAL_HEIGHT / 2 + 2, 0)
    billboard.AlwaysOnTop = true
    billboard.Parent = container

    local label = Instance.new("TextLabel")
    label.Name = "Label"
    label.Size = UDim2.new(1, 0, 0.6, 0)
    label.Position = UDim2.new(0, 0, 0, 0)
    label.BackgroundTransparency = 1
    label.Text = portalDef.Name
    label.TextColor3 = color
    label.Font = Enum.Font.GothamBold
    label.TextSize = 18
    label.TextStrokeTransparency = 0.5
    label.TextStrokeColor3 = Color3.new(0, 0, 0)
    label.Parent = billboard

    -- "Coming Soon" sub-label for disabled portals
    if portalDef.Disabled and portalDef.DisabledText then
        local subLabel = Instance.new("TextLabel")
        subLabel.Name = "SubLabel"
        subLabel.Size = UDim2.new(1, 0, 0.4, 0)
        subLabel.Position = UDim2.new(0, 0, 0.6, 0)
        subLabel.BackgroundTransparency = 1
        subLabel.Text = portalDef.DisabledText
        subLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
        subLabel.Font = Enum.Font.Gotham
        subLabel.TextSize = 12
        subLabel.TextStrokeTransparency = 0.7
        subLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
        subLabel.Parent = billboard
    end

    return {
        Container = container,
        OuterRing = outerRing,
        InnerDisc = innerDisc,
        Position = position,
        Rotation = 0,
        PortalDef = portalDef,
        PortalKey = portalKey,
    }
end

--============================================================================
-- CREATE INTERACTION PROMPT
--============================================================================

local function createPromptGui()
    local playerGui = player:WaitForChild("PlayerGui")

    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "PortalPromptUI"
    screenGui.ResetOnSpawn = false
    screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screenGui.Enabled = false
    screenGui.Parent = playerGui

    local promptFrame = Instance.new("Frame")
    promptFrame.Name = "PromptFrame"
    promptFrame.Size = UDim2.new(0, 250, 0, 60)
    promptFrame.Position = UDim2.new(0.5, -125, 0.7, 0)
    promptFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
    promptFrame.BackgroundTransparency = 0.3
    promptFrame.BorderSizePixel = 0
    promptFrame.Parent = screenGui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 8)
    corner.Parent = promptFrame

    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(150, 80, 255)
    stroke.Thickness = 2
    stroke.Parent = promptFrame
    promptStroke = stroke

    local text = Instance.new("TextLabel")
    text.Name = "PromptText"
    text.Size = UDim2.new(1, 0, 1, 0)
    text.BackgroundTransparency = 1
    text.Text = "Press E to Enter"
    text.TextColor3 = Color3.fromRGB(255, 255, 255)
    text.Font = Enum.Font.GothamBold
    text.TextSize = 18
    text.Parent = promptFrame
    promptText = text

    return screenGui
end

local function updatePrompt(portalKey, portalDef)
    if not promptGui or not promptText or not promptStroke then return end

    promptStroke.Color = portalDef.Color

    if portalDef.Disabled then
        promptText.Text = portalDef.DisabledText or "Coming Soon"
    else
        promptText.Text = "Press E to Enter " .. portalDef.Name
    end
end

--============================================================================
-- DISTANCE CHECK
--============================================================================

local function getDistanceToPosition(targetPos)
    local character = player.Character
    if not character then return math.huge end

    local rootPart = character:FindFirstChild("HumanoidRootPart")
    if not rootPart then return math.huge end

    local playerPos = rootPart.Position
    return (Vector3.new(playerPos.X, 0, playerPos.Z) - Vector3.new(targetPos.X, 0, targetPos.Z)).Magnitude
end

--============================================================================
-- UPDATE LOOP
--============================================================================

local function update(deltaTime)
    -- Update portal rotations
    for name, visual in pairs(portalVisuals) do
        visual.Rotation = visual.Rotation + ROTATION_SPEED * deltaTime
        local rotRad = math.rad(visual.Rotation)

        -- Rotate the rings (slower for disabled portals)
        local speedMult = visual.PortalDef.Disabled and 0.3 or 1
        visual.OuterRing.CFrame = CFrame.new(visual.Position) *
            CFrame.Angles(rotRad * 0.5 * speedMult, rotRad * speedMult, math.rad(90))
        visual.InnerDisc.CFrame = CFrame.new(visual.Position) *
            CFrame.Angles(-rotRad * 0.3 * speedMult, -rotRad * 0.7 * speedMult, math.rad(90))
    end

    -- Check proximity to all portals
    local closestPortal = nil
    local closestDist = math.huge
    local interactRadius = Constants.Nexus.PORTAL_INTERACT_RADIUS

    for portalKey, visual in pairs(portalVisuals) do
        local dist = getDistanceToPosition(visual.Position)
        if dist <= interactRadius and dist < closestDist then
            closestDist = dist
            closestPortal = portalKey
        end
    end

    -- Update prompt visibility
    if closestPortal then
        if nearbyPortal ~= closestPortal then
            nearbyPortal = closestPortal
            local portalDef = portalVisuals[closestPortal].PortalDef
            updatePrompt(closestPortal, portalDef)
            if promptGui then
                promptGui.Enabled = true
            end
        end
    else
        if nearbyPortal then
            nearbyPortal = nil
            if promptGui then
                promptGui.Enabled = false
            end
        end
    end
end

--============================================================================
-- INPUT HANDLING
--============================================================================

local function onInputBegan(input, gameProcessed)
    if gameProcessed then return end

    if input.KeyCode == Enum.KeyCode.E then
        if nearbyPortal then
            Remotes.Events.EnterPortal:FireServer(nearbyPortal)
        end
    end
end

--============================================================================
-- INITIALIZATION
--============================================================================

function PortalController.Init()
    -- Wait for remotes
    Remotes.Init()

    -- Create portal visuals for all defined portals
    for portalKey, portalDef in pairs(PORTAL_DEFS) do
        portalVisuals[portalKey] = createPortalVisual(portalKey, portalDef)
        print("[PortalController] Created portal: " .. portalKey .. " at " .. tostring(getPortalPosition(portalDef)))
    end

    -- Create prompt UI
    promptGui = createPromptGui()

    -- Connect update loop
    RunService.RenderStepped:Connect(update)

    -- Connect input
    UserInputService.InputBegan:Connect(onInputBegan)

    print("[PortalController] Initialized with " .. #PORTAL_DEFS .. " portals")
end

return PortalController
