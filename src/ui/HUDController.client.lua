--[[
    HUDController.client.lua
    Modern Roblox HUD - Right-side panel layout

    Features:
    - Right panel with minimap, stats, equipment, inventory
    - Modern card-based design with deep blue/purple theme
    - Clean GothamBold typography
    - Larger touch-friendly slots
]]

print("!!! HUDController script starting !!!")

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Check if UI already exists (StarterGui scripts re-run on respawn)
-- We need to destroy and recreate because old script's connections are gone
local existingHUD = playerGui:FindFirstChild("GameHUD")
local isRespawn = existingHUD ~= nil
if existingHUD then
    print("[HUDController] Respawn detected - destroying old HUD to recreate with fresh connections...")
    existingHUD:Destroy()
end

-- Debug logs disabled for cleaner console

-- Load shared modules early
local Shared = ReplicatedStorage:WaitForChild("Shared")
-- print("[HUDController] Found Shared folder")

local ItemDatabase = require(Shared.ItemDatabase)
local ClassDatabase = require(Shared.ClassDatabase)
local Constants = require(Shared.Constants)
local UIUtils = require(Shared.UIUtils)
-- print("[HUDController] Loaded shared modules")

-- Lazy-load InventoryController to avoid circular dependency
local InventoryController = nil
local function getInventoryController()
    if not InventoryController then
        local success, result = pcall(function()
            return require(player:WaitForChild("PlayerScripts"):WaitForChild("Client"):WaitForChild("Controllers"):WaitForChild("InventoryController"))
        end)
        if success then
            InventoryController = result
        end
    end
    return InventoryController
end

--============================================================================
-- STYLE CONSTANTS (Modern Roblox Theme)
--============================================================================
local COLORS = {
    -- Panel backgrounds - deep blue/purple gradient feel
    PANEL_BG = Color3.fromRGB(25, 28, 40),
    PANEL_SECONDARY = Color3.fromRGB(35, 40, 55),
    PANEL_BORDER = Color3.fromRGB(70, 80, 110),

    -- Health/Mana bars - vibrant but not harsh
    HP_BAR = Color3.fromRGB(235, 85, 75),
    HP_BAR_BG = Color3.fromRGB(50, 30, 35),
    MP_BAR = Color3.fromRGB(75, 130, 235),
    MP_BAR_BG = Color3.fromRGB(30, 40, 60),
    XP_BAR = Color3.fromRGB(255, 200, 80),
    XP_BAR_BG = Color3.fromRGB(50, 45, 30),

    -- Text colors
    TEXT = Color3.fromRGB(255, 255, 255),
    TEXT_SECONDARY = Color3.fromRGB(170, 175, 190),
    TEXT_GOLD = Color3.fromRGB(255, 210, 100),
    TEXT_GREEN = Color3.fromRGB(100, 230, 130),
    TEXT_YELLOW = Color3.fromRGB(255, 230, 100),  -- For maxed stats

    -- Slots - cleaner look
    SLOT_BG = Color3.fromRGB(40, 45, 60),
    SLOT_BORDER = Color3.fromRGB(80, 90, 120),
    SLOT_EMPTY = Color3.fromRGB(30, 35, 48),
    SLOT_HOVER = Color3.fromRGB(55, 65, 90),

    -- Accent colors
    ACCENT = Color3.fromRGB(130, 100, 220),
    ACCENT_LIGHT = Color3.fromRGB(160, 140, 240),
}

-- Backwards compatibility aliases
COLORS.TEXT_GRAY = COLORS.TEXT_SECONDARY

local FONT = Enum.Font.GothamBold
local FONT_SECONDARY = Enum.Font.Gotham
local PANEL_WIDTH = 220
local PANEL_PADDING = 10
local CORNER_RADIUS = 8

--============================================================================
-- UI SCALING SYSTEM
-- Base design is for 1080p - scales up for higher resolutions
--============================================================================

local UI_SCALE do
    local viewportY = workspace.CurrentCamera.ViewportSize.Y
    UI_SCALE = math.clamp(viewportY / 1080, 0.8, 2.0)
end

--============================================================================
-- CREATE MAIN SCREEN GUI
--============================================================================

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "GameHUD"
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.IgnoreGuiInset = true
screenGui.Parent = player:WaitForChild("PlayerGui")
-- print("[HUDController] Created GameHUD ScreenGui")

--============================================================================
-- FPS COUNTER (Top left, debug display) - Wrapped in do block to limit locals
--============================================================================

do
    local FPS_SAMPLE_SIZE = 100
    local frameTimes, frameIndex, lastTime, updateCounter, cachedOnePercentLow = {}, 0, tick(), 0, 0
    local ProjectileRenderer = nil

    local fpsFrame = Instance.new("Frame")
    fpsFrame.Name = "FPSCounter"
    fpsFrame.Size = UDim2.new(0, 140, 0, 65)
    fpsFrame.Position = UDim2.new(0, 10, 0, 60)
    fpsFrame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    fpsFrame.BackgroundTransparency = 0.5
    fpsFrame.BorderSizePixel = 0
    fpsFrame.Parent = screenGui

    Instance.new("UIScale", fpsFrame).Scale = UI_SCALE
    Instance.new("UICorner", fpsFrame).CornerRadius = UDim.new(0, 4)

    local function makeLabel(name, yPos, color, text)
        local label = Instance.new("TextLabel")
        label.Name = name
        label.Size = UDim2.new(1, -8, 0, 14)
        label.Position = UDim2.new(0, 4, 0, yPos)
        label.BackgroundTransparency = 1
        label.Font = Enum.Font.Code
        label.TextSize = 12
        label.TextColor3 = color
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.Text = text
        label.Parent = fpsFrame
        return label
    end

    local fpsLabel = makeLabel("FPSLabel", 2, Color3.fromRGB(0, 255, 0), "FPS: --")
    fpsLabel.TextSize = 14
    local lowsLabel = makeLabel("LowsLabel", 18, Color3.fromRGB(255, 200, 100), "1% Low: --")
    local frameTimeLabel = makeLabel("FrameTimeLabel", 34, Color3.fromRGB(150, 150, 255), "Frame: -- ms")
    local projCountLabel = makeLabel("ProjCountLabel", 48, Color3.fromRGB(200, 200, 200), "Proj: --")

    task.spawn(function()
        local Controllers = player:WaitForChild("PlayerScripts"):WaitForChild("Client"):WaitForChild("Controllers")
        ProjectileRenderer = require(Controllers:WaitForChild("ProjectileRenderer"))
    end)

    RunService.RenderStepped:Connect(function()
        local currentTime = tick()
        local deltaTime = currentTime - lastTime
        lastTime = currentTime

        frameIndex = (frameIndex % FPS_SAMPLE_SIZE) + 1
        frameTimes[frameIndex] = deltaTime
        updateCounter = updateCounter + 1

        local currentFPS = math.floor(1 / deltaTime + 0.5)

        if #frameTimes >= FPS_SAMPLE_SIZE and updateCounter % 30 == 0 then
            local maxTime = 0
            for i = 1, FPS_SAMPLE_SIZE do
                if frameTimes[i] > maxTime then maxTime = frameTimes[i] end
            end
            cachedOnePercentLow = math.floor(1 / maxTime + 0.5)
        end

        fpsLabel.Text = "FPS: " .. currentFPS
        lowsLabel.Text = "1% Low: " .. (cachedOnePercentLow > 0 and cachedOnePercentLow or "--")
        frameTimeLabel.Text = string.format("Frame: %.1f ms", deltaTime * 1000)
        projCountLabel.Text = "Proj: " .. (ProjectileRenderer and ProjectileRenderer.GetActiveCount and ProjectileRenderer.GetActiveCount() or "--")
    end)
end  -- End FPS counter scope

--============================================================================
-- ZONE INDICATOR (Top center of screen)
--============================================================================

local zoneIndicator = Instance.new("TextLabel")
zoneIndicator.Name = "ZoneIndicator"
zoneIndicator.Size = UDim2.new(0, 300, 0, 40)
zoneIndicator.Position = UDim2.new(0.5, -150, 0, 20)
zoneIndicator.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
zoneIndicator.BackgroundTransparency = 0.5
zoneIndicator.BorderSizePixel = 0
zoneIndicator.Font = Enum.Font.GothamBold
zoneIndicator.Text = "BEACH"
zoneIndicator.TextColor3 = Color3.fromRGB(255, 220, 150)
zoneIndicator.TextSize = 24
zoneIndicator.Parent = screenGui

local _, zoneStroke = UIUtils.styleFrame(zoneIndicator, {
    cornerRadius = 8,
    strokeColor = Color3.fromRGB(139, 90, 43),
    strokeThickness = 2
})

-- Zone colors for visual feedback
local ZONE_COLORS = {
    Nexus = {text = Color3.fromRGB(150, 80, 255), border = Color3.fromRGB(100, 50, 180)},
    Vault = {text = Color3.fromRGB(255, 215, 0), border = Color3.fromRGB(180, 140, 40)},
    Beach = {text = Color3.fromRGB(255, 220, 150), border = Color3.fromRGB(139, 90, 43)},
    Lowlands = {text = Color3.fromRGB(150, 255, 150), border = Color3.fromRGB(60, 120, 60)},
    Midlands = {text = Color3.fromRGB(150, 200, 255), border = Color3.fromRGB(60, 100, 150)},
    Godlands = {text = Color3.fromRGB(255, 100, 100), border = Color3.fromRGB(150, 50, 50)},
}

local currentZone = "Beach"

local function updateZoneIndicator(zoneName)
    if zoneName == currentZone then return end
    currentZone = zoneName

    zoneIndicator.Text = string.upper(zoneName)

    local colors = ZONE_COLORS[zoneName] or ZONE_COLORS.Beach
    zoneIndicator.TextColor3 = colors.text
    zoneStroke.Color = colors.border

    -- Flash effect on zone change
    local originalTransparency = zoneIndicator.BackgroundTransparency
    zoneIndicator.BackgroundTransparency = 0.2
    TweenService:Create(zoneIndicator, TweenInfo.new(0.5), {
        BackgroundTransparency = originalTransparency
    }):Play()
end

-- Determine zone based on position (same logic as server)
local function getZoneAtPosition(position)
    -- Check if in Nexus safe zone first
    local nexusCenter = Constants.Nexus.CENTER
    local nexusSafeRadius = Constants.Nexus.SAFE_RADIUS
    local distFromNexus = math.sqrt(
        (position.X - nexusCenter.X)^2 +
        (position.Z - nexusCenter.Z)^2
    )

    if distFromNexus < nexusSafeRadius then
        return "Nexus"
    end

    -- Otherwise use realm zone logic (Manhattan distance from realm center)
    local distFromCenter = math.abs(position.X) + math.abs(position.Z)

    if distFromCenter > 300 then
        return "Beach"
    elseif distFromCenter > 150 then
        return "Midlands"
    else
        return "Godlands"
    end
end

--============================================================================
-- RIGHT PANEL (Main HUD Container)
--============================================================================

