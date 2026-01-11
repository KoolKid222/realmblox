--[[
    AdminPanel.client.lua
    Debug/Admin panel for testing - Press F9 to toggle

    Features:
    - Modify any stat with +/- buttons
    - Max all stats button
    - Heal to full
    - Spawn enemies
    - Teleport to zones
    - Toggle godmode
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Check if UI already exists (StarterGui scripts re-run on respawn)
-- We need to destroy and recreate because old script's connections are gone
local existingUI = playerGui:FindFirstChild("AdminPanel")
if existingUI then
    existingUI:Destroy()
end

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local Constants = require(Shared.Constants)

-- EnemyVisuals for hitbox display (loaded lazily)
local EnemyVisuals = nil
local function getEnemyVisuals()
    if not EnemyVisuals then
        local Controllers = player.PlayerScripts:WaitForChild("Controllers", 1)
        if Controllers then
            local enemyVisualsModule = Controllers:FindFirstChild("EnemyVisuals")
            if enemyVisualsModule then
                EnemyVisuals = require(enemyVisualsModule)
            end
        end
    end
    return EnemyVisuals
end

--============================================================================
-- STYLE CONSTANTS (Match RotMG Theme)
--============================================================================
local COLORS = {
    PANEL_BG = Color3.fromRGB(25, 25, 30),
    PANEL_BORDER = Color3.fromRGB(80, 80, 100),
    HEADER_BG = Color3.fromRGB(40, 40, 50),
    BUTTON_BG = Color3.fromRGB(50, 50, 60),
    BUTTON_HOVER = Color3.fromRGB(70, 70, 85),
    BUTTON_PRESS = Color3.fromRGB(40, 40, 50),
    BUTTON_GREEN = Color3.fromRGB(50, 120, 50),
    BUTTON_RED = Color3.fromRGB(120, 50, 50),
    BUTTON_GOLD = Color3.fromRGB(180, 140, 50),
    TEXT = Color3.fromRGB(255, 255, 255),
    TEXT_GRAY = Color3.fromRGB(180, 180, 180),
    TEXT_GOLD = Color3.fromRGB(255, 215, 0),
    STAT_HP = Color3.fromRGB(226, 61, 40),
    STAT_MP = Color3.fromRGB(48, 76, 226),
}

local FONT = Enum.Font.Code
local PANEL_WIDTH = 280
local PANEL_HEIGHT = 500

--============================================================================
-- CREATE SCREEN GUI
--============================================================================

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "AdminPanel"
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.DisplayOrder = 100
screenGui.Parent = player:WaitForChild("PlayerGui")

--============================================================================
-- MAIN PANEL
--============================================================================

local mainPanel = Instance.new("Frame")
mainPanel.Name = "MainPanel"
mainPanel.Size = UDim2.new(0, PANEL_WIDTH, 0, PANEL_HEIGHT)
mainPanel.Position = UDim2.new(0, 20, 0.5, -PANEL_HEIGHT/2)
mainPanel.BackgroundColor3 = COLORS.PANEL_BG
mainPanel.BackgroundTransparency = 0.05
mainPanel.BorderSizePixel = 0
mainPanel.Visible = false
mainPanel.Parent = screenGui

local panelCorner = Instance.new("UICorner")
panelCorner.CornerRadius = UDim.new(0, 8)
panelCorner.Parent = mainPanel

local panelStroke = Instance.new("UIStroke")
panelStroke.Color = COLORS.PANEL_BORDER
panelStroke.Thickness = 2
panelStroke.Parent = mainPanel

-- Header
local header = Instance.new("Frame")
header.Name = "Header"
header.Size = UDim2.new(1, 0, 0, 30)
header.BackgroundColor3 = COLORS.HEADER_BG
header.BorderSizePixel = 0
header.Parent = mainPanel

local headerCorner = Instance.new("UICorner")
headerCorner.CornerRadius = UDim.new(0, 8)
headerCorner.Parent = header

-- Fix bottom corners of header
local headerFix = Instance.new("Frame")
headerFix.Size = UDim2.new(1, 0, 0, 10)
headerFix.Position = UDim2.new(0, 0, 1, -10)
headerFix.BackgroundColor3 = COLORS.HEADER_BG
headerFix.BorderSizePixel = 0
headerFix.Parent = header

local headerTitle = Instance.new("TextLabel")
headerTitle.Size = UDim2.new(1, -10, 1, 0)
headerTitle.Position = UDim2.new(0, 10, 0, 0)
headerTitle.BackgroundTransparency = 1
headerTitle.Font = FONT
headerTitle.Text = "ADMIN PANEL (P)"
headerTitle.TextColor3 = COLORS.TEXT_GOLD
headerTitle.TextSize = 14
headerTitle.TextXAlignment = Enum.TextXAlignment.Left
headerTitle.Parent = header

-- Content area with scroll
local contentFrame = Instance.new("ScrollingFrame")
contentFrame.Name = "Content"
contentFrame.Size = UDim2.new(1, -16, 1, -40)
contentFrame.Position = UDim2.new(0, 8, 0, 35)
contentFrame.BackgroundTransparency = 1
contentFrame.ScrollBarThickness = 4
contentFrame.ScrollBarImageColor3 = COLORS.PANEL_BORDER
contentFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
contentFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
contentFrame.Parent = mainPanel

local contentLayout = Instance.new("UIListLayout")
contentLayout.SortOrder = Enum.SortOrder.LayoutOrder
contentLayout.Padding = UDim.new(0, 6)
contentLayout.Parent = contentFrame

--============================================================================
-- UI HELPERS
--============================================================================

local function createSection(title, layoutOrder)
    local section = Instance.new("Frame")
    section.Name = title
    section.Size = UDim2.new(1, 0, 0, 0)
    section.BackgroundTransparency = 1
    section.AutomaticSize = Enum.AutomaticSize.Y
    section.LayoutOrder = layoutOrder
    section.Parent = contentFrame

    local sectionLayout = Instance.new("UIListLayout")
    sectionLayout.SortOrder = Enum.SortOrder.LayoutOrder
    sectionLayout.Padding = UDim.new(0, 4)
    sectionLayout.Parent = section

    local sectionTitle = Instance.new("TextLabel")
    sectionTitle.Name = "Title"
    sectionTitle.Size = UDim2.new(1, 0, 0, 20)
    sectionTitle.BackgroundTransparency = 1
    sectionTitle.Font = FONT
    sectionTitle.Text = "-- " .. title .. " --"
    sectionTitle.TextColor3 = COLORS.TEXT_GRAY
    sectionTitle.TextSize = 11
    sectionTitle.LayoutOrder = 0
    sectionTitle.Parent = section

    return section
end

local function createButton(parent, text, color, layoutOrder, callback)
    local button = Instance.new("TextButton")
    button.Name = text
    button.Size = UDim2.new(1, 0, 0, 28)
    button.BackgroundColor3 = color or COLORS.BUTTON_BG
    button.BorderSizePixel = 0
    button.Font = FONT
    button.Text = text
    button.TextColor3 = COLORS.TEXT
    button.TextSize = 12
    button.LayoutOrder = layoutOrder or 1
    button.Parent = parent

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 4)
    corner.Parent = button

    -- Hover effects
    button.MouseEnter:Connect(function()
        button.BackgroundColor3 = COLORS.BUTTON_HOVER
    end)
    button.MouseLeave:Connect(function()
        button.BackgroundColor3 = color or COLORS.BUTTON_BG
    end)
    button.MouseButton1Down:Connect(function()
        button.BackgroundColor3 = COLORS.BUTTON_PRESS
    end)
    button.MouseButton1Up:Connect(function()
        button.BackgroundColor3 = COLORS.BUTTON_HOVER
    end)

    if callback then
        button.MouseButton1Click:Connect(callback)
    end

    return button
end

local function createStatRow(parent, statName, displayName, layoutOrder, statColor)
    local row = Instance.new("Frame")
    row.Name = statName
    row.Size = UDim2.new(1, 0, 0, 26)
    row.BackgroundTransparency = 1
    row.LayoutOrder = layoutOrder
    row.Parent = parent

    -- Stat name
    local label = Instance.new("TextLabel")
    label.Name = "Label"
    label.Size = UDim2.new(0, 60, 1, 0)
    label.BackgroundTransparency = 1
    label.Font = FONT
    label.Text = displayName
    label.TextColor3 = statColor or COLORS.TEXT
    label.TextSize = 12
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = row

    -- Current value display
    local valueLabel = Instance.new("TextLabel")
    valueLabel.Name = "Value"
    valueLabel.Size = UDim2.new(0, 40, 1, 0)
    valueLabel.Position = UDim2.new(0, 65, 0, 0)
    valueLabel.BackgroundTransparency = 1
    valueLabel.Font = FONT
    valueLabel.Text = "0"
    valueLabel.TextColor3 = COLORS.TEXT
    valueLabel.TextSize = 12
    valueLabel.Parent = row

    -- -10 button
    local minusTen = Instance.new("TextButton")
    minusTen.Size = UDim2.new(0, 28, 0, 22)
    minusTen.Position = UDim2.new(0, 110, 0, 2)
    minusTen.BackgroundColor3 = COLORS.BUTTON_RED
    minusTen.Font = FONT
    minusTen.Text = "-10"
    minusTen.TextColor3 = COLORS.TEXT
    minusTen.TextSize = 10
    minusTen.Parent = row

    local c1 = Instance.new("UICorner")
    c1.CornerRadius = UDim.new(0, 4)
    c1.Parent = minusTen

    -- -1 button
    local minusOne = Instance.new("TextButton")
    minusOne.Size = UDim2.new(0, 24, 0, 22)
    minusOne.Position = UDim2.new(0, 142, 0, 2)
    minusOne.BackgroundColor3 = COLORS.BUTTON_RED
    minusOne.Font = FONT
    minusOne.Text = "-1"
    minusOne.TextColor3 = COLORS.TEXT
    minusOne.TextSize = 10
    minusOne.Parent = row

    local c2 = Instance.new("UICorner")
    c2.CornerRadius = UDim.new(0, 4)
    c2.Parent = minusOne

    -- +1 button
    local plusOne = Instance.new("TextButton")
    plusOne.Size = UDim2.new(0, 24, 0, 22)
    plusOne.Position = UDim2.new(0, 170, 0, 2)
    plusOne.BackgroundColor3 = COLORS.BUTTON_GREEN
    plusOne.Font = FONT
    plusOne.Text = "+1"
    plusOne.TextColor3 = COLORS.TEXT
    plusOne.TextSize = 10
    plusOne.Parent = row

    local c3 = Instance.new("UICorner")
    c3.CornerRadius = UDim.new(0, 4)
    c3.Parent = plusOne

    -- +10 button
    local plusTen = Instance.new("TextButton")
    plusTen.Size = UDim2.new(0, 28, 0, 22)
    plusTen.Position = UDim2.new(0, 198, 0, 2)
    plusTen.BackgroundColor3 = COLORS.BUTTON_GREEN
    plusTen.Font = FONT
    plusTen.Text = "+10"
    plusTen.TextColor3 = COLORS.TEXT
    plusTen.TextSize = 10
    plusTen.Parent = row

    local c4 = Instance.new("UICorner")
    c4.CornerRadius = UDim.new(0, 4)
    c4.Parent = plusTen

    -- Button callbacks
    local function updateStat(delta)
        local character = player.Character
        if character then
            local currentVal = character:GetAttribute(statName) or 0
            Remotes.Events.AdminCommand:FireServer("SetStat", {
                Stat = statName,
                Value = currentVal + delta
            })
        end
    end

    minusTen.MouseButton1Click:Connect(function() updateStat(-10) end)
    minusOne.MouseButton1Click:Connect(function() updateStat(-1) end)
    plusOne.MouseButton1Click:Connect(function() updateStat(1) end)
    plusTen.MouseButton1Click:Connect(function() updateStat(10) end)

    return row, valueLabel
end

--============================================================================
-- STATS SECTION
--============================================================================

local statsSection = createSection("STATS", 1)

local statRows = {}
local statValueLabels = {}

local stats = {
    {name = "HP", display = "HP", color = COLORS.STAT_HP},
    {name = "MP", display = "MP", color = COLORS.STAT_MP},
    {name = "Attack", display = "ATT", color = COLORS.TEXT},
    {name = "Defense", display = "DEF", color = COLORS.TEXT},
    {name = "Speed", display = "SPD", color = COLORS.TEXT},
    {name = "Dexterity", display = "DEX", color = COLORS.TEXT},
    {name = "Vitality", display = "VIT", color = COLORS.TEXT},
    {name = "Wisdom", display = "WIS", color = COLORS.TEXT},
}

for i, stat in ipairs(stats) do
    local row, valueLabel = createStatRow(statsSection, stat.name, stat.display, i, stat.color)
    statRows[stat.name] = row
    statValueLabels[stat.name] = valueLabel
end

--============================================================================
-- QUICK ACTIONS SECTION
--============================================================================

local actionsSection = createSection("QUICK ACTIONS", 2)

createButton(actionsSection, "Max All Stats", COLORS.BUTTON_GOLD, 1, function()
    Remotes.Events.AdminCommand:FireServer("MaxStats", {})
end)

createButton(actionsSection, "Heal to Full", COLORS.BUTTON_GREEN, 2, function()
    Remotes.Events.AdminCommand:FireServer("Heal", {})
end)

createButton(actionsSection, "Toggle Godmode", COLORS.BUTTON_BG, 3, function()
    Remotes.Events.ToggleGodmode:FireServer()
end)

createButton(actionsSection, "+1000 XP", COLORS.BUTTON_BG, 4, function()
    Remotes.Events.AdminCommand:FireServer("AddXP", {Amount = 1000})
end)

createButton(actionsSection, "+10000 XP", COLORS.BUTTON_BG, 5, function()
    Remotes.Events.AdminCommand:FireServer("AddXP", {Amount = 10000})
end)

--============================================================================
-- LEVEL SECTION
--============================================================================

local levelSection = createSection("SET LEVEL", 3)

local levelRow = Instance.new("Frame")
levelRow.Size = UDim2.new(1, 0, 0, 28)
levelRow.BackgroundTransparency = 1
levelRow.LayoutOrder = 1
levelRow.Parent = levelSection

for lvl = 1, 20, 1 do
    if lvl <= 10 or lvl == 15 or lvl == 20 then
        local btn = Instance.new("TextButton")
        local col = (lvl <= 10) and (lvl - 1) or ((lvl == 15) and 10 or 11)
        btn.Size = UDim2.new(0, 20, 0, 22)
        btn.Position = UDim2.new(0, col * 22, 0, 3)
        btn.BackgroundColor3 = COLORS.BUTTON_BG
        btn.Font = FONT
        btn.Text = tostring(lvl)
        btn.TextColor3 = COLORS.TEXT
        btn.TextSize = 10
        btn.Parent = levelRow

        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 4)
        corner.Parent = btn

        btn.MouseButton1Click:Connect(function()
            Remotes.Events.AdminCommand:FireServer("SetLevel", {Level = lvl})
        end)
    end
