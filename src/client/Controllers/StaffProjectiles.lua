--[[
    StaffProjectiles.lua
    RotMG-style staff projectile visuals with DNA helix pattern

    Client-side visual rendering using parametric sine wave motion.
    Two projectiles fire simultaneously and cross over each other.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)

local player = Players.LocalPlayer

local StaffProjectiles = {}

--============================================================================
-- TUNABLE VARIABLES (Adjust these to match RotMG feel)
--============================================================================
local PROJECTILE_SPEED = 80        -- Studs per second
local LIFETIME = 0.43              -- Range 8.6 units * 4 studs / 80 speed = ~0.43 sec
local AMPLITUDE = 2                -- Width of sine wave (studs)
local FREQUENCY = 15               -- Speed of wave oscillation (higher = more crossings)
local PROJECTILE_LENGTH = 2        -- Length of stretched projectile
local PROJECTILE_WIDTH = 0.5       -- Width/height of projectile
local PROJECTILE_COLOR = Color3.fromRGB(180, 100, 255)  -- Purple neon

--============================================================================
-- Projectile Pool
--============================================================================
local projectilePool = {}
local POOL_SIZE = 100

local projectileContainer = nil

-- Create a single projectile part
local function createProjectilePart()
    local part = Instance.new("Part")
    part.Name = "StaffProjectile"
    part.Size = Vector3.new(PROJECTILE_WIDTH, PROJECTILE_WIDTH, PROJECTILE_LENGTH)
    part.Material = Enum.Material.Neon
    part.Color = PROJECTILE_COLOR
    part.Anchored = true
    part.CanCollide = false
    part.CastShadow = false
    part.Transparency = 1  -- Start hidden
    part.Parent = projectileContainer

    return part
end

-- Get a projectile from pool
local function getProjectile()
    for _, proj in ipairs(projectilePool) do
        if not proj.InUse then
            proj.InUse = true
            proj.Part.Transparency = 0
            return proj
        end
    end

    -- Pool exhausted, create new
    local part = createProjectilePart()
    part.Transparency = 0
    local proj = {Part = part, InUse = true}
    table.insert(projectilePool, proj)
    return proj
end

-- Return projectile to pool
local function returnProjectile(proj)
    proj.InUse = false
    proj.Part.Transparency = 1
    proj.Part.Position = Vector3.new(0, -1000, 0)
end

-- Initialize pool
local function initializePool()
    projectileContainer = workspace:FindFirstChild("StaffProjectiles")
    if not projectileContainer then
        projectileContainer = Instance.new("Folder")
        projectileContainer.Name = "StaffProjectiles"
        projectileContainer.Parent = workspace
    end

    for i = 1, POOL_SIZE do
        local part = createProjectilePart()
        table.insert(projectilePool, {Part = part, InUse = false})
    end
end

--============================================================================
-- Active Projectiles
--============================================================================
local activeProjectiles = {}

--[[
    Projectile structure:
    {
        PooledPart = pooled part reference,
        StartPosition = Vector3,
        Direction = Vector3 (normalized forward direction),
        RightVector = Vector3 (perpendicular to direction, for sine offset),
        SpawnTime = number,
        WaveSign = 1 or -1 (determines which side of helix),
    }
]]

-- Create a pair of staff projectiles (DNA helix)
function StaffProjectiles.FireStaffShot(startPosition, direction)
    -- Normalize direction (horizontal only)
    direction = Vector3.new(direction.X, 0, direction.Z)
    if direction.Magnitude > 0 then
        direction = direction.Unit
    else
        return
    end

    -- Calculate right vector (perpendicular to direction)
    local rightVector = Vector3.new(-direction.Z, 0, direction.X)

    local currentTime = tick()

    -- Create two projectiles with opposite wave signs
    for waveSign = -1, 1, 2 do  -- -1 and 1
        local pooledProj = getProjectile()

        local projectile = {
            PooledPart = pooledProj,
            StartPosition = startPosition,
            Direction = direction,
            RightVector = rightVector,
            SpawnTime = currentTime,
            WaveSign = waveSign,
        }

        table.insert(activeProjectiles, projectile)
    end
end

-- Update all projectiles (called every frame)
local function updateProjectiles(deltaTime)
    local currentTime = tick()
    local toRemove = {}

    for i, proj in ipairs(activeProjectiles) do
        local elapsed = currentTime - proj.SpawnTime

        -- Check lifetime
        if elapsed > LIFETIME then
            table.insert(toRemove, i)
        else
            -- Calculate position using parametric equations
            -- Forward position = start + direction * speed * time
            local forwardDistance = PROJECTILE_SPEED * elapsed
            local forwardPosition = proj.StartPosition + proj.Direction * forwardDistance

            -- Sine wave offset perpendicular to direction
            -- WaveSign determines if this bullet goes right-first or left-first
            local sineValue = math.sin(FREQUENCY * elapsed)
            local lateralOffset = proj.RightVector * (AMPLITUDE * sineValue * proj.WaveSign)

            -- Final position
            local finalPosition = forwardPosition + lateralOffset

            -- Calculate velocity direction for orientation (derivative of position)
            -- d/dt of sin(freq * t) = freq * cos(freq * t)
            local cosValue = math.cos(FREQUENCY * elapsed)
            local lateralVelocity = proj.RightVector * (AMPLITUDE * FREQUENCY * cosValue * proj.WaveSign)
            local forwardVelocity = proj.Direction * PROJECTILE_SPEED
            local totalVelocity = forwardVelocity + lateralVelocity

            -- Orient projectile in direction of travel (stretched along velocity)
            if totalVelocity.Magnitude > 0 then
                local lookDirection = totalVelocity.Unit
                proj.PooledPart.Part.CFrame = CFrame.new(finalPosition, finalPosition + lookDirection)
            else
                proj.PooledPart.Part.Position = finalPosition
            end
        end
    end

    -- Remove expired projectiles (reverse order)
    for i = #toRemove, 1, -1 do
        local index = toRemove[i]
        local proj = activeProjectiles[index]
        returnProjectile(proj.PooledPart)
        table.remove(activeProjectiles, index)
    end
end

--============================================================================
-- Network Events
--============================================================================

-- Listen for staff shots from server (for other players' projectiles)
local function onProjectileSpawn(data)
    -- Only handle staff projectiles with wave pattern
    if data.WavePattern and data.WaveAmplitude and data.WaveAmplitude > 0 then
        -- This is handled by the server broadcast for other players
        -- Local player's shots are created directly in CombatController
        return
    end
end

--============================================================================
-- Initialization
--============================================================================
function StaffProjectiles.Init()
    initializePool()

    -- Update loop
    RunService.RenderStepped:Connect(updateProjectiles)

    -- Listen for remote projectiles (other players)
    -- Remotes.Events.ProjectileSpawn.OnClientEvent:Connect(onProjectileSpawn)

    print("[StaffProjectiles] Initialized with DNA helix pattern")
    print("  Speed:", PROJECTILE_SPEED, "studs/sec")
    print("  Lifetime:", LIFETIME, "sec")
    print("  Amplitude:", AMPLITUDE, "studs")
    print("  Frequency:", FREQUENCY)
end

--============================================================================
-- Public API for tweaking at runtime
--============================================================================
function StaffProjectiles.SetSpeed(speed)
    PROJECTILE_SPEED = speed
end

function StaffProjectiles.SetLifetime(lifetime)
    LIFETIME = lifetime
end

function StaffProjectiles.SetAmplitude(amplitude)
    AMPLITUDE = amplitude
end

function StaffProjectiles.SetFrequency(frequency)
    FREQUENCY = frequency
end

function StaffProjectiles.GetSettings()
    return {
        Speed = PROJECTILE_SPEED,
        Lifetime = LIFETIME,
        Amplitude = AMPLITUDE,
        Frequency = FREQUENCY,
    }
end

return StaffProjectiles