local rightPanel = Instance.new("Frame")
rightPanel.Name = "RightPanel"
rightPanel.Size = UDim2.new(0, PANEL_WIDTH, 1, -20)
rightPanel.Position = UDim2.new(1, -10, 0, 10)
rightPanel.AnchorPoint = Vector2.new(1, 0)  -- Anchor to right edge
rightPanel.BackgroundColor3 = COLORS.PANEL_BG
rightPanel.BackgroundTransparency = 0.15
rightPanel.BorderSizePixel = 0
rightPanel.Parent = screenGui

-- Apply UI scaling to the entire panel
Instance.new("UIScale", rightPanel).Scale = UI_SCALE

UIUtils.styleFrame(rightPanel, {
    cornerRadius = 8,
    strokeColor = COLORS.PANEL_BORDER,
    strokeThickness = 1
})

-- Content container with padding
local panelContent = Instance.new("Frame")
panelContent.Name = "Content"
panelContent.Size = UDim2.new(1, -PANEL_PADDING * 2, 1, -PANEL_PADDING * 2)
panelContent.Position = UDim2.new(0, PANEL_PADDING, 0, PANEL_PADDING)
panelContent.BackgroundTransparency = 1
panelContent.Parent = rightPanel

--============================================================================
-- MINIMAP (Top of panel) - RotMG Style with Biome Rendering
--============================================================================

local WorldGen = require(Shared.WorldGen)
local BiomeData = require(Shared.BiomeData)
local BiomeCache = require(Shared.BiomeCache)

local MINIMAP_SIZE = 140  -- Base design size (actual size comes from AbsoluteSize with UI scaling)
local MINIMAP_PIXEL_SIZE = 4                    -- Size of each "pixel" in the minimap (larger = less lag)
-- Grid size: visible cells + large buffer on ALL sides for smooth scrolling (extra buffer for UI scaling)
local MINIMAP_VISIBLE_CELLS = math.floor(MINIMAP_SIZE / MINIMAP_PIXEL_SIZE)  -- 35
local MINIMAP_GRID_SIZE = MINIMAP_VISIBLE_CELLS + 40  -- 75 cells (larger buffer for UI scaling)
-- Half-grid symmetric (center cell is at HALF_GRID position)
local MINIMAP_HALF_GRID = math.floor(MINIMAP_GRID_SIZE / 2)  -- Symmetric: 37

-- Zoom levels: studs per pixel (lower = more zoomed in)
local MINIMAP_ZOOM_LEVELS = {4, 8, 16, 32, 64}  -- Different zoom scales (studs per pixel)
local MINIMAP_ZOOM_INDEX = 2                     -- Start at zoom level 8
local MINIMAP_SCALE = MINIMAP_ZOOM_LEVELS[MINIMAP_ZOOM_INDEX]

-- Map-centered threshold (when fully zoomed out, center on map instead of player)
local MAP_CENTER = Vector3.new(0, 0, 0)
local MAP_CENTERED_ZOOM_INDEX = #MINIMAP_ZOOM_LEVELS  -- Last zoom level is map-centered

-- Minimap colors (RotMG style) for entities
local MINIMAP_COLORS = {
    PLAYER = Color3.fromRGB(50, 130, 255),      -- Blue (self)
    OTHER_PLAYER = Color3.fromRGB(255, 255, 0), -- Yellow (others)
    ENEMY = Color3.fromRGB(255, 0, 0),          -- Red
    LOOT = Color3.fromRGB(0, 255, 255),         -- Cyan
    PORTAL = Color3.fromRGB(128, 0, 255),       -- Purple
    OCEAN = Color3.fromRGB(20, 50, 80),         -- Deep blue for out-of-bounds
    OTHER = Color3.fromRGB(200, 200, 200),
    -- Zone-specific colors
    NEXUS_FLOOR = Color3.fromRGB(60, 60, 70),
    NEXUS_CENTER = Color3.fromRGB(80, 80, 90),
    NEXUS_ACCENT = Color3.fromRGB(100, 80, 180),
    NEXUS_OUTSIDE = Color3.fromRGB(15, 15, 25),
    VAULT_TILE_1 = Color3.fromRGB(65, 65, 75),
    VAULT_TILE_2 = Color3.fromRGB(85, 85, 95),
    VAULT_OUTSIDE = Color3.fromRGB(15, 15, 25),
    PORTAL_REALM = Color3.fromRGB(150, 80, 255),
    PORTAL_VAULT = Color3.fromRGB(255, 200, 50),
    PORTAL_PET = Color3.fromRGB(100, 200, 100),
    PORTAL_EXIT = Color3.fromRGB(100, 200, 255),
    CHEST_MARKER = Color3.fromRGB(139, 90, 43),
}

-- Zone constants for minimap
local ZONE_REALM = "Realm"
local ZONE_NEXUS = "Nexus"
local ZONE_VAULT = "Vault"

-- Detect which zone the player is in based on position
local function detectMinimapZone(position)
    -- Check Nexus (circular area)
    local nexusCenter = Constants.Nexus.CENTER
    local nexusRadius = Constants.Nexus.SAFE_RADIUS
    local dxN = position.X - nexusCenter.X
    local dzN = position.Z - nexusCenter.Z
    if (dxN * dxN + dzN * dzN) < (nexusRadius * nexusRadius) then
        return ZONE_NEXUS
    end

    -- Check Vault (rectangular area)
    local vaultCenter = Constants.Vault.CENTER
    local vaultSize = Constants.Vault.FLOOR_SIZE
    if math.abs(position.X - vaultCenter.X) < (vaultSize.X / 2 + 20) and
       math.abs(position.Z - vaultCenter.Z) < (vaultSize.Z / 2 + 20) then
        return ZONE_VAULT
    end

    -- Default to Realm
    return ZONE_REALM
end

local minimapFrame = Instance.new("Frame")
minimapFrame.Name = "Minimap"
minimapFrame.Size = UDim2.new(1, 0, 0, MINIMAP_SIZE)
minimapFrame.Position = UDim2.new(0, 0, 0, 0)
minimapFrame.BackgroundColor3 = MINIMAP_COLORS.OCEAN  -- Match ocean color to hide any edge gaps
minimapFrame.BorderSizePixel = 0
minimapFrame.ClipsDescendants = true
minimapFrame.Active = false  -- Don't capture keyboard input (allows E key for loot)
minimapFrame.Parent = panelContent

UIUtils.styleFrame(minimapFrame, {
    cornerRadius = 6,
    strokeColor = COLORS.PANEL_BORDER,
    strokeThickness = 1
})

-- Subtle inner vignette for polished edge appearance
local vignetteOverlay = Instance.new("Frame")
vignetteOverlay.Name = "Vignette"
vignetteOverlay.Size = UDim2.new(1, 0, 1, 0)
vignetteOverlay.BackgroundTransparency = 1
vignetteOverlay.BorderSizePixel = 0
vignetteOverlay.ZIndex = 18  -- Above dots but below UI elements
vignetteOverlay.Parent = minimapFrame

-- Inner shadow stroke for depth
local vignetteStroke = Instance.new("UIStroke")
vignetteStroke.Color = Color3.fromRGB(0, 0, 0)
vignetteStroke.Thickness = 3
vignetteStroke.Transparency = 0.7
vignetteStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
vignetteStroke.Parent = vignetteOverlay

local vignetteCorner = Instance.new("UICorner")
vignetteCorner.CornerRadius = UDim.new(0, 6)
vignetteCorner.Parent = vignetteOverlay

-- Ground layer container (holds the pixel grid)
local groundLayer = Instance.new("Frame")
groundLayer.Name = "GroundLayer"
-- Make it larger than the view to allow scrolling
groundLayer.Size = UDim2.new(0, MINIMAP_GRID_SIZE * MINIMAP_PIXEL_SIZE, 0, MINIMAP_GRID_SIZE * MINIMAP_PIXEL_SIZE)
groundLayer.BackgroundColor3 = MINIMAP_COLORS.OCEAN
groundLayer.BorderSizePixel = 0
groundLayer.ZIndex = 1
groundLayer.ClipsDescendants = false -- Don't clip inside, we clip at minimapFrame
groundLayer.Active = false  -- Don't capture input
groundLayer.Parent = minimapFrame

-- No corner radius on groundLayer itself since it scrolls

-- Create pixel grid for terrain rendering
local minimapPixels = {}
for row = 0, MINIMAP_GRID_SIZE - 1 do
    minimapPixels[row] = {}
    for col = 0, MINIMAP_GRID_SIZE - 1 do
        local pixel = Instance.new("Frame")
        pixel.Name = "Pixel_" .. row .. "_" .. col
        pixel.Size = UDim2.new(0, MINIMAP_PIXEL_SIZE, 0, MINIMAP_PIXEL_SIZE)
        pixel.Position = UDim2.new(0, col * MINIMAP_PIXEL_SIZE, 0, row * MINIMAP_PIXEL_SIZE)
        pixel.BackgroundColor3 = MINIMAP_COLORS.OCEAN
        pixel.BorderSizePixel = 0
        pixel.ZIndex = 2
        pixel.Parent = groundLayer
        minimapPixels[row][col] = pixel
    end
end

-- Dots container (for enemies, loot, players) - world-aligned (same coords as groundLayer)
local dotsContainer = Instance.new("Frame")
dotsContainer.Name = "DotsContainer"
dotsContainer.Size = UDim2.new(1, 0, 1, 0)
dotsContainer.Position = UDim2.new(0, 0, 0, 0)
dotsContainer.AnchorPoint = Vector2.new(0, 0)  -- Top-left anchor
dotsContainer.BackgroundTransparency = 1
dotsContainer.ZIndex = 3  -- Above groundLayer (ZIndex 1-2)
dotsContainer.ClipsDescendants = true  -- Clip dots outside minimap bounds
dotsContainer.Active = false  -- Don't capture input
dotsContainer.Parent = minimapFrame

-- Player indicator (custom icon pointing in camera direction)
local playerDot = Instance.new("ImageLabel")
playerDot.Name = "PlayerIndicator"
playerDot.Size = UDim2.new(0, 40, 0, 40)
playerDot.Position = UDim2.new(0, 70, 0, 70)  -- Center of minimap (updated dynamically)
playerDot.AnchorPoint = Vector2.new(0.5, 0.5)  -- Rotate around center
playerDot.BackgroundTransparency = 1
playerDot.Image = "rbxassetid://125225694269539"  -- Custom player icon
playerDot.Rotation = 0  -- Will be updated based on camera direction
playerDot.ZIndex = 10  -- Always on top
playerDot.Parent = dotsContainer

-- Compass indicator (shows North at top-left)
local compassFrame = Instance.new("Frame")
compassFrame.Name = "Compass"
compassFrame.Size = UDim2.new(0, 20, 0, 20)
compassFrame.Position = UDim2.new(0, 6, 0, 6)
compassFrame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
compassFrame.BackgroundTransparency = 0.5
compassFrame.BorderSizePixel = 0
compassFrame.ZIndex = 15
compassFrame.Parent = minimapFrame

local compassCorner = Instance.new("UICorner")
compassCorner.CornerRadius = UDim.new(1, 0)
compassCorner.Parent = compassFrame

