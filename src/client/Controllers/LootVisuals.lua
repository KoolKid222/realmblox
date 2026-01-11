--[[
    LootVisuals.lua
    Handles visual representation of loot bags on the client

    RotMG Bag Types (6-bag system):
    - Brown (1): HP/MP potions only (PUBLIC)
    - Pink (2): Low tier gear T0-6 weapons/armor, T0-1 rings, T0-2 abilities (PUBLIC)
    - Purple (3): Mid tier gear T7-9 weapons/armor, T2-4 rings, T3-4 abilities (SOULBOUND)
    - Cyan (4): High tier gear T10+ weapons/armor, T5+ rings/abilities (SOULBOUND)
    - Blue (5): Stat potions (SOULBOUND)
    - White (6): Ultra-rare UT drops (SOULBOUND)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local ItemDatabase = require(Shared.ItemDatabase)

local LootVisuals = {}

--============================================================================
-- CONSTANTS
--============================================================================

-- Loot bag colors (RotMG 6-bag system)
local BAG_COLORS = {
    [1] = Color3.fromRGB(139, 90, 43),   -- Brown (HP/MP potions) - PUBLIC
    [2] = Color3.fromRGB(255, 150, 200), -- Pink (low tier gear) - PUBLIC
    [3] = Color3.fromRGB(148, 0, 211),   -- Purple (mid tier gear) - SOULBOUND
    [4] = Color3.fromRGB(0, 255, 255),   -- Cyan (high tier gear) - SOULBOUND
    [5] = Color3.fromRGB(0, 100, 255),   -- Blue (stat potions) - SOULBOUND
    [6] = Color3.fromRGB(255, 255, 255), -- White (ultra-rare UT) - SOULBOUND
}

local BAG_SIZE = Vector3.new(2, 1.5, 2)
local BAG_LIFETIME_VISUAL = 60 -- Seconds before starting to fade

--============================================================================
-- STATE
--============================================================================

local activeBags = {} -- [bagId] = {Part, Items, SpawnTime, BagType, Soulbound}
local lootContainer = nil

--============================================================================
-- BAG VISUALS
--============================================================================

-- Create a visual loot bag (bagType comes from server)
local function createBag(bagId, position, items, bagType)
    bagType = bagType or 1  -- Default to brown if not specified
    local color = BAG_COLORS[bagType] or BAG_COLORS[1]

    -- Main bag part
    local bag = Instance.new("Part")
    bag.Name = "LootBag_" .. bagId
    bag.Size = BAG_SIZE
    bag.Position = position + Vector3.new(0, BAG_SIZE.Y / 2, 0)
    bag.Color = color
    bag.Material = Enum.Material.SmoothPlastic
    bag.Anchored = true
    bag.CanCollide = false
    bag.CastShadow = true
    bag.Shape = Enum.PartType.Cylinder
    bag.Orientation = Vector3.new(0, 0, 90) -- Lay flat

    -- Store bag ID for reference
    bag:SetAttribute("BagId", bagId)

    -- Tag for proximity detection
    CollectionService:AddTag(bag, "LootBag")

    -- Visual effects
    local highlight = Instance.new("Highlight")
    highlight.FillColor = color
    highlight.FillTransparency = 0.7
    highlight.OutlineColor = color
    highlight.OutlineTransparency = 0.3
    highlight.Parent = bag

    -- Bobbing animation
    local startY = bag.Position.Y
    local bobTween = TweenService:Create(bag, TweenInfo.new(1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
        Position = bag.Position + Vector3.new(0, 0.3, 0)
    })
    bobTween:Play()

    -- Particle effect for higher tier bags
    if bagType >= 3 then
        local attachment = Instance.new("Attachment")
        attachment.Parent = bag

        local sparkles = Instance.new("ParticleEmitter")
        sparkles.Color = ColorSequence.new(color)
        sparkles.Size = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0.2),
            NumberSequenceKeypoint.new(1, 0)
        })
        sparkles.Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0.5),
            NumberSequenceKeypoint.new(1, 1)
        })
        sparkles.Lifetime = NumberRange.new(0.5, 1)
        sparkles.Rate = 5
        sparkles.Speed = NumberRange.new(1, 2)
        sparkles.SpreadAngle = Vector2.new(180, 180)
        sparkles.Parent = attachment
    end

    bag.Parent = lootContainer

    return bag
end

