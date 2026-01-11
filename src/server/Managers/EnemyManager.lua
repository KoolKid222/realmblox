--[[
    EnemyManager.lua
    Handles enemy spawning, AI, and state management

    RotMG-Style Movement System:
    - Snappy, arcade-like movement (no floaty physics)
    - Behaviors: Chase, Orbit, Wander
    - Charge attacks with telegraph warning
    - Soft collision (separation force)
    - Y-axis locked for 2.5D gameplay
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local Utilities = require(Shared.Utilities)
local EnemyDatabase = require(Shared.EnemyDatabase)
local Remotes = require(Shared.Remotes)
local WorldGen = require(Shared.WorldGen)
local BiomeData = require(Shared.BiomeData)
local LazyLoader = require(Shared.LazyLoader)
local SpatialGrid = require(Shared.SpatialGrid)

local EnemyManager = {}

-- Lazy load managers using LazyLoader utility
local getPlayerManager = LazyLoader.create(script.Parent, "PlayerManager")
local getCombatManager = LazyLoader.create(script.Parent, "CombatManager")
local getLootManager = LazyLoader.create(script.Parent, "LootManager")

-- Active enemies
EnemyManager.Enemies = {}  -- [id] = enemyData
EnemyManager.EnemyCount = 0

-- Spatial grid for O(1) nearby enemy queries (separation, network culling)
local EnemyGrid = SpatialGrid.new(20)  -- 20 stud cells

--============================================================================
-- AI STATES
--============================================================================
local AI_STATE = {
    IDLE = "Idle",              -- Wandering, no target
    ENGAGED = "Engaged",        -- Has target, moving towards
    ATTACKING = "Attacking",    -- In attack range, firing
    CHARGING = "Charging",      -- Performing charge attack
    CHARGE_WARNING = "ChargeWarning",  -- Telegraph before charge
}

--============================================================================
-- MOVEMENT CONSTANTS
--============================================================================
local ENEMY_Y_POSITION = 2  -- Fixed Y height (flat terrain at Y=0)
local SEPARATION_RADIUS = 6
local SEPARATION_FORCE = 0.5
local ORBIT_BLEND_RANGE = 8

-- Performance toggles
local SEPARATION_ENABLED = true   -- Now O(cells) with spatial grid instead of O(n²)
local AI_UPDATE_INTERVAL = 1      -- Every frame (smooth movement)
local aiFrameCounter = 0

-- Network culling radius (only send nearby enemies to each player)
local BROADCAST_RADIUS = 150

-- Cached player positions (updated once per frame, not per enemy)
local cachedPlayerPositions = {}  -- [player] = {Position, RootPart}
local lastPlayerCacheTime = 0

-- Get enemy Y position (flat terrain - always same height)
local function getEnemyYPosition(x, z)
    return ENEMY_Y_POSITION
end

--============================================================================
-- HELPER FUNCTIONS
--============================================================================

local function getHorizontalDirection(from, to)
    local dir = Vector3.new(to.X - from.X, 0, to.Z - from.Z)
    if dir.Magnitude > 0.001 then
        return dir.Unit
    end
    return Vector3.zero
end

local function getHorizontalDistance(a, b)
    return math.sqrt((a.X - b.X)^2 + (a.Z - b.Z)^2)
end

local function getPerpendicularDirection(dir)
    return Vector3.new(-dir.Z, 0, dir.X)
end

-- Check if position is in a safe zone (no enemies spawn here)
-- Uses the new biome system - Beach and DeepWater are safe
local function isInSafeZone(position)
    local biome = WorldGen.GetBiome(position.X, position.Z)
    if not biome then return true end  -- Unknown = safe

    -- Beach and DeepWater are safe (no enemy spawns)
    return not biome.SpawnEnemies
end

-- Update player position cache (call once per frame, not per enemy)
local function updatePlayerCache()
    local currentTime = tick()
    if currentTime - lastPlayerCacheTime < 0.016 then return end  -- ~60fps throttle
    lastPlayerCacheTime = currentTime

    -- Clear old entries
    for player, _ in pairs(cachedPlayerPositions) do
        if not player.Parent then
            cachedPlayerPositions[player] = nil
        end
    end

    -- Update positions
    for _, player in ipairs(Players:GetPlayers()) do
        if player.Character then
            local rootPart = player.Character:FindFirstChild("HumanoidRootPart")
            if rootPart then
                cachedPlayerPositions[player] = {
                    Position = rootPart.Position,
                    RootPart = rootPart
                }
            end
        end
    end
end

local function findNearestPlayer(enemy)
    local nearestPlayer = nil
    local nearestDist = math.huge
    local nearestPos = nil

    -- Use cached positions instead of FindFirstChild every call
    for player, data in pairs(cachedPlayerPositions) do
        local dist = getHorizontalDistance(enemy.Position, data.Position)
        if dist < nearestDist then
            nearestDist = dist
            nearestPlayer = player
            nearestPos = data.Position
        end
    end

    return nearestPlayer, nearestDist, nearestPos
end

--============================================================================
-- SEPARATION FORCE (Soft Collision)
--============================================================================

local function calculateSeparationForce(enemy)
    -- Skip if separation disabled for performance
    if not SEPARATION_ENABLED then
        return Vector3.zero
    end

    local separationDir = Vector3.zero
    local neighborCount = 0

    -- SPATIAL QUERY: Only check enemies in nearby cells (O(cells) instead of O(n))
    local nearbyIds = EnemyGrid:GetNearby(enemy.Position, SEPARATION_RADIUS)

    for otherId in pairs(nearbyIds) do
        if otherId ~= enemy.Id then
            local other = EnemyManager.Enemies[otherId]
            if other then
                local dist = getHorizontalDistance(enemy.Position, other.Position)
                if dist < SEPARATION_RADIUS and dist > 0.01 then
                    local pushDir = getHorizontalDirection(other.Position, enemy.Position)
                    local strength = 1 - (dist / SEPARATION_RADIUS)
                    separationDir = separationDir + pushDir * strength
                    neighborCount = neighborCount + 1
                end
            end
        end
    end

    if neighborCount > 0 then
        separationDir = separationDir / neighborCount
        if separationDir.Magnitude > 0.001 then
            return separationDir.Unit * SEPARATION_FORCE
        end
    end

    return Vector3.zero
end

--============================================================================
-- BEHAVIOR IMPLEMENTATIONS
--============================================================================

-- Get the appropriate speed for current state
local function getSpeed(enemy, isChasing)
    local def = enemy.Definition
    if isChasing then
        return def.ChaseSpeed or def.Speed or 12
    end
    return def.Speed or 12
end

-- Chase Behavior: Run straight at player
local function calculateChaseVelocity(enemy, playerPos, distance)
    local def = enemy.Definition
    local speed = getSpeed(enemy, true)
    local stopRange = def.StopRange or 3

    local chaseDir = getHorizontalDirection(enemy.Position, playerPos)

    -- Stop if within stop range
    if distance < stopRange then
        return Vector3.zero
    end

    return chaseDir * speed
end

-- Orbit Behavior: Maintain distance while circling
local function calculateOrbitVelocity(enemy, playerPos, distance)
    local def = enemy.Definition
    local speed = getSpeed(enemy, true)
    local orbitRadius = def.OrbitRadius or 20

    local toPlayer = getHorizontalDirection(enemy.Position, playerPos)

    -- Perpendicular for orbiting
    local orbitClockwise = (string.byte(enemy.Id, 1) % 2 == 0)
    local tangent = getPerpendicularDirection(toPlayer)
    if orbitClockwise then
        tangent = -tangent
    end

    -- Blend based on distance from orbit radius
    local distanceError = distance - orbitRadius
    local blendFactor = 0.5

    if distanceError > ORBIT_BLEND_RANGE then
        blendFactor = 0.9
    elseif distanceError < -ORBIT_BLEND_RANGE then
        blendFactor = -0.3
    else
        blendFactor = 0.5 + (distanceError / ORBIT_BLEND_RANGE) * 0.4
    end

    local chaseComponent = toPlayer * blendFactor
    local orbitComponent = tangent * (1 - math.abs(blendFactor))

    local finalDir = chaseComponent + orbitComponent
    if finalDir.Magnitude > 0.001 then
        finalDir = finalDir.Unit
    end

    return finalDir * speed
end

-- Wander Behavior: Random movement when idle
local function calculateWanderVelocity(enemy, deltaTime)
    local def = enemy.Definition
    local speed = (def.Speed or 12) * 0.3

    enemy.WanderCooldown = (enemy.WanderCooldown or 0) - deltaTime

    if enemy.WanderCooldown <= 0 or not enemy.WanderDirection then
        local angle = math.random() * math.pi * 2
        enemy.WanderDirection = Vector3.new(math.cos(angle), 0, math.sin(angle))
        enemy.WanderDuration = 0.5 + math.random() * 0.5
        enemy.WanderCooldown = enemy.WanderDuration + 1 + math.random() * 2
    end

    enemy.WanderDuration = (enemy.WanderDuration or 0) - deltaTime
    if enemy.WanderDuration > 0 then
        return enemy.WanderDirection * speed
    end

    return Vector3.zero
end

-- Charge Behavior: Fast burst towards player
local function calculateChargeVelocity(enemy)
    local def = enemy.Definition
    local chargeSpeed = def.ChargeSpeed or 40

    if enemy.ChargeDirection then
        return enemy.ChargeDirection * chargeSpeed
    end

    return Vector3.zero
end

--============================================================================
-- CHARGE ATTACK LOGIC
--============================================================================

local function shouldStartCharge(enemy, distance)
    local def = enemy.Definition
    if not def.CanCharge then return false end

    local currentTime = tick()
    local lastCharge = enemy.LastChargeTime or 0
    local cooldown = def.ChargeCooldown or 5
    local chargeRange = def.ChargeRange or 25

    -- Check cooldown and range
    if currentTime - lastCharge < cooldown then return false end
    if distance > chargeRange then return false end

    return true
end

local function startChargeWarning(enemy, playerPos)
    local def = enemy.Definition

    enemy.State = AI_STATE.CHARGE_WARNING
    enemy.ChargeWarningStart = tick()
    enemy.ChargeDirection = getHorizontalDirection(enemy.Position, playerPos)

    -- Notify clients of charge warning (for visual telegraph)
    Remotes.Events.EnemyUpdate:FireAllClients({
        Id = enemy.Id,
        ChargeWarning = true,
        ChargeDirection = enemy.ChargeDirection,
    })
end

local function startCharge(enemy)
    local def = enemy.Definition

    enemy.State = AI_STATE.CHARGING
    enemy.ChargeStart = tick()
    enemy.LastChargeTime = tick()

    -- Notify clients of charge start
    Remotes.Events.EnemyUpdate:FireAllClients({
        Id = enemy.Id,
        Charging = true,
    })
end

local function endCharge(enemy)
    enemy.State = AI_STATE.ENGAGED
    enemy.ChargeDirection = nil

    -- Notify clients charge ended
    Remotes.Events.EnemyUpdate:FireAllClients({
        Id = enemy.Id,
        Charging = false,
    })
end

--============================================================================
-- ATTACK LOGIC
--============================================================================

local function updateEnemyAttack(enemy, nearestPlayer, playerPos, CM)
    local def = enemy.Definition
    local currentTime = tick()

    -- Handle burst attacks (if in burst mode, always return - even if waiting for delay)
    if (enemy.BurstCount or 0) > 0 then
        if currentTime >= (enemy.BurstCooldown or 0) then
            CM.CreateEnemyProjectile(enemy, playerPos)
            enemy.BurstCount = enemy.BurstCount - 1
            local delay = def.BurstDelay or 0.2
            enemy.BurstCooldown = currentTime + delay

            if enemy.BurstCount <= 0 then
                enemy.LastAttack = currentTime
            end
        end
        return  -- ALWAYS return when in burst mode (prevents restart)
    end

    -- Check cooldown
    if currentTime - (enemy.LastAttack or 0) < def.AttackCooldown then
        return
    end

    -- Execute attack
    local pattern = def.AttackPattern or "SingleShot"

    if pattern == "SingleShot" then
        CM.CreateEnemyProjectile(enemy, playerPos)
        enemy.LastAttack = currentTime

    elseif pattern == "Burst" then
        enemy.BurstCount = def.BurstCount or 3
        enemy.BurstCooldown = currentTime

    elseif pattern == "Ring" then
        CM.CreateEnemyRingAttack(enemy)
        enemy.LastAttack = currentTime

    elseif pattern == "Shotgun" then
        CM.CreateEnemyShotgunAttack(enemy, playerPos)
        enemy.LastAttack = currentTime

    elseif pattern == "Spiral" then
        CM.CreateEnemyRingAttack(enemy)
        enemy.LastAttack = currentTime
    end
end

--============================================================================
-- MAIN AI UPDATE
--============================================================================

local function updateEnemyAI(enemy, deltaTime)
    local CM = getCombatManager()
    local def = enemy.Definition
    local behavior = def.Behavior or "Chase"
    local currentTime = tick()

    -- Find nearest player
    local nearestPlayer, distance, playerPos = findNearestPlayer(enemy)

    local velocity = Vector3.zero

    --========================================================================
    -- CHARGE STATES (override normal behavior)
    --========================================================================

    if enemy.State == AI_STATE.CHARGE_WARNING then
        -- Waiting before charge (telegraph)
        local warningDuration = def.ChargeWarning or 0.3
        if currentTime - enemy.ChargeWarningStart >= warningDuration then
            startCharge(enemy)
        end
        -- Don't move during warning (or could do slight movement)
        velocity = Vector3.zero

    elseif enemy.State == AI_STATE.CHARGING then
        -- Executing charge
        local chargeDuration = def.ChargeDuration or 0.5
        if currentTime - enemy.ChargeStart >= chargeDuration then
            endCharge(enemy)
        else
            velocity = calculateChargeVelocity(enemy)
        end

    --========================================================================
    -- NORMAL STATES
    --========================================================================

    elseif nearestPlayer and playerPos then
        local aggroRange = def.AggroRange or 30
        local chaseRange = def.ChaseRange or 50
        local attackRange = def.AttackRange or (aggroRange * 0.8)
        local skipNormalBehavior = false

        -- Check for charge opportunity
        if enemy.State ~= AI_STATE.CHARGE_WARNING and enemy.State ~= AI_STATE.CHARGING then
            if shouldStartCharge(enemy, distance) then
                startChargeWarning(enemy, playerPos)
                skipNormalBehavior = true
            end
        end

        -- Normal behavior based on distance (skip if starting charge)
        if not skipNormalBehavior then
            if distance < aggroRange then
                enemy.State = AI_STATE.ENGAGED
                enemy.Target = nearestPlayer

                -- Apply behavior-specific movement
                if behavior == "Orbit" then
                    velocity = calculateOrbitVelocity(enemy, playerPos, distance)
                else -- "Chase" (default)
                    velocity = calculateChaseVelocity(enemy, playerPos, distance)
                end

                -- Handle attacks
                if distance < attackRange then
                    enemy.State = AI_STATE.ATTACKING
                    updateEnemyAttack(enemy, nearestPlayer, playerPos, CM)
                end

            elseif distance < chaseRange and enemy.State == AI_STATE.ENGAGED then
                -- Still chasing
                if behavior == "Orbit" then
                    velocity = calculateOrbitVelocity(enemy, playerPos, distance)
                else
                    velocity = calculateChaseVelocity(enemy, playerPos, distance)
                end
            else
                -- Lost target
                enemy.State = AI_STATE.IDLE
                enemy.Target = nil
                velocity = calculateWanderVelocity(enemy, deltaTime)
            end
        end
    else
        -- No players
        enemy.State = AI_STATE.IDLE
        velocity = calculateWanderVelocity(enemy, deltaTime)
    end

    -- Add separation force (except during charge)
    if enemy.State ~= AI_STATE.CHARGING then
        local separation = calculateSeparationForce(enemy)
        velocity = velocity + separation * (def.Speed or 12)
    end

    -- Apply velocity
    local movement = velocity * deltaTime
    local newPos = enemy.Position + movement

    -- Lock Y position
    enemy.Position = Vector3.new(newPos.X, getEnemyYPosition(newPos.X, newPos.Z), newPos.Z)
    enemy.Velocity = velocity

    -- Update spatial grid position (for separation and network culling)
    EnemyGrid:Update(enemy.Id, enemy.Position)
end

--============================================================================
-- ENEMY LIFECYCLE
--============================================================================

function EnemyManager.SpawnEnemy(definition, position)
    local enemy = {
        Id = Utilities.GenerateUID(),
        Definition = definition,
        Position = Vector3.new(position.X, getEnemyYPosition(position.X, position.Z), position.Z),
        Velocity = Vector3.zero,
        State = AI_STATE.IDLE,
        CurrentHP = definition.MaxHP,
        Target = nil,
        LastAttack = 0,
        LastChargeTime = 0,
        BurstCount = 0,
        BurstCooldown = 0,
        WanderCooldown = 0,
        WanderDirection = nil,
        WanderDuration = 0,
        ChargeDirection = nil,
        DamageContributors = {},
    }

    EnemyManager.Enemies[enemy.Id] = enemy
    EnemyManager.EnemyCount = EnemyManager.EnemyCount + 1

    -- Add to spatial grid (for separation force and network culling)
    EnemyGrid:Insert(enemy.Id, enemy.Position)

    -- Notify clients
    Remotes.Events.EnemySpawn:FireAllClients({
        Id = enemy.Id,
        Name = definition.Name,
        Position = enemy.Position,
        MaxHP = definition.MaxHP,
        CurrentHP = definition.MaxHP,
        Size = definition.Size,
        Color = definition.Color,
        IsBoss = definition.IsBoss or false,
    })

    return enemy
end

function EnemyManager.RemoveEnemy(enemy)
    if EnemyManager.Enemies[enemy.Id] then
        -- Remove from spatial grid
        EnemyGrid:Remove(enemy.Id)

        EnemyManager.Enemies[enemy.Id] = nil
        EnemyManager.EnemyCount = EnemyManager.EnemyCount - 1
    end
end

function EnemyManager.DamageEnemy(enemy, damage, attacker)
    local oldHP = enemy.CurrentHP
    enemy.CurrentHP = math.max(0, enemy.CurrentHP - damage)

    if attacker then
        enemy.DamageContributors[attacker] = (enemy.DamageContributors[attacker] or 0) + damage
    end

    print(string.format("[EnemyManager] %s took %d damage (HP: %d -> %d / %d)",
        enemy.Definition.Name, damage, oldHP, enemy.CurrentHP, enemy.Definition.MaxHP))

    Remotes.Events.EnemyUpdate:FireAllClients({
        Id = enemy.Id,
        CurrentHP = enemy.CurrentHP,
        MaxHP = enemy.Definition.MaxHP,
    })

    if enemy.CurrentHP <= 0 then
        print("[EnemyManager] " .. enemy.Definition.Name .. " died!")
        EnemyManager.OnEnemyDeath(enemy)
        return true
    end

    return false
end

function EnemyManager.OnEnemyDeath(enemy)
    local PM = getPlayerManager()
    local LM = getLootManager()

    -- Calculate base XP (RotMG: HP/10 if not specified)
    local baseXP = Utilities.GetEnemyBaseXP(enemy.Definition.MaxHP, enemy.Definition.XPReward)
    local isBossOrQuest = enemy.Definition.IsBoss or enemy.Definition.IsGod

    local totalDamage = 0
    for _, dmg in pairs(enemy.DamageContributors) do
        totalDamage = totalDamage + dmg
    end

    for player, damage in pairs(enemy.DamageContributors) do
        if player and player.Parent then
            local charData = PM.ActiveCharacters[player]
            if charData then
                -- RotMG XP cap based on player level
                local cappedXP = Utilities.CapXPReward(baseXP, charData.Level, isBossOrQuest)

                -- Award proportionally based on damage contribution
                local contribution = damage / math.max(totalDamage, 1)
                local xpReward = math.floor(cappedXP * contribution)

                if xpReward > 0 then
                    PM.AddXP(player, xpReward)
                end

                charData.EnemiesKilled = charData.EnemiesKilled + 1

                if enemy.Definition.Zone == "Godlands" then
                    charData.GodKills = charData.GodKills + 1
                end
            end
        end
    end

    -- Pass enemy data for soulbound threshold calculation
    local enemyData = {
        MaxHP = enemy.Definition.MaxHP,
        SoulboundThreshold = enemy.Definition.SoulboundThreshold or 0.15,
        IsBoss = enemy.Definition.IsBoss,
        IsGod = enemy.Definition.IsGod,
    }
    LM.DropLoot(enemy.Position, enemy.Definition.LootTable, enemy.DamageContributors, enemyData)

    Remotes.Events.EnemyDeath:FireAllClients({
        Id = enemy.Id,
        Position = enemy.Position,
    })

    EnemyManager.RemoveEnemy(enemy)
end

function EnemyManager.CheckProjectileHit(projectile)
    for _, enemy in pairs(EnemyManager.Enemies) do
        if not projectile.HitEnemies[enemy.Id] then
            -- Use horizontal distance only (ignore Y difference)
            local dx = projectile.Position.X - enemy.Position.X
            local dz = projectile.Position.Z - enemy.Position.Z
            local horizontalDist = math.sqrt(dx * dx + dz * dz)

            -- Hit radius based on enemy size + projectile size
            local enemyRadius = math.max(enemy.Definition.Size.X, enemy.Definition.Size.Z) / 2
            local hitRadius = enemyRadius + (projectile.Size or 0.8)

            if horizontalDist < hitRadius then
                return enemy
            end
        end
    end

    return nil
end

--============================================================================
-- SPAWNING SYSTEM
--============================================================================

local playerSpawnTimers = {}

local function spawnEnemiesNearPlayers()
    local currentTime = tick()

    for _, player in ipairs(Players:GetPlayers()) do
        if player.Character then
            local rootPart = player.Character:FindFirstChild("HumanoidRootPart")
            if rootPart then
                local playerPos = rootPart.Position

                -- Skip spawning enemies if player is in a safe zone (Beach, DeepWater)
                if isInSafeZone(playerPos) then
                    continue
                end

                if not playerSpawnTimers[player] then
                    playerSpawnTimers[player] = currentTime
                end

                -- Get biome at player position for enemy spawning
                local biome = WorldGen.GetBiome(playerPos.X, playerPos.Z)
                if biome and biome.SpawnEnemies then
                    -- Use biome-specific settings or defaults
                    local maxEnemies = 50 * #Players:GetPlayers()

                    -- Use spatial grid for O(cells) nearby count instead of O(n)
                    local nearbyIds = EnemyGrid:GetNearby(playerPos, 80)
                    local nearbyEnemies = 0
                    for _ in pairs(nearbyIds) do
                        nearbyEnemies = nearbyEnemies + 1
                    end

                    local targetEnemies = 6
                    local spawnInterval = 1.5

                    if nearbyEnemies < targetEnemies and EnemyManager.EnemyCount < maxEnemies then
                        if currentTime - playerSpawnTimers[player] >= spawnInterval then
                            playerSpawnTimers[player] = currentTime

                            -- Find a valid spawn position
                            local spawnPos, spawnBiome = WorldGen.GetEnemySpawnPosition(
                                playerPos.X, playerPos.Z,
                                20, 40  -- Min/max distance
                            )

                            if spawnPos and spawnBiome and spawnBiome.SpawnEnemies then
                                -- Get enemy types for this biome
                                local enemyTypes = spawnBiome.EnemyTypes or {}
                                if #enemyTypes > 0 then
                                    local enemyName = enemyTypes[math.random(#enemyTypes)]
                                    local enemyDef = EnemyDatabase.Enemies[enemyName]

                                    if enemyDef then
                                        EnemyManager.SpawnEnemy(enemyDef, spawnPos)
                                    end
                                else
                                    -- Fallback: Use zone-based spawning if no biome enemies defined
                                    local zoneName = spawnBiome.Name
                                    local enemyDef = EnemyDatabase.GetRandomEnemyForZone(zoneName)
                                    if enemyDef then
                                        EnemyManager.SpawnEnemy(enemyDef, spawnPos)
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end

local function despawnFarEnemies()
    local toRemove = {}
    local despawnDist = Constants.Spawning.DESPAWN_RADIUS * Constants.STUDS_PER_UNIT

    for id, enemy in pairs(EnemyManager.Enemies) do
        local nearAnyPlayer = false
        local closestDist = math.huge

        for _, player in ipairs(Players:GetPlayers()) do
            if player.Character then
                local rootPart = player.Character:FindFirstChild("HumanoidRootPart")
                if rootPart then
                    local dist = getHorizontalDistance(enemy.Position, rootPart.Position)
                    closestDist = math.min(closestDist, dist)
                    if dist < despawnDist then
                        nearAnyPlayer = true
                        break
                    end
                end
            end
        end

        if not nearAnyPlayer then
            print(string.format("[EnemyManager] DESPAWN: %s too far (dist: %.1f > %.1f)",
                enemy.Definition.Name, closestDist, despawnDist))
            table.insert(toRemove, enemy)
        end
    end

    for _, enemy in ipairs(toRemove) do
        Remotes.Events.EnemyDeath:FireAllClients({
            Id = enemy.Id,
            Position = enemy.Position,
            Despawn = true,
        })
        EnemyManager.RemoveEnemy(enemy)
    end
end

-- Get zone/biome at a world position using the new WorldGen system
function EnemyManager.GetZoneAtPosition(position)
    local biome = WorldGen.GetBiome(position.X, position.Z)
    if biome then
        return biome.Name
    end
    return "Beach"  -- Default fallback
end

-- Get biome data at position (for more detailed info)
function EnemyManager.GetBiomeAtPosition(position)
    return WorldGen.GetBiome(position.X, position.Z)
end

--============================================================================
-- NETWORK SYNC
--============================================================================

local function broadcastEnemyPositions()
    -- Network culling: Send only nearby enemies to each player (massive bandwidth savings)
    for _, player in ipairs(Players:GetPlayers()) do
        local playerData = cachedPlayerPositions[player]
        if playerData then
            local positions = {}

            -- Use spatial grid to find only nearby enemies
            local nearbyIds = EnemyGrid:GetNearby(playerData.Position, BROADCAST_RADIUS)

            for enemyId in pairs(nearbyIds) do
                local enemy = EnemyManager.Enemies[enemyId]
                if enemy then
                    positions[enemyId] = {
                        Position = enemy.Position,
                        Velocity = enemy.Velocity,
                        State = enemy.State,
                    }
                end
            end

            if next(positions) then
                Remotes.Events.EnemyUpdate:FireClient(player, {
                    Positions = positions,
                })
            end
        end
    end
end

--============================================================================
-- INITIALIZATION
--============================================================================

local spawnTimer = 0
local despawnTimer = 0
local broadcastTimer = 0

function EnemyManager.Init()
    print("[EnemyManager] Starting initialization...")

    -- Debug: Check if EnemyDatabase has enemies
    local enemyCount = 0
    for name, _ in pairs(EnemyDatabase.Enemies) do
        enemyCount = enemyCount + 1
    end
    print("[EnemyManager] Found " .. enemyCount .. " enemy definitions")

    Players.PlayerRemoving:Connect(function(player)
        playerSpawnTimers[player] = nil
    end)

    RunService.Heartbeat:Connect(function(deltaTime)
        -- Update player position cache ONCE per frame (not per enemy)
        updatePlayerCache()

        -- Throttle AI updates for performance (every N frames)
        aiFrameCounter = aiFrameCounter + 1
        if aiFrameCounter >= AI_UPDATE_INTERVAL then
            aiFrameCounter = 0
            local scaledDelta = deltaTime * AI_UPDATE_INTERVAL
            for _, enemy in pairs(EnemyManager.Enemies) do
                updateEnemyAI(enemy, scaledDelta)
            end
        end

        spawnTimer = spawnTimer + deltaTime
        if spawnTimer >= 0.5 then
            spawnTimer = 0
            spawnEnemiesNearPlayers()
        end

        despawnTimer = despawnTimer + deltaTime
        if despawnTimer >= 2.0 then
            despawnTimer = 0
            despawnFarEnemies()
        end

        broadcastTimer = broadcastTimer + deltaTime
        if broadcastTimer >= 0.1 then
            broadcastTimer = 0
            broadcastEnemyPositions()
        end
    end)

    print("[EnemyManager] Initialized (RotMG-style AI with Charge)")
end

return EnemyManager