local compassLabel = Instance.new("TextLabel")
compassLabel.Name = "N"
compassLabel.Size = UDim2.new(1, 0, 1, 0)
compassLabel.BackgroundTransparency = 1
compassLabel.Font = Enum.Font.GothamBold
compassLabel.Text = "N"
compassLabel.TextColor3 = Color3.fromRGB(255, 100, 100)
compassLabel.TextSize = 12
compassLabel.ZIndex = 16
compassLabel.Parent = compassFrame

-- Zoom label (polished styling)
local zoomLabel = Instance.new("TextLabel")
zoomLabel.Name = "ZoomLabel"
zoomLabel.Size = UDim2.new(0, 36, 0, 18)
zoomLabel.Position = UDim2.new(1, -42, 1, -24)
zoomLabel.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
zoomLabel.BackgroundTransparency = 0.4
zoomLabel.BorderSizePixel = 0
zoomLabel.Font = Enum.Font.GothamBold
zoomLabel.Text = MINIMAP_SCALE .. "x"
zoomLabel.TextColor3 = Color3.new(1, 1, 1)
zoomLabel.TextSize = 11
zoomLabel.ZIndex = 15
zoomLabel.Parent = minimapFrame

local zoomCorner = Instance.new("UICorner")
zoomCorner.CornerRadius = UDim.new(0, 4)
zoomCorner.Parent = zoomLabel

local zoomStroke = Instance.new("UIStroke")
zoomStroke.Color = Color3.fromRGB(80, 80, 80)
zoomStroke.Thickness = 1
zoomStroke.Transparency = 0.5
zoomStroke.Parent = zoomLabel

-- Check if at max zoom (map-centered mode)
local function isMapCentered()
    return MINIMAP_ZOOM_INDEX >= MAP_CENTERED_ZOOM_INDEX
end

-- Calculate the world range visible on the minimap (uses actual frame size for UI scaling)
local function getMinimapRange()
    local frameSize = minimapFrame.AbsoluteSize
    local minDim = math.min(frameSize.X, frameSize.Y)
    return (minDim * MINIMAP_SCALE) / (2 * MINIMAP_PIXEL_SIZE)
end

-- Zoom functions
local function updateZoom()
    MINIMAP_SCALE = MINIMAP_ZOOM_LEVELS[MINIMAP_ZOOM_INDEX]

    -- Update zoom label to show mode
    if isMapCentered() then
        zoomLabel.Text = "MAP"
    else
        zoomLabel.Text = tostring(MINIMAP_SCALE) .. "x"
    end
end

local function zoomIn()
    if MINIMAP_ZOOM_INDEX > 1 then
        MINIMAP_ZOOM_INDEX = MINIMAP_ZOOM_INDEX - 1
        updateZoom()
    end
end

local function zoomOut()
    if MINIMAP_ZOOM_INDEX < #MINIMAP_ZOOM_LEVELS then
        MINIMAP_ZOOM_INDEX = MINIMAP_ZOOM_INDEX + 1
        updateZoom()
    end
end

-- Track if mouse is over minimap
local isMouseOverMinimap = false

-- Invisible button for mouse detection
local minimapHoverDetector = Instance.new("TextButton")
minimapHoverDetector.Name = "HoverDetector"
minimapHoverDetector.Size = UDim2.new(1, 0, 1, 0)
minimapHoverDetector.BackgroundTransparency = 1
minimapHoverDetector.Text = ""
minimapHoverDetector.ZIndex = 20
minimapHoverDetector.Parent = minimapFrame

minimapHoverDetector.MouseEnter:Connect(function()
    isMouseOverMinimap = true
end)

minimapHoverDetector.MouseLeave:Connect(function()
    isMouseOverMinimap = false
end)

-- Mouse wheel zoom when hovering
local UserInputService = game:GetService("UserInputService")
UserInputService.InputChanged:Connect(function(input, gameProcessed)
    if input.UserInputType == Enum.UserInputType.MouseWheel and isMouseOverMinimap then
        if input.Position.Z > 0 then
            zoomIn()  -- Scroll up = zoom in (smaller scale = closer view)
        else
            zoomOut()  -- Scroll down = zoom out (larger scale = wider view)
        end
    end
end)

-- Dot pool for efficient reuse
local dotPool = {}
local activeDots = {}

local function getDot()
    local dot = table.remove(dotPool)
    if not dot then
        dot = Instance.new("Frame")
        dot.BorderSizePixel = 0
        dot.ZIndex = 5
        dot.Parent = dotsContainer

        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(1, 0)
        corner.Parent = dot

        -- Add subtle dark outline for visibility on any terrain
        local dotStroke = Instance.new("UIStroke")
        dotStroke.Name = "Outline"
        dotStroke.Color = Color3.fromRGB(0, 0, 0)
        dotStroke.Thickness = 1
        dotStroke.Transparency = 0.3
        dotStroke.Parent = dot
    end
    dot.Size = UDim2.new(0, 5, 0, 5)  -- Slightly larger for visibility
    dot.Visible = true
    return dot
end

local function returnDot(dot)
    dot.Visible = false
    table.insert(dotPool, dot)
end

local function clearAllDots()
    for _, dot in ipairs(activeDots) do
        returnDot(dot)
    end
    activeDots = {}
end

-- Convert world position to minimap pixel position (uses actual frame size for UI scaling)
-- centerPos is either player position (zoomed in) or map center (zoomed out)
local function worldToMinimap(worldPos, centerPos)
    local frameSize = minimapFrame.AbsoluteSize
    local dx = worldPos.X - centerPos.X
    local dz = worldPos.Z - centerPos.Z

    -- Scale to minimap coordinates (pixels) using actual frame center
    local mapX = (dx / MINIMAP_SCALE) * MINIMAP_PIXEL_SIZE + (frameSize.X * 0.5)
    local mapY = (dz / MINIMAP_SCALE) * MINIMAP_PIXEL_SIZE + (frameSize.Y * 0.5)

    return mapX, mapY
end

-- Check if position is within minimap range
local function isInRange(worldPos, centerPos)
    local range = getMinimapRange()
    local dx = math.abs(worldPos.X - centerPos.X)
    local dz = math.abs(worldPos.Z - centerPos.Z)
    return dx < range and dz < range
end

-- State tracking for optimization
local lastSnapX, lastSnapZ = nil, nil
local lastScale = nil
local lastZone = nil  -- Track current zone for cache invalidation

-- Render Realm minimap using BiomeCache
local function renderRealmMinimap(snapX, snapZ)
    if not BiomeCache.IsReady() then return end

    for row = 0, MINIMAP_GRID_SIZE - 1 do
        for col = 0, MINIMAP_GRID_SIZE - 1 do
            local worldX = snapX + (col - MINIMAP_HALF_GRID) * MINIMAP_SCALE
            local worldZ = snapZ + (row - MINIMAP_HALF_GRID) * MINIMAP_SCALE
            minimapPixels[row][col].BackgroundColor3 = BiomeCache.GetBiomeColor(worldX, worldZ)
        end
    end
end

-- Render Nexus minimap (circular floor with accent ring)
local function renderNexusMinimap(snapX, snapZ)
    local nexusCenter = Constants.Nexus.CENTER
    local floorRadius = Constants.Nexus.FLOOR_RADIUS

    for row = 0, MINIMAP_GRID_SIZE - 1 do
        for col = 0, MINIMAP_GRID_SIZE - 1 do
            local worldX = snapX + (col - MINIMAP_HALF_GRID) * MINIMAP_SCALE
            local worldZ = snapZ + (row - MINIMAP_HALF_GRID) * MINIMAP_SCALE

            local dx = worldX - nexusCenter.X
            local dz = worldZ - nexusCenter.Z
            local distSq = dx * dx + dz * dz

            local color
            if distSq < (floorRadius * floorRadius) then
                -- Inside floor - center platform vs main floor
                if distSq < (15 * 15) then
                    color = MINIMAP_COLORS.NEXUS_CENTER
                else
                    color = MINIMAP_COLORS.NEXUS_FLOOR
                end
            elseif distSq < ((floorRadius + 8) * (floorRadius + 8)) then
                -- Outer ring accent
                color = MINIMAP_COLORS.NEXUS_ACCENT
            else
                -- Outside Nexus
                color = MINIMAP_COLORS.NEXUS_OUTSIDE
            end

            minimapPixels[row][col].BackgroundColor3 = color
        end
    end
end

-- Render Vault minimap (checkered floor)
local function renderVaultMinimap(snapX, snapZ)
    local vaultCenter = Constants.Vault.CENTER
    local floorSize = Constants.Vault.FLOOR_SIZE
    local tileSize = Constants.Vault.TILE_SIZE
    local halfX, halfZ = floorSize.X / 2, floorSize.Z / 2

    for row = 0, MINIMAP_GRID_SIZE - 1 do
        for col = 0, MINIMAP_GRID_SIZE - 1 do
            local worldX = snapX + (col - MINIMAP_HALF_GRID) * MINIMAP_SCALE
            local worldZ = snapZ + (row - MINIMAP_HALF_GRID) * MINIMAP_SCALE

            local dx = worldX - vaultCenter.X
            local dz = worldZ - vaultCenter.Z

            local color
            if math.abs(dx) < halfX and math.abs(dz) < halfZ then
                -- Inside floor - checkered pattern
                local tileX = math.floor((dx + halfX) / tileSize)
                local tileZ = math.floor((dz + halfZ) / tileSize)
                local isEven = (tileX + tileZ) % 2 == 0
                color = isEven and MINIMAP_COLORS.VAULT_TILE_1 or MINIMAP_COLORS.VAULT_TILE_2
            else
                -- Outside Vault
                color = MINIMAP_COLORS.VAULT_OUTSIDE
            end

            minimapPixels[row][col].BackgroundColor3 = color
        end
    end
end

-- Update minimap terrain pixels - dispatches to zone-specific renderer
local function updateMinimapTerrain(snapX, snapZ, forceUpdate, currentZone)
    -- Skip if grid hasn't moved, scale hasn't changed, and zone is the same
    if not forceUpdate and snapX == lastSnapX and snapZ == lastSnapZ
       and MINIMAP_SCALE == lastScale and currentZone == lastZone then
        return
    end

    lastSnapX = snapX
    lastSnapZ = snapZ
    lastScale = MINIMAP_SCALE
    lastZone = currentZone

    -- Dispatch to zone-specific renderer
    if currentZone == ZONE_NEXUS then
        renderNexusMinimap(snapX, snapZ)
    elseif currentZone == ZONE_VAULT then
        renderVaultMinimap(snapX, snapZ)
    else
        renderRealmMinimap(snapX, snapZ)
    end
end

