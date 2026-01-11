--[[
    CombatManager.lua
    Combat system with CLIENT-AUTHORITATIVE player projectiles - OPTIMIZED FOR 50+ PLAYERS

    ARCHITECTURE:
    - Player projectiles: Client creates visuals, detects hits, reports to server
    - Server validates hits (anti-cheat) and applies damage
    - NO per-shot network calls from shooting (eliminates 8+ events/sec at max DEX)
    - Server only tracks ability projectiles and enemy projectiles

    Optimizations:
    - Dictionary-based projectiles (O(1) removal)
    - Spatial grid for hit detection (O(1) nearby lookup)
    - Network culling (send to nearby players only)
    - Batch projectile spawns
    - Hit rate limiting (anti-exploit)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local Utilities = require(Shared.Utilities)
local ItemDatabase = require(Shared.ItemDatabase)
local Remotes = require(Shared.Remotes)
local SpatialGrid = require(Shared.SpatialGrid)
local LazyLoader = require(Shared.LazyLoader)

-- FastCast
local Lib = Shared:WaitForChild("Lib")
local FastCast = require(Lib.FastCast)

local CombatManager = {}

-- Lazy load managers using LazyLoader utility
local getPlayerManager = LazyLoader.create(script.Parent, "PlayerManager")
local getEnemyManager = LazyLoader.create(script.Parent, "EnemyManager")

--============================================================================
-- CONFIGURATION
--============================================================================

local NETWORK_CULL_RADIUS = 150      -- Only send projectile events within this range
local BATCH_INTERVAL = 0.05          -- Batch projectile spawns every 50ms
local SPATIAL_CELL_SIZE = 20         -- Grid cell size for hit detection
local MAX_PROJECTILE_CHECK_PER_FRAME = 100  -- Limit checks per frame to spread load

--============================================================================
-- SPATIAL GRIDS
--============================================================================

-- Grid for enemy positions (updated by EnemyManager)
CombatManager.EnemyGrid = SpatialGrid.new(SPATIAL_CELL_SIZE)

-- Grid for player positions (updated each frame)
CombatManager.PlayerGrid = SpatialGrid.new(SPATIAL_CELL_SIZE)

--============================================================================
-- ACTIVE PROJECTILES (Dictionary-based for O(1) removal)
--============================================================================

CombatManager.PlayerProjectiles = {}  -- [id] = projectileData
CombatManager.EnemyProjectiles = {}   -- [id] = projectileData
CombatManager.ProjectileCount = {Player = 0, Enemy = 0}

CombatManager.PlayerCooldowns = {}
CombatManager.AbilityCooldowns = {}

-- Batch queue for network optimization
local projectileBatchQueue = {}
local lastBatchTime = 0

--============================================================================
-- ROTMG PROJECTILE PHYSICS
--============================================================================

local WAVY_PERIOD = 6 * math.pi
local WAVY_MAGNITUDE = math.pi / 64
local STAFF_SPEED = 80
local STAFF_AMPLITUDE = 2
local STAFF_FREQUENCY = 2

local function calculateProjectilePosition(proj, elapsedMs)
    local rotmgSpeed = proj.Speed * 10000 / 1000
    local distance = (rotmgSpeed / 10000) * elapsedMs
    local phase = (proj.BulletId % 2 == 0) and 0 or math.pi
    local angle = math.atan2(proj.Direction.Z, proj.Direction.X)

    local finalX, finalZ

    if proj.Wavy then
        local wavyAngle = angle + WAVY_MAGNITUDE * math.sin(phase + (WAVY_PERIOD * elapsedMs / 1000))
        finalX = proj.StartX + distance * math.cos(wavyAngle)
        finalZ = proj.StartZ + distance * math.sin(wavyAngle)
    elseif proj.Boomerang then
        local midpoint = (rotmgSpeed / 10000) * (proj.Lifetime * 1000 / 2)
        if distance > midpoint then
            distance = midpoint - (distance - midpoint)
        end
        finalX = proj.StartX + distance * math.cos(angle)
        finalZ = proj.StartZ + distance * math.sin(angle)
    else
        finalX = proj.StartX + distance * math.cos(angle)
        finalZ = proj.StartZ + distance * math.sin(angle)

        if proj.WaveAmplitude and proj.WaveAmplitude > 0 then
            local frequency = proj.WaveFrequency or 1
            local lifetimeMs = proj.Lifetime * 1000
            local wavePhase = phase + ((elapsedMs / lifetimeMs) * frequency * 2 * math.pi)
            local waveOffset = proj.WaveAmplitude * math.sin(wavePhase)
            local perpAngle = angle + math.pi / 2
            finalX = finalX + waveOffset * math.cos(perpAngle)
            finalZ = finalZ + waveOffset * math.sin(perpAngle)
        end
    end

    return Vector3.new(finalX, proj.StartY, finalZ)
end

--============================================================================
-- NETWORK CULLING HELPERS
--============================================================================

-- Cache for player positions (updated once per frame in updatePlayerGrid)
local playerPositionCache = {}  -- [player] = Vector3

-- Get players within radius of a position (uses cached positions)
local function getPlayersInRadius(position, radius, excludePlayer)
    local nearbyPlayers = {}
    local radiusSq = radius * radius  -- Avoid sqrt in distance check

    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= excludePlayer then  -- Skip excluded player (e.g., shooter)
            local cachedPos = playerPositionCache[player]
            if cachedPos then
                local dx = cachedPos.X - position.X
                local dz = cachedPos.Z - position.Z
                local distSq = dx * dx + dz * dz
                if distSq <= radiusSq then
                    table.insert(nearbyPlayers, player)
                end
            end
        end
    end
    return nearbyPlayers
end

-- Fire event to nearby players only (excludePlayer skips that player)
local function fireToNearbyClients(eventName, position, data, excludePlayer)
    local nearbyPlayers = getPlayersInRadius(position, NETWORK_CULL_RADIUS, excludePlayer)
    for _, player in ipairs(nearbyPlayers) do
        Remotes.Events[eventName]:FireClient(player, data)
    end
end

--============================================================================
-- BATCH PROJECTILE SYSTEM
--============================================================================

local function addToBatch(projectileData, position)
    table.insert(projectileBatchQueue, {
        Data = projectileData,
        Position = position,
    })
end

local function flushBatch()
    if #projectileBatchQueue == 0 then return end

    -- Group by nearby players to reduce network calls
    local playerBatches = {}

    for _, entry in ipairs(projectileBatchQueue) do
        local nearbyPlayers = getPlayersInRadius(entry.Position, NETWORK_CULL_RADIUS)
        for _, player in ipairs(nearbyPlayers) do
            if not playerBatches[player] then
                playerBatches[player] = {}
            end
            table.insert(playerBatches[player], entry.Data)
        end
    end

    -- Send batched data to each player
    for player, batch in pairs(playerBatches) do
        if #batch > 0 then
            Remotes.Events.ProjectileBatch:FireClient(player, batch)
        end
    end

    projectileBatchQueue = {}
end

--============================================================================
-- CREATE PLAYER PROJECTILE
--============================================================================

function CombatManager.CreatePlayerProjectile(player, direction, spawnTime)
    local PM = getPlayerManager()
    local weapon = PM.GetEquippedWeapon(player)
    if not weapon then return end

    local character = player.Character
    if not character then return end
    local rootPart = character:FindFirstChild("HumanoidRootPart")
    if not rootPart then return end

    local effectiveStats = PM.GetEffectiveStats(player)
    if not effectiveStats then return end

    direction = Vector3.new(direction.X, 0, direction.Z)
    if direction.Magnitude > 0.01 then
        direction = direction.Unit
    else
        direction = rootPart.CFrame.LookVector
        direction = Vector3.new(direction.X, 0, direction.Z).Unit
    end

    -- Use provided spawn time or current time
    local projectileSpawnTime = spawnTime or tick()

    local baseDamage = math.random(weapon.Damage.Min, weapon.Damage.Max)
    local spawnPos = rootPart.Position + direction * 3 + Vector3.new(0, 2, 0)

    local numProjectiles = weapon.NumProjectiles or 1
    local spread = weapon.ShotSpread or 0
    local rangeInStuds = (weapon.Range or 8) * Constants.STUDS_PER_UNIT
    local speed = weapon.ProjectileSpeed or 20
    local isStaffHelix = weapon.WavePattern and weapon.Subtype == "Staff"

    for i = 1, numProjectiles do
        local shotDir = direction

        if numProjectiles > 1 and spread > 0 and not weapon.WavePattern then
            local angleOffset = (i - (numProjectiles + 1) / 2) * math.rad(spread)
            local rotatedCF = CFrame.Angles(0, angleOffset, 0) * CFrame.new(direction)
            shotDir = rotatedCF.Position.Unit
        end

        local waveSign = 1
        if isStaffHelix and numProjectiles == 2 then
            waveSign = (i == 1) and -1 or 1
        end

        local projSpeed = isStaffHelix and STAFF_SPEED or speed
        local projLifetime = rangeInStuds / projSpeed
        local projAmplitude = isStaffHelix and STAFF_AMPLITUDE or ((weapon.WaveAmplitude or 0) * Constants.STUDS_PER_UNIT)
        local projFrequency = isStaffHelix and STAFF_FREQUENCY or (weapon.WaveFrequency or 0)
        local bulletId = math.random(0, 500000) * 2 + (i - 1)

        local projId = Utilities.GenerateUID()
        local projectile = {
            Id = projId,
            Owner = player,
            OwnerType = "Player",
            Position = spawnPos,
            Direction = shotDir,
            Speed = projSpeed,
            Damage = baseDamage,
            AttackStat = effectiveStats.Attack,
            Lifetime = projLifetime,
            SpawnTime = projectileSpawnTime,  -- Use latency-adjusted spawn time
            HitEnemies = {},
            Pierce = weapon.Pierce or false,
            PierceCount = weapon.PierceCount or 1,
            HitCount = 0,
            Size = 0.8,
            MaxRange = rangeInStuds,
            Color = weapon.ProjectileColor or Color3.fromRGB(180, 100, 255),

            StartX = spawnPos.X,
            StartZ = spawnPos.Z,
            StartY = spawnPos.Y,
            BulletId = bulletId,

            WavePattern = weapon.WavePattern or false,
            WaveAmplitude = projAmplitude,
            WaveFrequency = projFrequency,
            WaveSign = waveSign,
            Wavy = weapon.Wavy or false,
            Boomerang = weapon.Boomerang or false,
        }

        -- Dictionary insert (O(1))
        CombatManager.PlayerProjectiles[projId] = projectile
        CombatManager.ProjectileCount.Player = CombatManager.ProjectileCount.Player + 1

        -- Send to nearby players (exclude shooter - they have client-side prediction)
        fireToNearbyClients("ProjectileSpawn", spawnPos, {
            Id = projId,
            OwnerId = player.UserId,
            Position = spawnPos,
            Direction = shotDir,
            Speed = projectile.Speed,
            Lifetime = projectile.Lifetime,
            Color = projectile.Color,
            Size = projectile.Size,
            IsEnemy = false,
            Pierce = projectile.Pierce,
            BulletId = bulletId,
            Amplitude = projectile.WaveAmplitude,
            Frequency = projectile.WaveFrequency,
            Wavy = projectile.Wavy,
            Boomerang = projectile.Boomerang,
            WavePattern = projectile.WavePattern,
        }, player)  -- Exclude shooter from receiving their own projectile
    end
end

--============================================================================
-- CREATE ENEMY PROJECTILE
--============================================================================

function CombatManager.CreateEnemyProjectile(enemyData, targetPosition)
    local direction = Utilities.GetDirection(enemyData.Position, targetPosition)
    local spawnPos = enemyData.Position + Vector3.new(0, 3, 0)

    local projId = Utilities.GenerateUID()
    -- DEBUG: Log projectile creation (disabled - uncomment to debug)
    -- print("[CombatManager] Creating enemy projectile - Id:", projId, "Enemy:", enemyData.Id)
    local projectile = {
        Id = projId,
        Owner = enemyData,
        OwnerType = "Enemy",
        Position = spawnPos,
        Direction = direction,
        Speed = enemyData.Definition.ProjectileSpeed or 40,
        Damage = enemyData.Definition.AttackDamage or 20,
        Lifetime = 3.0,
        SpawnTime = tick(),
        HitPlayers = {},
        Size = 1.5,
        Color = enemyData.Definition.ProjectileColor or Color3.fromRGB(255, 0, 0),

        StartX = spawnPos.X,
        StartZ = spawnPos.Z,
        StartY = spawnPos.Y,
    }

    -- Dictionary insert (O(1))
    CombatManager.EnemyProjectiles[projId] = projectile
    CombatManager.ProjectileCount.Enemy = CombatManager.ProjectileCount.Enemy + 1

    -- Send enemy projectiles immediately to all nearby players (not just batched)
    -- Enemy projectiles are less frequent than player projectiles, so immediate send is fine
    local netData = {
        Id = projId,
        Position = spawnPos,
        Direction = direction,
        Speed = projectile.Speed,
        Lifetime = projectile.Lifetime,
        Color = projectile.Color,
        Size = projectile.Size,
        IsEnemy = true,
    }

    -- Fire immediately to nearby players for responsive enemy attacks
    fireToNearbyClients("ProjectileSpawn", spawnPos, netData)

    return projectile
end

function CombatManager.CreateEnemyRingAttack(enemyData)
    local count = enemyData.Definition.ProjectileCount or 8
    for i = 1, count do
        local angle = (i / count) * math.pi * 2
        local direction = Vector3.new(math.cos(angle), 0, math.sin(angle))
        local targetPos = enemyData.Position + direction * 10
        CombatManager.CreateEnemyProjectile(enemyData, targetPos)
    end
end

function CombatManager.CreateEnemyShotgunAttack(enemyData, targetPosition)
    local count = enemyData.Definition.ProjectileCount or 3
    local spread = enemyData.Definition.ShotgunSpread or 30
    local baseDirection = Utilities.GetDirection(enemyData.Position, targetPosition)

    for i = 1, count do
        local angleOffset = (i - (count + 1) / 2) * math.rad(spread / math.max(count - 1, 1))
        local rotatedCF = CFrame.Angles(0, angleOffset, 0) * CFrame.new(baseDirection)
        local shotDir = rotatedCF.Position.Unit
        local targetPos = enemyData.Position + shotDir * 50

        local proj = CombatManager.CreateEnemyProjectile(enemyData, targetPos)
        proj.Direction = shotDir
    end
end

--============================================================================
-- UPDATE ENEMY GRID (Called by EnemyManager)
--============================================================================

function CombatManager.UpdateEnemyInGrid(enemyId, position)
    CombatManager.EnemyGrid:Update(enemyId, position)
end

function CombatManager.AddEnemyToGrid(enemyId, position)
    CombatManager.EnemyGrid:Insert(enemyId, position)
end

function CombatManager.RemoveEnemyFromGrid(enemyId)
    CombatManager.EnemyGrid:Remove(enemyId)
end

--============================================================================
-- UPDATE PLAYER POSITIONS IN GRID
--============================================================================

local function updatePlayerGrid()
    for _, player in ipairs(Players:GetPlayers()) do
        if player.Character then
            local rootPart = player.Character:FindFirstChild("HumanoidRootPart")
            if rootPart then
                local pos = rootPart.Position
                -- Update position cache for network culling (used by getPlayersInRadius)
                playerPositionCache[player] = pos

                local existing = CombatManager.PlayerGrid.EntityCells[player]
                if existing then
                    CombatManager.PlayerGrid:Update(player, pos)
                else
                    CombatManager.PlayerGrid:Insert(player, pos)
                end
            end
        else
            -- Clear cache for players without characters
            playerPositionCache[player] = nil
        end
    end
end

--============================================================================
-- UPDATE PROJECTILES (OPTIMIZED)
--============================================================================

function CombatManager.Update(deltaTime)
    local PM = getPlayerManager()
    local EM = getEnemyManager()
    local currentTime = tick()

    -- Update player grid for enemy projectile hit detection
    updatePlayerGrid()

    --========================================================================
    -- UPDATE PLAYER PROJECTILES
    --========================================================================
    local playerToRemove = {}
    local checksThisFrame = 0

    for projId, proj in pairs(CombatManager.PlayerProjectiles) do
        local elapsed = currentTime - proj.SpawnTime
        local elapsedMs = elapsed * 1000

        -- Update position
        if proj.StartX then
            proj.Position = calculateProjectilePosition(proj, elapsedMs)
        else
            proj.Position = proj.Position + proj.Direction * proj.Speed * deltaTime
        end

        -- Check lifetime
        if elapsed > proj.Lifetime then
            table.insert(playerToRemove, projId)
        end
        -- DISABLED: Server-side hit detection for player projectiles
        -- Hit detection is now CLIENT-AUTHORITATIVE (like enemy projectiles)
        -- Client detects hits via ProjectileRenderer, reports via PlayerHitEnemy
        -- Server validates and applies damage in processHitBatch()
        -- This prevents duplicate damage application and duplicate damage indicators
    end

    --========================================================================
    -- UPDATE ENEMY PROJECTILES
    -- NOTE: Hit detection is now CLIENT-AUTHORITATIVE
    -- Server only updates positions and removes expired projectiles
    -- Actual hit detection happens on client via PlayerHitByProjectile remote
    --========================================================================
    local enemyToRemove = {}

    for projId, proj in pairs(CombatManager.EnemyProjectiles) do
        local elapsed = currentTime - proj.SpawnTime

        -- Update position (for tracking/cleanup only)
        proj.Position = proj.Position + proj.Direction * proj.Speed * deltaTime

        -- Remove expired projectiles
        if elapsed > proj.Lifetime then
            table.insert(enemyToRemove, projId)
        end

        -- DISABLED: Server-side hit detection
        -- This was causing "ghost hits" due to server-client position desync
        -- Hit detection is now handled by the client (see ProjectileVisuals.lua)
        -- Client reports hits via PlayerHitByProjectile remote (see ProjectileManager.lua)
        --[[
        if checksThisFrame < MAX_PROJECTILE_CHECK_PER_FRAME then
            local nearbyPlayers = CombatManager.PlayerGrid:GetNearby(proj.Position, 8)
            for targetPlayer in pairs(nearbyPlayers) do
                if not proj.HitPlayers[targetPlayer] then
                    if targetPlayer.Character then
                        local rootPart = targetPlayer.Character:FindFirstChild("HumanoidRootPart")
                        if rootPart then
                            local dist = (proj.Position - rootPart.Position).Magnitude
                            if dist < 4 then
                                proj.HitPlayers[targetPlayer] = true
                                checksThisFrame = checksThisFrame + 1
                                local damage = PM.DamagePlayer(targetPlayer, proj.Damage)
                                Remotes.Events.DamageNumber:FireClient(targetPlayer, {
                                    Position = rootPart.Position + Vector3.new(0, 2, 0),
                                    Damage = damage,
                                    IsPlayer = true,
                                })
                                table.insert(enemyToRemove, projId)
                                break
                            end
                        end
                    end
                end
            end
        end
        ]]
    end

    -- Remove projectiles (O(1) dictionary removal)
    for _, projId in ipairs(playerToRemove) do
        CombatManager.PlayerProjectiles[projId] = nil
        CombatManager.ProjectileCount.Player = CombatManager.ProjectileCount.Player - 1
    end

    for _, projId in ipairs(enemyToRemove) do
        CombatManager.EnemyProjectiles[projId] = nil
        CombatManager.ProjectileCount.Enemy = CombatManager.ProjectileCount.Enemy - 1
    end

    -- Flush batch queue periodically
    if currentTime - lastBatchTime >= BATCH_INTERVAL then
        flushBatch()
        lastBatchTime = currentTime
    end
end

--============================================================================
-- CLIENT-AUTHORITATIVE HIT VALIDATION
-- Player projectiles are now tracked client-side for performance
-- Server validates reported hits and applies damage
--============================================================================

-- Anti-cheat: Maximum range a projectile could reasonably travel
local MAX_HIT_RANGE = 50  -- studs (generous to account for latency)

-- Rate limiting per player (prevents spam exploits)
local hitRateLimits = {}  -- [player] = {lastHitTime, hitCount}
local HIT_RATE_WINDOW = 1.0  -- seconds
local MAX_HITS_PER_WINDOW = 50  -- max hits per window (16 proj/sec at max DEX + buffer)

--============================================================================
-- DPS TRACKING (Sanity Check / Flagging System)
-- Tracks damage per player over rolling window
-- Flags players who exceed expected DPS threshold for staff review
--============================================================================
local playerDPSTracking = {}  -- [player] = {TotalDamage, WindowStart, FlagCount}
local DPS_WINDOW = 5.0  -- 5 second rolling window
local DPS_TOLERANCE = 3.0  -- Allow 3x expected max DPS before flagging (generous for burst)
local FLAG_THRESHOLD = 3  -- Number of flags before warning (reduces false positives)

-- Calculate expected max DPS for a player based on weapon and stats
local function calculateExpectedMaxDPS(player, weapon, effectiveStats)
    -- Max fire rate formula: 1 / (1.5 + 6.5 * (DEX / 75)) at DEX=75 → ~8 shots/sec
    local dex = effectiveStats.Dexterity or 50
    local fireRate = 1.5 + 6.5 * (dex / 75)  -- shots per second

    -- Projectiles per shot (staff = 2, bow = 1-3, etc.)
    local projectilesPerShot = weapon.NumProjectiles or weapon.ProjectileCount or 1

    -- Max damage per projectile (use weapon max damage + attack scaling)
    local maxWeaponDamage = weapon.Damage and weapon.Damage.Max or 100
    local attackBonus = (effectiveStats.Attack or 0) * 0.5  -- Rough attack scaling
    local maxDamagePerProjectile = maxWeaponDamage + attackBonus

    -- Expected max DPS = fireRate * projectiles * damage
    return fireRate * projectilesPerShot * maxDamagePerProjectile
end

-- Track DPS and flag suspicious players
local function trackPlayerDPS(player, damage, weapon, effectiveStats)
    local now = tick()
    local tracking = playerDPSTracking[player]

    if not tracking then
        tracking = {TotalDamage = 0, WindowStart = now, FlagCount = 0}
        playerDPSTracking[player] = tracking
    end

    -- Check if window expired
    if now - tracking.WindowStart >= DPS_WINDOW then
        -- Calculate actual DPS for the completed window
        local windowDuration = now - tracking.WindowStart
        local actualDPS = tracking.TotalDamage / windowDuration

        -- Calculate expected max DPS
        local expectedMaxDPS = calculateExpectedMaxDPS(player, weapon, effectiveStats)

        -- Check if exceeds threshold
        if actualDPS > expectedMaxDPS * DPS_TOLERANCE then
            tracking.FlagCount = tracking.FlagCount + 1

            if tracking.FlagCount >= FLAG_THRESHOLD then
                -- Log for staff review (could send to Discord webhook, database, etc.)
                warn(string.format(
                    "[DPS-FLAG] %s exceeded DPS limit %d times | Actual: %.0f DPS | Expected Max: %.0f DPS | Tolerance: %.0fx",
                    player.Name,
                    tracking.FlagCount,
                    actualDPS,
                    expectedMaxDPS,
                    DPS_TOLERANCE
                ))
            end
        else
            -- Good behavior, decay flag count
            tracking.FlagCount = math.max(0, tracking.FlagCount - 1)
        end

        -- Reset window
        tracking.TotalDamage = damage
        tracking.WindowStart = now
    else
        -- Accumulate damage in current window
        tracking.TotalDamage = tracking.TotalDamage + damage
    end
end

function CombatManager.OnPlayerHitEnemy(player, enemyId, hitPosition, clientTimestamp, hitCount)
    local PM = getPlayerManager()
    local EM = getEnemyManager()
    local serverTime = tick()
    hitCount = hitCount or 1

    -- Rate limiting check (count all hits in the batch)
    local rateData = hitRateLimits[player]
    if not rateData then
        rateData = {LastTime = serverTime, Count = 0}
        hitRateLimits[player] = rateData
    end

    if serverTime - rateData.LastTime > HIT_RATE_WINDOW then
        rateData.LastTime = serverTime
        rateData.Count = hitCount
    else
        rateData.Count = rateData.Count + hitCount
        if rateData.Count > MAX_HITS_PER_WINDOW then
            return
        end
    end

    -- Validate enemy exists
    local enemy = EM.Enemies[enemyId]
    if not enemy then
        return
    end

    -- Validate player has weapon
    local weapon = PM.GetEquippedWeapon(player)
    if not weapon then
        return
    end

    -- Validate player is within reasonable range (anti-cheat)
    local character = player.Character
    if not character then return end
    local rootPart = character:FindFirstChild("HumanoidRootPart")
    if not rootPart then return end

    local playerPos = rootPart.Position
    local enemyPos = enemy.Position
    local distToEnemy = (Vector3.new(playerPos.X, 0, playerPos.Z) - Vector3.new(enemyPos.X, 0, enemyPos.Z)).Magnitude

    local weaponRange = (weapon.Range or 8) * Constants.STUDS_PER_UNIT
    if distToEnemy > weaponRange + MAX_HIT_RANGE then
        return
    end

    -- Calculate total damage for all hits in batch
    local effectiveStats = PM.GetEffectiveStats(player)
    local totalDamage = 0
    for i = 1, hitCount do
        local baseDamage = math.random(weapon.Damage.Min, weapon.Damage.Max)
        totalDamage = totalDamage + Utilities.CalculateDamage(
            baseDamage,
            effectiveStats.Attack,
            enemy.Definition.Defense or 0
        )
    end

    -- Apply total damage (single call)
    local killed = EM.DamageEnemy(enemy, totalDamage, player)

    -- Track DPS for anti-cheat flagging
    trackPlayerDPS(player, totalDamage, weapon, effectiveStats)

    -- Send damage to ALL nearby players (including shooter)
    -- Shooter's local damage display is disabled, so they need server damage numbers
    fireToNearbyClients("DamageNumber", enemyPos, {
        Position = enemyPos + Vector3.new(0, 3, 0),
        Damage = totalDamage,
        IsCrit = false,
        EnemyId = enemyId,
    })
end

-- Clean up rate limit and DPS tracking data when player leaves
local function cleanupHitRateLimits(player)
    hitRateLimits[player] = nil
    playerDPSTracking[player] = nil
end

--============================================================================
-- ABILITY SYSTEM
--============================================================================

local ClassDatabase = require(Shared.ClassDatabase)

function CombatManager.ExecuteAbility(player, aimDirection, abilityItem, cursorPosition)
    local PM = getPlayerManager()
    local EM = getEnemyManager()
    local charData = PM.ActiveCharacters[player]
    if not charData then return false end

    local character = player.Character
    if not character then return false end

    local rootPart = character:FindFirstChild("HumanoidRootPart")
    if not rootPart then return false end

    local playerPos = rootPart.Position
    local effectiveStats = PM.GetEffectiveStats(player)

    local abilityData = nil
    if abilityItem then
        abilityData = {
            Effect = abilityItem.Effect,
            Damage = abilityItem.Damage,
            MPCost = abilityItem.MPCost,
            Radius = abilityItem.Radius,
            Range = abilityItem.Range or 8,
            NumProjectiles = abilityItem.NumProjectiles,
            ProjectileSpeed = abilityItem.ProjectileSpeed,
        }
    else
        local classData = ClassDatabase.GetClass(charData.Class)
        if classData and classData.Ability then
            abilityData = classData.Ability
        end
    end

    if not abilityData then return false end

    local maxRange = (abilityData.Range or 8) * Constants.STUDS_PER_UNIT
    local targetPos

    if cursorPosition then
        local toCursor = Vector3.new(cursorPosition.X - playerPos.X, 0, cursorPosition.Z - playerPos.Z)
        local cursorDist = toCursor.Magnitude

        if cursorDist <= maxRange then
            targetPos = Vector3.new(cursorPosition.X, playerPos.Y, cursorPosition.Z)
        else
            targetPos = playerPos + toCursor.Unit * maxRange
        end
    else
        targetPos = playerPos + aimDirection * maxRange
    end

    local effect = abilityData.Effect or "BulletNova"

    if effect == "BulletNova" or effect == "SpellBomb" then
        local numProjectiles = abilityData.NumProjectiles or 20
        local projSpeed = (abilityData.ProjectileSpeed or 16) * Constants.STUDS_PER_UNIT
        local projRange = (abilityData.Range or 16) * Constants.STUDS_PER_UNIT
        local lifetime = projRange / projSpeed
        local spawnPos = targetPos + Vector3.new(0, 2, 0)

        for i = 1, numProjectiles do
            local angle = (i / numProjectiles) * math.pi * 2
            local direction = Vector3.new(math.cos(angle), 0, math.sin(angle))

            local baseDamage = abilityData.Damage
            if type(baseDamage) == "table" then
                baseDamage = math.random(baseDamage.Min, baseDamage.Max)
            end
            baseDamage = baseDamage or 100

            local projId = Utilities.GenerateUID()
            local projectile = {
                Id = projId,
                Owner = player,
                OwnerType = "Player",
                Position = spawnPos,
                Direction = direction,
                Speed = projSpeed,
                Damage = baseDamage,
                AttackStat = effectiveStats.Attack,
                Lifetime = lifetime,
                SpawnTime = tick(),
                HitEnemies = {},
                Pierce = false,
                PierceCount = 1,
                HitCount = 0,
                Size = 0.8,
                MaxRange = projRange,
                Color = Color3.fromRGB(200, 100, 255),
                StartX = spawnPos.X,
                StartZ = spawnPos.Z,
                StartY = spawnPos.Y,
                BulletId = i,
            }

            CombatManager.PlayerProjectiles[projId] = projectile
            CombatManager.ProjectileCount.Player = CombatManager.ProjectileCount.Player + 1

            -- Send immediately for responsive ability feedback
            fireToNearbyClients("ProjectileSpawn", spawnPos, {
                Id = projId,
                OwnerId = player.UserId,
                Position = spawnPos,
                Direction = direction,
                Speed = projSpeed,
                Lifetime = lifetime,
                Color = projectile.Color,
                Size = 0.8,
                IsEnemy = false,
                Pierce = false,
                Effect = "BulletNova",
            })
        end

        return true, numProjectiles

    elseif effect == "Heal" then
        local healAmount = abilityData.HealAmount or 100
        local radius = (abilityData.Radius or 4) * Constants.STUDS_PER_UNIT

        PM.HealPlayer(player, healAmount)

        fireToNearbyClients("DamageNumber", playerPos, {
            Position = playerPos,
            Amount = healAmount,
            IsHeal = true,
        })

        for _, otherPlayer in ipairs(Players:GetPlayers()) do
            if otherPlayer ~= player and otherPlayer.Character then
                local otherRoot = otherPlayer.Character:FindFirstChild("HumanoidRootPart")
                if otherRoot then
                    local dist = (otherRoot.Position - playerPos).Magnitude
                    if dist <= radius then
                        PM.HealPlayer(otherPlayer, healAmount)
                        fireToNearbyClients("DamageNumber", otherRoot.Position, {
                            Position = otherRoot.Position,
                            Amount = healAmount,
                            IsHeal = true,
                        })
                    end
                end
            end
        end

        fireToNearbyClients("ProjectileSpawn", playerPos, {
            Effect = "Heal",
            Position = playerPos,
            Radius = radius,
            Color = Color3.fromRGB(100, 255, 100),
            OwnerId = player.UserId,
        })

        return true

    elseif effect == "Stun" then
        local radius = (abilityData.Radius or 3) * Constants.STUDS_PER_UNIT
        local stunDuration = abilityData.Duration or 2.0

        local stunCount = 0
        for id, enemyData in pairs(EM.Enemies) do
            local enemyPos = enemyData.Position
            local toEnemy = Vector3.new(enemyPos.X - playerPos.X, 0, enemyPos.Z - playerPos.Z)
            local dist = toEnemy.Magnitude

            if dist <= radius then
                if dist > 0.1 then
                    local dot = toEnemy.Unit:Dot(aimDirection)
                    if dot > 0.5 then
                        enemyData.StunnedUntil = tick() + stunDuration
                        stunCount = stunCount + 1
                    end
                end
            end
        end

        fireToNearbyClients("ProjectileSpawn", playerPos, {
            Effect = "ShieldBash",
            Position = playerPos + aimDirection * 2,
            Color = Color3.fromRGB(200, 200, 255),
            OwnerId = player.UserId,
        })

        return true, stunCount

    elseif effect == "PiercingShot" then
        local baseDamage = abilityData.Damage
        if type(baseDamage) == "table" then
            baseDamage = math.random(baseDamage.Min, baseDamage.Max)
        end
        baseDamage = baseDamage or 150

        local finalDamage = math.floor(baseDamage * Utilities.GetDamageMult(effectiveStats.Attack))
        local rangeStuds = (abilityData.Range or 10) * Constants.STUDS_PER_UNIT
        local speed = 100
        local lifetime = rangeStuds / speed
        local spawnPos = playerPos + aimDirection * 2 + Vector3.new(0, 2, 0)

        local projId = Utilities.GenerateUID()
        local projectile = {
            Id = projId,
            Owner = player,
            OwnerType = "Player",
            Position = spawnPos,
            Direction = aimDirection,
            Speed = speed,
            Damage = finalDamage,
            AttackStat = effectiveStats.Attack,
            Lifetime = lifetime,
            SpawnTime = tick(),
            HitEnemies = {},
            Pierce = true,
            PierceCount = 999,
            HitCount = 0,
            Size = 1.2,
            MaxRange = rangeStuds,
            Color = Color3.fromRGB(0, 255, 200),
            StartX = spawnPos.X,
            StartZ = spawnPos.Z,
            StartY = spawnPos.Y,
            BulletId = math.random(0, 1000000),
        }

        CombatManager.PlayerProjectiles[projId] = projectile
        CombatManager.ProjectileCount.Player = CombatManager.ProjectileCount.Player + 1

        -- Send immediately for responsive ability feedback
        fireToNearbyClients("ProjectileSpawn", spawnPos, {
            Id = projId,
            OwnerId = player.UserId,
            Position = spawnPos,
            Direction = aimDirection,
            Speed = speed,
            Lifetime = lifetime,
            Color = projectile.Color,
            Size = projectile.Size,
            IsEnemy = false,
            Pierce = true,
            Effect = "PiercingShot",
        })

        return true
    end

    return false
end

function CombatManager.OnPlayerAbility(player, aimDirection, cursorPosition)
    local PM = getPlayerManager()
    local charData = PM.ActiveCharacters[player]
    if not charData then return end

    if typeof(aimDirection) ~= "Vector3" then return end
    if aimDirection.Magnitude < 0.1 then
        aimDirection = Vector3.new(0, 0, 1)
    else
        aimDirection = aimDirection.Unit
    end

    if typeof(cursorPosition) ~= "Vector3" then
        cursorPosition = nil
    end

    local lastAbility = CombatManager.AbilityCooldowns[player] or 0
    local cooldown = 1.0

    local abilityItemId = charData.Equipment.Ability
    local abilityItem = abilityItemId and ItemDatabase.GetItem(abilityItemId)
    if abilityItem and abilityItem.Cooldown then
        cooldown = abilityItem.Cooldown
    else
        local classData = ClassDatabase.GetClass(charData.Class)
        if classData and classData.Ability and classData.Ability.Cooldown then
            cooldown = classData.Ability.Cooldown
        end
    end

    if tick() - lastAbility < cooldown then
        return
    end

    local mpCost = 20
    if abilityItem and abilityItem.MPCost then
        mpCost = abilityItem.MPCost
    else
        local classData = ClassDatabase.GetClass(charData.Class)
        if classData and classData.Ability and classData.Ability.ManaCost then
            mpCost = classData.Ability.ManaCost
        end
    end

    if charData.CurrentMP < mpCost then
        return
    end

    charData.CurrentMP = charData.CurrentMP - mpCost
    CombatManager.AbilityCooldowns[player] = tick()

    local success = CombatManager.ExecuteAbility(player, aimDirection, abilityItem, cursorPosition)

    local effectiveStats = PM.GetEffectiveStats(player)
    Remotes.Events.StatUpdate:FireClient(player, {
        CurrentMP = charData.CurrentMP,
        MaxMP = effectiveStats.MaxMP,
    })

    if player.Character then
        player.Character:SetAttribute("CurrentMP", charData.CurrentMP)
    end
end

--============================================================================
-- INITIALIZATION
--============================================================================

function CombatManager.Init()
    -- Wait for Remotes to be ready (prevents race condition)
    if not Remotes.IsReady then
        Remotes.WaitForReady(5)
    end

    -- PlayerHitEnemy - handles aggregated hit batches (one entry per enemy with count)
    local hitRemote = Remotes.GetRemote("PlayerHitEnemy", 5)
    if hitRemote then
        hitRemote.OnServerEvent:Connect(function(player, hitData)
            -- Handle aggregated format: array of {EnemyId, Count, Position, Timestamp}
            if type(hitData) == "table" and hitData[1] then
                for _, hit in ipairs(hitData) do
                    local hitCount = hit.Count or 1
                    -- Process hits for this enemy (apply damage × count)
                    CombatManager.OnPlayerHitEnemy(player, hit.EnemyId, hit.Position, hit.Timestamp, hitCount)
                end
            elseif type(hitData) == "string" then
                -- Legacy: individual enemyId
                CombatManager.OnPlayerHitEnemy(player, hitData, nil, nil, 1)
            end
        end)
    else
        warn("[CombatManager] CRITICAL: PlayerHitEnemy remote not found!")
    end

    -- UseAbility remote event (with safe access)
    local useAbilityRemote = Remotes.GetRemote("UseAbility", 5)
    if useAbilityRemote then
        useAbilityRemote.OnServerEvent:Connect(function(player, aimDirection, cursorPosition)
            CombatManager.OnPlayerAbility(player, aimDirection, cursorPosition)
        end)
    else
        warn("[CombatManager] CRITICAL: UseAbility remote not found!")
    end

    -- PlayerHitByProjectile - DISABLED: ProjectileManager.lua handles this event
    -- Having both handlers caused duplicate damage and duplicate damage indicators
    -- local hitByProjRemote = Remotes.GetRemote("PlayerHitByProjectile", 5)
    -- if hitByProjRemote then
    --     hitByProjRemote.OnServerEvent:Connect(function(player, projectileId, hitPosition)
    --         -- Validate and apply damage to player
    --         local PM = getPlayerManager()
    --         if not PM then return end
    --
    --         -- Basic validation - player must have a character
    --         local character = player.Character
    --         if not character then return end
    --
    --         -- Look up projectile to get damage
    --         local proj = CombatManager.EnemyProjectiles[projectileId]
    --         local damage = 20  -- Default fallback
    --         if proj then
    --             damage = proj.Damage or 20
    --             -- Remove projectile after hit
    --             CombatManager.EnemyProjectiles[projectileId] = nil
    --             CombatManager.ProjectileCount.Enemy = CombatManager.ProjectileCount.Enemy - 1
    --         end
    --
    --         -- Apply damage (PlayerManager handles godmode check, etc.)
    --         local actualDamage = PM.DamagePlayer(player, damage)
    --
    --         -- Send damage number to player
    --         local rootPart = character:FindFirstChild("HumanoidRootPart")
    --         if rootPart and actualDamage and actualDamage > 0 then
    --             Remotes.Events.DamageNumber:FireClient(player, {
    --                 Position = rootPart.Position + Vector3.new(0, 2, 0),
    --                 Damage = actualDamage,
    --                 IsPlayer = true,
    --             })
    --         end
    --     end)
    -- else
    --     warn("[CombatManager] PlayerHitByProjectile remote not found")
    -- end

    RunService.Heartbeat:Connect(function(deltaTime)
        CombatManager.Update(deltaTime)
    end)

    Players.PlayerRemoving:Connect(function(player)
        CombatManager.PlayerCooldowns[player] = nil
        CombatManager.AbilityCooldowns[player] = nil
        CombatManager.PlayerGrid:Remove(player)
        playerPositionCache[player] = nil  -- Clean up position cache
        cleanupHitRateLimits(player)  -- Clean up rate limit data
    end)

    print("[CombatManager] Initialized (Client-Auth Projectiles + Spatial Grid + Network Culling)")
end

return CombatManager
