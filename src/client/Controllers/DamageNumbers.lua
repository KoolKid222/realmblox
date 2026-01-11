--[[
    DamageNumbers.lua
    Clean RotMG-style damage numbers with batching optimization

    Style: Simple, readable, not arcadey
    - Straight upward drift
    - Small horizontal jitter (no stacking)
    - No rotation or scale animation
    - Smooth fade out

    Optimization: Batches rapid hits to same enemy into single numbers
    - Reduces billboard count at high fire rates
    - Accumulates damage over short window before displaying
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)

local player = Players.LocalPlayer

local DamageNumbers = {}

local EnemyVisuals = nil

--============================================================================
-- ROTMG-STYLE CONFIGURATION
--============================================================================

local POOL_SIZE = 50  -- Reduced since we batch now

-- Batching settings (reduces billboard spam at high fire rates)
local BATCH_WINDOW = 0.15  -- Accumulate damage for 150ms before showing
local MIN_DISPLAY_INTERVAL = 0.1  -- Min time between numbers for same enemy

-- Colors (RotMG style - darker, more muted)
local COLOR_DAMAGE = Color3.fromRGB(180, 50, 50)          -- Dark red
local COLOR_ARMOR_PIERCE = Color3.fromRGB(130, 50, 180)   -- Dark purple
local COLOR_HEAL = Color3.fromRGB(50, 180, 50)            -- Green
local COLOR_MANA = Color3.fromRGB(80, 130, 200)           -- Blue
local COLOR_PLAYER_DAMAGE = Color3.fromRGB(200, 30, 30)   -- Brighter red for player
local COLOR_XP = Color3.fromRGB(50, 180, 50)              -- Green
local COLOR_FAME = Color3.fromRGB(200, 150, 50)           -- Gold
local COLOR_STROKE = Color3.fromRGB(0, 0, 0)              -- Black outline

-- Animation (RotMG: simple linear drift)
local LIFETIME = 1.0                  -- 1 second lifetime
local DRIFT_SPEED = 2.5               -- Studs per second upward
local JITTER_RANGE = 1.5              -- Random X offset range

-- Font
local FONT_SIZE = 26
local FONT = Enum.Font.GothamBold

-- Positioning
local ENEMY_Y_OFFSET = 3

--============================================================================
-- BILLBOARD POOL
--============================================================================

local billboardPool = {}
local container = nil

local function createBillboard()
    local billboard = Instance.new("BillboardGui")
    billboard.Name = "DamageNumber"
    billboard.Size = UDim2.new(0, 120, 0, 50)
    billboard.StudsOffset = Vector3.new(0, 0, 0)
    billboard.AlwaysOnTop = true
    billboard.LightInfluence = 0
    billboard.MaxDistance = 100
    billboard.Enabled = false
    billboard.Parent = container

    local textLabel = Instance.new("TextLabel")
    textLabel.Name = "Text"
    textLabel.Size = UDim2.new(1, 0, 1, 0)
    textLabel.Position = UDim2.new(0, 0, 0, 0)
    textLabel.BackgroundTransparency = 1
    textLabel.Font = FONT
    textLabel.TextSize = FONT_SIZE
    textLabel.TextColor3 = COLOR_DAMAGE
    textLabel.TextStrokeColor3 = COLOR_STROKE
    textLabel.TextStrokeTransparency = 0
    textLabel.Text = ""
    textLabel.TextScaled = false
    textLabel.Parent = billboard

    return {
        Billboard = billboard,
        TextLabel = textLabel,
        InUse = false,
    }
end

local function initializePool()
    container = Instance.new("Folder")
    container.Name = "DamageNumbers"
    container.Parent = player.PlayerGui

    for i = 1, POOL_SIZE do
        table.insert(billboardPool, createBillboard())
    end
end

local activeDamageNumbers = {}

-- Damage batching queues (accumulate rapid hits before displaying)
local pendingDamage = {}  -- [enemyId] = {damage, position, startTime, isHeal, isArmorPierce}
local lastDisplayTime = {}  -- [enemyId] = timestamp of last displayed number

local function getBillboard()
    if not container or not container.Parent then
        billboardPool = {}
        activeDamageNumbers = {}
        initializePool()
    end

    for _, pooled in ipairs(billboardPool) do
        if not pooled.InUse then
            pooled.InUse = true
            pooled.Billboard.Enabled = true
            return pooled
        end
    end

    local newBillboard = createBillboard()
    newBillboard.InUse = true
    newBillboard.Billboard.Enabled = true
    table.insert(billboardPool, newBillboard)
    return newBillboard
end

local function returnBillboard(pooled)
    pooled.InUse = false
    pooled.Billboard.Enabled = false
    pooled.Billboard.Adornee = nil
    pooled.TextLabel.Rotation = 0
end

--============================================================================
-- DAMAGE NUMBER DISPLAY (Internal - called after batching)
--============================================================================

local function displayDamageNumber(worldPosition, damage, isPlayer, enemyId, isHeal, isArmorPierce)
    local pooled = getBillboard()
    local billboard = pooled.Billboard
    local textLabel = pooled.TextLabel

    -- Determine color
    local color = COLOR_DAMAGE
    if isHeal then
        color = COLOR_HEAL
    elseif isArmorPierce then
        color = COLOR_ARMOR_PIERCE
    elseif isPlayer then
        color = COLOR_PLAYER_DAMAGE
    end

    -- Set text
    if isHeal then
        textLabel.Text = "+" .. tostring(math.floor(damage))
    else
        textLabel.Text = "-" .. tostring(math.floor(damage))
    end
    textLabel.TextColor3 = color
    textLabel.TextTransparency = 0
    textLabel.TextStrokeTransparency = 0
    textLabel.TextSize = FONT_SIZE
    textLabel.Rotation = 0

    -- Random X jitter (small, just to prevent stacking)
    local jitterX = (math.random() - 0.5) * JITTER_RANGE

    -- Try to attach to enemy body
    local enemyBody = nil
    if enemyId and EnemyVisuals and EnemyVisuals.Enemies[enemyId] then
        local enemyVisual = EnemyVisuals.Enemies[enemyId]
        if enemyVisual and enemyVisual.Body then
            enemyBody = enemyVisual.Body
        end
    end

    if enemyBody then
        billboard.Adornee = enemyBody
        billboard.StudsOffset = Vector3.new(jitterX, ENEMY_Y_OFFSET, 0)

        table.insert(activeDamageNumbers, {
            Pooled = pooled,
            EnemyId = enemyId,
            EnemyBody = enemyBody,
            Anchor = nil,
            StartTime = tick(),
            JitterX = jitterX,
            BaseY = ENEMY_Y_OFFSET,
        })
    else
        -- Fallback: create anchor part
        local anchor = Instance.new("Part")
        anchor.Name = "DamageAnchor"
        anchor.Size = Vector3.new(0.1, 0.1, 0.1)
        anchor.Transparency = 1
        anchor.Anchored = true
        anchor.CanCollide = false
        anchor.CastShadow = false
        anchor.Position = worldPosition
        anchor.Parent = workspace

        billboard.Adornee = anchor
        billboard.StudsOffset = Vector3.new(jitterX, 0, 0)

        table.insert(activeDamageNumbers, {
            Pooled = pooled,
            EnemyId = nil,
            EnemyBody = nil,
            Anchor = anchor,
            StartTime = tick(),
            JitterX = jitterX,
            BaseY = 0,
        })
    end

    -- Track last display time for this enemy
    if enemyId then
        lastDisplayTime[enemyId] = tick()
    end
end

--============================================================================
-- DAMAGE BATCHING (Queue rapid hits, display combined)
--============================================================================

local function queueDamage(worldPosition, damage, isPlayer, enemyId, isHeal, isArmorPierce)
    local currentTime = tick()

    -- Player damage (to self) - show immediately, no batching
    if isPlayer then
        displayDamageNumber(worldPosition, damage, true, nil, isHeal, false)
        return
    end

    -- No enemy ID - show immediately (fallback case)
    if not enemyId then
        displayDamageNumber(worldPosition, damage, false, nil, isHeal, isArmorPierce)
        return
    end

    -- Check if we have pending damage for this enemy
    local pending = pendingDamage[enemyId]
    if pending then
        -- Add to existing batch
        pending.damage = pending.damage + damage
        pending.position = worldPosition  -- Update position
        -- Keep original flags (first hit determines type)
    else
        -- Start new batch
        pendingDamage[enemyId] = {
            damage = damage,
            position = worldPosition,
            startTime = currentTime,
            isHeal = isHeal,
            isArmorPierce = isArmorPierce,
        }
    end
end

local function flushPendingDamage()
    local currentTime = tick()
    local toRemove = {}

    for enemyId, pending in pairs(pendingDamage) do
        local elapsed = currentTime - pending.startTime
        local lastDisplay = lastDisplayTime[enemyId] or 0
        local timeSinceDisplay = currentTime - lastDisplay

        -- Display if batch window elapsed OR enough time since last display
        if elapsed >= BATCH_WINDOW or timeSinceDisplay >= MIN_DISPLAY_INTERVAL then
            displayDamageNumber(
                pending.position,
                pending.damage,
                false,
                enemyId,
                pending.isHeal,
                pending.isArmorPierce
            )
            table.insert(toRemove, enemyId)
        end
    end

    -- Clear flushed entries
    for _, enemyId in ipairs(toRemove) do
        pendingDamage[enemyId] = nil
    end
end

-- Alias for external calls
local function showDamageNumber(worldPosition, damage, isPlayer, isCrit, enemyId, isHeal, isArmorPierce)
    queueDamage(worldPosition, damage, isPlayer, enemyId, isHeal, isArmorPierce)
end

--============================================================================
-- STATUS TEXT (XP, HP/MP Potions)
--============================================================================

local function showStatusText(targetPlayer, amount, textType)
    local character = targetPlayer.Character
    if not character then return end

    local rootPart = character:FindFirstChild("HumanoidRootPart")
    if not rootPart then return end

    local pooled = getBillboard()
    local billboard = pooled.Billboard
    local textLabel = pooled.TextLabel

    local color = COLOR_XP
    local text = "+" .. tostring(math.floor(amount))

    if textType == "XP" then
        color = COLOR_XP
        text = "+" .. tostring(math.floor(amount)) .. " XP"
    elseif textType == "HP" then
        color = COLOR_HEAL
        text = "+" .. tostring(math.floor(amount)) .. " HP"
    elseif textType == "MP" then
        color = COLOR_MANA
        text = "+" .. tostring(math.floor(amount)) .. " MP"
    elseif textType == "Fame" then
        color = COLOR_FAME
        text = "+" .. tostring(math.floor(amount)) .. " Fame"
    end

    textLabel.Text = text
    textLabel.TextColor3 = color
    textLabel.TextTransparency = 0
    textLabel.TextStrokeTransparency = 0
    textLabel.TextSize = FONT_SIZE
    textLabel.Rotation = 0

    local jitterX = (math.random() - 0.5) * JITTER_RANGE

    billboard.Adornee = rootPart
    billboard.StudsOffset = Vector3.new(jitterX, 3, 0)

    table.insert(activeDamageNumbers, {
        Pooled = pooled,
        EnemyId = nil,
        EnemyBody = nil,
        Anchor = nil,
        StartTime = tick(),
        JitterX = jitterX,
        BaseY = 3,
    })
end

--============================================================================
-- UPDATE LOOP (Simple linear drift + fade + batch flush)
--============================================================================

local function updateDamageNumbers()
    -- Flush any pending batched damage numbers
    flushPendingDamage()

    local currentTime = tick()
    local toRemove = {}

    for i, dn in ipairs(activeDamageNumbers) do
        local elapsed = currentTime - dn.StartTime
        local progress = elapsed / LIFETIME

        local billboard = dn.Pooled and dn.Pooled.Billboard
        local textLabel = dn.Pooled and dn.Pooled.TextLabel

        if not billboard or not textLabel then
            table.insert(toRemove, i)
        elseif progress >= 1 then
            table.insert(toRemove, i)
        else
            -- Simple linear upward drift
            local driftY = elapsed * DRIFT_SPEED
            billboard.StudsOffset = Vector3.new(dn.JitterX, dn.BaseY + driftY, 0)

            -- Fade out in last 30% of lifetime
            if progress > 0.7 then
                local fadeProgress = (progress - 0.7) / 0.3
                textLabel.TextTransparency = fadeProgress
                textLabel.TextStrokeTransparency = fadeProgress
            end

            -- Keep attached to enemy if it exists
            if dn.EnemyId and EnemyVisuals then
                local enemyVisual = EnemyVisuals.Enemies[dn.EnemyId]
                if enemyVisual and enemyVisual.Body then
                    billboard.Adornee = enemyVisual.Body
                end
            end
        end
    end

    -- Remove completed (reverse order, swap-and-pop)
    for i = #toRemove, 1, -1 do
        local index = toRemove[i]
        local dn = activeDamageNumbers[index]

        if dn.Anchor then
            dn.Anchor:Destroy()
        end

        if dn.Pooled then
            returnBillboard(dn.Pooled)
        end

        local lastIdx = #activeDamageNumbers
        if index ~= lastIdx then
            activeDamageNumbers[index] = activeDamageNumbers[lastIdx]
        end
        activeDamageNumbers[lastIdx] = nil
    end
end

--============================================================================
-- INITIALIZATION
--============================================================================

function DamageNumbers.Init()
    initializePool()

    local Controllers = script.Parent
    EnemyVisuals = require(Controllers:WaitForChild("EnemyVisuals"))

    Remotes.Events.DamageNumber.OnClientEvent:Connect(function(data)
        if data.StatusType then
            showStatusText(player, data.Amount, data.StatusType)
            return
        end

        if data.Position and data.Damage then
            showDamageNumber(
                data.Position,
                data.Damage,
                data.IsPlayer or false,
                data.IsCrit or false,
                data.EnemyId,
                data.IsHeal or false,
                data.IsArmorPierce or false
            )
        end
    end)

    RunService.RenderStepped:Connect(updateDamageNumbers)

    print("[DamageNumbers] Initialized (RotMG style)")
end

function DamageNumbers.ShowDamage(position, damage, isPlayer, isCrit, enemyId, isHeal, isArmorPierce)
    showDamageNumber(position, damage, isPlayer, isCrit, enemyId, isHeal, isArmorPierce)
end

return DamageNumbers