-- Add Nexus portal markers as dots
local function addNexusPortalDots(centerPos)
    local frameSize = minimapFrame.AbsoluteSize
    local nexusCenter = Constants.Nexus.CENTER
    local portals = {
        {offset = Constants.Nexus.REALM_PORTAL_OFFSET, color = MINIMAP_COLORS.PORTAL_REALM},
        {offset = Constants.Nexus.VAULT_PORTAL_OFFSET, color = MINIMAP_COLORS.PORTAL_VAULT},
        {offset = Constants.Nexus.PET_YARD_PORTAL_OFFSET, color = MINIMAP_COLORS.PORTAL_PET},
    }

    for _, p in ipairs(portals) do
        local pos = nexusCenter + p.offset
        if isInRange(pos, centerPos) then
            local mapX, mapY = worldToMinimap(pos, centerPos)
            if mapX >= 0 and mapX <= frameSize.X and mapY >= 0 and mapY <= frameSize.Y then
                local dot = getDot()
                dot.Size = UDim2.new(0, 8, 0, 8)
                dot.Position = UDim2.new(0, mapX - 4, 0, mapY - 4)
                dot.BackgroundColor3 = p.color
                table.insert(activeDots, dot)
            end
        end
    end
end

-- Add Vault markers (exit portal and chest positions)
local function addVaultMarkerDots(centerPos)
    local frameSize = minimapFrame.AbsoluteSize
    local vaultCenter = Constants.Vault.CENTER

    -- Exit portal
    local exitPos = vaultCenter + Constants.Vault.EXIT_PORTAL_POS
    if isInRange(exitPos, centerPos) then
        local mapX, mapY = worldToMinimap(exitPos, centerPos)
        if mapX >= 0 and mapX <= frameSize.X and mapY >= 0 and mapY <= frameSize.Y then
            local dot = getDot()
            dot.Size = UDim2.new(0, 8, 0, 8)
            dot.Position = UDim2.new(0, mapX - 4, 0, mapY - 4)
            dot.BackgroundColor3 = MINIMAP_COLORS.PORTAL_EXIT
            table.insert(activeDots, dot)
        end
    end

    -- Chest markers (only at zoomed-in levels to avoid clutter)
    if MINIMAP_SCALE <= 8 then
        local grid = Constants.Vault.CHEST_GRID
        local startPos = vaultCenter + grid.startOffset

        for r = 0, grid.rows - 1 do
            for c = 0, grid.columns - 1 do
                local chestPos = startPos + Vector3.new(c * grid.spacingX, 0, r * grid.spacingZ)
                if isInRange(chestPos, centerPos) then
                    local mapX, mapY = worldToMinimap(chestPos, centerPos)
                    if mapX >= 0 and mapX <= frameSize.X and mapY >= 0 and mapY <= frameSize.Y then
                        local dot = getDot()
                        dot.Size = UDim2.new(0, 4, 0, 4)
                        dot.Position = UDim2.new(0, mapX - 2, 0, mapY - 2)
                        dot.BackgroundColor3 = MINIMAP_COLORS.CHEST_MARKER
                        table.insert(activeDots, dot)
                    end
                end
            end
        end
    end
end

-- Add other player dots (used in all zones)
local function addOtherPlayerDots(centerPos)
    local frameSize = minimapFrame.AbsoluteSize
    for _, otherPlayer in ipairs(Players:GetPlayers()) do
        if otherPlayer ~= player and otherPlayer.Character then
            local otherRoot = otherPlayer.Character:FindFirstChild("HumanoidRootPart")
            if otherRoot then
                local otherPos = otherRoot.Position
                if isInRange(otherPos, centerPos) then
                    local mapX, mapY = worldToMinimap(otherPos, centerPos)
                    if mapX >= 0 and mapX <= frameSize.X and mapY >= 0 and mapY <= frameSize.Y then
                        local dot = getDot()
                        dot.Position = UDim2.new(0, mapX - 2, 0, mapY - 2)
                        dot.BackgroundColor3 = MINIMAP_COLORS.OTHER_PLAYER
                        table.insert(activeDots, dot)
                    end
                end
            end
        end
    end
end

-- Main minimap update function
local camera = workspace.CurrentCamera

local function updateMinimap()
    local character = player.Character
    if not character then return end

    local rootPart = character:FindFirstChild("HumanoidRootPart")
    if not rootPart then return end

    local playerPos = rootPart.Position

    -- Detect current zone based on player position
    local currentZone = detectMinimapZone(playerPos)

    -- Determine center based on zoom mode and zone
    local mapCentered = isMapCentered()
    local centerPos

    if mapCentered then
        -- When fully zoomed out, center on the appropriate zone
        if currentZone == ZONE_NEXUS then
            centerPos = Constants.Nexus.CENTER
        elseif currentZone == ZONE_VAULT then
            centerPos = Constants.Vault.CENTER
        else
            centerPos = MAP_CENTER
        end
    else
        centerPos = playerPos
    end

    -- Get actual frame size (accounts for UI scaling)
    local frameSize = minimapFrame.AbsoluteSize
    local centerX = frameSize.X * 0.5
    local centerY = frameSize.Y * 0.5

    -- Calculate grid snapping for smooth scrolling
    local snapX = math.floor(centerPos.X / MINIMAP_SCALE) * MINIMAP_SCALE
    local snapZ = math.floor(centerPos.Z / MINIMAP_SCALE) * MINIMAP_SCALE

    -- Calculate offset for smooth scrolling (in pixels)
    local offsetX = (centerPos.X - snapX) / MINIMAP_SCALE * MINIMAP_PIXEL_SIZE
    local offsetZ = (centerPos.Z - snapZ) / MINIMAP_SCALE * MINIMAP_PIXEL_SIZE

    -- Position ground layer with smooth scrolling using actual frame center
    -- Center cell sits at MINIMAP_HALF_GRID position in groundLayer (in pixels)
    local cellCenterPx = MINIMAP_HALF_GRID * MINIMAP_PIXEL_SIZE
    -- Place ground so center cell aligns to minimap frame center
    groundLayer.Position = UDim2.fromOffset(
        centerX - cellCenterPx - offsetX,
        centerY - cellCenterPx - offsetZ
    )

    -- Update terrain pixels with zone context
    updateMinimapTerrain(snapX, snapZ, false, currentZone)

    -- Update player indicator position and rotation using actual frame size
    if mapCentered then
        local playerMapX, playerMapY = worldToMinimap(playerPos, centerPos)
        playerMapX = math.clamp(playerMapX, 6, frameSize.X - 6)
        playerMapY = math.clamp(playerMapY, 6, frameSize.Y - 6)
        playerDot.Position = UDim2.fromOffset(playerMapX, playerMapY)
    else
        -- Player centered - use actual frame center
        playerDot.Position = UDim2.fromOffset(centerX, centerY)
    end

    -- Rotate arrow to point in camera direction
    local lookVector = camera.CFrame.LookVector
    local angle = math.atan2(-lookVector.X, -lookVector.Z)
    playerDot.Rotation = -math.deg(angle)  -- Negated for correct rotation direction

    -- Clear previous dots
    clearAllDots()

    -- Zone-specific dot rendering
    if currentZone == ZONE_NEXUS then
        -- Nexus: Show portal markers and other players
        addNexusPortalDots(centerPos)
        addOtherPlayerDots(centerPos)

    elseif currentZone == ZONE_VAULT then
        -- Vault: Show exit portal, chest markers, and other players
        addVaultMarkerDots(centerPos)
        addOtherPlayerDots(centerPos)

    else
        -- Realm: Show enemies, loot, portals, and other players
        local enemyFolder = workspace:FindFirstChild("Enemies")
        if enemyFolder then
            for _, enemy in ipairs(enemyFolder:GetChildren()) do
                local enemyPos = nil
                if enemy:IsA("Model") then
                    if enemy.PrimaryPart then
                        enemyPos = enemy.PrimaryPart.Position
                    else
                        local body = enemy:FindFirstChild("Body")
                        if body then
                            enemyPos = body.Position
                        end
                    end
                elseif enemy:IsA("BasePart") then
                    enemyPos = enemy.Position
                end

                if enemyPos and isInRange(enemyPos, centerPos) then
                    local mapX, mapY = worldToMinimap(enemyPos, centerPos)
                    if mapX >= 0 and mapX <= frameSize.X and mapY >= 0 and mapY <= frameSize.Y then
                        local dot = getDot()
                        dot.Position = UDim2.new(0, mapX - 2, 0, mapY - 2)
                        dot.BackgroundColor3 = MINIMAP_COLORS.ENEMY
                        table.insert(activeDots, dot)
                    end
                end
            end
        end

        local lootFolder = workspace:FindFirstChild("LootBags")
        if lootFolder then
            for _, lootPart in ipairs(lootFolder:GetChildren()) do
                local lootPos = lootPart.Position
                if lootPart:IsA("BasePart") and isInRange(lootPos, centerPos) then
                    local mapX, mapY = worldToMinimap(lootPos, centerPos)
                    if mapX >= 0 and mapX <= frameSize.X and mapY >= 0 and mapY <= frameSize.Y then
                        local dot = getDot()
                        dot.Position = UDim2.new(0, mapX - 2, 0, mapY - 2)
                        dot.BackgroundColor3 = MINIMAP_COLORS.LOOT
                        table.insert(activeDots, dot)
                    end
                end
            end
        end

        local portalFolder = workspace:FindFirstChild("Portals")
        if portalFolder then
            for _, portal in ipairs(portalFolder:GetChildren()) do
                local portalPos = nil
                if portal:IsA("Model") and portal.PrimaryPart then
                    portalPos = portal.PrimaryPart.Position
                elseif portal:IsA("BasePart") then
                    portalPos = portal.Position
                end

                if portalPos and isInRange(portalPos, centerPos) then
                    local mapX, mapY = worldToMinimap(portalPos, centerPos)
                    if mapX >= 0 and mapX <= frameSize.X and mapY >= 0 and mapY <= frameSize.Y then
                        local dot = getDot()
                        dot.Size = UDim2.new(0, 6, 0, 6)
                        dot.Position = UDim2.new(0, mapX - 3, 0, mapY - 3)
                        dot.BackgroundColor3 = MINIMAP_COLORS.PORTAL
                        table.insert(activeDots, dot)
                    end
                end
            end
        end

        addOtherPlayerDots(centerPos)
    end
end

--============================================================================
-- CHARACTER INFO (Below minimap)
--============================================================================

local yOffset = 148

-- Character name and level row
local charInfoFrame = Instance.new("Frame")
charInfoFrame.Name = "CharInfo"
charInfoFrame.Size = UDim2.new(1, 0, 0, 40)
charInfoFrame.Position = UDim2.new(0, 0, 0, yOffset)
charInfoFrame.BackgroundTransparency = 1
charInfoFrame.Parent = panelContent

local charName = Instance.new("TextLabel")
charName.Name = "CharName"
charName.Size = UDim2.new(1, 0, 0, 20)
charName.Position = UDim2.new(0, 0, 0, 0)
charName.BackgroundTransparency = 1
charName.Font = FONT
charName.Text = "WIZARD"
charName.TextColor3 = COLORS.TEXT
charName.TextSize = 14
charName.TextXAlignment = Enum.TextXAlignment.Left
charName.Parent = charInfoFrame