end

--============================================================================
-- SPAWN ENEMIES SECTION
--============================================================================

local spawnSection = createSection("SPAWN ENEMY", 4)

local enemies = {"Dummy", "Pirate", "PirateCaptain", "Snake", "Crab", "Goblin", "Orc", "MedusaConstruct", "WhiteDemon"}

for i, enemyName in ipairs(enemies) do
    createButton(spawnSection, enemyName, COLORS.BUTTON_BG, i, function()
        Remotes.Events.AdminCommand:FireServer("SpawnEnemy", {Enemy = enemyName})
    end)
end

--============================================================================
-- TELEPORT SECTION
--============================================================================

local teleportSection = createSection("TELEPORT", 5)

local zones = {
    {name = "Beach (Spawn)", pos = Vector3.new(400, 10, 400)},
    {name = "Midlands", pos = Vector3.new(200, 10, 200)},
    {name = "Godlands", pos = Vector3.new(50, 10, 50)},
    {name = "Center", pos = Vector3.new(0, 10, 0)},
}

for i, zone in ipairs(zones) do
    createButton(teleportSection, zone.name, COLORS.BUTTON_BG, i, function()
        Remotes.Events.AdminCommand:FireServer("Teleport", {Position = zone.pos})
    end)
end

--============================================================================
-- DEBUG SECTION - HITBOX VISUALIZATION
--============================================================================

