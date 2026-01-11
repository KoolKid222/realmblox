--[[
    EnemyVisuals.lua
    Handles enemy visual representation on the client

    Uses velocity-based interpolation for snappy, arcade-like movement
    that matches the server's RotMG-style AI
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local SpatialGrid = require(Shared.SpatialGrid)

local EnemyVisuals = {}

-- Active enemy visuals
EnemyVisuals.Enemies = {}  -- [id] = {model, healthBar, etc}

-- Spatial grid for O(1) nearby enemy queries (used by ProjectileRenderer)
local ClientEnemyGrid = SpatialGrid.new(20)  -- 20 stud cells

-- Container for enemy models
local enemyContainer = nil

-- Interpolation settings
local INTERPOLATION_SPEED = 15      -- How fast to lerp to target (higher = snappier)
local PREDICTION_ENABLED = true     -- Use velocity for prediction

-- Performance optimization
local PROJECTILE_HIT_RADIUS = 0.8   -- Must match ProjectileRenderer
local DISABLE_HEALTH_BARS = true    -- Keep disabled until we identify the bottleneck

-- Create a simple enemy visual (colored part with health bar)
local function createEnemyModel(data)
    local model = Instance.new("Model")
    model.Name = "Enemy_" .. data.Id

    -- Main body
    local body = Instance.new("Part")
    body.Name = "Body"
    body.Size = data.Size or Vector3.new(4, 5, 2)
    body.Color = data.Color or Color3.fromRGB(255, 0, 0)
    body.Material = Enum.Material.SmoothPlastic
    body.Anchored = true
    body.CanCollide = false
    body.CastShadow = true  -- Re-enabled (fixed duplicate projectile rendering)
    body.Position = data.Position
    body.Parent = model

    -- Name label and health bar (can be disabled for performance testing)
    local healthBar = nil
    if not DISABLE_HEALTH_BARS then
        local billboardGui = Instance.new("BillboardGui")
        billboardGui.Name = "NameLabel"
        billboardGui.Size = UDim2.new(0, 100, 0, 40)
        billboardGui.StudsOffset = Vector3.new(0, body.Size.Y / 2 + 2, 0)
        billboardGui.Adornee = body
        billboardGui.Parent = body

        local nameLabel = Instance.new("TextLabel")
        nameLabel.Name = "Name"
        nameLabel.Size = UDim2.new(1, 0, 0.5, 0)
        nameLabel.BackgroundTransparency = 1
        nameLabel.Text = data.Name or "Enemy"
        nameLabel.TextColor3 = Color3.new(1, 1, 1)
        nameLabel.TextStrokeTransparency = 0
        nameLabel.TextScaled = true
        nameLabel.Font = Enum.Font.GothamBold
        nameLabel.Parent = billboardGui

        -- Health bar background
        local healthBarBg = Instance.new("Frame")
        healthBarBg.Name = "HealthBarBg"
        healthBarBg.Size = UDim2.new(0.8, 0, 0.3, 0)
        healthBarBg.Position = UDim2.new(0.1, 0, 0.6, 0)
        healthBarBg.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
        healthBarBg.BorderSizePixel = 0
        healthBarBg.Parent = billboardGui

        healthBar = Instance.new("Frame")
        healthBar.Name = "HealthBar"
        healthBar.Size = UDim2.new(1, 0, 1, 0)
        healthBar.BackgroundColor3 = Color3.fromRGB(0, 255, 0)
        healthBar.BorderSizePixel = 0
        healthBar.Parent = healthBarBg
    end

    model.PrimaryPart = body
    model.Parent = enemyContainer

    -- Pre-calculate hit radius for collision detection (avoids Body.Size access every frame)
    local bodySize = data.Size or Vector3.new(4, 5, 2)
    local enemyRadius = math.max(bodySize.X, bodySize.Z) / 2
    local hitRadius = enemyRadius + PROJECTILE_HIT_RADIUS
    local hitRadiusSq = hitRadius * hitRadius

    return {
        Model = model,
        Body = body,
        HealthBar = healthBar,
        TargetPosition = data.Position,
        CurrentPosition = data.Position,
        Velocity = Vector3.zero,
        LastUpdateTime = tick(),
        CurrentHP = data.CurrentHP or data.MaxHP,
        MaxHP = data.MaxHP,
        -- Cached for hit detection (ProjectileRenderer uses these)
        HitRadius = hitRadius,
        HitRadiusSq = hitRadiusSq,
    }
end

-- Update enemy health bar
local function updateHealthBar(enemyVisual)
    if not enemyVisual.HealthBar then return end  -- Skip if health bars disabled

    local healthPercent = enemyVisual.CurrentHP / enemyVisual.MaxHP
    enemyVisual.HealthBar.Size = UDim2.new(healthPercent, 0, 1, 0)

    -- Color based on health
    if healthPercent > 0.5 then
        enemyVisual.HealthBar.BackgroundColor3 = Color3.fromRGB(0, 255, 0)
    elseif healthPercent > 0.25 then
        enemyVisual.HealthBar.BackgroundColor3 = Color3.fromRGB(255, 255, 0)
    else
        enemyVisual.HealthBar.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
    end
end

-- Velocity-based interpolation with prediction
local function updateEnemyPositions(deltaTime)
    local currentTime = tick()
    local toCleanup = nil

    for id, visual in pairs(EnemyVisuals.Enemies) do
        -- Safety check
        if not visual.Model or not visual.Model.Parent or not visual.Body or not visual.Body.Parent then
            toCleanup = toCleanup or {}
            toCleanup[#toCleanup + 1] = id
        elseif visual.TargetPosition then
            local currentPos = visual.CurrentPosition
            local targetPos = visual.TargetPosition

            -- Use velocity prediction for smoother movement
            if PREDICTION_ENABLED and visual.Velocity and visual.Velocity.Magnitude > 0.1 then
                local timeSinceUpdate = currentTime - visual.LastUpdateTime
                local predictedOffset = visual.Velocity * math.min(timeSinceUpdate, 0.15)
                targetPos = targetPos + predictedOffset
            end

            -- Snappy interpolation
            local alpha = math.min(1, deltaTime * INTERPOLATION_SPEED)
            local newPos = currentPos:Lerp(targetPos, alpha)

            -- Update position
            visual.CurrentPosition = newPos
            visual.Body.Position = newPos

            -- Update spatial grid (for projectile hit detection queries)
            ClientEnemyGrid:Update(id, newPos)
        end
    end

    -- Cleanup any orphaned entries
    if toCleanup then
        for i = 1, #toCleanup do
            local cleanupId = toCleanup[i]
            ClientEnemyGrid:Remove(cleanupId)
            EnemyVisuals.Enemies[cleanupId] = nil
        end
    end
end

-- Query for nearby enemies (used by ProjectileRenderer for hit detection)
function EnemyVisuals.GetNearbyEnemies(position, radius)
    return ClientEnemyGrid:GetNearby(position, radius)
end

-- Handle enemy spawn
local function onEnemySpawn(data)
    -- Remove old visual if exists
    if EnemyVisuals.Enemies[data.Id] then
        EnemyVisuals.Enemies[data.Id].Model:Destroy()
        ClientEnemyGrid:Remove(data.Id)
    end

    -- Create new visual
    EnemyVisuals.Enemies[data.Id] = createEnemyModel(data)

    -- Add to spatial grid
    ClientEnemyGrid:Insert(data.Id, data.Position)
end

-- Handle enemy update (position, health)
local function onEnemyUpdate(data)
    -- Batch position update (from server broadcastEnemyPositions)
    if data.Positions then
        local currentTime = tick()
        for id, posData in pairs(data.Positions) do
            local visual = EnemyVisuals.Enemies[id]
            if visual then
                visual.TargetPosition = posData.Position
                visual.Velocity = posData.Velocity or Vector3.zero
                visual.LastUpdateTime = currentTime
            end
        end
        return
    end

    -- Individual enemy update (health, etc.)
    local visual = EnemyVisuals.Enemies[data.Id]
    if not visual then return end

    if data.CurrentHP then
        visual.CurrentHP = data.CurrentHP
        visual.MaxHP = data.MaxHP or visual.MaxHP
        updateHealthBar(visual)
    end

    if data.Position then
        visual.TargetPosition = data.Position
        visual.LastUpdateTime = tick()
    end

    if data.Velocity then
        visual.Velocity = data.Velocity
    end
end

-- Handle enemy death
local function onEnemyDeath(data)
    local visual = EnemyVisuals.Enemies[data.Id]
    if not visual then return end

    -- Remove from spatial grid immediately
    ClientEnemyGrid:Remove(data.Id)

    -- Death animation (quick fade out)
    if not data.Despawn then
        local body = visual.Body

        -- Flash red
        body.Color = Color3.fromRGB(255, 100, 100)

        -- Scale down and fade
        local tween = TweenService:Create(body, TweenInfo.new(0.3), {
            Size = Vector3.new(0.1, 0.1, 0.1),
            Transparency = 1,
        })
        tween:Play()

        tween.Completed:Connect(function()
            if visual.Model then
                visual.Model:Destroy()
            end
        end)
    else
        -- Just remove (despawn)
        visual.Model:Destroy()
    end

    EnemyVisuals.Enemies[data.Id] = nil
end

-- Initialize
function EnemyVisuals.Init()
    -- Create container
    enemyContainer = workspace:FindFirstChild("Enemies")
    if not enemyContainer then
        enemyContainer = Instance.new("Folder")
        enemyContainer.Name = "Enemies"
        enemyContainer.Parent = workspace
    end

    -- Connect to remote events
    Remotes.Events.EnemySpawn.OnClientEvent:Connect(onEnemySpawn)
    Remotes.Events.EnemyUpdate.OnClientEvent:Connect(onEnemyUpdate)
    Remotes.Events.EnemyDeath.OnClientEvent:Connect(onEnemyDeath)

    -- Position interpolation (RenderStepped for smooth visuals)
    RunService.RenderStepped:Connect(updateEnemyPositions)

    print("[EnemyVisuals] Initialized (velocity interpolation)")
end

return EnemyVisuals