local levelLabel = Instance.new("TextLabel")
levelLabel.Name = "Level"
levelLabel.Size = UDim2.new(1, 0, 0, 16)
levelLabel.Position = UDim2.new(0, 0, 0, 20)
levelLabel.BackgroundTransparency = 1
levelLabel.Font = FONT
levelLabel.Text = "Lvl 1"
levelLabel.TextColor3 = COLORS.TEXT_GRAY
levelLabel.TextSize = 12
levelLabel.TextXAlignment = Enum.TextXAlignment.Left
levelLabel.Parent = charInfoFrame

yOffset = yOffset + 45

--============================================================================
-- HP / MP / XP BARS
--============================================================================

local function createStatBar(parent, name, yPos, barColor, bgColor, height)
    local container = Instance.new("Frame")
    container.Name = name .. "Container"
    container.Size = UDim2.new(1, 0, 0, height)
    container.Position = UDim2.new(0, 0, 0, yPos)
    container.BackgroundColor3 = bgColor
    container.BorderSizePixel = 0
    container.Parent = parent

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 3)
    corner.Parent = container

    local fill = Instance.new("Frame")
    fill.Name = "Fill"
    fill.Size = UDim2.new(1, 0, 1, 0)
    fill.BackgroundColor3 = barColor
    fill.BorderSizePixel = 0
    fill.Parent = container

    local fillCorner = Instance.new("UICorner")
    fillCorner.CornerRadius = UDim.new(0, 3)
    fillCorner.Parent = fill

    local label = Instance.new("TextLabel")
    label.Name = "Label"
    label.Size = UDim2.new(1, 0, 1, 0)
    label.BackgroundTransparency = 1
    label.Font = FONT
    label.Text = name
    label.TextColor3 = COLORS.TEXT
    label.TextSize = 11
    label.ZIndex = 2
    label.Parent = container

    return container, fill, label
end

-- HP Bar
local hpContainer, hpFill, hpLabel = createStatBar(panelContent, "HP", yOffset, COLORS.HP_BAR, COLORS.HP_BAR_BG, 18)
yOffset = yOffset + 22

-- MP Bar
local mpContainer, mpFill, mpLabel = createStatBar(panelContent, "MP", yOffset, COLORS.MP_BAR, COLORS.MP_BAR_BG, 18)
yOffset = yOffset + 22

-- XP Bar (thinner)
local xpContainer, xpFill, xpLabel = createStatBar(panelContent, "XP", yOffset, COLORS.XP_BAR, COLORS.XP_BAR_BG, 10)
xpLabel.TextSize = 8
xpLabel.Text = ""
yOffset = yOffset + 18

--============================================================================
-- HELPER: Create section header with line
--============================================================================

local function createSectionHeader(parent, text, yPos)
    local container = Instance.new("Frame")
    container.Name = text .. "Header"
    container.Size = UDim2.new(1, 0, 0, 16)
    container.Position = UDim2.new(0, 0, 0, yPos)
    container.BackgroundTransparency = 1
    container.Parent = parent

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(0, 50, 1, 0)
    label.BackgroundTransparency = 1
    label.Font = FONT
    label.Text = text
    label.TextColor3 = COLORS.TEXT_SECONDARY
    label.TextSize = 11
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = container

    local line = Instance.new("Frame")
    line.Size = UDim2.new(1, -55, 0, 1)
    line.Position = UDim2.new(0, 55, 0.5, 0)
    line.BackgroundColor3 = COLORS.SLOT_BORDER
    line.BorderSizePixel = 0
    line.Parent = container

    return container
end

--============================================================================
-- STATS GRID (ATT, DEF, SPD, DEX, VIT, WIS)
--============================================================================

createSectionHeader(panelContent, "STATS", yOffset)
yOffset = yOffset + 20

local statsFrame = Instance.new("Frame")
statsFrame.Name = "StatsGrid"
statsFrame.Size = UDim2.new(1, 0, 0, 36)
statsFrame.Position = UDim2.new(0, 0, 0, yOffset)
statsFrame.BackgroundTransparency = 1
statsFrame.Parent = panelContent

local statLabels = {}
local statNames = {"ATT", "DEF", "SPD", "DEX", "VIT", "WIS"}

for i, statName in ipairs(statNames) do
    local col = (i - 1) % 3
    local row = math.floor((i - 1) / 3)

    local statLabel = Instance.new("TextLabel")
    statLabel.Name = statName
    statLabel.Size = UDim2.new(0.33, -2, 0, 16)
    statLabel.Position = UDim2.new(col * 0.33, 0, 0, row * 18)
    statLabel.BackgroundTransparency = 1
    statLabel.Font = FONT
    statLabel.Text = statName .. " - 0"
    statLabel.TextColor3 = COLORS.TEXT_SECONDARY
    statLabel.TextSize = 11
    statLabel.TextXAlignment = Enum.TextXAlignment.Left
    statLabel.Parent = statsFrame

    statLabels[statName] = statLabel
end

yOffset = yOffset + 44

--============================================================================
-- EQUIPMENT SLOTS (4 slots with labels below)
--============================================================================

local SLOT_SIZE = 42
local SLOT_GAP = 6

createSectionHeader(panelContent, "EQUIPMENT", yOffset)
yOffset = yOffset + 20

local equipFrame = Instance.new("Frame")
equipFrame.Name = "Equipment"
equipFrame.Size = UDim2.new(1, 0, 0, SLOT_SIZE + 14)
equipFrame.Position = UDim2.new(0, 0, 0, yOffset)
equipFrame.BackgroundTransparency = 1
equipFrame.Parent = panelContent

local equipSlots = {}
local equipNames = {"Weapon", "Ability", "Armor", "Ring"}
local totalWidth = 4 * SLOT_SIZE + 3 * SLOT_GAP
local startX = 0  -- Left aligned

for i, slotName in ipairs(equipNames) do
    local slot = Instance.new("Frame")
    slot.Name = slotName
    slot.Size = UDim2.new(0, SLOT_SIZE, 0, SLOT_SIZE)
    slot.Position = UDim2.new(0, startX + (i - 1) * (SLOT_SIZE + SLOT_GAP), 0, 0)
    slot.BackgroundColor3 = COLORS.SLOT_BG
    slot.BorderSizePixel = 0
    slot.Parent = equipFrame

    Instance.new("UICorner", slot).CornerRadius = UDim.new(0, 4)
    Instance.new("UIStroke", slot).Color = COLORS.SLOT_BORDER

    -- Label below slot
    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(0, SLOT_SIZE, 0, 12)
    label.Position = UDim2.new(0, startX + (i - 1) * (SLOT_SIZE + SLOT_GAP), 0, SLOT_SIZE + 2)
    label.BackgroundTransparency = 1
    label.Font = FONT_SECONDARY
    label.Text = slotName
    label.TextColor3 = COLORS.TEXT_SECONDARY
    label.TextSize = 8
    label.Parent = equipFrame

    equipSlots[slotName] = slot
end

yOffset = yOffset + SLOT_SIZE + 20

--============================================================================
-- INVENTORY GRID (8 slots, 4x2)
--============================================================================

createSectionHeader(panelContent, "INVENTORY", yOffset)
yOffset = yOffset + 20

local invFrame = Instance.new("Frame")
invFrame.Name = "Inventory"
invFrame.Size = UDim2.new(1, 0, 0, SLOT_SIZE * 2 + SLOT_GAP)
invFrame.Position = UDim2.new(0, 0, 0, yOffset)
invFrame.BackgroundTransparency = 1
invFrame.Parent = panelContent

local invSlots = UIUtils.createGrid(invFrame, {
    numSlots = 8,
    columns = 4,
    slotSize = SLOT_SIZE,
    gap = SLOT_GAP,
    slotColor = COLORS.SLOT_BG,
    borderColor = COLORS.SLOT_BORDER,
    cornerRadius = 4,
    namePrefix = "Slot",
    showNumbers = false,
})

yOffset = yOffset + SLOT_SIZE * 2 + SLOT_GAP + 10

--============================================================================
-- POTIONS DISPLAY (HP/MP pot count)
--============================================================================

local potFrame = Instance.new("Frame")
potFrame.Name = "Potions"
potFrame.Size = UDim2.new(1, 0, 0, 20)
potFrame.Position = UDim2.new(0, 0, 0, yOffset)
potFrame.BackgroundTransparency = 1
potFrame.Parent = panelContent

local hpPotLabel = Instance.new("TextLabel")
hpPotLabel.Name = "HPPots"
hpPotLabel.Size = UDim2.new(0.5, 0, 1, 0)
hpPotLabel.BackgroundTransparency = 1
hpPotLabel.Font = FONT
hpPotLabel.Text = "❤ 6/6"
hpPotLabel.TextColor3 = COLORS.HP_BAR
hpPotLabel.TextSize = 12
hpPotLabel.TextXAlignment = Enum.TextXAlignment.Left
hpPotLabel.Parent = potFrame

local mpPotLabel = Instance.new("TextLabel")
mpPotLabel.Name = "MPPots"
mpPotLabel.Size = UDim2.new(0.5, 0, 1, 0)
mpPotLabel.Position = UDim2.new(0.5, 0, 0, 0)
mpPotLabel.BackgroundTransparency = 1
mpPotLabel.Font = FONT
mpPotLabel.Text = "💧 6/6"
mpPotLabel.TextColor3 = COLORS.MP_BAR
mpPotLabel.TextSize = 12
mpPotLabel.TextXAlignment = Enum.TextXAlignment.Left
mpPotLabel.Parent = potFrame

--============================================================================
-- LOOT BAG / VAULT UI (Slides up from bottom of panel when near loot or vault)
--============================================================================

local isLootVisible = false
local currentLootBag = nil

-- Vault mode tracking
local lootUISource = nil  -- "loot" or "vault"
local currentVaultChest = nil

local lootFrame = Instance.new("Frame")
lootFrame.Name = "LootBag"
lootFrame.Size = UDim2.new(1, 0, 0, 120)
lootFrame.AnchorPoint = Vector2.new(0, 1)  -- Anchor at bottom-left
lootFrame.Position = UDim2.new(0, 0, 1, 130)  -- Start below panel (hidden, 130px past bottom)
lootFrame.BackgroundColor3 = Color3.fromRGB(35, 30, 20)
lootFrame.BorderSizePixel = 0
lootFrame.Visible = false
lootFrame.ClipsDescendants = true
lootFrame.ZIndex = 10  -- Render above other panel content
lootFrame.Parent = panelContent

local _, lootStroke = UIUtils.styleFrame(lootFrame, {
    cornerRadius = 6,
    strokeColor = Color3.fromRGB(139, 90, 43),
    strokeThickness = 2
})

local lootTitle = Instance.new("TextLabel")
lootTitle.Name = "Title"
lootTitle.Size = UDim2.new(1, 0, 0, 20)
lootTitle.Position = UDim2.new(0, 0, 0, 4)
lootTitle.BackgroundTransparency = 1
lootTitle.Font = FONT
lootTitle.Text = "LOOT BAG"
lootTitle.TextColor3 = COLORS.TEXT_GOLD
lootTitle.TextSize = 12
lootTitle.Parent = lootFrame

