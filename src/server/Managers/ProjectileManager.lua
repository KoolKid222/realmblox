--[[
    ProjectileManager.lua
    Client-Authoritative hit detection with Server Verification

    Features:
    - FastCast for high-performance raycasting (player projectiles → enemies)
    - Client reports hits for enemy projectiles → server verifies plausibility
    - Latency-tolerant verification using player ping
    - Pierce mechanics via CanPierceFunction
    - Soulbound damage tracking for loot

    Hit Detection Model:
    - Player → Enemy: Server-authoritative (enemies are data-only)
    - Enemy → Player: Client-authoritative (reduces ghost hits from lag)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local Utilities = require(Shared.Utilities)
local ItemDatabase = require(Shared.ItemDatabase)
local Remotes = require(Shared.Remotes)
local LazyLoader = require(Shared.LazyLoader)

-- FastCast
local Lib = Shared:WaitForChild("Lib")
local FastCast = require(Lib.FastCast)

local ProjectileManager = {}

-- Lazy load managers using LazyLoader utility
local getPlayerManager = LazyLoader.create(script.Parent, "PlayerManager")
local getEnemyManager = LazyLoader.create(script.Parent, "EnemyManager")
local getCombatManager = LazyLoader.create(script.Parent, "CombatManager")
local getRegenManager = LazyLoader.create(script.Parent, "RegenManager")

--============================================================================
-- CASTER SETUP
--============================================================================

-- Create the FastCast caster for player projectiles
local playerCaster = FastCast.new()

-- Create the FastCast caster for enemy projectiles
local enemyCaster = FastCast.new()

--============================================================================
-- ENEMY PROJECTILE TRACKING (for client-authoritative hit verification)
--============================================================================
-- Stores active enemy projectiles by Id for server verification
-- Format: EnemyProjectiles[id] = { Position, Direction, Speed, Damage, SpawnTime, EnemyId }
local EnemyProjectiles = {}

-- Cleanup old projectiles periodically (prevents memory leak)
local PROJECTILE_LIFETIME = 5  -- Max lifetime before auto-cleanup

-- Raycast params for player projectiles (ignore players, hit enemies)
local playerRayParams = RaycastParams.new()
playerRayParams.FilterType = Enum.RaycastFilterType.Include
playerRayParams.FilterDescendantsInstances = {}  -- Will be updated with enemy parts

-- Raycast params for enemy projectiles (ignore enemies, hit players)
local enemyRayParams = RaycastParams.new()
enemyRayParams.FilterType = Enum.RaycastFilterType.Include
enemyRayParams.FilterDescendantsInstances = {}  -- Will be updated with player characters

--============================================================================
-- PIERCE FUNCTION
--============================================================================

-- Determines if a projectile should pierce through a target
-- Returns TRUE to pierce, FALSE to stop
local function canPierceTarget(cast, result, velocity)
    local userData = cast.UserData
    if not userData then return false end

    -- Check if pierce is enabled
    if not userData.Pierce then
        return false
    end

    -- Check pierce count
    local pierceCount = userData.PierceCount or 1
    local hitCount = userData.HitCount or 0

    -- If we haven't exceeded pierce count, allow pierce
    if hitCount < pierceCount - 1 then
        userData.HitCount = hitCount + 1
        return true
    end

    return false
end

--============================================================================
-- HIT DETECTION - PLAYER PROJECTILES
--============================================================================

local function onPlayerProjectileHit(cast, result, velocity, bullet)
    local userData = cast.UserData
    if not userData then return end

    local owner = userData.Owner
    local hitPart = result.Instance
    local hitPosition = result.Position

    -- Find which enemy was hit
    local EM = getEnemyManager()
    local PM = getPlayerManager()

    -- Look up enemy by the hit part (enemies are stored by ID)
    -- Uses RotMG-style 2D distance (ignore Y axis) with proper hitbox radius
    local hitEnemy = nil
    for _, enemy in pairs(EM.Enemies) do
        -- 2D distance calculation (RotMG-style: ignore Y axis)
        local dx = hitPosition.X - enemy.Position.X
        local dz = hitPosition.Z - enemy.Position.Z
        local horizontalDist = math.sqrt(dx * dx + dz * dz)

        -- Use enemy's defined hitbox radius (smaller than visual)
        local enemyHitboxRadius = enemy.Definition.HitboxRadius or (math.max(enemy.Definition.Size.X, enemy.Definition.Size.Z) * 0.4)
        local projectileRadius = Constants.Hitbox and Constants.Hitbox.PROJECTILE_RADIUS or 0.3

        if horizontalDist < enemyHitboxRadius + projectileRadius then
            hitEnemy = enemy
            break
        end
    end

    if not hitEnemy then return end

    -- Anti-cheat: Verify the shot could have reached this point
    local shotOrigin = userData.Origin
    local maxRange = userData.MaxRange or 100
    local distanceToHit = (hitPosition - shotOrigin).Magnitude

    if distanceToHit > maxRange * 1.2 then  -- 20% tolerance for latency
        warn("[ProjectileManager] Anti-cheat: Shot exceeded max range for " .. (owner and owner.Name or "unknown"))
        return
    end

    -- Calculate damage using RotMG formula
    local baseDamage = userData.Damage or 50
    local attackStat = userData.AttackStat or 0
    local enemyDefense = hitEnemy.Definition.Defense or 0

    local finalDamage = Utilities.CalculateDamage(baseDamage, attackStat, enemyDefense)

    -- Apply damage to enemy (also handles soulbound damage tracking)
    local killed = EM.DamageEnemy(hitEnemy, finalDamage, owner)

    -- Send damage number to all clients
    Remotes.Events.DamageNumber:FireAllClients({
        Position = hitEnemy.Position + Vector3.new(0, 3, 0),
        Damage = finalDamage,
        IsCrit = false,
        IsEnemy = true,
    })
end

-- Also handle pierced hits
local function onPlayerProjectilePierced(cast, result, velocity, bullet)
    -- Same logic as hit, but projectile continues
    onPlayerProjectileHit(cast, result, velocity, bullet)
end

--============================================================================
-- LEGACY: HIT DETECTION - ENEMY PROJECTILES (DISABLED)
-- This function is NO LONGER USED - kept for reference only
-- Enemy → Player hit detection is now CLIENT-AUTHORITATIVE
-- See: onPlayerHitByProjectile() and PlayerHitByProjectile remote event
--============================================================================

--[[
local function onEnemyProjectileHit(cast, result, velocity, bullet)
    local userData = cast.UserData
    if not userData then return end

    local hitPart = result.Instance
    local hitPosition = result.Position

    -- Find which player was hit
    local PM = getPlayerManager()

    -- Get hitbox radii from Constants
    local playerHitboxRadius = Constants.Hitbox and Constants.Hitbox.PLAYER_RADIUS or 0.5
    local projectileRadius = Constants.Hitbox and Constants.Hitbox.PROJECTILE_RADIUS or 0.3
    local totalHitRadius = playerHitboxRadius + projectileRadius

    for _, player in ipairs(Players:GetPlayers()) do
        if player.Character then
            local rootPart = player.Character:FindFirstChild("HumanoidRootPart")
            if rootPart then
                -- 2D distance calculation (RotMG-style: ignore Y axis)
                local dx = hitPosition.X - rootPart.Position.X
                local dz = hitPosition.Z - rootPart.Position.Z
                local horizontalDist = math.sqrt(dx * dx + dz * dz)

                if horizontalDist < totalHitRadius then
                    -- Apply damage to player
                    local rawDamage = userData.Damage or 20
                    local actualDamage = PM.DamagePlayer(player, rawDamage)

                    -- Send damage number to the hit player
                    Remotes.Events.DamageNumber:FireClient(player, {
                        Position = rootPart.Position + Vector3.new(0, 2, 0),
                        Damage = actualDamage,
                        IsPlayer = true,
                    })

                    break
                end
            end
        end
    end
end
]]  -- END OF LEGACY onEnemyProjectileHit (commented out)

--============================================================================
-- CREATE PROJECTILES
--============================================================================

-- Create a player projectile (called when FireWeapon event received)
function ProjectileManager.CreatePlayerProjectile(player, direction, weaponData)
    local PM = getPlayerManager()
    local EM = getEnemyManager()

    local character = player.Character
    if not character then return end
    local rootPart = character:FindFirstChild("HumanoidRootPart")
    if not rootPart then return end

    local effectiveStats = PM.GetEffectiveStats(player)
    if not effectiveStats then return end

    -- Normalize direction
    direction = Vector3.new(direction.X, 0, direction.Z)
    if direction.Magnitude > 0.01 then
        direction = direction.Unit
    else
        direction = rootPart.CFrame.LookVector
        direction = Vector3.new(direction.X, 0, direction.Z).Unit
    end

    -- Calculate damage
    local baseDamage = math.random(weaponData.Damage.Min, weaponData.Damage.Max)

    -- Get spawn position
    local spawnPos = rootPart.Position + direction * 2 + Vector3.new(0, 2, 0)

    -- Calculate range in studs
    local rangeInStuds = (weaponData.Range or 8) * Constants.STUDS_PER_UNIT
    local speed = weaponData.ProjectileSpeed or 80

    -- Update raycast params to include enemy hitboxes
    -- For simplicity, we raycast against a ground plane and check enemy positions manually
    playerRayParams.FilterDescendantsInstances = {workspace.Terrain}

    -- Create cast behavior
    local behavior = FastCast.newBehavior()
    behavior.RaycastParams = playerRayParams
    behavior.MaxDistance = rangeInStuds
    behavior.HighFidelitySegmentSize = 4
    behavior.Acceleration = Vector3.zero
    behavior.CanPierceFunction = canPierceTarget

    -- User data for this projectile
    local userData = {
        Owner = player,
        Origin = spawnPos,
        Direction = direction,
        Damage = baseDamage,
        AttackStat = effectiveStats.Attack,
        MaxRange = rangeInStuds,
        Pierce = weaponData.Pierce or false,
        PierceCount = weaponData.PierceCount or 1,
        HitCount = 0,
        WeaponId = weaponData.Id,
        HitEnemies = {},  -- Track hit enemies for pierce
    }

    -- Fire the cast
    local cast = playerCaster:Fire(spawnPos, direction, speed, behavior, userData)

    -- Notify clients to show cosmetic bullet
    local numProjectiles = weaponData.NumProjectiles or 1
    local isStaffHelix = weaponData.WavePattern and weaponData.Subtype == "Staff"

    for i = 1, numProjectiles do
        local shotDir = direction

        -- Calculate wave sign for DNA helix
        local waveSign = 1
        if isStaffHelix and numProjectiles == 2 then
            waveSign = (i == 1) and -1 or 1
        end

        Remotes.Events.ProjectileSpawn:FireAllClients({
            Id = Utilities.GenerateUID(),
            OwnerId = player.UserId,
            Position = spawnPos,
            Direction = shotDir,
            Speed = speed,
            Lifetime = rangeInStuds / speed,
            Color = weaponData.ProjectileColor or Color3.fromRGB(180, 100, 255),
            Size = 0.8,
            IsEnemy = false,
            Pierce = weaponData.Pierce or false,

            -- Wave pattern data
            WavePattern = weaponData.WavePattern or false,
            WaveAmplitude = isStaffHelix and 2 or ((weaponData.WaveAmplitude or 0) * Constants.STUDS_PER_UNIT),
            WaveFrequency = isStaffHelix and 15 or (weaponData.WaveFrequency or 0),
            WaveSign = waveSign,
        })
    end

    return cast
end

-- Create an enemy projectile
function ProjectileManager.CreateEnemyProjectile(enemy, targetPosition)
    local direction = Utilities.GetDirection(enemy.Position, targetPosition)
    local spawnPos = enemy.Position + Vector3.new(0, 2, 0)

    -- Update raycast params
    local playerChars = {}
    for _, player in ipairs(Players:GetPlayers()) do
        if player.Character then
            table.insert(playerChars, player.Character)
        end
    end
    enemyRayParams.FilterDescendantsInstances = playerChars

    -- Create cast behavior
    local behavior = FastCast.newBehavior()
    behavior.RaycastParams = enemyRayParams
    behavior.MaxDistance = 200
    behavior.HighFidelitySegmentSize = 8
    behavior.Acceleration = Vector3.zero

    local speed = enemy.Definition.ProjectileSpeed or 40
    local damage = enemy.Definition.AttackDamage or 20

    local userData = {
        EnemyId = enemy.Id,
        Damage = damage,
        Origin = spawnPos,
    }

    local cast = enemyCaster:Fire(spawnPos, direction, speed, behavior, userData)

    -- Generate unique ID for client-server synchronization
    local projectileId = Utilities.GenerateUID()

    -- Store projectile for client hit verification
    EnemyProjectiles[projectileId] = {
        Position = spawnPos,
        Direction = direction,
        Speed = speed,
        Damage = damage,
        SpawnTime = tick(),
        EnemyId = enemy.Id,
        Cast = cast,  -- Reference to FastCast for position updates
    }

    -- Notify clients (include damage for local feedback)
    Remotes.Events.ProjectileSpawn:FireAllClients({
        Id = projectileId,
        Position = spawnPos,
        Direction = direction,
        Speed = speed,
        Lifetime = 3.0,
        Color = enemy.Definition.ProjectileColor or Color3.fromRGB(255, 0, 0),
        Size = 1.5,
        IsEnemy = true,
        Damage = damage,
    })

    return cast
end

--============================================================================
-- ATTACK COOLDOWNS
--============================================================================

local playerCooldowns = {}

function ProjectileManager.OnPlayerFire(player, aimDirection)
    local PM = getPlayerManager()

    -- Get weapon
    local weapon = PM.GetEquippedWeapon(player)
    if not weapon then return end

    -- Check cooldown
    local lastFire = playerCooldowns[player] or 0
    local effectiveStats = PM.GetEffectiveStats(player)
    local cooldown = Utilities.GetAttackCooldown(effectiveStats.Dexterity, weapon.RateOfFire)

    if tick() - lastFire < cooldown then
        return
    end

    playerCooldowns[player] = tick()

    -- Create the projectile(s)
    ProjectileManager.CreatePlayerProjectile(player, aimDirection, weapon)
end

--============================================================================
-- CUSTOM HIT DETECTION (for enemies without physical parts)
--============================================================================

-- Since enemies are data-only (no physical parts), we need custom hit detection
-- Uses RotMG-style 2D cylinder collision (ignore Y axis)
local function checkEnemyHits(deltaTime)
    local EM = getEnemyManager()

    -- For each active player cast, check against enemy positions
    for _, cast in ipairs(playerCaster._activeCasts or {}) do
        if cast.StateInfo.IsActive then
            local userData = cast.UserData
            if userData then
                for id, enemy in pairs(EM.Enemies) do
                    -- Skip if already hit this enemy
                    if not userData.HitEnemies[id] then
                        -- 2D distance calculation (RotMG-style: ignore Y axis)
                        local dx = cast.Position.X - enemy.Position.X
                        local dz = cast.Position.Z - enemy.Position.Z
                        local horizontalDist = math.sqrt(dx * dx + dz * dz)

                        -- Use enemy's defined hitbox radius (smaller than visual)
                        local enemyHitboxRadius = enemy.Definition.HitboxRadius or (math.max(enemy.Definition.Size.X, enemy.Definition.Size.Z) * 0.4)
                        local projectileRadius = Constants.Hitbox and Constants.Hitbox.PROJECTILE_RADIUS or 0.3
                        local hitRadius = enemyHitboxRadius + projectileRadius

                        if horizontalDist < hitRadius then
                            -- Mark as hit
                            userData.HitEnemies[id] = true

                            -- Calculate and apply damage
                            local PM = getPlayerManager()
                            local baseDamage = userData.Damage or 50
                            local attackStat = userData.AttackStat or 0
                            local enemyDefense = enemy.Definition.Defense or 0

                            local finalDamage = Utilities.CalculateDamage(baseDamage, attackStat, enemyDefense)
                            local killed = EM.DamageEnemy(enemy, finalDamage, userData.Owner)

                            -- Notify RegenManager that player dealt damage (enters combat state)
                            if userData.Owner then
                                getRegenManager().OnPlayerDealtDamage(userData.Owner)
                            end

                            -- Send damage number
                            Remotes.Events.DamageNumber:FireAllClients({
                                Position = enemy.Position + Vector3.new(0, 3, 0),
                                Damage = finalDamage,
                                IsCrit = false,
                                IsEnemy = true,
                            })

                            -- Handle pierce
                            if userData.Pierce then
                                userData.HitCount = (userData.HitCount or 0) + 1
                                if userData.HitCount >= (userData.PierceCount or 1) then
                                    cast:Terminate()
                                    break
                                end
                            else
                                -- Non-piercing: terminate immediately
                                cast:Terminate()
                                break
                            end
                        end
                    end
                end
            end
        end
    end
end

--============================================================================
-- CLIENT-AUTHORITATIVE HIT VERIFICATION
-- Client reports hits, server verifies plausibility using ping tolerance
--============================================================================

-- Calculate expected projectile position at current time
local function getExpectedProjectilePosition(projData)
    local elapsed = tick() - projData.SpawnTime

    -- Use original spawn position (StartX/Y/Z) if available, otherwise use Position
    local startPos
    if projData.StartX and projData.StartY and projData.StartZ then
        startPos = Vector3.new(projData.StartX, projData.StartY, projData.StartZ)
    else
        -- Fallback for ProjectileManager-created projectiles
        startPos = projData.Position
    end

    return startPos + projData.Direction * projData.Speed * elapsed
end

-- Verify a client-reported hit is plausible
local function onPlayerHitByProjectile(player, bulletId, clientBulletPos)
    -- Debug logging disabled for performance
    -- print("[ProjectileManager] PlayerHitByProjectile received from", player.Name, "bulletId:", bulletId)

    local PM = getPlayerManager()
    local CM = getCombatManager()

    -- Sanity Check 1: Verify bullet exists
    -- Check CombatManager's table (where EnemyManager creates projectiles)
    local projData = CM.EnemyProjectiles[bulletId]
    local source = "CombatManager"
    if not projData then
        -- Also check our local table as fallback
        projData = EnemyProjectiles[bulletId]
        source = "ProjectileManager"
    end
    if not projData then
        -- Bullet doesn't exist or already consumed
        -- print("[ProjectileManager] Bullet not found in either table - already consumed or invalid")
        return
    end
    -- print("[ProjectileManager] Found bullet in", source, "table")

    -- Get player position
    local character = player.Character
    if not character then return end

    local rootPart = character:FindFirstChild("HumanoidRootPart")
    if not rootPart then return end

    local playerPos = rootPart.Position

    -- Sanity Check 2: Latency Tolerance
    -- Calculate max allowed distance based on player ping
    local ping = player:GetNetworkPing()  -- Returns ping in seconds
    local clampedPing = math.clamp(ping, 0.05, 0.5)  -- 50ms to 500ms

    -- MaxLeeway = bullet travel distance during ping + base tolerance
    -- This accounts for the time between client detecting hit and server receiving event
    local maxLeeway = (projData.Speed * clampedPing) + 4  -- 4 studs base tolerance

    -- Calculate server's expected bullet position
    local expectedBulletPos = getExpectedProjectilePosition(projData)

    -- Check distance between expected bullet position and player (2D, ignore Y)
    local dx = expectedBulletPos.X - playerPos.X
    local dz = expectedBulletPos.Z - playerPos.Z
    local distanceFromPlayer = math.sqrt(dx * dx + dz * dz)

    -- Also check if client's reported bullet position is reasonable
    local clientDx = clientBulletPos.X - expectedBulletPos.X
    local clientDz = clientBulletPos.Z - expectedBulletPos.Z
    local clientPosDeviation = math.sqrt(clientDx * clientDx + clientDz * clientDz)

    -- Verify hit is plausible
    if distanceFromPlayer <= maxLeeway and clientPosDeviation <= maxLeeway then
        -- Hit verified - apply damage
        local rawDamage = projData.Damage or 20
        local actualDamage = PM.DamagePlayer(player, rawDamage)

        -- Send damage number to ALL nearby players (so they can see when others take damage)
        Remotes.Events.DamageNumber:FireAllClients({
            Position = rootPart.Position + Vector3.new(0, 2, 0),
            Damage = actualDamage,
            IsPlayer = true,
        })

        -- Remove the projectile from tracking (prevent double hits)
        -- Remove from both tables to be safe
        EnemyProjectiles[bulletId] = nil
        CM.EnemyProjectiles[bulletId] = nil
        if CM.ProjectileCount then
            CM.ProjectileCount.Enemy = math.max(0, (CM.ProjectileCount.Enemy or 0) - 1)
        end

        -- Terminate the FastCast if still active
        if projData.Cast and projData.Cast.StateInfo and projData.Cast.StateInfo.IsActive then
            projData.Cast:Terminate()
        end
    else
        -- Hit rejected - too far from expected position
        warn(string.format(
            "[ProjectileManager] Hit rejected for %s: distance=%.1f, leeway=%.1f, ping=%.0fms",
            player.Name, distanceFromPlayer, maxLeeway, ping * 1000
        ))
    end
end

-- Cleanup old projectiles periodically
local function cleanupOldProjectiles()
    local currentTime = tick()
    local toRemove = {}

    for id, projData in pairs(EnemyProjectiles) do
        if currentTime - projData.SpawnTime > PROJECTILE_LIFETIME then
            table.insert(toRemove, id)
        end
    end

    for _, id in ipairs(toRemove) do
        EnemyProjectiles[id] = nil
    end
end

--============================================================================
-- INITIALIZATION
--============================================================================

function ProjectileManager.Init()
    -- DISABLED: Server-side player projectile raycast hit detection
    -- Hit detection for player projectiles is now CLIENT-AUTHORITATIVE
    -- Client detects hits via ProjectileRenderer, reports via PlayerHitEnemy remote
    -- Server validates and applies damage in CombatManager.OnPlayerHitEnemy()
    -- playerCaster.RayHit:Connect(onPlayerProjectileHit)  -- LEGACY - DO NOT ENABLE
    -- playerCaster.RayPierced:Connect(onPlayerProjectilePierced)  -- LEGACY - DO NOT ENABLE

    -- DISABLED: Server-side enemy projectile raycast hit detection
    -- This was causing "ghost hits" due to server-client position desync
    -- Hit detection for enemy projectiles is now CLIENT-AUTHORITATIVE
    -- The client detects hits locally and reports via PlayerHitByProjectile remote
    -- enemyCaster.RayHit:Connect(onEnemyProjectileHit)  -- LEGACY - DO NOT ENABLE

    -- Listen for player fire events
    Remotes.Events.FireWeapon.OnServerEvent:Connect(function(player, aimDirection)
        ProjectileManager.OnPlayerFire(player, aimDirection)
    end)

    -- Listen for client-reported projectile hits (client-authoritative)
    Remotes.Events.PlayerHitByProjectile.OnServerEvent:Connect(onPlayerHitByProjectile)

    -- DISABLED: Server-side hit detection for player projectiles → enemies
    -- This caused duplicate damage when combined with client-reported hits
    -- RunService.Heartbeat:Connect(checkEnemyHits)  -- LEGACY - DO NOT ENABLE

    -- Cleanup old enemy projectiles every second
    task.spawn(function()
        while true do
            task.wait(1)
            cleanupOldProjectiles()
        end
    end)

    -- Cleanup on player leave
    Players.PlayerRemoving:Connect(function(player)
        playerCooldowns[player] = nil
    end)

    print("[ProjectileManager] Initialized (Client-Auth hit detection for enemy projectiles)")
end

return ProjectileManager
