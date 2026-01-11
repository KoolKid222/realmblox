--[[
    LoadingScreen.client.lua
    Simple loading screen for transitions (entering game, returning to menu)
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Check for existing UI
local existingUI = playerGui:FindFirstChild("LoadingScreenUI")
if existingUI then
    existingUI:Destroy()
end

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
Remotes.Init()

--============================================================================
-- UI SETUP
--============================================================================

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "LoadingScreenUI"
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 100  -- Show above other UIs
screenGui.Enabled = false
screenGui.Parent = playerGui

-- Full screen dark background
local background = Instance.new("Frame")
background.Name = "Background"
background.Size = UDim2.new(1, 0, 1, 0)
background.BackgroundColor3 = Color3.fromRGB(10, 10, 15)
background.BackgroundTransparency = 0
background.BorderSizePixel = 0
background.Parent = screenGui

-- Loading text
local loadingText = Instance.new("TextLabel")
loadingText.Name = "LoadingText"
loadingText.Size = UDim2.new(0, 300, 0, 50)
loadingText.Position = UDim2.new(0.5, -150, 0.5, -50)
loadingText.BackgroundTransparency = 1
loadingText.Text = "LOADING"
loadingText.TextColor3 = Color3.fromRGB(255, 255, 255)
loadingText.Font = Enum.Font.GothamBold
loadingText.TextSize = 32
loadingText.Parent = background

-- Subtitle text (shows what's happening)
local subtitleText = Instance.new("TextLabel")
subtitleText.Name = "SubtitleText"
subtitleText.Size = UDim2.new(0, 400, 0, 30)
subtitleText.Position = UDim2.new(0.5, -200, 0.5, 10)
subtitleText.BackgroundTransparency = 1
subtitleText.Text = "Preparing your adventure..."
subtitleText.TextColor3 = Color3.fromRGB(180, 180, 180)
subtitleText.Font = Enum.Font.Gotham
subtitleText.TextSize = 16
subtitleText.Parent = background

-- Spinner container
local spinnerContainer = Instance.new("Frame")
spinnerContainer.Name = "SpinnerContainer"
spinnerContainer.Size = UDim2.new(0, 60, 0, 60)
spinnerContainer.Position = UDim2.new(0.5, -30, 0.5, 50)
spinnerContainer.BackgroundTransparency = 1
spinnerContainer.Parent = background

-- Create spinner dots
local NUM_DOTS = 8
local dots = {}
for i = 1, NUM_DOTS do
    local angle = (i - 1) * (360 / NUM_DOTS)
    local rad = math.rad(angle)
    local radius = 25

    local dot = Instance.new("Frame")
    dot.Name = "Dot" .. i
    dot.Size = UDim2.new(0, 8, 0, 8)
    dot.Position = UDim2.new(0.5, math.cos(rad) * radius - 4, 0.5, math.sin(rad) * radius - 4)
    dot.BackgroundColor3 = Color3.fromRGB(100, 150, 255)
    dot.BackgroundTransparency = 0.7
    dot.BorderSizePixel = 0
    dot.Parent = spinnerContainer

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(1, 0)
    corner.Parent = dot

    dots[i] = dot
end

--============================================================================
-- ANIMATION
--============================================================================

local isAnimating = false
local animationConnection = nil
local dotAnimationTime = 0

local function startAnimation()
    if isAnimating then return end
    isAnimating = true
    dotAnimationTime = 0

    animationConnection = RunService.RenderStepped:Connect(function(dt)
        dotAnimationTime = dotAnimationTime + dt

        -- Animate dots (wave pattern)
        for i, dot in ipairs(dots) do
            local offset = (i - 1) / NUM_DOTS
            local wave = math.sin((dotAnimationTime * 3) - (offset * math.pi * 2))
            local transparency = 0.3 + (0.5 * (1 - (wave + 1) / 2))
            dot.BackgroundTransparency = transparency

            -- Slight scale pulse
            local scale = 1 + (0.3 * (wave + 1) / 2)
            dot.Size = UDim2.new(0, 8 * scale, 0, 8 * scale)
        end

        -- Animate loading text dots
        local dotCount = math.floor(dotAnimationTime * 2) % 4
        loadingText.Text = "LOADING" .. string.rep(".", dotCount)
    end)
end

local function stopAnimation()
    isAnimating = false
    if animationConnection then
        animationConnection:Disconnect()
        animationConnection = nil
    end
end

--============================================================================
-- SHOW/HIDE FUNCTIONS
--============================================================================

local function showLoading(message)
    subtitleText.Text = message or "Preparing your adventure..."
    background.BackgroundTransparency = 1
    screenGui.Enabled = true
    startAnimation()

    -- Fade in
    TweenService:Create(background, TweenInfo.new(0.3), {
        BackgroundTransparency = 0
    }):Play()
end

local function hideLoading()
    -- Fade out
    local tween = TweenService:Create(background, TweenInfo.new(0.3), {
        BackgroundTransparency = 1
    })
    tween:Play()
    tween.Completed:Connect(function()
        screenGui.Enabled = false
        stopAnimation()
    end)
end

--============================================================================
-- PUBLIC API (accessible via module-like pattern)
--============================================================================

-- Store functions globally so other scripts can access them
local LoadingScreen = {}
LoadingScreen.Show = showLoading
LoadingScreen.Hide = hideLoading

-- Make accessible via shared storage
local loadingModule = Instance.new("BindableEvent")
loadingModule.Name = "LoadingScreenAPI"
loadingModule.Parent = playerGui

-- Listen for show/hide requests via BindableEvent
loadingModule.Event:Connect(function(action, message)
    if action == "Show" then
        showLoading(message)
    elseif action == "Hide" then
        hideLoading()
    end
end)

-- Also listen for remote events from server
Remotes.Events.ShowLoading.OnClientEvent:Connect(function(message)
    showLoading(message)
end)

Remotes.Events.HideLoading.OnClientEvent:Connect(function()
    hideLoading()
end)

print("[LoadingScreen] Initialized")