-- Loot grid container (offset by 8px from left, 26px from top)
local lootGridContainer = Instance.new("Frame")
lootGridContainer.Name = "LootGridContainer"
lootGridContainer.Size = UDim2.new(1, -16, 0, 90)
lootGridContainer.Position = UDim2.new(0, 8, 0, 26)
lootGridContainer.BackgroundTransparency = 1
lootGridContainer.Parent = lootFrame

local lootSlots = UIUtils.createGrid(lootGridContainer, {
    numSlots = 8,
    columns = 4,
    slotSize = 38,
    gap = 6,
    slotColor = COLORS.SLOT_BG,
    borderColor = COLORS.SLOT_BORDER,
    cornerRadius = 4,
    namePrefix = "LootSlot"
})

--============================================================================
-- UPDATE FUNCTIONS
--============================================================================

local function updateHP(current, max)
    local ratio = math.clamp(current / math.max(max, 1), 0, 1)
    hpFill.Size = UDim2.new(ratio, 0, 1, 0)
    hpLabel.Text = string.format("%d/%d", current, max)
end

local function updateMP(current, max)
    local ratio = math.clamp(current / math.max(max, 1), 0, 1)
    mpFill.Size = UDim2.new(ratio, 0, 1, 0)
    mpLabel.Text = string.format("%d/%d", current, max)
end

local function updateXP(current, needed)
    local ratio = math.clamp(current / math.max(needed, 1), 0, 1)
    xpFill.Size = UDim2.new(ratio, 0, 1, 0)
end

-- Track current class for stat cap checking
local currentClass = "Wizard"

local function updateLevel(level, className)
    charName.Text = string.upper(className or "WIZARD")
    levelLabel.Text = "Lvl " .. (level or 1)
    if className then
        currentClass = className  -- Update current class for stat cap checking
    end
end

local function updateStats(stats)
    if not stats then return end

    local statMap = {
        ATT = "Attack",
        DEF = "Defense",
        SPD = "Speed",
        DEX = "Dexterity",
        VIT = "Vitality",
        WIS = "Wisdom"
    }

    for shortName, fullName in pairs(statMap) do
        local label = statLabels[shortName]
        if label and stats[fullName] then
            local statValue = stats[fullName]
            label.Text = shortName .. " - " .. tostring(statValue)

            -- Check if stat is maxed (yellow if at cap)
            local cap = ClassDatabase.GetStatCap(currentClass, fullName)
            if cap and statValue >= cap then
                label.TextColor3 = COLORS.TEXT_YELLOW
            else
                label.TextColor3 = COLORS.TEXT_GRAY
            end
        end
    end
end

--============================================================================
-- ITEM DISPLAY HELPER
--============================================================================

local RARITY_COLORS = {
    Common = Color3.fromRGB(180, 180, 180),
    Uncommon = Color3.fromRGB(100, 255, 100),
    Rare = Color3.fromRGB(100, 180, 255),
    Epic = Color3.fromRGB(200, 100, 255),
    Legendary = Color3.fromRGB(255, 215, 0),
}

local function createItemDisplay(slot, itemId)
    -- Clear existing display
    local existing = slot:FindFirstChild("ItemDisplay")
    if existing then
        existing:Destroy()
    end

    -- Clear ItemId attribute if no item
    if not itemId then
        slot:SetAttribute("ItemId", nil)
        return
    end

    local item = ItemDatabase.GetItem(itemId)
    if not item then
        slot:SetAttribute("ItemId", nil)
        return
    end

    local display = Instance.new("Frame")
    display.Name = "ItemDisplay"
    display.Size = UDim2.new(1, -4, 1, -4)
    display.Position = UDim2.new(0, 2, 0, 2)
    display.BackgroundColor3 = RARITY_COLORS[item.Rarity] or RARITY_COLORS.Common
    display.BackgroundTransparency = 0.3
    display.BorderSizePixel = 0
    display.Parent = slot

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 4)
    corner.Parent = display

    local tierLabel = Instance.new("TextLabel")
    tierLabel.Name = "Tier"
    tierLabel.Size = UDim2.new(1, 0, 1, 0)
    tierLabel.BackgroundTransparency = 1
    tierLabel.Font = Enum.Font.GothamBold
    tierLabel.Text = "T" .. (item.Tier or 0)
    tierLabel.TextColor3 = Color3.new(1, 1, 1)
    tierLabel.TextSize = 12
    tierLabel.TextStrokeTransparency = 0.5
    tierLabel.Parent = display

    slot:SetAttribute("ItemId", itemId)
end

--============================================================================
-- LOOT UI FUNCTIONS
--============================================================================

-- Track active loot bags and their items
local lootBagItems = {} -- [bagId] = {itemId, itemId, ...}

-- Track vault chest items (temporary while viewing)
local vaultChestItems = {} -- {itemId, itemId, ...} for current vault chest

local function updateLootSlots()
    local items = {}

    if lootUISource == "vault" then
        -- Vault mode: use vault chest items
        items = vaultChestItems or {}
    else
        -- Loot mode: use loot bag items
        local bagId = currentLootBag and currentLootBag:GetAttribute("BagId")
        items = bagId and lootBagItems[bagId] or {}
    end

    -- Update each loot slot
    for i, slot in ipairs(lootSlots) do
        local itemId = items[i]
        createItemDisplay(slot, itemId)
    end
end

local function showLootUI(lootBag)
    -- print("[HUD Loot] showLootUI called, bag:", lootBag.Name, "already visible:", isLootVisible)
    if isLootVisible and currentLootBag == lootBag and lootUISource == "loot" then return end

    -- Set loot mode
    lootUISource = "loot"
    currentVaultChest = nil
    currentLootBag = lootBag
    isLootVisible = true
    lootFrame.Visible = true

    -- Update title for loot bag
    lootTitle.Text = "LOOT BAG"
    lootTitle.TextColor3 = Color3.fromRGB(200, 150, 80)
    lootStroke.Color = Color3.fromRGB(139, 90, 43)

    -- print("[HUD Loot] Showing loot UI for bag:", lootBag:GetAttribute("BagId"))

    -- Update slot displays
    updateLootSlots()

    -- Notify InventoryController about current loot bag
    local bagId = lootBag:GetAttribute("BagId")
    local items = bagId and lootBagItems[bagId] or {}
    local invController = getInventoryController()
    if invController then
        invController.SetCurrentLootBag(bagId, items)
        invController.SetCurrentVaultChest(nil)  -- Clear vault mode
    end

    lootFrame.Position = UDim2.new(0, 0, 1, 130)  -- Start below panel (hidden)
    TweenService:Create(lootFrame, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
        Position = UDim2.new(0, 0, 1, 0)  -- Slide up to bottom of panel
    }):Play()
end

-- Show vault chest UI (reuses loot UI)
local function showVaultUI(chestIndex, contents)
    -- print("[HUD Vault] showVaultUI called, chest:", chestIndex)

    -- Set vault mode
    lootUISource = "vault"
    currentVaultChest = chestIndex
    currentLootBag = nil
    vaultChestItems = contents or {}
    isLootVisible = true
    lootFrame.Visible = true

    -- Update title for vault
    lootTitle.Text = "VAULT CHEST " .. chestIndex
    lootTitle.TextColor3 = COLORS.TEXT_GOLD
    lootStroke.Color = Color3.fromRGB(180, 140, 40)

    -- Update slot displays
    updateLootSlots()

    -- Notify InventoryController about current vault chest
    local invController = getInventoryController()
    if invController then
        invController.ClearCurrentLootBag()  -- Clear loot mode
        invController.SetCurrentVaultChest(chestIndex, contents)
    end

    lootFrame.Position = UDim2.new(0, 0, 1, 130)  -- Start below panel (hidden)
    TweenService:Create(lootFrame, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
        Position = UDim2.new(0, 0, 1, 0)  -- Slide up to bottom of panel
    }):Play()
end

-- Update vault slots when contents change
local function updateVaultUI(chestIndex, contents)
    if lootUISource ~= "vault" or currentVaultChest ~= chestIndex then return end

    vaultChestItems = contents or {}
    updateLootSlots()

    -- Notify InventoryController of update
    local invController = getInventoryController()
    if invController then
        invController.SetCurrentVaultChest(chestIndex, contents)
    end
end

local function hideLootUI()
    if not isLootVisible then return end

    isLootVisible = false
    currentLootBag = nil
    currentVaultChest = nil
    lootUISource = nil
    vaultChestItems = {}

    -- Notify InventoryController that loot/vault is closed
    local invController = getInventoryController()
    if invController then
        invController.ClearCurrentLootBag()
        invController.ClearCurrentVaultChest()
    end

    local tween = TweenService:Create(lootFrame, TweenInfo.new(0.2), {
        Position = UDim2.new(0, 0, 1, 130)  -- Slide back down below panel (hidden)
    })
    tween:Play()
    tween.Completed:Connect(function()
        if not isLootVisible then
            lootFrame.Visible = false
        end
    end)
end

-- Hide vault UI specifically (called when walking away from chest)
local function hideVaultUI()
    if lootUISource == "vault" then
        hideLootUI()
    end
end

-- Proximity check
local LOOT_RANGE = 5

