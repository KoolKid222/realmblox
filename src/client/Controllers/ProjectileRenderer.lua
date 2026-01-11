--[[
    ProjectileRenderer.lua
    Exact RotMG Projectile.as implementation

    Source: Projectile.as positionAt() function
    Movement patterns:
    - Wavy: angle + (π/64) * sin(phase + (6π * time / 1000))
    - Amplitude: amplitude * sin(phase + (elapsed/lifetime * frequency * 2π))
    - Parametric: Lissajous curves with magnitude scaling
    - Boomerang: Reverses direction at midpoint

    Collision: Horizontal distance check with radius
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)

-- PartCache for object pooling
local Lib = Shared:WaitForChild("Lib")
local PartCache = require(Lib.PartCache)

local player = Players.LocalPlayer

local ProjectileRenderer = {}

-- Lazy-loaded dependencies (to avoid circular requires)
local EnemyVisuals = nil
local CombatController = nil
local DamageNumbers = nil

local function getEnemyVisuals()
    if not EnemyVisuals then
        EnemyVisuals = require(script.Parent.EnemyVisuals)
    end
    return EnemyVisuals
end

local function getCombatController()
    if not CombatController then
        CombatController = require(script.Parent.CombatController)
    end
    return CombatController
end

local function getDamageNumbers()
    if not DamageNumbers then
        DamageNumbers = require(script.Parent.DamageNumbers)
    end
    return DamageNumbers
end

-- Client-side damage display (immediate feedback, no server round-trip)
-- DISABLED: Server sends accurate damage numbers via PlayerHitEnemy handler
-- This prevents duplicate/inaccurate damage indicators (client showed 80, server calculated ~40)
local LOCAL_DAMAGE_DISPLAY = false  -- Let server send actual damage
local BASE_WEAPON_DAMAGE = 80  -- (unused when LOCAL_DAMAGE_DISPLAY = false)

-- Hit detection settings
local HIT_DETECTION_ENABLED = true
local PROJECTILE_HIT_RADIUS = 0.8  -- Base projectile collision radius
local SPATIAL_QUERY_RADIUS = 30    -- Radius for spatial grid query (cells check)

-- Enemy→Player hit detection (client-authoritative)
local ENEMY_HIT_DETECTION_ENABLED = true
local PLAYER_HITBOX_RADIUS = 2.0  -- Player collision radius
local ENEMY_PROJECTILE_RADIUS = 1.5  -- Enemy projectile collision radius

--============================================================================
-- ROTMG PROJECTILE CONSTANTS (from Projectile.as)
--============================================================================

local POOL_SIZE = 300
local TRAILS_ENABLED = true           -- Player projectile trails
local ENEMY_TRAILS_ENABLED = true     -- Re-enabled (fixed duplicate projectile rendering)

-- RotMG wave constants (from positionAt)
local WAVY_PERIOD = 6 * math.pi           -- 6π - wave period for wavy projectiles
local WAVY_MAGNITUDE = math.pi / 64       -- π/64 - angle deviation magnitude

-- Pre-cached NumberSequences (avoid GC pressure from repeated allocation)
local TRAIL_TRANSPARENCY = NumberSequence.new({
    NumberSequenceKeypoint.new(0, 0),
    NumberSequenceKeypoint.new(1, 1),
})
local TRAIL_WIDTH_PLAYER = NumberSequence.new({
    NumberSequenceKeypoint.new(0, 1),
    NumberSequenceKeypoint.new(1, 0.3),
})
local TRAIL_WIDTH_ENEMY = NumberSequence.new({
    NumberSequenceKeypoint.new(0, 1.5),
    NumberSequenceKeypoint.new(1, 0.5),
})

-- Pre-cached ColorSequences for common projectile colors
local CACHED_COLOR_SEQUENCES = {}
local function getColorSequence(color)
    -- Use color as a simple key (R*1000000 + G*1000 + B)
    local key = math.floor(color.R * 255) * 1000000 + math.floor(color.G * 255) * 1000 + math.floor(color.B * 255)
    local cached = CACHED_COLOR_SEQUENCES[key]
    if not cached then
        cached = ColorSequence.new(color)
        CACHED_COLOR_SEQUENCES[key] = cached
    end
    return cached
end

--============================================================================
-- PROJECTILE TEMPLATE
--============================================================================

local function createTemplate()
    local part = Instance.new("Part")
    part.Name = "Projectile"
    part.Size = Vector3.new(0.5, 0.5, 2)
    part.Material = Enum.Material.Neon
    part.Color = Color3.fromRGB(255, 255, 255)
    part.Anchored = true
    part.CanCollide = false
    part.CastShadow = false
    part.Transparency = 0

    -- Trail effect (only create attachments and trail if enabled)
    if TRAILS_ENABLED then
        local attach0 = Instance.new("Attachment")
        attach0.Name = "TrailStart"
        attach0.Position = Vector3.new(0, 0, 1)
        attach0.Parent = part

        local attach1 = Instance.new("Attachment")
        attach1.Name = "TrailEnd"
        attach1.Position = Vector3.new(0, 0, -0.5)
        attach1.Parent = part

        local trail = Instance.new("Trail")
        trail.Name = "Trail"
        trail.Attachment0 = attach0
        trail.Attachment1 = attach1
        trail.Lifetime = 0.15
        trail.MinLength = 0.05
        trail.FaceCamera = true
        trail.Transparency = TRAIL_TRANSPARENCY
        trail.WidthScale = TRAIL_WIDTH_PLAYER
        trail.Enabled = false  -- Start disabled
        trail.Parent = part
    end

    return part
end

-- Trail cache to avoid FindFirstChild overhead (populated on first use)
local trailCache = setmetatable({}, {__mode = "k"})  -- Weak keys

local function getTrail(part)
    local trail = trailCache[part]
    if not trail then
        trail = part:FindFirstChild("Trail")
        if trail then
            trailCache[part] = trail
        end
    end
    return trail
end

-- Clear trail history when reusing pooled projectile (prevents visual glitch)
local function clearTrailHistory(part)
    local trail = getTrail(part)
    if trail then
        trail.Enabled = false
    end
end

-- Re-enable trail after positioning (call after setting CFrame)
local function enableTrail(part)
    if not TRAILS_ENABLED then return end
    local trail = getTrail(part)
    if trail then
        trail.Enabled = true
    end
end

--============================================================================
-- PART CACHE SETUP
--============================================================================

local projectileContainer = nil
local projectileCache = nil
local templatePart = nil

local function initializeCache()
    projectileContainer = workspace:FindFirstChild("ProjectileContainer")
    if not projectileContainer then
        projectileContainer = Instance.new("Folder")
        projectileContainer.Name = "ProjectileContainer"
        projectileContainer.Parent = workspace
    end

    templatePart = createTemplate()
    projectileCache = PartCache.new(templatePart, POOL_SIZE, projectileContainer)
end

--============================================================================
-- ACTIVE PROJECTILES
--============================================================================

local activeProjectiles = {}

--[[
    Projectile structure (matching RotMG Projectile.as):
    {
        Part = BasePart,
        StartX = number,
        StartY = number (Z in Roblox),
        StartZ = number (Y in Roblox - height),
        Angle = number (radians),
        BulletId = number,
        SpawnTime = number,
        Lifetime = number,
        Speed = number,
        Color = Color3,

        -- Movement patterns (from ProjectileProperties.as)
        Wavy = bool,
        Parametric = bool,
        Boomerang = bool,
        Amplitude = number,
        Frequency = number,
        Magnitude = number,

        -- Right vector for perpendicular calculations
        RightVector = Vector3,
    }
]]

--============================================================================
-- ROTMG POSITION CALCULATION (exact from Projectile.as positionAt)
--============================================================================

local function calculatePosition(proj, elapsedMs)
    -- Base distance traveled (RotMG: speed / 10000 * elapsed)
    local distance = (proj.Speed / 10000) * elapsedMs

    -- Phase offset based on bullet ID parity (RotMG: bulletId % 2 == 0 ? 0 : π)
    local phase = (proj.BulletId % 2 == 0) and 0 or math.pi

    local finalX, finalZ  -- X and Z in Roblox (horizontal plane)
    local angle = proj.Angle

    if proj.Wavy then
        -- RotMG Wavy: angle + (π/64) * sin(phase + (6π * elapsed / 1000))
        local wavyAngle = angle + WAVY_MAGNITUDE * math.sin(phase + (WAVY_PERIOD * elapsedMs / 1000))
        finalX = proj.StartX + distance * math.cos(wavyAngle)
        finalZ = proj.StartZ + distance * math.sin(wavyAngle)

    elseif proj.Parametric then
        -- RotMG Parametric: Lissajous curve
        -- t = elapsed / lifetime * 2π
        local t = (elapsedMs / (proj.Lifetime * 1000)) * 2 * math.pi
        local magnitude = proj.Magnitude or 3

        -- Parametric offset (perpendicular to direction)
        local xOffset = math.sin(t) * ((proj.BulletId % 2 == 0) and 1 or -1)
        local yOffset = math.sin(2 * t) * ((proj.BulletId % 4 < 2) and 1 or -1)

        -- Rotate offset by angle
        local rotatedX = xOffset * math.cos(angle) - yOffset * math.sin(angle)
        local rotatedZ = xOffset * math.sin(angle) + yOffset * math.cos(angle)

        finalX = proj.StartX + distance * math.cos(angle) + rotatedX * magnitude
        finalZ = proj.StartZ + distance * math.sin(angle) + rotatedZ * magnitude

    elseif proj.Boomerang then
        -- RotMG Boomerang: Reverse direction after halfway
        local midpoint = (proj.Speed / 10000) * (proj.Lifetime * 1000 / 2)
        if distance > midpoint then
            distance = midpoint - (distance - midpoint)
        end
        finalX = proj.StartX + distance * math.cos(angle)
        finalZ = proj.StartZ + distance * math.sin(angle)

    else
        -- Standard movement with optional amplitude wave
        finalX = proj.StartX + distance * math.cos(angle)
        finalZ = proj.StartZ + distance * math.sin(angle)

        if proj.Amplitude and proj.Amplitude > 0 then
            -- RotMG Amplitude: amplitude * sin(phase + (elapsed/lifetime * frequency * 2π))
            local frequency = proj.Frequency or 1
            local lifetimeMs = proj.Lifetime * 1000
            local wavePhase = phase + ((elapsedMs / lifetimeMs) * frequency * 2 * math.pi)
            local waveOffset = proj.Amplitude * math.sin(wavePhase)

            -- Apply perpendicular offset
            local perpAngle = angle + math.pi / 2
            finalX = finalX + waveOffset * math.cos(perpAngle)
            finalZ = finalZ + waveOffset * math.sin(perpAngle)
        end
    end

    return finalX, finalZ
end

-- Calculate velocity direction for projectile orientation
-- OPTIMIZED: For straight projectiles, use cached direction (no recalculation needed)
local function calculateVelocityDirection(proj, elapsedMs)
    -- Fast path: straight projectiles have constant direction
    if proj.CachedDirection then
        return proj.CachedDirection
    end

    -- Slow path: complex trajectories need derivative approximation
    local dt = 1  -- Small time delta for derivative approximation
    local x1, z1 = calculatePosition(proj, elapsedMs)
    local x2, z2 = calculatePosition(proj, elapsedMs + dt)

    local dx = x2 - x1
    local dz = z2 - z1
    local magnitude = math.sqrt(dx * dx + dz * dz)

    if magnitude > 0.001 then
        return Vector3.new(dx / magnitude, 0, dz / magnitude)
    end

    return Vector3.new(math.cos(proj.Angle), 0, math.sin(proj.Angle))
end

--============================================================================
-- PROJECTILE CREATION
--============================================================================

local function createProjectile(data)
    local part = projectileCache:GetPart()

    -- Set visual properties
    local color = data.Color or Color3.fromRGB(255, 255, 255)
    part.Color = color
    local size = data.Size or 0.5
    part.Size = Vector3.new(size, size, size * 3)

    -- Trail handling (skip for enemy projectiles if disabled)
    local useTrails = TRAILS_ENABLED and (not data.IsEnemy or ENEMY_TRAILS_ENABLED)
    if useTrails then
        clearTrailHistory(part)
        local trail = getTrail(part)
        if trail then
            trail.Color = getColorSequence(color)
            trail.WidthScale = data.IsEnemy and TRAIL_WIDTH_ENEMY or TRAIL_WIDTH_PLAYER
        end
    elseif TRAILS_ENABLED then
        -- Disable trail for this enemy projectile
        clearTrailHistory(part)
    end

    -- Calculate angle from direction
    local direction = data.Direction
    if direction.Magnitude > 0.01 then
        direction = direction.Unit
    else
        direction = Vector3.new(0, 0, 1)
    end
    local angle = math.atan2(direction.Z, direction.X)

    -- Initial position
    part.CFrame = CFrame.new(data.Position, data.Position + direction)

    -- Re-enable trail AFTER positioning (only if this projectile uses trails)
    if useTrails then
        enableTrail(part)
    end

    -- RotMG uses speed in units per 10000ms, we convert from studs/sec
    local rotmgSpeed = (data.Speed or 80) * 10000 / 1000  -- Convert to RotMG units

    -- Determine movement pattern
    local isWavy = data.Wavy or false
    local isParametric = data.Parametric or false
    local isBoomerang = data.Boomerang or false
    local amplitude = data.Amplitude or 0

    -- Cache direction vector (avoid recalculating trig every frame)
    -- Wavy/Parametric/Boomerang need dynamic direction, but Amplitude uses base direction
    local baseDir = Vector3.new(math.cos(angle), 0, math.sin(angle))
    local cachedDir = nil
    local needsDynamicDirection = isWavy or isParametric or isBoomerang

    if not needsDynamicDirection then
        -- Straight and Amplitude projectiles can use cached direction for orientation
        cachedDir = baseDir
    end

    -- For amplitude, also cache perpendicular direction
    local perpDir = nil
    if amplitude > 0 then
        local perpAngle = angle + math.pi / 2
        perpDir = Vector3.new(math.cos(perpAngle), 0, math.sin(perpAngle))
    end

    local lifetime = data.Lifetime or 0.5
    local frequency = data.Frequency or 1
    local bulletId = data.BulletId or (staffBulletCounter + 1)

    -- Pre-calculate values used every frame
    local speedFactor = rotmgSpeed / 10000  -- Avoid division in update loop
    local lifetimeMs = lifetime * 1000

    -- Calculate phase for DNA helix pattern
    -- WaveSign from server: -1 = first wave (phase pi), 1 = second wave (phase 0)
    -- Fallback to bulletId parity for local projectiles
    local phase
    if data.WaveSign then
        phase = (data.WaveSign == -1) and math.pi or 0
    else
        phase = (bulletId % 2 == 0) and 0 or math.pi
    end

    local projectile = {
        Part = part,
        StartX = data.Position.X,
        StartZ = data.Position.Z,
        StartY = data.Position.Y,  -- Height (Roblox Y)
        SpawnTime = tick(),
        Lifetime = lifetime,

        -- Pre-calculated for update loop performance
        SpeedFactor = speedFactor,         -- Speed / 10000 (avoids division per frame)
        LifetimeMs = lifetimeMs,           -- Lifetime in ms
        Phase = phase,                     -- Wave phase based on bullet ID parity
        FreqFactor = frequency * 2 * math.pi / lifetimeMs,  -- Pre-calc frequency factor

        -- Movement patterns
        Wavy = isWavy,
        Parametric = isParametric,
        Boomerang = isBoomerang,
        Amplitude = amplitude,
        Magnitude = data.Magnitude or 3,

        -- For slow path only
        Angle = angle,
        BulletId = bulletId,
        Speed = rotmgSpeed,
        Frequency = frequency,

        -- Cached vectors (avoids per-frame trig recalculation)
        CachedDirection = cachedDir,      -- Base direction for orientation
        BaseDirection = baseDir,          -- Always cached for position calc
        PerpDirection = perpDir,          -- For amplitude wave offset

        IsEnemy = data.IsEnemy or false,
        OwnerId = data.OwnerId,
        UseTrails = useTrails,  -- Track if this projectile uses trails

        -- Hit detection (for local player projectiles only)
        HitEnemies = {},  -- Track which enemies this projectile has hit
        IsLocalPlayer = data.OwnerId == player.UserId and not data.IsEnemy,

        -- Enemy projectile hit detection
        ProjectileId = data.ProjectileId,  -- Server ID for hit verification
        HasHitPlayer = false,              -- Prevent duplicate hit reports
    }

    table.insert(activeProjectiles, projectile)

    return projectile
end

local function destroyProjectile(index)
    local proj = activeProjectiles[index]
    if proj and proj.Part then
        projectileCache:ReturnPart(proj.Part)
    end
    table.remove(activeProjectiles, index)
end

--============================================================================
-- UPDATE LOOP (exact RotMG timing)
--============================================================================

local function updateProjectiles(deltaTime)
    local currentTime = tick()

    -- Process in reverse order for efficient removal (no index shifting)
    local i = #activeProjectiles
    while i >= 1 do
        local proj = activeProjectiles[i]
        local elapsedSec = currentTime - proj.SpawnTime

        -- Check lifetime
        if elapsedSec > proj.Lifetime then
            -- Disable trail before returning (only if this projectile used trails)
            if proj.UseTrails then
                clearTrailHistory(proj.Part)
            end
            -- Swap with last element and remove (O(1) removal)
            projectileCache:ReturnPart(proj.Part)
            local lastIdx = #activeProjectiles
            if i ~= lastIdx then
                activeProjectiles[i] = activeProjectiles[lastIdx]
            end
            activeProjectiles[lastIdx] = nil
        else
            local elapsedMs = elapsedSec * 1000
            local x, z
            local lookDirection

            -- OPTIMIZATION: Fast paths based on projectile type
            if proj.CachedDirection then
                -- Fast path: straight or amplitude projectiles (pre-calculated values)
                local distance = proj.SpeedFactor * elapsedMs
                local baseDir = proj.BaseDirection

                -- Base position
                x = proj.StartX + distance * baseDir.X
                z = proj.StartZ + distance * baseDir.Z

                -- Add amplitude wave offset if applicable
                if proj.Amplitude > 0 then
                    local wavePhase = proj.Phase + elapsedMs * proj.FreqFactor
                    local waveOffset = proj.Amplitude * math.sin(wavePhase)
                    x = x + waveOffset * proj.PerpDirection.X
                    z = z + waveOffset * proj.PerpDirection.Z
                end

                lookDirection = proj.CachedDirection
            else
                -- Slow path: Wavy/Parametric/Boomerang - need full calculation
                x, z = calculatePosition(proj, elapsedMs)
                lookDirection = calculateVelocityDirection(proj, elapsedMs)
            end

            -- Update part CFrame
            local position = Vector3.new(x, proj.StartY, z)
            proj.Part.CFrame = CFrame.new(position, position + lookDirection)

            -- CLIENT-SIDE HIT DETECTION (for local player projectiles only)
            -- OPTIMIZED: Spatial grid query (O(cells) instead of O(n enemies))
            if HIT_DETECTION_ENABLED and proj.IsLocalPlayer then
                local ev = getEnemyVisuals()
                local projPos = Vector3.new(x, proj.StartY, z)

                -- SPATIAL GRID QUERY: Only check enemies in nearby cells
                local nearbyIds = ev.GetNearbyEnemies(projPos, SPATIAL_QUERY_RADIUS)

                for enemyId in pairs(nearbyIds) do
                    -- Skip if already hit this enemy
                    if not proj.HitEnemies[enemyId] then
                        local enemyVisual = ev.Enemies[enemyId]
                        if enemyVisual then
                            -- Use cached CurrentPosition (updated by EnemyVisuals)
                            local enemyPos = enemyVisual.CurrentPosition
                            if enemyPos then
                                -- Precise collision check with cached HitRadius
                                local dx = x - enemyPos.X
                                local dz = z - enemyPos.Z
                                local distSq = dx * dx + dz * dz
                                local hitRadiusSq = enemyVisual.HitRadiusSq or 25  -- Default 5^2

                                if distSq < hitRadiusSq then
                                    -- HIT! Mark as hit and report to server
                                    proj.HitEnemies[enemyId] = true

                                    -- Show damage number LOCALLY (immediate feedback)
                                    if LOCAL_DAMAGE_DISPLAY then
                                        local dmgNumbers = getDamageNumbers()
                                        if dmgNumbers and dmgNumbers.ShowDamage then
                                            dmgNumbers.ShowDamage(enemyPos, BASE_WEAPON_DAMAGE, false, false, enemyId, false, false)
                                        end
                                    end

                                    -- Report hit to CombatController (will batch and send to server)
                                    local combat = getCombatController()
                                    if combat and combat.OnProjectileHit then
                                        combat.OnProjectileHit(enemyId, position)
                                    end

                                    -- Non-piercing projectile: remove after first hit
                                    if proj.UseTrails then
                                        clearTrailHistory(proj.Part)
                                    end
                                    projectileCache:ReturnPart(proj.Part)
                                    local lastIdx = #activeProjectiles
                                    if i ~= lastIdx then
                                        activeProjectiles[i] = activeProjectiles[lastIdx]
                                    end
                                    activeProjectiles[lastIdx] = nil
                                    break  -- Exit enemy loop, projectile is destroyed
                                end
                            end
                        end
                    end
                end
            end

            -- ENEMY→PLAYER HIT DETECTION (client-authoritative)
            -- Check if enemy projectile hits local player
            if ENEMY_HIT_DETECTION_ENABLED and proj.IsEnemy and not proj.HasHitPlayer then
                local character = player.Character
                if character then
                    local rootPart = character:FindFirstChild("HumanoidRootPart")
                    if rootPart then
                        local playerPos = rootPart.Position
                        -- 2D distance check (ignore Y axis, RotMG style)
                        local dx = x - playerPos.X
                        local dz = z - playerPos.Z
                        local distSq = dx * dx + dz * dz
                        local hitRadiusSq = (PLAYER_HITBOX_RADIUS + ENEMY_PROJECTILE_RADIUS) ^ 2

                        if distSq < hitRadiusSq then
                            -- HIT! Mark as hit to prevent duplicate reports
                            proj.HasHitPlayer = true

                            -- Report hit to server for damage verification
                            if proj.ProjectileId then
                                Remotes.Events.PlayerHitByProjectile:FireServer(proj.ProjectileId, position)
                            end

                            -- Remove projectile immediately
                            if proj.UseTrails then
                                clearTrailHistory(proj.Part)
                            end
                            projectileCache:ReturnPart(proj.Part)
                            local lastIdx = #activeProjectiles
                            if i ~= lastIdx then
                                activeProjectiles[i] = activeProjectiles[lastIdx]
                            end
                            activeProjectiles[lastIdx] = nil
                        end
                    end
                end
            end
        end

        i = i - 1
    end
end

--============================================================================
-- LOCAL PLAYER SHOT (Client Prediction)
--============================================================================

-- Bullet ID counter for staff (avoids math.random overhead)
local staffBulletCounter = 0

-- Pre-cached staff projectile color
local STAFF_COLOR = Color3.fromRGB(180, 100, 255)

-- Fire staff projectiles with DNA helix pattern
function ProjectileRenderer.FireStaffShot(origin, direction, color)
    local useColor = color or STAFF_COLOR
    staffBulletCounter = staffBulletCounter + 2

    -- Two projectiles with opposite wave signs (DNA helix)
    for bulletOffset = 0, 1 do
        createProjectile({
            Position = origin,
            Direction = direction,
            Speed = 80,
            Lifetime = 0.43,
            Color = useColor,
            Size = 0.5,
            BulletId = staffBulletCounter + bulletOffset,
            Amplitude = 2,
            Frequency = 2,
            OwnerId = player.UserId,
        })
    end
end

-- Fire a single projectile
function ProjectileRenderer.FireProjectile(origin, direction, speed, lifetime, color, size)
    createProjectile({
        Position = origin,
        Direction = direction,
        Speed = speed or 80,
        Lifetime = lifetime or 0.5,
        Color = color or Color3.fromRGB(255, 255, 100),
        Size = size or 0.5,
        OwnerId = player.UserId,
    })
end

-- Fire wavy projectile
function ProjectileRenderer.FireWavyProjectile(origin, direction, speed, lifetime, color, size)
    createProjectile({
        Position = origin,
        Direction = direction,
        Speed = speed or 60,
        Lifetime = lifetime or 0.8,
        Color = color or Color3.fromRGB(100, 255, 100),
        Size = size or 0.6,
        Wavy = true,
        OwnerId = player.UserId,
    })
end

-- Fire boomerang projectile
function ProjectileRenderer.FireBoomerangProjectile(origin, direction, speed, lifetime, color, size)
    createProjectile({
        Position = origin,
        Direction = direction,
        Speed = speed or 100,
        Lifetime = lifetime or 1.0,
        Color = color or Color3.fromRGB(255, 200, 100),
        Size = size or 0.7,
        Boomerang = true,
        OwnerId = player.UserId,
    })
end

--============================================================================
-- NETWORK EVENTS
--============================================================================

local function onProjectileSpawn(data)
    -- Skip local player's weapon projectiles (already rendered via client prediction)
    -- But DO render ability projectiles (BulletNova, PiercingShot) since they have no client prediction
    if data.OwnerId == player.UserId and not data.Effect then
        return
    end

    -- DEBUG: Log projectile spawns (disabled - uncomment to debug)
    -- if data.IsEnemy then
    --     print("[ProjectileRenderer] Enemy projectile spawn - Id:", data.Id)
    -- end

    -- Map server field names to client field names
    -- Server sends: WavePattern, WaveAmplitude, WaveFrequency, WaveSign
    -- Client expects: Amplitude, Frequency
    local amplitude = data.Amplitude or data.WaveAmplitude or 0
    local frequency = data.Frequency or data.WaveFrequency or 1

    -- Ensure BulletId is always a number (server may send string UIDs)
    local bulletId = data.BulletId
    if bulletId == nil or type(bulletId) == "string" then
        bulletId = math.random(0, 1000000)
    end

    createProjectile({
        Position = data.Position,
        Direction = data.Direction,
        Speed = data.Speed or 80,
        Lifetime = data.Lifetime or 0.5,
        Color = data.Color,
        Size = data.Size or 0.8,
        BulletId = bulletId,
        IsEnemy = data.IsEnemy or false,
        Wavy = data.Wavy or false,
        Parametric = data.Parametric or false,
        Boomerang = data.Boomerang or false,
        Amplitude = amplitude,
        Frequency = frequency,
        Magnitude = data.Magnitude or 3,
        OwnerId = data.OwnerId,
        WaveSign = data.WaveSign,  -- Pass wave sign for DNA helix
        ProjectileId = data.Id,    -- Server projectile ID for hit verification
    })
end

local function onProjectileHit(data)
    local hitPos = data.Position
    if not hitPos then return end

    local destroyRadius = 5
    local toDestroy = {}

    for i, proj in ipairs(activeProjectiles) do
        local projPos = Vector3.new(proj.Part.Position.X, 0, proj.Part.Position.Z)
        local targetPos = Vector3.new(hitPos.X, 0, hitPos.Z)
        local dist = (projPos - targetPos).Magnitude
        if dist < destroyRadius then
            table.insert(toDestroy, i)
        end
    end

    for i = #toDestroy, 1, -1 do
        destroyProjectile(toDestroy[i])
    end
end

--============================================================================
-- ABILITY VISUAL EFFECTS
--============================================================================

local TweenService = game:GetService("TweenService")

-- Create spell bomb explosion effect
local function createSpellBombEffect(position, radius, color)
    -- Main explosion sphere
    local sphere = Instance.new("Part")
    sphere.Name = "SpellBomb"
    sphere.Shape = Enum.PartType.Ball
    sphere.Size = Vector3.new(1, 1, 1)
    sphere.Position = position
    sphere.Color = color or Color3.fromRGB(200, 100, 255)
    sphere.Material = Enum.Material.Neon
    sphere.Transparency = 0.3
    sphere.Anchored = true
    sphere.CanCollide = false
    sphere.CastShadow = false
    sphere.Parent = projectileContainer

    -- Expand and fade
    local targetSize = Vector3.new(radius * 2, radius * 2, radius * 2)
    local expandTween = TweenService:Create(sphere, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        Size = targetSize,
        Transparency = 1,
    })
    expandTween:Play()
    expandTween.Completed:Connect(function()
        sphere:Destroy()
    end)

    -- Particles
    local attachment = Instance.new("Attachment")
    attachment.Parent = sphere

    local particles = Instance.new("ParticleEmitter")
    particles.Color = ColorSequence.new(color or Color3.fromRGB(200, 100, 255))
    particles.Size = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 1),
        NumberSequenceKeypoint.new(1, 0)
    })
    particles.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.3),
        NumberSequenceKeypoint.new(1, 1)
    })
    particles.Lifetime = NumberRange.new(0.3, 0.5)
    particles.Rate = 100
    particles.Speed = NumberRange.new(radius, radius * 2)
    particles.SpreadAngle = Vector2.new(180, 180)
    particles.Enabled = true
    particles.Parent = attachment

    -- Disable after burst
    task.delay(0.1, function()
        particles.Enabled = false
    end)
