--[[
    ProjectileVisuals.lua
    Handles projectile visual representation on the client
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local Constants = require(Shared.Constants)

local player = Players.LocalPlayer

local ProjectileVisuals = {}

-- Hitbox constants for client-side hit detection
local PLAYER_HITBOX_RADIUS = Constants.Hitbox and Constants.Hitbox.PLAYER_RADIUS or 0.5
local PROJECTILE_HITBOX_RADIUS = Constants.Hitbox and Constants.Hitbox.PROJECTILE_RADIUS or 0.15

-- PERFORMANCE FIX: ProjectileRenderer handles visual rendering
-- This module handles hit detection for enemy projectiles → player
local RENDER_PARTS = false  -- Disable Part rendering (ProjectileRenderer handles it)
local HIT_DETECTION_ENABLED = true  -- Keep hit detection (enemy → player)

-- Pre-cached NumberSequence for trails (avoid GC pressure)
local TRAIL_TRANSPARENCY = NumberSequence.new(0, 1)

-- Active projectiles (for hit detection only, not rendering)
ProjectileVisuals.Projectiles = {}  -- [id] = projectileData

-- Projectile pool for performance (only used if RENDER_PARTS is true)
local projectilePool = {}
local POOL_SIZE = 500

-- Container
local projectileContainer = nil

-- Get or create a projectile part
local function getProjectile()
    for i, proj in ipairs(projectilePool) do
        if not proj.InUse then
            proj.InUse = true
            -- Disable trail BEFORE repositioning (prevents visual glitch)
            if proj.Trail then
                proj.Trail.Enabled = false
            end
            proj.Part.Transparency = 0
            return proj
        end
    end

    -- Pool exhausted, create new
    local part = Instance.new("Part")
    part.Name = "Projectile"
    part.Size = Vector3.new(1, 1, 2)
    part.Material = Enum.Material.Neon
    part.Anchored = true
    part.CanCollide = false
    part.CastShadow = false
    part.Parent = projectileContainer

    -- Trail effect
    local attachment0 = Instance.new("Attachment")
    attachment0.Position = Vector3.new(0, 0, 1)
    attachment0.Parent = part

    local attachment1 = Instance.new("Attachment")
    attachment1.Position = Vector3.new(0, 0, -1)
    attachment1.Parent = part

    local trail = Instance.new("Trail")
    trail.Attachment0 = attachment0
    trail.Attachment1 = attachment1
    trail.Lifetime = 0.2
    trail.MinLength = 0.1
    trail.FaceCamera = true
    trail.Transparency = TRAIL_TRANSPARENCY
    trail.Enabled = false  -- Start disabled, enable after positioning
    trail.Parent = part

    local proj = {Part = part, Trail = trail, InUse = true}
    table.insert(projectilePool, proj)

    return proj
end

-- Return projectile to pool
local function returnProjectile(proj)
    proj.InUse = false
    -- Disable trail before moving to prevent visual artifacts
    if proj.Trail then
        proj.Trail.Enabled = false
    end
    proj.Part.Transparency = 1
    proj.Part.Position = Vector3.new(0, -1000, 0)  -- Move out of view
end

-- Create projectile visual (or just tracking data if RENDER_PARTS is false)
local function createProjectileVisual(data)
    local pooledProj = nil
    local direction = data.Direction

    -- Only create visual Parts if RENDER_PARTS is enabled
    -- Otherwise, just track position data for hit detection
    if RENDER_PARTS then
        pooledProj = getProjectile()
        local part = pooledProj.Part

        -- Set visual properties
        local size = data.Size or 1
        part.Size = Vector3.new(size, size, size * 2)
        local color = data.Color or Color3.fromRGB(255, 255, 0)

        -- Enemy projectiles are red-tinted
        if data.IsEnemy then
            color = data.Color or Color3.fromRGB(255, 100, 100)
        end

        part.Color = color
        pooledProj.Trail.Color = ColorSequence.new(color)

        -- Orient in direction of travel (set CFrame BEFORE enabling trail)
        if direction.Magnitude > 0 then
            part.CFrame = CFrame.new(data.Position, data.Position + direction)
        else
            part.Position = data.Position
        end

        -- Enable trail AFTER positioning (prevents visual glitch from pool reuse)
        pooledProj.Trail.Enabled = true
    end

    return {
        Id = data.Id,
        PooledProjectile = pooledProj,  -- nil if RENDER_PARTS is false
        Position = data.Position,
        BasePosition = data.Position,       -- For wave pattern
        Direction = direction,
        Speed = data.Speed,
        SpawnTime = tick(),
        Lifetime = data.Lifetime,

        -- Wave pattern data (DNA helix)
        WavePattern = data.WavePattern or false,
        WaveAmplitude = data.WaveAmplitude or 0,
        WaveFrequency = data.WaveFrequency or 0,
        WaveSign = data.WaveSign or 1,

        -- Enemy projectile data (for client-side hit detection)
        IsEnemy = data.IsEnemy or false,
        HasHitLocal = false,  -- Prevents duplicate hit events
        Damage = data.Damage or 20,
        HitboxRadius = data.HitboxRadius or PROJECTILE_HITBOX_RADIUS,
    }
end

-- Calculate wave offset perpendicular to direction (DNA helix pattern)
local function getWaveOffset(proj, elapsedTime)
    if not proj.WavePattern or proj.WaveAmplitude == 0 then
        return Vector3.new(0, 0, 0)
    end

    -- Calculate perpendicular direction (rotate 90 degrees on Y axis)
    local perpendicular = Vector3.new(-proj.Direction.Z, 0, proj.Direction.X)

    -- Sinusoidal wave: amplitude * sin(frequency * time) * waveSign
    -- WaveSign of -1 or 1 creates the mirrored DNA helix
    local sineValue = math.sin(proj.WaveFrequency * elapsedTime)
    local waveValue = proj.WaveAmplitude * sineValue * proj.WaveSign

    return perpendicular * waveValue
end

-- Handle projectile spawn
local function onProjectileSpawn(data)
    -- DISABLED: ProjectileRenderer now handles ALL projectile visuals
    -- This module only tracks enemy projectiles for hit detection

    -- Skip non-enemy projectiles (we only need to track enemy projectiles for player hit detection)
    if not data.IsEnemy then
        return
    end

    -- DEBUG: Log enemy projectile spawns
    print("[ProjectileVisuals] Enemy projectile spawn - Id:", data.Id)

    local visual = createProjectileVisual(data)
    ProjectileVisuals.Projectiles[data.Id] = visual
end

--============================================================================
-- CLIENT-SIDE HIT DETECTION (Client-Authoritative with Server Verification)
-- Detects hits locally for crisp gameplay, server verifies for anti-cheat
--============================================================================

local function checkLocalPlayerHit()
    -- Skip if hit detection is disabled (ProjectileRenderer handles it)
    if not HIT_DETECTION_ENABLED then return end

    local character = player.Character
    if not character then return end

    local rootPart = character:FindFirstChild("HumanoidRootPart")
    if not rootPart then return end

    local playerPos = rootPart.Position

    for id, proj in pairs(ProjectileVisuals.Projectiles) do
        -- Only check enemy projectiles that haven't already hit locally
        if proj.IsEnemy and not proj.HasHitLocal then
            -- 2D distance calculation (XZ plane only, ignore Y)
            local dx = proj.Position.X - playerPos.X
            local dz = proj.Position.Z - playerPos.Z
            local horizontalDist = math.sqrt(dx * dx + dz * dz)

            -- Use projectile's specific hitbox radius if available
            local actualHitRadius = PLAYER_HITBOX_RADIUS + (proj.HitboxRadius or PROJECTILE_HITBOX_RADIUS)

            if horizontalDist < actualHitRadius then
                -- Mark as hit locally to prevent duplicate events
                proj.HasHitLocal = true

                -- Report hit to server for verification and damage application
                Remotes.Events.PlayerHitByProjectile:FireServer(id, proj.Position)

                -- Remove projectile visually (server will verify)
                proj.Lifetime = 0  -- Forces removal in next update
            end
        end
    end
end

-- Update all projectiles
local function updateProjectiles(deltaTime)
    local currentTime = tick()
    local toRemove = {}

    -- Update all projectile positions
    for id, proj in pairs(ProjectileVisuals.Projectiles) do
        -- Check lifetime
        if currentTime - proj.SpawnTime > proj.Lifetime then
            table.insert(toRemove, id)
        else
            -- Update base position (linear movement)
            proj.BasePosition = proj.BasePosition + proj.Direction * proj.Speed * deltaTime

            -- Calculate wave offset for actual position
            local elapsedTime = currentTime - proj.SpawnTime
            local waveOffset = getWaveOffset(proj, elapsedTime)
            proj.Position = proj.BasePosition + waveOffset

            -- Update visual (only if RENDER_PARTS is enabled)
            if proj.PooledProjectile then
                local part = proj.PooledProjectile.Part
                part.CFrame = CFrame.new(proj.Position, proj.Position + proj.Direction)
            end
        end
    end

    -- THEN: Check for hits using CURRENT positions (matches visual)
    -- This ensures hit detection uses the same position the player sees
    checkLocalPlayerHit()

    -- Remove expired projectiles
    for _, id in ipairs(toRemove) do
        local proj = ProjectileVisuals.Projectiles[id]
        if proj then
            if proj.PooledProjectile then
                returnProjectile(proj.PooledProjectile)
            end
            ProjectileVisuals.Projectiles[id] = nil
        end
    end
end

-- Initialize projectile pool
local function initializePool()
    for i = 1, POOL_SIZE do
        local part = Instance.new("Part")
        part.Name = "Projectile"
        part.Size = Vector3.new(1, 1, 2)
        part.Material = Enum.Material.Neon
        part.Anchored = true
        part.CanCollide = false
        part.CastShadow = false
        part.Transparency = 1
        part.Position = Vector3.new(0, -1000, 0)
        part.Parent = projectileContainer

        local attachment0 = Instance.new("Attachment")
        attachment0.Position = Vector3.new(0, 0, 1)
        attachment0.Parent = part

        local attachment1 = Instance.new("Attachment")
        attachment1.Position = Vector3.new(0, 0, -1)
        attachment1.Parent = part

        local trail = Instance.new("Trail")
        trail.Attachment0 = attachment0
        trail.Attachment1 = attachment1
        trail.Lifetime = 0.2
        trail.MinLength = 0.1
        trail.FaceCamera = true
        trail.Transparency = TRAIL_TRANSPARENCY
        trail.Enabled = false  -- Start disabled, enable when projectile is used
        trail.Parent = part

        table.insert(projectilePool, {Part = part, Trail = trail, InUse = false})
    end
end

-- Initialize
function ProjectileVisuals.Init()
    -- Only create container and pool if we're rendering Parts
    if RENDER_PARTS then
        -- Create container
        projectileContainer = workspace:FindFirstChild("Projectiles")
        if not projectileContainer then
            projectileContainer = Instance.new("Folder")
            projectileContainer.Name = "Projectiles"
            projectileContainer.Parent = workspace
        end

        -- Initialize pool
        initializePool()
    end

    -- DISABLED: ProjectileRenderer now handles ALL projectile visuals and tracking
    -- Hit detection for enemy→player is now in ProjectileRenderer
    -- if Remotes.Events.ProjectileSpawn then
    --     Remotes.Events.ProjectileSpawn.OnClientEvent:Connect(onProjectileSpawn)
    -- end

    -- Batch projectile spawns (optimization for many projectiles)
    -- if Remotes.Events.ProjectileBatch then
    --     Remotes.Events.ProjectileBatch.OnClientEvent:Connect(function(batch)
    --         for _, data in ipairs(batch) do
    --             onProjectileSpawn(data)
    --         end
    --     end)
    -- end

    -- Update loop
    RunService.RenderStepped:Connect(updateProjectiles)
end

return ProjectileVisuals
