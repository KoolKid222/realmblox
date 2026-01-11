--[[
    MovementController.client.lua
    WASD movement for top-down game (movement relative to world, not camera)

    Uses RotMG SPD formula: WalkSpeed = BASE + (SPD * 0.2)
    Reads SPD from Character Attributes for zero-latency response
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Utilities = require(Shared.Utilities)

local player = Players.LocalPlayer

-- Movement settings (fallback if no Speed attribute)
local DEFAULT_WALK_SPEED = 16

-- Track which keys are pressed
local keysPressed = {
    W = false,
    A = false,
    S = false,
    D = false,
}

-- Key mappings
local keyMap = {
    [Enum.KeyCode.W] = "W",
    [Enum.KeyCode.A] = "A",
    [Enum.KeyCode.S] = "S",
    [Enum.KeyCode.D] = "D",
    -- Arrow keys as alternative
    [Enum.KeyCode.Up] = "W",
    [Enum.KeyCode.Left] = "A",
    [Enum.KeyCode.Down] = "S",
    [Enum.KeyCode.Right] = "D",
}

-- Handle key press
local function onInputBegan(input, gameProcessed)
    if gameProcessed then return end

    local key = keyMap[input.KeyCode]
    if key then
        keysPressed[key] = true
    end
end

-- Handle key release
local function onInputEnded(input, gameProcessed)
    local key = keyMap[input.KeyCode]
    if key then
        keysPressed[key] = false
    end
end

-- Calculate movement direction from keys
local function getMovementDirection()
    local direction = Vector3.new(0, 0, 0)

    if keysPressed.W then
        direction = direction + Vector3.new(0, 0, -1)
    end
    if keysPressed.S then
        direction = direction + Vector3.new(0, 0, 1)
    end
    if keysPressed.A then
        direction = direction + Vector3.new(-1, 0, 0)
    end
    if keysPressed.D then
        direction = direction + Vector3.new(1, 0, 0)
    end

    -- Normalize so diagonal movement isn't faster
    if direction.Magnitude > 0 then
        direction = direction.Unit
    end

    return direction
end

-- Apply movement each frame
local function updateMovement()
    local character = player.Character
    if not character then return end

    local humanoid = character:FindFirstChild("Humanoid")
    local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
    if not humanoid or not humanoidRootPart then return end

    local moveDirection = getMovementDirection()

    -- Move the humanoid
    humanoid:Move(moveDirection, false) -- false = world relative, not camera relative
end

-- Connect input events
UserInputService.InputBegan:Connect(onInputBegan)
UserInputService.InputEnded:Connect(onInputEnded)

-- Update movement each frame
RunService.Heartbeat:Connect(updateMovement)

-- Calculate walk speed from Speed attribute using RotMG formula
local function getWalkSpeedFromAttributes(character)
    local speedStat = character:GetAttribute("Speed")
    if speedStat then
        return Utilities.GetWalkSpeed(speedStat)
    end
    return DEFAULT_WALK_SPEED
end

-- Update walk speed when Speed attribute changes
local function setupSpeedListener(character)
    local humanoid = character:FindFirstChild("Humanoid")
    if not humanoid then return end

    -- Set initial speed
    humanoid.WalkSpeed = getWalkSpeedFromAttributes(character)

    -- Listen for Speed attribute changes (zero-latency updates)
    character:GetAttributeChangedSignal("Speed"):Connect(function()
        humanoid.WalkSpeed = getWalkSpeedFromAttributes(character)
    end)
end

-- Set walk speed when character loads
local function onCharacterAdded(character)
    local humanoid = character:WaitForChild("Humanoid")

    -- Initial speed (fallback until attributes are set)
    humanoid.WalkSpeed = DEFAULT_WALK_SPEED

    -- DISABLE JUMPING (Space bar is used for abilities in RotMG)
    humanoid.JumpPower = 0
    humanoid.JumpHeight = 0

    -- Also disable the jump state change
    humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)

    -- Wait a moment for attributes to be set by server
    task.spawn(function()
        task.wait(0.2)
        setupSpeedListener(character)
    end)
end

player.CharacterAdded:Connect(onCharacterAdded)
if player.Character then
    onCharacterAdded(player.Character)
end

-- print("[MovementController] WASD movement initialized (RotMG SPD formula, jumping disabled)")