end

-- Create healing aura effect
local function createHealEffect(position, radius, color)
    -- Rising heal rings
    for i = 0, 2 do
        task.delay(i * 0.15, function()
            local ring = Instance.new("Part")
            ring.Name = "HealRing"
            ring.Shape = Enum.PartType.Cylinder
            ring.Size = Vector3.new(0.2, radius * 0.5, radius * 0.5)
            ring.Position = position + Vector3.new(0, i * 2, 0)
            ring.Orientation = Vector3.new(0, 0, 90)
            ring.Color = color or Color3.fromRGB(100, 255, 100)
            ring.Material = Enum.Material.Neon
            ring.Transparency = 0.3
            ring.Anchored = true
            ring.CanCollide = false
            ring.CastShadow = false
            ring.Parent = projectileContainer

            -- Rise and expand
            local targetPos = position + Vector3.new(0, 6 + i * 2, 0)
            local targetSize = Vector3.new(0.1, radius * 2, radius * 2)

            local riseTween = TweenService:Create(ring, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
                Position = targetPos,
                Size = targetSize,
                Transparency = 1,
            })
            riseTween:Play()
            riseTween.Completed:Connect(function()
                ring:Destroy()
            end)
        end)
    end

    -- Central glow
    local glow = Instance.new("Part")
    glow.Name = "HealGlow"
    glow.Shape = Enum.PartType.Ball
    glow.Size = Vector3.new(radius, radius, radius)
    glow.Position = position
    glow.Color = color or Color3.fromRGB(100, 255, 100)
    glow.Material = Enum.Material.Neon
    glow.Transparency = 0.6
    glow.Anchored = true
    glow.CanCollide = false
    glow.CastShadow = false
    glow.Parent = projectileContainer

    local fadeOut = TweenService:Create(glow, TweenInfo.new(0.5), {
        Transparency = 1,
        Size = Vector3.new(radius * 1.5, radius * 1.5, radius * 1.5),
    })
    fadeOut:Play()
    fadeOut.Completed:Connect(function()
        glow:Destroy()
    end)