local debugSection = createSection("DEBUG", 6)

-- Hitbox visualization state
local showHitboxes = false
local hitboxFolder = nil
local hitboxConnection = nil
local playerHitboxPart = nil
local enemyHitboxParts = {}

-- Colors for hitbox visualization
local PLAYER_HITBOX_COLOR = Color3.fromRGB(0, 255, 0)      -- Green for player
local ENEMY_HITBOX_COLOR = Color3.fromRGB(255, 0, 0)       -- Red for enemies
local HITBOX_TRANSPARENCY = 0.7

-- Create a cylinder to visualize a hitbox (2D circle extruded on Y)
local function createHitboxVisual(radius, color, name)
    local part = Instance.new("Part")
    part.Name = name or "HitboxVisual"
    part.Shape = Enum.PartType.Cylinder
    part.Size = Vector3.new(0.1, radius * 2, radius * 2)  -- Cylinder: height, diameter, diameter
    part.Anchored = true
    part.CanCollide = false
    part.CastShadow = false
    part.Material = Enum.Material.Neon
    part.Color = color
    part.Transparency = HITBOX_TRANSPARENCY
    -- Rotate to be flat on XZ plane (cylinder lies on Y axis by default)
    part.CFrame = CFrame.new() * CFrame.Angles(0, 0, math.rad(90))
    return part
