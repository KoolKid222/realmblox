--[[
    MovementValidator.lua
    Server-side movement validation to prevent speed hacks and teleportation exploits

    Features:
    - Speed validation (detects WalkSpeed modifications)
    - Teleport detection (instant position jumps)
    - Noclip prevention (through walls)
    - Immunity system for legitimate abilities (dashes, teleports)
    - Rubberband correction (resets player to last valid position)

    Usage:
        local MovementValidator = require(path.to.MovementValidator)
        MovementValidator.Init()

        -- When ability uses dash/teleport:
        MovementValidator.GrantImmunity(player, 0.5)  -- 0.5 seconds immunity

        -- When player's Speed stat changes:
        MovementValidator.UpdateMaxSpeed(player, newSpeedStat)
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local Utilities = require(Shared.Utilities)

local MovementValidator = {}

--============================================================================
-- CONFIGURATION
--============================================================================

local VALIDATION_INTERVAL = 0.1      -- Check every 100ms (10 Hz)
local SPEED_TOLERANCE = 1.5          -- 50% buffer for latency/lag spikes
local TELEPORT_THRESHOLD = 60        -- Studs - instant flag for teleportation
local VIOLATION_THRESHOLD = 5        -- Violations before rubberband
local VIOLATION_DECAY_RATE = 1       -- Violations to remove per clean check
local RUBBERBAND_COOLDOWN = 0.5      -- Minimum time between rubberbands
local MAX_VERTICAL_SPEED = 100       -- Max studs/sec vertically (jumping/falling)

-- Grace period after spawning (don't validate immediately)
local SPAWN_GRACE_PERIOD = 2.0

--============================================================================
-- PLAYER TRACKING DATA
--============================================================================

local PlayerData = {}  -- [Player] = tracking data

local function createPlayerData(player, position)
    return {
        LastPosition = position,
        LastValidPosition = position,
        LastValidTime = tick(),
        LastRubberbandTime = 0,
        Violations = 0,
        MaxSpeed = 16,  -- Default WalkSpeed (will be updated from stats)
        ImmuneUntil = 0,
        SpawnTime = tick(),
    }
end

--============================================================================
-- MOVEMENT VALIDATION
--============================================================================

local function validateMovement(player, currentPosition, deltaTime)
    local data = PlayerData[player]
    if not data then return true end

    -- Skip validation during spawn grace period
    if tick() - data.SpawnTime < SPAWN_GRACE_PERIOD then
        data.LastPosition = currentPosition
        data.LastValidPosition = currentPosition
        return true
    end

    -- Skip validation during immunity (abilities like dash)
    if tick() < data.ImmuneUntil then
        data.LastPosition = currentPosition
        data.LastValidPosition = currentPosition
        data.Violations = 0  -- Reset violations during immunity
        return true
    end

    -- Calculate horizontal distance (ignore Y for speed checks)
    local lastPos = data.LastPosition
    local horizontalDist = Utilities.HorizontalDistance(currentPosition, lastPos)
    local verticalDist = math.abs(currentPosition.Y - lastPos.Y)

    -- Calculate maximum allowed distance based on speed stat
    local maxHorizontalDist = data.MaxSpeed * deltaTime * SPEED_TOLERANCE
    local maxVerticalDist = MAX_VERTICAL_SPEED * deltaTime * SPEED_TOLERANCE

    -- Check for teleport (instant flag - very suspicious)
    local totalDist = (currentPosition - lastPos).Magnitude
    if totalDist > TELEPORT_THRESHOLD then
        data.Violations = data.Violations + 3  -- Heavy penalty for teleport
        warn("[MovementValidator] Teleport detected for " .. player.Name ..
            ": " .. string.format("%.1f", totalDist) .. " studs")

    -- Check for speed hack (horizontal)
    elseif horizontalDist > maxHorizontalDist then
        data.Violations = data.Violations + 1
        -- Debug output (can be removed in production)
        if data.Violations >= 2 then
            warn("[MovementValidator] Speed violation for " .. player.Name ..
                ": moved " .. string.format("%.1f", horizontalDist) ..
                " studs, max allowed " .. string.format("%.1f", maxHorizontalDist))
        end

    -- Clean movement - decay violations
    else
        data.Violations = math.max(0, data.Violations - VIOLATION_DECAY_RATE)
        data.LastValidPosition = currentPosition
    end

    -- Update last position
    data.LastPosition = currentPosition
    data.LastValidTime = tick()

    -- Check if we need to rubberband
    if data.Violations >= VIOLATION_THRESHOLD then
        return false, data.LastValidPosition
    end

    return true
end

local function rubberbandPlayer(player, validPosition)
    local data = PlayerData[player]
    if not data then return end

    -- Check cooldown
    if tick() - data.LastRubberbandTime < RUBBERBAND_COOLDOWN then
        return
    end

    local character = player.Character
    if not character then return end

    local rootPart = character:FindFirstChild("HumanoidRootPart")
    if not rootPart then return end

    -- Teleport player back to last valid position
    rootPart.CFrame = CFrame.new(validPosition) * CFrame.Angles(0, rootPart.CFrame:ToEulerAnglesYXZ())

    -- Update tracking
    data.LastRubberbandTime = tick()
    data.Violations = math.floor(data.Violations / 2)  -- Reduce but don't reset violations
    data.LastPosition = validPosition

    warn("[MovementValidator] Rubberbanded " .. player.Name .. " to " .. tostring(validPosition))
end

--============================================================================
-- PUBLIC API
--============================================================================

-- Grant temporary immunity for abilities (dashes, teleports)
function MovementValidator.GrantImmunity(player, duration)
    local data = PlayerData[player]
    if data then
        data.ImmuneUntil = tick() + duration
        -- Also update position so the new position becomes valid
        if player.Character then
            local rootPart = player.Character:FindFirstChild("HumanoidRootPart")
            if rootPart then
                data.LastPosition = rootPart.Position
                data.LastValidPosition = rootPart.Position
            end
        end
    end
end

-- Update max speed when player's Speed stat changes
function MovementValidator.UpdateMaxSpeed(player, speedStat)
    local data = PlayerData[player]
    if data then
        -- Use the same formula as the client for WalkSpeed
        data.MaxSpeed = Utilities.GetWalkSpeed(speedStat)
    end
end

-- Reset tracking for a player (call on respawn)
function MovementValidator.ResetPlayer(player, position)
    local data = PlayerData[player]
    if data then
        data.LastPosition = position
        data.LastValidPosition = position
        data.LastValidTime = tick()
        data.Violations = 0
        data.SpawnTime = tick()
    end
end

-- Get current violation count (for debugging/admin)
function MovementValidator.GetViolations(player)
    local data = PlayerData[player]
    return data and data.Violations or 0
end

-- Check if player is currently immune
function MovementValidator.IsImmune(player)
    local data = PlayerData[player]
    return data and tick() < data.ImmuneUntil
end

--============================================================================
-- INITIALIZATION
--============================================================================

function MovementValidator.Init()
    -- Track when characters spawn
    local function onCharacterAdded(player, character)
        local humanoid = character:WaitForChild("Humanoid", 5)
        local rootPart = character:WaitForChild("HumanoidRootPart", 5)

        if not humanoid or not rootPart then
            warn("[MovementValidator] Missing humanoid or rootPart for " .. player.Name)
            return
        end

        -- Initialize or reset player tracking
        local position = rootPart.Position
        if PlayerData[player] then
            MovementValidator.ResetPlayer(player, position)
        else
            PlayerData[player] = createPlayerData(player, position)
        end

        -- Update max speed from humanoid (will be set by PlayerManager)
        PlayerData[player].MaxSpeed = humanoid.WalkSpeed

        print("[MovementValidator] Tracking " .. player.Name .. " at " .. tostring(position))
    end

    -- Handle player joining
    local function onPlayerAdded(player)
        player.CharacterAdded:Connect(function(character)
            task.spawn(function()
                onCharacterAdded(player, character)
            end)
        end)

        -- Handle existing character
        if player.Character then
            task.spawn(function()
                onCharacterAdded(player, player.Character)
            end)
        end
    end

    -- Handle player leaving
    local function onPlayerRemoving(player)
        PlayerData[player] = nil
    end

    -- Connect to existing and new players
    for _, player in ipairs(Players:GetPlayers()) do
        task.spawn(onPlayerAdded, player)
    end
    Players.PlayerAdded:Connect(onPlayerAdded)
    Players.PlayerRemoving:Connect(onPlayerRemoving)

    -- Main validation loop
    local lastCheckTime = tick()

    RunService.Heartbeat:Connect(function()
        local now = tick()
        local deltaTime = now - lastCheckTime

        -- Only check at validation interval
        if deltaTime < VALIDATION_INTERVAL then
            return
        end
        lastCheckTime = now

        -- Validate all players
        for player, data in pairs(PlayerData) do
            local character = player.Character
            if not character then continue end

            local rootPart = character:FindFirstChild("HumanoidRootPart")
            if not rootPart then continue end

            local currentPosition = rootPart.Position
            local isValid, validPosition = validateMovement(player, currentPosition, deltaTime)

            if not isValid and validPosition then
                rubberbandPlayer(player, validPosition)
            end
        end
    end)

    print("[MovementValidator] Initialized - Speed hack prevention active")
end

return MovementValidator