end

-- Create shield bash effect
local function createShieldBashEffect(position, color)
    -- Arc of impact
    local arc = Instance.new("Part")
    arc.Name = "ShieldBash"
    arc.Size = Vector3.new(6, 4, 0.5)
    arc.Position = position + Vector3.new(0, 2, 0)
    arc.Color = color or Color3.fromRGB(200, 200, 255)
    arc.Material = Enum.Material.Neon
    arc.Transparency = 0.3
    arc.Anchored = true
    arc.CanCollide = false
    arc.CastShadow = false
    arc.Parent = projectileContainer

    local expandTween = TweenService:Create(arc, TweenInfo.new(0.3), {
        Size = Vector3.new(12, 6, 0.5),
        Transparency = 1,
    })
    expandTween:Play()
    expandTween.Completed:Connect(function()
        arc:Destroy()
    end)
end

-- Handle ability effect events
local function onAbilityEffect(data)
    if not data.Effect then return end

    if data.Effect == "SpellBomb" then
        createSpellBombEffect(data.Position, data.Radius or 12, data.Color)
    elseif data.Effect == "Heal" then
        createHealEffect(data.Position, data.Radius or 12, data.Color)
    elseif data.Effect == "ShieldBash" then
        createShieldBashEffect(data.Position, data.Color)
    end
end

--============================================================================
-- INITIALIZATION
--============================================================================

function ProjectileRenderer.Init()
    initializeCache()

    RunService.RenderStepped:Connect(updateProjectiles)

    -- Handle projectile spawns (regular projectiles and ability effects)
    Remotes.Events.ProjectileSpawn.OnClientEvent:Connect(function(data)
        if data.Effect then
            -- Handle special visual effects (explosions, heals, etc.)
            onAbilityEffect(data)

            -- For projectile-based abilities, also create the actual projectile
            if data.Effect == "BulletNova" or data.Effect == "PiercingShot" then
                onProjectileSpawn(data)
            end
        else
            onProjectileSpawn(data)
        end
    end)
    Remotes.Events.ProjectileHit.OnClientEvent:Connect(onProjectileHit)
end

function ProjectileRenderer.GetStats()
    local cacheStats = projectileCache:GetStats()
    return {
        ActiveProjectiles = #activeProjectiles,
        CacheOpen = cacheStats.Open,
        CacheInUse = cacheStats.InUse,
        CacheTotal = cacheStats.Total,
    }
end

return ProjectileRenderer