end

-- Update hitbox positions each frame
local function updateHitboxVisuals()
    if not showHitboxes or not hitboxFolder then return end

    -- Update player hitbox
    local character = player.Character
    if character and playerHitboxPart then
        local rootPart = character:FindFirstChild("HumanoidRootPart")
        if rootPart then
            local pos = rootPart.Position
            -- Keep cylinder flat on XZ plane, at player's feet level
            playerHitboxPart.CFrame = CFrame.new(pos.X, pos.Y, pos.Z) * CFrame.Angles(0, 0, math.rad(90))
        end
    end

    -- Update enemy hitboxes
    local enemyVisuals = getEnemyVisuals()
    if enemyVisuals and enemyVisuals.Enemies then
        -- Track which enemies still exist
        local existingEnemies = {}

        for id, enemyData in pairs(enemyVisuals.Enemies) do
            existingEnemies[id] = true

            -- Create hitbox if doesn't exist
            if not enemyHitboxParts[id] then
                local hitboxRadius = 1.6  -- Default fallback

                -- Try to get hitbox from Definition first, then calculate from Body.Size
                if enemyData.Definition and enemyData.Definition.HitboxRadius then
                    hitboxRadius = enemyData.Definition.HitboxRadius
                elseif enemyData.Body then
                    -- Calculate from visual body size (80% of visual radius = 40% of diameter)
                    local size = enemyData.Body.Size
                    hitboxRadius = math.max(size.X, size.Z) * 0.4
                end

                local hitboxPart = createHitboxVisual(hitboxRadius, ENEMY_HITBOX_COLOR, "EnemyHitbox_" .. id)
                hitboxPart.Parent = hitboxFolder
                enemyHitboxParts[id] = hitboxPart
            end

            -- Update position
            local hitboxPart = enemyHitboxParts[id]
            if hitboxPart and enemyData.Body then
                local pos = enemyData.Body.Position
                hitboxPart.CFrame = CFrame.new(pos.X, pos.Y, pos.Z) * CFrame.Angles(0, 0, math.rad(90))
            end
        end

        -- Remove hitboxes for despawned enemies
        for id, part in pairs(enemyHitboxParts) do
            if not existingEnemies[id] then
                part:Destroy()
                enemyHitboxParts[id] = nil
            end
        end
    end