local lootCheckDebugTimer = 0
local function checkLootProximity()
    local character = player.Character
    if not character then
        if isLootVisible then hideLootUI() end
        return
    end

    local rootPart = character:FindFirstChild("HumanoidRootPart")
    if not rootPart then
        if isLootVisible then hideLootUI() end
        return
    end

    local playerPos = rootPart.Position
    local closestBag = nil
    local closestDist = LOOT_RANGE

    local taggedBags = CollectionService:GetTagged("LootBag")

    -- Debug output every 2 seconds
    lootCheckDebugTimer = lootCheckDebugTimer + 1
    if lootCheckDebugTimer >= 120 then  -- ~2 seconds at 60fps
        lootCheckDebugTimer = 0
        -- print("[HUD Loot] Found", #taggedBags, "tagged bags, LOOT_RANGE:", LOOT_RANGE)
    end

    for _, lootBag in ipairs(taggedBags) do
        if lootBag:IsA("BasePart") then
            local dist = (lootBag.Position - playerPos).Magnitude
            if dist < closestDist then
                closestDist = dist
                closestBag = lootBag
            end
        end
    end

    if closestBag then
        showLootUI(closestBag)
    elseif isLootVisible and lootUISource ~= "vault" then
        -- Only auto-close for loot bags, not vault (VaultController handles vault closing)
        hideLootUI()
    end
end

RunService.Heartbeat:Connect(checkLootProximity)

--============================================================================
-- ATTRIBUTE LISTENERS
--============================================================================

local function setupAttributeListeners(character)
    -- Debug: Print what attributes we're reading (disabled)
    -- print("[HUD] Reading attributes from character:")
    -- print("  Attack=" .. tostring(character:GetAttribute("Attack")))
    -- print("  Dexterity=" .. tostring(character:GetAttribute("Dexterity")))
    -- print("  HP=" .. tostring(character:GetAttribute("HP")))

    local hp = character:GetAttribute("CurrentHP") or 100
    local maxHp = character:GetAttribute("HP") or 100
    local mp = character:GetAttribute("CurrentMP") or 100
    local maxMp = character:GetAttribute("MP") or 100
    local level = character:GetAttribute("Level") or 1
    local className = character:GetAttribute("Class") or "Wizard"

    updateHP(hp, maxHp)
    updateMP(mp, maxMp)
    updateLevel(level, className)

    -- Update stats
    local stats = {
        Attack = character:GetAttribute("Attack") or 0,
        Defense = character:GetAttribute("Defense") or 0,
        Speed = character:GetAttribute("Speed") or 0,
        Dexterity = character:GetAttribute("Dexterity") or 0,
        Vitality = character:GetAttribute("Vitality") or 0,
        Wisdom = character:GetAttribute("Wisdom") or 0,
    }
    updateStats(stats)

    -- Listen for changes
    character:GetAttributeChangedSignal("CurrentHP"):Connect(function()
        updateHP(character:GetAttribute("CurrentHP") or 0, character:GetAttribute("HP") or 100)
    end)

    character:GetAttributeChangedSignal("HP"):Connect(function()
        updateHP(character:GetAttribute("CurrentHP") or 0, character:GetAttribute("HP") or 100)
    end)

    character:GetAttributeChangedSignal("CurrentMP"):Connect(function()
        updateMP(character:GetAttribute("CurrentMP") or 0, character:GetAttribute("MP") or 100)
    end)

    character:GetAttributeChangedSignal("MP"):Connect(function()
        updateMP(character:GetAttribute("CurrentMP") or 0, character:GetAttribute("MP") or 100)
    end)

    character:GetAttributeChangedSignal("Level"):Connect(function()
        updateLevel(character:GetAttribute("Level"), character:GetAttribute("Class"))
    end)

    -- Stat changes
    for _, statName in ipairs({"Attack", "Defense", "Speed", "Dexterity", "Vitality", "Wisdom"}) do
        character:GetAttributeChangedSignal(statName):Connect(function()
            local newStats = {
                Attack = character:GetAttribute("Attack") or 0,
                Defense = character:GetAttribute("Defense") or 0,
                Speed = character:GetAttribute("Speed") or 0,
                Dexterity = character:GetAttribute("Dexterity") or 0,
                Vitality = character:GetAttribute("Vitality") or 0,
                Wisdom = character:GetAttribute("Wisdom") or 0,
            }
            updateStats(newStats)
        end)
    end
end

-- Remote events
local Remotes = require(Shared.Remotes)
Remotes.Init()  -- Wait for server to create remotes

Remotes.Events.StatUpdate.OnClientEvent:Connect(function(data)
    -- print("[HUD] StatUpdate received")
    if data.Stats then
        -- print("[HUD] Stats received - Attack:", data.Stats.Attack, "HP:", data.Stats.HP)
    end

    if data.CurrentHP and data.MaxHP then
        updateHP(data.CurrentHP, data.MaxHP)
    end
    if data.CurrentMP and data.MaxMP then
        updateMP(data.CurrentMP, data.MaxMP)
    end
    if data.XP and data.XPNeeded then
        updateXP(data.XP, data.XPNeeded)
    end
    if data.Level then
        updateLevel(data.Level, data.Class)
    end
    if data.Stats then
        updateStats(data.Stats)
    end
end)

Remotes.Events.LevelUp.OnClientEvent:Connect(function(data)
    if data.NewLevel then
        updateLevel(data.NewLevel, player.Character and player.Character:GetAttribute("Class"))
        -- Flash effect
        levelLabel.TextColor3 = COLORS.TEXT_GOLD
        task.delay(0.5, function()
            levelLabel.TextColor3 = COLORS.TEXT_GRAY
        end)
    end
end)

-- Loot drop/pickup events
Remotes.Events.LootDrop.OnClientEvent:Connect(function(data)
    lootBagItems[data.Id] = data.Items or {}
end)

Remotes.Events.LootPickup.OnClientEvent:Connect(function(data)
    if data.Removed then
        lootBagItems[data.BagId] = nil
    elseif data.RemainingItems then
        lootBagItems[data.BagId] = data.RemainingItems
    end

    -- Update UI if this is the current bag
    if currentLootBag and currentLootBag:GetAttribute("BagId") == data.BagId then
        updateLootSlots()

        -- Also update InventoryController's loot bag items
        local invController = getInventoryController()
        if invController then
            if data.Removed then
                invController.ClearCurrentLootBag()
            elseif data.RemainingItems then
                invController.SetCurrentLootBag(data.BagId, data.RemainingItems)
            end
        end
    end
end)

-- Vault chest events
Remotes.Events.VaultChestOpened.OnClientEvent:Connect(function(data)
    -- print("[HUD] VaultChestOpened received, chest:", data.ChestIndex)
    showVaultUI(data.ChestIndex, data.Contents)
end)

Remotes.Events.VaultChestUpdated.OnClientEvent:Connect(function(data)
    -- print("[HUD] VaultChestUpdated received, chest:", data.ChestIndex)
    updateVaultUI(data.ChestIndex, data.Contents)
end)

Remotes.Events.VaultChestClosed.OnClientEvent:Connect(function()
    -- print("[HUD] VaultChestClosed received")
    hideLootUI()
end)

-- Inventory update for equipment/backpack display
Remotes.Events.InventoryUpdate.OnClientEvent:Connect(function(data)
    -- Update equipment slots
    if data.Equipment then
        local equipNames = {"Weapon", "Ability", "Armor", "Ring"}
        for i, slotName in ipairs(equipNames) do
            local slot = equipSlots[slotName]
            if slot then
                createItemDisplay(slot, data.Equipment[slotName])
            end
        end
    end

    -- Update inventory slots
    if data.Backpack then
        for i = 1, 8 do
            local slot = invSlots[i]
            if slot then
                -- Convert false (empty slot placeholder) to nil
                local itemId = data.Backpack[i]
                if itemId == false then itemId = nil end
                createItemDisplay(slot, itemId)
            end
        end
    end

    -- Update potion counts
    if data.HealthPotions then
        hpPotLabel.Text = "❤ " .. data.HealthPotions .. "/6"
    end
    if data.ManaPotions then
        mpPotLabel.Text = "💧 " .. data.ManaPotions .. "/6"
    end
end)

--============================================================================
-- NOTIFICATION SYSTEM
--============================================================================

-- Notification container (center-top of screen)
local notificationContainer = Instance.new("Frame")
notificationContainer.Name = "NotificationContainer"
notificationContainer.Size = UDim2.new(0, 400, 0, 200)
notificationContainer.Position = UDim2.new(0.5, -200, 0, 100)
notificationContainer.BackgroundTransparency = 1
notificationContainer.Parent = screenGui

local notificationLayout = Instance.new("UIListLayout")
notificationLayout.FillDirection = Enum.FillDirection.Vertical
notificationLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
notificationLayout.VerticalAlignment = Enum.VerticalAlignment.Top
notificationLayout.Padding = UDim.new(0, 5)
notificationLayout.Parent = notificationContainer

-- Show a notification message
local function showNotification(message, notifType)
    notifType = notifType or "info"

    local colors = {
        error = Color3.fromRGB(200, 50, 50),
        success = Color3.fromRGB(50, 200, 50),
        warning = Color3.fromRGB(200, 150, 50),
        info = Color3.fromRGB(100, 150, 200),
    }

    local bgColor = colors[notifType] or colors.info

    local notif = Instance.new("Frame")
    notif.Name = "Notification"
    notif.Size = UDim2.new(1, 0, 0, 36)
    notif.BackgroundColor3 = bgColor
    notif.BackgroundTransparency = 0.2
    notif.BorderSizePixel = 0
    notif.Parent = notificationContainer

    UIUtils.styleFrame(notif, {
        cornerRadius = 6,
        strokeColor = Color3.new(1, 1, 1),
        strokeTransparency = 0.7
    })

    local text = Instance.new("TextLabel")
    text.Name = "Message"
    text.Size = UDim2.new(1, -20, 1, 0)
    text.Position = UDim2.new(0, 10, 0, 0)
    text.BackgroundTransparency = 1
    text.Font = FONT
    text.TextSize = 16
    text.TextColor3 = Color3.new(1, 1, 1)
    text.Text = message
    text.TextXAlignment = Enum.TextXAlignment.Center
    text.Parent = notif

    -- Animate in
    notif.Position = UDim2.new(0, -400, 0, 0)
    local slideIn = TweenService:Create(notif, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
        Position = UDim2.new(0, 0, 0, 0)
    })
    slideIn:Play()

    -- Fade out and remove after 3 seconds
    task.delay(3, function()
        local fadeOut = TweenService:Create(notif, TweenInfo.new(0.5), {
            BackgroundTransparency = 1,
            Position = UDim2.new(0, 400, 0, 0)
        })
        local textFade = TweenService:Create(text, TweenInfo.new(0.5), {
            TextTransparency = 1
        })
        fadeOut:Play()
        textFade:Play()
        fadeOut.Completed:Connect(function()
            notif:Destroy()
        end)
    end)
end

-- Listen for error notifications
Remotes.Events.InventoryError.OnClientEvent:Connect(function(data)
    showNotification(data.Message or "Action failed", "error")
end)

-- Listen for general notifications
Remotes.Events.Notification.OnClientEvent:Connect(function(data)
    showNotification(data.Message or "", data.Type or "info")
end)

--============================================================================
-- ITEM TOOLTIP SYSTEM
--============================================================================

-- Create tooltip frame (appears above hovered item)
local tooltip = Instance.new("Frame")
tooltip.Name = "ItemTooltip"
tooltip.Size = UDim2.new(0, 180, 0, 120)
tooltip.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
tooltip.BackgroundTransparency = 0.1
tooltip.BorderSizePixel = 0
tooltip.Visible = false
tooltip.ZIndex = 100
tooltip.Parent = screenGui

UIUtils.styleFrame(tooltip, {
    cornerRadius = 6,
    strokeColor = COLORS.SLOT_BORDER,
    strokeThickness = 2
})

local tooltipPadding = Instance.new("UIPadding")
tooltipPadding.PaddingTop = UDim.new(0, 8)
tooltipPadding.PaddingBottom = UDim.new(0, 8)
tooltipPadding.PaddingLeft = UDim.new(0, 10)
tooltipPadding.PaddingRight = UDim.new(0, 10)
tooltipPadding.Parent = tooltip

-- Item name (top)
local tooltipName = Instance.new("TextLabel")
tooltipName.Name = "ItemName"
tooltipName.Size = UDim2.new(1, 0, 0, 20)
tooltipName.Position = UDim2.new(0, 0, 0, 0)
tooltipName.BackgroundTransparency = 1
tooltipName.Font = Enum.Font.GothamBold
tooltipName.TextSize = 14
tooltipName.TextColor3 = COLORS.TEXT
tooltipName.TextXAlignment = Enum.TextXAlignment.Left
tooltipName.TextWrapped = true
tooltipName.ZIndex = 101
tooltipName.Parent = tooltip

