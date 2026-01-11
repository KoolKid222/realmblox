--[[
    DeathScreen.client.lua
    Death screen UI shown when player dies (permadeath)

    Shows:
    - "YOU DIED" message
    - Character class and level
    - Fame earned
    - Enemies killed
    - Return to character select button
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Check if UI already exists (StarterGui scripts re-run on respawn)
-- We need to destroy and recreate because old script's connections are gone
local existingUI = playerGui:FindFirstChild("DeathScreenUI")
if existingUI then
    -- print("[DeathScreen] Respawn detected - destroying old UI to recreate with fresh connections...")
    existingUI:Destroy()
end

-- print("[DeathScreen] Initializing...")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)

-- Wait for remotes to initialize
Remotes.Init()

--============================================================================
-- UI COLORS (RotMG Style - Dark/Red for death)
--============================================================================

local COLORS = {
    Background = Color3.fromRGB(10, 5, 5),
    Panel = Color3.fromRGB(30, 20, 20),
    PanelBorder = Color3.fromRGB(80, 40, 40),
    Text = Color3.fromRGB(255, 255, 255),
    TextDim = Color3.fromRGB(180, 180, 180),
    DeathRed = Color3.fromRGB(200, 50, 50),
    FameGold = Color3.fromRGB(255, 200, 100),
    Button = Color3.fromRGB(60, 60, 80),
    ButtonHover = Color3.fromRGB(80, 80, 110),
}

--============================================================================
-- CREATE UI
--============================================================================

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "DeathScreenUI"
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.IgnoreGuiInset = true
screenGui.Enabled = false
screenGui.Parent = playerGui

-- Full screen dark background with fade
local background = Instance.new("Frame")
background.Name = "Background"
background.Size = UDim2.new(1, 0, 1, 0)
background.BackgroundColor3 = COLORS.Background
background.BackgroundTransparency = 0.3
background.BorderSizePixel = 0
background.Parent = screenGui

-- Main panel (centered)
local mainPanel = Instance.new("Frame")
mainPanel.Name = "MainPanel"
mainPanel.Size = UDim2.new(0, 450, 0, 380)
mainPanel.Position = UDim2.new(0.5, -225, 0.5, -190)
mainPanel.BackgroundColor3 = COLORS.Panel
mainPanel.BorderSizePixel = 0
mainPanel.Parent = background

local panelCorner = Instance.new("UICorner")
panelCorner.CornerRadius = UDim.new(0, 10)
panelCorner.Parent = mainPanel

local panelStroke = Instance.new("UIStroke")
panelStroke.Color = COLORS.PanelBorder
panelStroke.Thickness = 3
panelStroke.Parent = mainPanel

-- "YOU DIED" title
local deathTitle = Instance.new("TextLabel")
deathTitle.Name = "DeathTitle"
deathTitle.Size = UDim2.new(1, 0, 0, 60)
deathTitle.Position = UDim2.new(0, 0, 0, 20)
deathTitle.BackgroundTransparency = 1
deathTitle.Text = "YOU DIED"
deathTitle.TextColor3 = COLORS.DeathRed
deathTitle.Font = Enum.Font.GothamBold
deathTitle.TextSize = 42
deathTitle.Parent = mainPanel

-- Character info (class + level)
local charInfo = Instance.new("TextLabel")
charInfo.Name = "CharInfo"
charInfo.Size = UDim2.new(1, 0, 0, 30)
charInfo.Position = UDim2.new(0, 0, 0, 85)
charInfo.BackgroundTransparency = 1
charInfo.Text = "Level 1 Wizard"
charInfo.TextColor3 = COLORS.TextDim
charInfo.Font = Enum.Font.Gotham
charInfo.TextSize = 20
charInfo.Parent = mainPanel

-- Divider line
local divider = Instance.new("Frame")
divider.Name = "Divider"
divider.Size = UDim2.new(0.7, 0, 0, 2)
divider.Position = UDim2.new(0.15, 0, 0, 130)
divider.BackgroundColor3 = COLORS.PanelBorder
divider.BorderSizePixel = 0
divider.Parent = mainPanel

-- Stats container
local statsContainer = Instance.new("Frame")
statsContainer.Name = "StatsContainer"
statsContainer.Size = UDim2.new(1, -60, 0, 120)
statsContainer.Position = UDim2.new(0, 30, 0, 150)
statsContainer.BackgroundTransparency = 1
statsContainer.Parent = mainPanel

-- Fame earned
local fameLabel = Instance.new("TextLabel")
fameLabel.Name = "FameLabel"
fameLabel.Size = UDim2.new(1, 0, 0, 35)
fameLabel.Position = UDim2.new(0, 0, 0, 0)
fameLabel.BackgroundTransparency = 1
fameLabel.Text = "Fame Earned"
fameLabel.TextColor3 = COLORS.TextDim
fameLabel.Font = Enum.Font.Gotham
fameLabel.TextSize = 16
fameLabel.Parent = statsContainer

local fameValue = Instance.new("TextLabel")
fameValue.Name = "FameValue"
fameValue.Size = UDim2.new(1, 0, 0, 45)
fameValue.Position = UDim2.new(0, 0, 0, 25)
fameValue.BackgroundTransparency = 1
fameValue.Text = "0"
fameValue.TextColor3 = COLORS.FameGold
fameValue.Font = Enum.Font.GothamBold
fameValue.TextSize = 36
fameValue.Parent = statsContainer

-- Enemies killed
local killsLabel = Instance.new("TextLabel")
killsLabel.Name = "KillsLabel"
killsLabel.Size = UDim2.new(1, 0, 0, 25)
killsLabel.Position = UDim2.new(0, 0, 0, 80)
killsLabel.BackgroundTransparency = 1
killsLabel.Text = "Enemies Killed"
killsLabel.TextColor3 = COLORS.TextDim
killsLabel.Font = Enum.Font.Gotham
killsLabel.TextSize = 14
killsLabel.Parent = statsContainer

local killsValue = Instance.new("TextLabel")
killsValue.Name = "KillsValue"
killsValue.Size = UDim2.new(1, 0, 0, 30)
killsValue.Position = UDim2.new(0, 0, 0, 95)
killsValue.BackgroundTransparency = 1
killsValue.Text = "0"
killsValue.TextColor3 = COLORS.Text
killsValue.Font = Enum.Font.GothamBold
killsValue.TextSize = 24
killsValue.Parent = statsContainer

-- Return button
local returnButton = Instance.new("TextButton")
returnButton.Name = "ReturnButton"
returnButton.Size = UDim2.new(0, 300, 0, 50)
returnButton.Position = UDim2.new(0.5, -150, 1, -70)
returnButton.BackgroundColor3 = COLORS.Button
returnButton.Text = "RETURN TO CHARACTER SELECT"
returnButton.TextColor3 = COLORS.Text
returnButton.Font = Enum.Font.GothamBold
returnButton.TextSize = 16
returnButton.AutoButtonColor = false
returnButton.Parent = mainPanel

local returnCorner = Instance.new("UICorner")
returnCorner.CornerRadius = UDim.new(0, 6)
returnCorner.Parent = returnButton

local returnStroke = Instance.new("UIStroke")
returnStroke.Color = Color3.fromRGB(80, 80, 100)
returnStroke.Thickness = 2
returnStroke.Parent = returnButton

--============================================================================
-- ANIMATIONS
--============================================================================

local function showDeathScreen(data)
    -- Update UI with death data
    charInfo.Text = "Level " .. (data.Level or 1) .. " " .. (data.Class or "Unknown")
    fameValue.Text = tostring(data.FameEarned or 0)
    killsValue.Text = tostring(data.EnemiesKilled or 0)

    -- Reset panel position for animation
    mainPanel.Position = UDim2.new(0.5, -225, 0.5, -250)
    background.BackgroundTransparency = 1

    -- Show screen
    screenGui.Enabled = true

    -- Fade in background
    local bgTween = TweenService:Create(background, TweenInfo.new(0.5, Enum.EasingStyle.Quad), {
        BackgroundTransparency = 0.3
    })
    bgTween:Play()

    -- Slide in panel
    local panelTween = TweenService:Create(mainPanel, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
        Position = UDim2.new(0.5, -225, 0.5, -190)
    })
    panelTween:Play()