end

-- Toggle hitbox visualization
local function toggleHitboxes()
    showHitboxes = not showHitboxes

    if showHitboxes then
        -- Create folder for hitbox visuals
        hitboxFolder = Instance.new("Folder")
        hitboxFolder.Name = "HitboxDebug"
        hitboxFolder.Parent = workspace

        -- Create player hitbox
        local playerRadius = Constants.Hitbox and Constants.Hitbox.PLAYER_RADIUS or 0.5
        playerHitboxPart = createHitboxVisual(playerRadius, PLAYER_HITBOX_COLOR, "PlayerHitbox")
        playerHitboxPart.Parent = hitboxFolder

        -- Start update loop
        hitboxConnection = RunService.RenderStepped:Connect(updateHitboxVisuals)

        -- print("[AdminPanel] Hitbox visualization ENABLED")
    else
        -- Stop update loop
        if hitboxConnection then
            hitboxConnection:Disconnect()
            hitboxConnection = nil
        end

        -- Destroy all hitbox visuals
        if hitboxFolder then
            hitboxFolder:Destroy()
            hitboxFolder = nil
        end

        playerHitboxPart = nil
        enemyHitboxParts = {}

        -- print("[AdminPanel] Hitbox visualization DISABLED")
    end
end

-- Create toggle button
local hitboxButton = createButton(debugSection, "Show Hitboxes: OFF", COLORS.BUTTON_BG, 1, function()
    toggleHitboxes()
    -- Update button text
    if showHitboxes then
        hitboxButton.Text = "Show Hitboxes: ON"
        hitboxButton.BackgroundColor3 = COLORS.BUTTON_GREEN
    else
        hitboxButton.Text = "Show Hitboxes: OFF"
        hitboxButton.BackgroundColor3 = COLORS.BUTTON_BG
    end
end)

