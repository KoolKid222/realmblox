--[[
    CameraController.client.lua
    RotMG-style fixed top-down camera with Q/E continuous rotation
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

-- Camera settings (RotMG style)
local CAMERA_ANGLE = 75           -- Degrees from horizontal (90 = straight down)
local ROTATION_SPEED = 120        -- Degrees per second while holding Q/E

-- Zoom settings
local MIN_ZOOM = 20               -- Closest zoom (lowest height)
local MAX_ZOOM = 50               -- Furthest zoom (max height, current default)
local ZOOM_SPEED = 5              -- How much each scroll tick changes zoom

-- State
local currentRotation = 0         -- Current camera rotation in degrees
local currentZoom = MAX_ZOOM      -- Current camera height (start zoomed out)
local rotationEnabled = true      -- Whether Q/E rotation is enabled

-- Track held keys
local keysHeld = {
    Q = false,
    E = false,
}

-- Cache for rootPart to avoid FindFirstChild every frame
local cachedCharacter = nil
local cachedRootPart = nil

-- Convert angle to radians
local angleRad = math.rad(CAMERA_ANGLE)

-- Calculate camera offset based on angle, zoom, and rotation
local function getCameraOffset()
    local distance = currentZoom / math.sin(angleRad)
    local horizontalOffset = distance * math.cos(angleRad)

    -- Apply rotation
    local rotRad = math.rad(currentRotation)
    local offsetX = math.sin(rotRad) * horizontalOffset
    local offsetZ = math.cos(rotRad) * horizontalOffset

    return Vector3.new(offsetX, currentZoom, offsetZ)
end

-- Handle scroll wheel zoom
local function onInputChanged(input, gameProcessed)
    if gameProcessed then return end

    if input.UserInputType == Enum.UserInputType.MouseWheel then
        -- Scroll up = zoom in (decrease height), scroll down = zoom out (increase height)
        local scrollDirection = input.Position.Z
        currentZoom = currentZoom - (scrollDirection * ZOOM_SPEED)

        -- Clamp to min/max
        currentZoom = math.clamp(currentZoom, MIN_ZOOM, MAX_ZOOM)
    end
end

-- Update camera position and rotation
local function updateCamera(deltaTime)
    local character = player.Character
    if not character then return end

    -- Cache rootPart to avoid FindFirstChild every frame
    if character ~= cachedCharacter then
        cachedCharacter = character
        cachedRootPart = character:FindFirstChild("HumanoidRootPart")
    end

    local humanoidRootPart = cachedRootPart
    if not humanoidRootPart then return end

    -- Continuous rotation while keys are held
    if rotationEnabled then
        if keysHeld.Q then
            currentRotation = currentRotation + ROTATION_SPEED * deltaTime
        end
        if keysHeld.E then
            currentRotation = currentRotation - ROTATION_SPEED * deltaTime
        end
    end

    -- Normalize rotation to 0-360
    currentRotation = currentRotation % 360
    if currentRotation < 0 then
        currentRotation = currentRotation + 360
    end

    -- Fixed camera position (no smoothing - snaps to player)
    local targetPos = humanoidRootPart.Position
    local cameraOffset = getCameraOffset()
    local cameraPos = targetPos + cameraOffset

    -- Set camera CFrame (looking at player)
    camera.CameraType = Enum.CameraType.Scriptable
    camera.CFrame = CFrame.new(cameraPos, targetPos)
end

-- Handle key press
local function onInputBegan(input, gameProcessed)
    if gameProcessed then return end

    if input.KeyCode == Enum.KeyCode.X then
        -- Toggle rotation lock
        rotationEnabled = not rotationEnabled
        -- print("[Camera] Rotation " .. (rotationEnabled and "ENABLED" or "LOCKED"))

    elseif input.KeyCode == Enum.KeyCode.Q then
        keysHeld.Q = true

    elseif input.KeyCode == Enum.KeyCode.E then
        keysHeld.E = true
    end
end

-- Handle key release
local function onInputEnded(input, gameProcessed)
    if input.KeyCode == Enum.KeyCode.Q then
        keysHeld.Q = false

    elseif input.KeyCode == Enum.KeyCode.E then
        keysHeld.E = false
    end
end

-- Wait for character to load
local function onCharacterAdded(character)
    character:WaitForChild("HumanoidRootPart")
end

-- Connect events
player.CharacterAdded:Connect(onCharacterAdded)
if player.Character then
    onCharacterAdded(player.Character)
end

UserInputService.InputBegan:Connect(onInputBegan)
UserInputService.InputEnded:Connect(onInputEnded)
UserInputService.InputChanged:Connect(onInputChanged)

-- Update camera every frame
RunService.RenderStepped:Connect(updateCamera)

-- print("[CameraController] RotMG-style camera initialized (Q/E rotate, X lock, scroll zoom)")