-- Update bag display (when items change)
local function updateBag(bagId, remainingItems)
    local bagData = activeBags[bagId]
    if not bagData then return end

    if not remainingItems or #remainingItems == 0 then
        -- Remove bag
        if bagData.Part then
            bagData.Part:Destroy()
        end
        activeBags[bagId] = nil
        return
    end

    -- Update items
    bagData.Items = remainingItems

    -- Could update visual here if needed (e.g., change color based on remaining items)
end

-- Remove a bag
local function removeBag(bagId)
    local bagData = activeBags[bagId]
    if not bagData then return end

    -- Fade out animation
    if bagData.Part then
        local fadeOut = TweenService:Create(bagData.Part, TweenInfo.new(0.3), {
            Transparency = 1,
            Size = Vector3.new(0.1, 0.1, 0.1)
        })
        fadeOut:Play()
        fadeOut.Completed:Connect(function()
            if bagData.Part then
                bagData.Part:Destroy()
            end
        end)
    end

    activeBags[bagId] = nil
end

--============================================================================
-- EVENT HANDLERS
--============================================================================

local function onLootDrop(data)
    -- print("[LootVisuals] LootDrop received - Id:", data.Id, "Position:", data.Position, "BagType:", data.BagType)

    -- Create visual bag using server-provided bag type
    local part = createBag(data.Id, data.Position, data.Items, data.BagType)

    activeBags[data.Id] = {
        Part = part,
        Items = data.Items,
        SpawnTime = tick(),
        BagType = data.BagType,
        Soulbound = data.Soulbound,
    }

    -- print("[LootVisuals] Bag created and tagged, total active bags:", #CollectionService:GetTagged("LootBag"))
end

local function onLootPickup(data)
    if data.Removed then
        removeBag(data.BagId)
    elseif data.RemainingItems then
        updateBag(data.BagId, data.RemainingItems)
    end
end

--============================================================================
-- PROXIMITY CHECK & INPUT
--============================================================================

local PICKUP_RANGE = 5
local nearestBag = nil
local lastNearestBag = nil  -- Track when we enter proximity of a new bag

local function checkNearestBag()
    local character = player.Character
    if not character then
        nearestBag = nil
        return
    end

    local rootPart = character:FindFirstChild("HumanoidRootPart")
    if not rootPart then
        nearestBag = nil
        return
    end

    local playerPos = rootPart.Position
    local closest = nil
    local closestDist = PICKUP_RANGE

    for bagId, bagData in pairs(activeBags) do
        if bagData.Part then
            local dist = (bagData.Part.Position - playerPos).Magnitude
            if dist < closestDist then
                closestDist = dist
                closest = bagId
            end
        end
    end

    -- If we entered proximity of a new bag, request its contents
    if closest and closest ~= lastNearestBag then
        local bagData = activeBags[closest]
        -- Only request if we don't have item data (late arrival scenario)
        if bagData and (not bagData.Items or #bagData.Items == 0) then
            Remotes.Events.GetBagContents:FireServer(closest)
        end
    end

    lastNearestBag = closest
    nearestBag = closest
end

-- Handle bag contents response from server
local function onLootBagContents(data)
    local bagData = activeBags[data.BagId]
    if bagData then
        bagData.Items = data.Items
        bagData.BagType = data.BagType
        bagData.Soulbound = data.Soulbound
    end
end

-- Pickup input handler
local function setupPickupInput()
    local UserInputService = game:GetService("UserInputService")

    UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if gameProcessed then return end

        -- E key to pickup
        if input.KeyCode == Enum.KeyCode.E then
            if nearestBag then
                Remotes.Events.RequestLoot:FireServer(nearestBag)
            end
        end
    end)
end

--============================================================================
-- INITIALIZATION
--============================================================================

function LootVisuals.Init()
    -- Create container
    lootContainer = workspace:FindFirstChild("LootBags")
    if not lootContainer then
        lootContainer = Instance.new("Folder")
        lootContainer.Name = "LootBags"
        lootContainer.Parent = workspace
    end

    -- Connect events
    Remotes.Events.LootDrop.OnClientEvent:Connect(onLootDrop)
    Remotes.Events.LootPickup.OnClientEvent:Connect(onLootPickup)
    Remotes.Events.LootBagContents.OnClientEvent:Connect(onLootBagContents)

    -- Proximity check loop
    RunService.Heartbeat:Connect(checkNearestBag)

    -- Setup input
    setupPickupInput()

    -- print("[LootVisuals] Initialized")
end

-- Get data for the nearest loot bag (for HUD display)
function LootVisuals.GetNearestBag()
    if nearestBag then
        return activeBags[nearestBag]
    end
    return nil
end

-- Get all active bags
function LootVisuals.GetActiveBags()
    return activeBags
end

return LootVisuals