-- Tier/Rarity line
local tooltipTier = Instance.new("TextLabel")
tooltipTier.Name = "TierRarity"
tooltipTier.Size = UDim2.new(1, 0, 0, 14)
tooltipTier.Position = UDim2.new(0, 0, 0, 22)
tooltipTier.BackgroundTransparency = 1
tooltipTier.Font = FONT
tooltipTier.TextSize = 11
tooltipTier.TextColor3 = COLORS.TEXT_GRAY
tooltipTier.TextXAlignment = Enum.TextXAlignment.Left
tooltipTier.ZIndex = 101
tooltipTier.Parent = tooltip

-- Stats section
local tooltipStats = Instance.new("TextLabel")
tooltipStats.Name = "Stats"
tooltipStats.Size = UDim2.new(1, 0, 0, 50)
tooltipStats.Position = UDim2.new(0, 0, 0, 40)
tooltipStats.BackgroundTransparency = 1
tooltipStats.Font = FONT
tooltipStats.TextSize = 11
tooltipStats.TextColor3 = COLORS.TEXT_GREEN
tooltipStats.TextXAlignment = Enum.TextXAlignment.Left
tooltipStats.TextYAlignment = Enum.TextYAlignment.Top
tooltipStats.TextWrapped = true
tooltipStats.ZIndex = 101
tooltipStats.Parent = tooltip

-- Description
local tooltipDesc = Instance.new("TextLabel")
tooltipDesc.Name = "Description"
tooltipDesc.Size = UDim2.new(1, 0, 0, 30)
tooltipDesc.Position = UDim2.new(0, 0, 0, 85)
tooltipDesc.BackgroundTransparency = 1
tooltipDesc.Font = FONT
tooltipDesc.TextSize = 10
tooltipDesc.TextColor3 = COLORS.TEXT_GRAY
tooltipDesc.TextXAlignment = Enum.TextXAlignment.Left
tooltipDesc.TextYAlignment = Enum.TextYAlignment.Top
tooltipDesc.TextWrapped = true
tooltipDesc.ZIndex = 101
tooltipDesc.Parent = tooltip

-- Show tooltip for an item
local function showTooltip(slot, itemId)
    if not itemId then return end

    local item = ItemDatabase.GetItem(itemId)
    if not item then return end

    -- Set name with rarity color
    tooltipName.Text = item.Name or itemId
    tooltipName.TextColor3 = RARITY_COLORS[item.Rarity] or COLORS.TEXT

    -- Set tier and rarity
    local tierText = item.Tier and ("Tier " .. item.Tier) or ""
    local rarityText = item.Rarity or "Common"
    tooltipTier.Text = tierText .. (tierText ~= "" and " - " or "") .. rarityText

    -- Build stats string
    local statLines = {}
    if item.Damage then
        if type(item.Damage) == "table" then
            -- Handle damage range {Min, Max}
            table.insert(statLines, "Damage: " .. (item.Damage.Min or item.Damage[1] or "?") .. "-" .. (item.Damage.Max or item.Damage[2] or "?"))
        else
            table.insert(statLines, "Damage: " .. tostring(item.Damage))
        end
    end
    if item.RateOfFire then
        table.insert(statLines, "Fire Rate: " .. string.format("%.1f", item.RateOfFire))
    end
    if item.Range then
        table.insert(statLines, "Range: " .. item.Range)
    end
    if item.Defense then
        table.insert(statLines, "+" .. item.Defense .. " DEF")
    end
    if item.StatBonus then
        for stat, value in pairs(item.StatBonus) do
            if value > 0 then
                table.insert(statLines, "+" .. value .. " " .. stat)
            elseif value < 0 then
                table.insert(statLines, value .. " " .. stat)
            end
        end
    end
    if item.MPCost then
        table.insert(statLines, "MP Cost: " .. item.MPCost)
    end

    tooltipStats.Text = table.concat(statLines, "\n")

    -- Set description
    tooltipDesc.Text = item.Description or ""

    -- Calculate height based on content
    local statsHeight = #statLines * 12 + 5
    local hasDesc = item.Description and item.Description ~= ""
    local totalHeight = 45 + statsHeight + (hasDesc and 35 or 0)
    tooltip.Size = UDim2.new(0, 180, 0, totalHeight)
    tooltipStats.Size = UDim2.new(1, 0, 0, statsHeight)
    tooltipDesc.Position = UDim2.new(0, 0, 0, 40 + statsHeight)
    tooltipDesc.Visible = hasDesc

    -- Position tooltip to the left of the slot
    local slotAbsPos = slot.AbsolutePosition
    local slotAbsSize = slot.AbsoluteSize
    tooltip.Position = UDim2.new(0, slotAbsPos.X - 190, 0, slotAbsPos.Y)

    -- Make sure tooltip stays on screen
    if slotAbsPos.X - 190 < 10 then
        -- Show to the right instead
        tooltip.Position = UDim2.new(0, slotAbsPos.X + slotAbsSize.X + 10, 0, slotAbsPos.Y)
    end

    tooltip.Visible = true
end

local function hideTooltip()
    tooltip.Visible = false
end

-- Add hover handlers to a slot
local function addTooltipHandlers(slot)
    local button = Instance.new("TextButton")
    button.Name = "HoverDetector"
    button.Size = UDim2.new(1, 0, 1, 0)
    button.BackgroundTransparency = 1
    button.Text = ""
    button.ZIndex = 10
    button.Parent = slot

    button.MouseEnter:Connect(function()
        local itemId = slot:GetAttribute("ItemId")
        if itemId then
            showTooltip(slot, itemId)
        end
    end)

    button.MouseLeave:Connect(function()
        hideTooltip()
    end)
end

-- Add tooltip handlers to all equipment slots
for _, slot in pairs(equipSlots) do
    addTooltipHandlers(slot)
end

-- Add tooltip handlers to all inventory slots
for _, slot in ipairs(invSlots) do
    addTooltipHandlers(slot)
end

-- Add tooltip handlers to all loot slots
for _, slot in ipairs(lootSlots) do
    addTooltipHandlers(slot)
end

--============================================================================
-- AUDIO FEEDBACK SYSTEM
--============================================================================

-- Sound IDs (using Roblox sound library - classic RotMG-style sounds)
local SOUNDS = {
    Pickup = "rbxassetid://9114713167",      -- Coin/pickup sound
    Equip = "rbxassetid://9119720813",       -- Equip sound
    Error = "rbxassetid://9118823111",       -- Error/buzz sound
    LevelUp = "rbxassetid://9118831587",     -- Fanfare
    PotionUse = "rbxassetid://9114238192",   -- Gulp/drink sound
    BagOpen = "rbxassetid://9113617638",     -- Bag rustle
}

-- Create sound instances
local soundFolder = Instance.new("Folder")
soundFolder.Name = "HUDSounds"
soundFolder.Parent = screenGui

local soundInstances = {}
for name, id in pairs(SOUNDS) do
    local sound = Instance.new("Sound")
    sound.Name = name
    sound.SoundId = id
    sound.Volume = 0.5
    sound.Parent = soundFolder
    soundInstances[name] = sound
end

-- Play a sound effect
local function playSound(soundName)
    local sound = soundInstances[soundName]
    if sound then
        sound:Play()
    end
end

-- Hook into notification events for audio
local originalShowNotification = showNotification
showNotification = function(message, notifType)
    originalShowNotification(message, notifType)

    -- Play appropriate sound based on notification type
    if notifType == "error" then
        playSound("Error")
    elseif notifType == "success" then
        if message:lower():find("picked up") then
            playSound("Pickup")
        else
            playSound("Equip")
        end
    end
end

-- Play sound when level up occurs
Remotes.Events.LevelUp.OnClientEvent:Connect(function()
    playSound("LevelUp")
end)

-- Play sound when inventory updates (swap/equip)
local lastEquipment = {}
Remotes.Events.InventoryUpdate.OnClientEvent:Connect(function(data)
    if data.Equipment then
        -- Check if equipment actually changed
        local changed = false
        for slot, itemId in pairs(data.Equipment) do
            if lastEquipment[slot] ~= itemId then
                changed = true
                lastEquipment[slot] = itemId
            end
        end
        if changed then
            playSound("Equip")
        end
    end
end)

-- Play sound when approaching a loot bag
local lastLootBagVisible = false
RunService.Heartbeat:Connect(function()
    if isLootVisible and not lastLootBagVisible then
        playSound("BagOpen")
    end
    lastLootBagVisible = isLootVisible
end)

-- Zone detection and minimap update loop
RunService.Heartbeat:Connect(function()
    local character = player.Character
    if character then
        local rootPart = character:FindFirstChild("HumanoidRootPart")
        if rootPart then
            local zone = getZoneAtPosition(rootPart.Position)
            updateZoneIndicator(zone)
        end
    end

    -- Update minimap (runs every frame for smooth updates)
    -- Now uses BiomeCache for instant O(1) lookups - no more incremental processing needed
    updateMinimap()
end)

--============================================================================
-- CHARACTER SETUP
--============================================================================

local function onCharacterAdded(character)
    task.spawn(function()
        task.wait(0.3)
        setupAttributeListeners(character)
    end)
end

player.CharacterAdded:Connect(onCharacterAdded)
if player.Character then
    onCharacterAdded(player.Character)
end

--============================================================================
-- HUD VISIBILITY (Hide during character select)
--============================================================================

-- Check if player already has an active character (script re-runs on respawn)
local function hasActiveCharacter()
    local character = player.Character
    if character and character:GetAttribute("Class") then
        return true
    end
    return false
end

-- Start with HUD hidden UNLESS player already has an active character
-- (This handles the case where script re-runs after respawn)
if hasActiveCharacter() then
    -- print("[HUDController] Player already has active character, enabling HUD immediately")
    screenGui.Enabled = true
else
    -- print("[HUDController] No active character yet, HUD starts hidden")
    screenGui.Enabled = false
end

-- Show HUD when character select is hidden (player enters game)
Remotes.Events.HideCharacterSelect.OnClientEvent:Connect(function()
    -- print("[HUDController] HideCharacterSelect received, enabling HUD")
    screenGui.Enabled = true
end)

-- Hide HUD when character select is shown (death/return to menu)
Remotes.Events.ShowCharacterSelect.OnClientEvent:Connect(function()
    -- print("[HUDController] ShowCharacterSelect received, hiding HUD")
    screenGui.Enabled = false
    -- Reset zone to prevent stale text
    currentZone = ""
end)

-- Handle zone change notifications from server (e.g., after portal teleport)
Remotes.Events.ZoneChanged.OnClientEvent:Connect(function(data)
    if data.Zone then
        -- Force update the zone indicator (bypass the same-zone check)
        currentZone = "" -- Clear to force update
        updateZoneIndicator(data.Zone)
        -- print("[HUDController] Zone changed via server event: " .. data.Zone)
    end
end)

-- If this is a respawn, reinitialize InventoryController to update slot references
if isRespawn then
    task.defer(function()
        local invController = getInventoryController()
        if invController and invController.Reinitialize then
            invController.Reinitialize()
        end
    end)
end

-- print("[HUDController] RotMG-style right panel HUD initialized")