end

local function hideDeathScreen()
    -- Fade out
    local bgTween = TweenService:Create(background, TweenInfo.new(0.3, Enum.EasingStyle.Quad), {
        BackgroundTransparency = 1
    })
    bgTween:Play()

    local panelTween = TweenService:Create(mainPanel, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
        Position = UDim2.new(0.5, -225, 0.5, -250)
    })
    panelTween:Play()

    panelTween.Completed:Connect(function()
        screenGui.Enabled = false
    end)
end

--============================================================================
-- EVENT HANDLERS
--============================================================================

-- Return button hover effects
returnButton.MouseEnter:Connect(function()
    returnButton.BackgroundColor3 = COLORS.ButtonHover
end)

returnButton.MouseLeave:Connect(function()
    returnButton.BackgroundColor3 = COLORS.Button
end)

-- Helper to show loading screen
local function showLoading(message)
    local loadingAPI = playerGui:FindFirstChild("LoadingScreenAPI")
    if loadingAPI then
        loadingAPI:Fire("Show", message)
    end
end

-- Return button click
returnButton.MouseButton1Click:Connect(function()
    -- print("[DeathScreen] Return button clicked!")

    -- Show loading screen
    showLoading("Returning to Nexus...")

    hideDeathScreen()
    -- Request to return to character select
    -- print("[DeathScreen] Firing ReturnToCharSelect event...")
    Remotes.Events.ReturnToCharSelect:FireServer()
    -- print("[DeathScreen] ReturnToCharSelect event fired")
end)

-- Player death event
-- print("[DeathScreen] Setting up PlayerDeath event listener...")
Remotes.Events.PlayerDeath.OnClientEvent:Connect(function(data)
    -- print("[DeathScreen] !!! PlayerDeath event received !!!")
    -- print("[DeathScreen] Fame: " .. tostring(data.FameEarned))
    -- print("[DeathScreen] Class: " .. tostring(data.Class))
    -- print("[DeathScreen] Level: " .. tostring(data.Level))
    -- print("[DeathScreen] Calling showDeathScreen...")
    showDeathScreen(data)
    -- print("[DeathScreen] showDeathScreen completed")
end)

-- print("[DeathScreen] !!! DeathScreen fully initialized - listening for PlayerDeath events !!!")