--============================================================================
-- UPDATE STAT DISPLAY
--============================================================================

local function updateStatDisplay()
    local character = player.Character
    if not character then return end

    for statName, valueLabel in pairs(statValueLabels) do
        local value = character:GetAttribute(statName)
        if value then
            valueLabel.Text = tostring(math.floor(value))
        end
    end
end

-- Listen for attribute changes
local function setupAttributeListeners(character)
    for statName, _ in pairs(statValueLabels) do
        character:GetAttributeChangedSignal(statName):Connect(updateStatDisplay)
    end
    updateStatDisplay()
end

player.CharacterAdded:Connect(function(character)
    task.wait(0.2)
    setupAttributeListeners(character)
end)

if player.Character then
    setupAttributeListeners(player.Character)
end

--============================================================================
-- TOGGLE PANEL WITH P
--============================================================================

local panelVisible = false

local function togglePanel()
    panelVisible = not panelVisible

    if panelVisible then
        mainPanel.Visible = true
        mainPanel.Position = UDim2.new(-0.2, 0, 0.5, -PANEL_HEIGHT/2)
        TweenService:Create(mainPanel, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
            Position = UDim2.new(0, 20, 0.5, -PANEL_HEIGHT/2)
        }):Play()
        updateStatDisplay()
    else
        local tween = TweenService:Create(mainPanel, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
            Position = UDim2.new(-0.2, 0, 0.5, -PANEL_HEIGHT/2)
        })
        tween:Play()
        tween.Completed:Connect(function()
            if not panelVisible then
                mainPanel.Visible = false
            end
        end)
    end
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end

    if input.KeyCode == Enum.KeyCode.P then
        togglePanel()
    end
end)

-- print("[AdminPanel] Initialized - Press P to toggle")
