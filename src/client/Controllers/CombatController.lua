--[[
    CombatController.lua
    Handles player input for combat (shooting, abilities, potions)

    ARCHITECTURE: Client-Authoritative Projectiles
    - Client creates and tracks projectile visuals locally
    - Client detects hits against enemies
    - Client reports hits to server for validation and damage
    - NO per-shot network calls (eliminates 8+ events/sec at max DEX)

    Uses RotMG DEX formula: Cooldown = 1 / (1.5 + 6.5 * (DEX / 75))
    Reads DEX from Character Attributes for zero-latency response
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local Constants = require(Shared.Constants)
local Utilities = require(Shared.Utilities)

-- Load ProjectileRenderer for visual rendering
local ProjectileRenderer = require(script.Parent.ProjectileRenderer)
local InventoryController = require(script.Parent.InventoryController)

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local CombatController = {}

-- State
local isMouseDown = false
local lastFireTime = 0
local fireCooldown = 0.125  -- Default at max DEX (75) = 8 APS
local currentWeaponType = "Staff"  -- Track weapon type for visual selection
local weaponRateMultiplier = 1.0  -- Weapon-specific fire rate modifier

-- Cache for rootPart to avoid repeated FindFirstChild
local cachedRootPart = nil
local cachedCharacter = nil

-- Hit report batching - aggregates hits PER ENEMY (massively reduces network)
local hitReportQueue = {}  -- [enemyId] = {count, position, timestamp}
local HIT_BATCH_INTERVAL = 0.2  -- Send hit reports every 200ms

-- Hybrid immediate/batch system - first N hits send immediately for responsive insta-kills
local IMMEDIATE_HIT_COUNT = 2  -- Send first 2 hits immediately per enemy
local immediateHitsSent = {}  -- [enemyId] = count of immediate hits sent
local IMMEDIATE_HIT_RESET_TIME = 1.0  -- Reset immediate counter after 1 second of no hits
local lastHitTime = {}  -- [enemyId] = timestamp of last hit

-- PERF DEBUG: Set to false for production
local DISABLE_HIT_REPORTING = false

-- Cached remote for immediate sends
local cachedHitRemote = nil

local function getRootPart()
    local character = player.Character
    if character ~= cachedCharacter then
        cachedCharacter = character
        cachedRootPart = character and character:FindFirstChild("HumanoidRootPart")
    end
    return cachedRootPart
end

-- Get world position from mouse (on horizontal plane)
local function getMouseWorldPosition(rootPart)
    local mousePos = UserInputService:GetMouseLocation()

    -- Ray from camera through mouse position
    local ray = camera:ViewportPointToRay(mousePos.X, mousePos.Y)

    -- Find intersection with player's Y plane
    local playerY = rootPart and rootPart.Position.Y or 3

    -- Calculate intersection point
    if ray.Direction.Y ~= 0 then
        local t = (playerY - ray.Origin.Y) / ray.Direction.Y
        if t > 0 then
            return ray.Origin + ray.Direction * t
        end
    end

    -- Fallback: use mouse hit (only when ray fails)
    return player:GetMouse().Hit.Position
end

-- Get aim direction and spawn position in one call (avoids duplicate work)
local function getAimAndSpawn()
    local rootPart = getRootPart()
    if not rootPart then return nil, nil end

    local playerPos = rootPart.Position
    local targetPos = getMouseWorldPosition(rootPart)

    local dx = targetPos.X - playerPos.X
    local dz = targetPos.Z - playerPos.Z
    local mag = math.sqrt(dx * dx + dz * dz)

    local aimDirection
    if mag > 0.01 then
        aimDirection = Vector3.new(dx / mag, 0, dz / mag)
    else
        aimDirection = Vector3.new(0, 0, 1)
    end

    -- Spawn slightly in front of player
    local spawnPos = playerPos + aimDirection * 2 + Vector3.new(0, 2, 0)

    return aimDirection, spawnPos
end

-- Check if player has a weapon equipped
local function hasWeaponEquipped()
    local inv = InventoryController.GetInventory()
    if not inv or not inv.Equipment then return false end

    local weaponId = inv.Equipment.Weapon
    return weaponId ~= nil and weaponId ~= ""
end

-- Fire weapon (CLIENT-ONLY - no network call!)
local function fireWeapon()
    -- Check cooldown first (cheap comparison) before expensive checks
    local currentTime = tick()
    if currentTime - lastFireTime < fireCooldown then
        return  -- Still on cooldown
    end

    -- Only check weapon when cooldown has passed
    if not hasWeaponEquipped() then
        return
    end

    -- Get aim and spawn in single call (avoids duplicate calculations)
    local aimDirection, spawnPos = getAimAndSpawn()
    if not spawnPos then return end

    lastFireTime = currentTime

    -- Create local visual immediately (client prediction)
    -- ProjectileRenderer handles hit detection and calls OnProjectileHit
    if currentWeaponType == "Staff" then
        ProjectileRenderer.FireStaffShot(spawnPos, aimDirection)
    else
        -- For other weapon types (bow, wand, etc.)
        ProjectileRenderer.FireProjectile(spawnPos, aimDirection, 80, 0.5)
    end

    -- Tell server so other players can see our projectiles
    -- (Server broadcasts to nearby clients via fireToNearbyClients)
    if Remotes.Events.FireWeapon then
        Remotes.Events.FireWeapon:FireServer(aimDirection)
    end
end

-- Calculate cooldown from Dexterity using RotMG formula
-- At 0 DEX = 1.5 APS (0.667 sec cooldown)
-- At 75 DEX = 8 APS (0.125 sec cooldown)
local function updateCooldownFromDex(dexterity)
    fireCooldown = Utilities.GetAttackCooldown(dexterity or 0, weaponRateMultiplier)
end

-- Update cooldown from server stats (legacy/fallback)
local function updateCooldown(stats)
    if stats and stats.Dexterity then
        updateCooldownFromDex(stats.Dexterity)
    end
end

-- Read DEX from Character Attribute (zero-latency)
local function getCooldownFromAttributes()
    local character = player.Character
    if not character then return end

    local dexterity = character:GetAttribute("Dexterity")
    if dexterity then
        updateCooldownFromDex(dexterity)
    end
end

-- Setup listener for Dexterity attribute changes
local function setupDexterityListener(character)
    -- Set initial cooldown
    getCooldownFromAttributes()

    -- Listen for Dexterity changes (zero-latency updates)
    character:GetAttributeChangedSignal("Dexterity"):Connect(function()
        getCooldownFromAttributes()
    end)
end

--============================================================================
-- CLIENT-SIDE HIT DETECTION CALLBACK
-- Called by ProjectileRenderer when a projectile hits an enemy
--============================================================================

function CombatController.OnProjectileHit(enemyId, hitPosition)
    if DISABLE_HIT_REPORTING then return end

    local currentTime = tick()

    -- Reset immediate counter if enemy hasn't been hit recently
    if lastHitTime[enemyId] and (currentTime - lastHitTime[enemyId]) > IMMEDIATE_HIT_RESET_TIME then
        immediateHitsSent[enemyId] = 0
    end
    lastHitTime[enemyId] = currentTime

    -- Track how many immediate hits we've sent for this enemy
    local sentCount = immediateHitsSent[enemyId] or 0

    -- First N hits send immediately for responsive insta-kills
    if sentCount < IMMEDIATE_HIT_COUNT then
        immediateHitsSent[enemyId] = sentCount + 1

        -- Lazy-load remote
        if not cachedHitRemote then
            cachedHitRemote = Remotes.Events and Remotes.Events.PlayerHitEnemy
        end

        if cachedHitRemote then
            -- Send single hit immediately
            cachedHitRemote:FireServer({{
                EnemyId = enemyId,
                Count = 1,
                Position = hitPosition,
                Timestamp = currentTime,
            }})
        end
    else
        -- Subsequent hits get batched for efficiency
        local existing = hitReportQueue[enemyId]
        if existing then
            existing.Count = existing.Count + 1
            existing.Position = hitPosition
        else
            hitReportQueue[enemyId] = {
                Count = 1,
                Position = hitPosition,
                Timestamp = currentTime,
            }
        end
    end
end

-- Send queued hit reports in batch (runs on separate thread)
-- Aggregated format: one entry per enemy with hit count
local function sendQueuedHitReports()
    -- Wait for Remotes to be ready before starting
    Remotes.WaitForReady(10)

    local hitRemote = nil

    while true do
        task.wait(HIT_BATCH_INTERVAL)

        -- Check if we have any pending hits
        if next(hitReportQueue) then
            -- PERF DEBUG: Skip sending if disabled
            if DISABLE_HIT_REPORTING then
                hitReportQueue = {}
            else
                -- Lazy-load remote on first use
                if not hitRemote then
                    hitRemote = Remotes.Events and Remotes.Events.PlayerHitEnemy
                end

                if hitRemote then
                    -- Convert to array format for sending
                    local batch = {}
                    for enemyId, data in pairs(hitReportQueue) do
                        table.insert(batch, {
                            EnemyId = enemyId,
                            Count = data.Count,
                            Position = data.Position,
                            Timestamp = data.Timestamp,
                        })
                    end
                    -- Send single batch (one entry per enemy)
                    hitRemote:FireServer(batch)
                end
                -- Clear queue
                hitReportQueue = {}
            end
        end
    end
end

--============================================================================
-- INPUT HANDLING
--============================================================================

local function onInputBegan(input, gameProcessed)
    if gameProcessed then return end

    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        isMouseDown = true
    elseif input.KeyCode == Enum.KeyCode.F then
        -- Health potion (F key, like RotMG)
        Remotes.Events.UsePotion:FireServer("Health")
    elseif input.KeyCode == Enum.KeyCode.V then
        -- Mana potion (V key)
        Remotes.Events.UsePotion:FireServer("Mana")
    elseif input.KeyCode == Enum.KeyCode.Space then
        -- Ability - send both direction and cursor position
        local aimDir, _ = getAimAndSpawn()
        local rootPart = getRootPart()
        local cursorPos = rootPart and getMouseWorldPosition(rootPart) or Vector3.new(0, 0, 0)
        Remotes.Events.UseAbility:FireServer(aimDir or Vector3.new(0, 0, 1), cursorPos)
    elseif input.KeyCode == Enum.KeyCode.H then
        -- Toggle godmode (debug testing)
        Remotes.Events.ToggleGodmode:FireServer()
    end
end

local function onInputEnded(input, gameProcessed)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        isMouseDown = false
    end
end

--============================================================================
-- INITIALIZATION
--============================================================================

function CombatController.Init()
    -- Input handlers
    UserInputService.InputBegan:Connect(onInputBegan)
    UserInputService.InputEnded:Connect(onInputEnded)

    -- Auto-fire when holding mouse button
    RunService.RenderStepped:Connect(function()
        if isMouseDown then
            fireWeapon()
        end
    end)

    -- Start hit report batch sender (runs off main thread)
    task.spawn(sendQueuedHitReports)

    -- Listen for stat updates to adjust cooldown (fallback)
    Remotes.Events.StatUpdate.OnClientEvent:Connect(function(data)
        if data.Stats then
            updateCooldown(data.Stats)
        end
    end)

    -- Setup Dexterity attribute listener on character
    local function onCharacterAdded(character)
        -- Wait a moment for attributes to be set by server
        task.spawn(function()
            task.wait(0.2)
            setupDexterityListener(character)
        end)
    end

    player.CharacterAdded:Connect(onCharacterAdded)
    if player.Character then
        onCharacterAdded(player.Character)
    end

    print("[CombatController] Initialized (Client-Auth Projectiles)")
end

return CombatController
