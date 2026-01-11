--[[
    VaultBuilder.lua
    Creates the physical Vault room area - Simple grid layout

    Features:
    - Open room (no ceiling/walls) for top-down camera view
    - Checkered tile floor pattern
    - Flat glowing chest squares flush with floor
    - Exit portal behind spawn point
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)

local VaultBuilder = {}

-- Visual settings - Flat glowing floor squares
local CHEST_COLOR_UNLOCKED = Color3.fromRGB(200, 160, 50)  -- Golden glow
local CHEST_COLOR_GOLD = Color3.fromRGB(255, 200, 80)      -- Brighter gold for premium
local LOCKED_CHEST_COLOR = Color3.fromRGB(40, 40, 50)      -- Dark, barely visible
local ACCENT_COLOR = Color3.fromRGB(255, 215, 0)           -- Gold accent for decorations

local vaultFolder = nil

--============================================================================
-- HELPER FUNCTIONS
--============================================================================

local function createPart(properties)
    local part = Instance.new("Part")
    part.Anchored = true
    part.CanCollide = properties.CanCollide ~= false
    part.CastShadow = properties.CastShadow ~= false
    part.Color = properties.Color or Color3.fromRGB(100, 100, 100)
    part.Material = properties.Material or Enum.Material.SmoothPlastic
    part.Size = properties.Size or Vector3.new(4, 1, 4)
    part.CFrame = CFrame.new(properties.Position or Vector3.new(0, 0, 0))
    part.Name = properties.Name or "VaultPart"
    part.Parent = properties.Parent or vaultFolder
    return part
end

--============================================================================
-- CHECKERED FLOOR
--============================================================================

function VaultBuilder.CreateCheckeredFloor()
    local center = Constants.Vault.CENTER
    local floorSize = Constants.Vault.FLOOR_SIZE
    local tileSize = Constants.Vault.TILE_SIZE
    local color1 = Constants.Vault.TILE_COLOR_1
    local color2 = Constants.Vault.TILE_COLOR_2

    local floorFolder = Instance.new("Folder")
    floorFolder.Name = "Floor"
    floorFolder.Parent = vaultFolder

    -- Calculate tile grid
    local tilesX = math.floor(floorSize.X / tileSize)
    local tilesZ = math.floor(floorSize.Z / tileSize)
    local startX = center.X - (tilesX * tileSize) / 2 + tileSize / 2
    local startZ = center.Z - (tilesZ * tileSize) / 2 + tileSize / 2

    for x = 0, tilesX - 1 do
        for z = 0, tilesZ - 1 do
            local isEven = (x + z) % 2 == 0
            local tileColor = isEven and color1 or color2

            createPart({
                Name = "Tile_" .. x .. "_" .. z,
                Size = Vector3.new(tileSize, floorSize.Y, tileSize),
                Position = Vector3.new(
                    startX + x * tileSize,
                    center.Y - floorSize.Y / 2,
                    startZ + z * tileSize
                ),
                Color = tileColor,
                Material = Enum.Material.Concrete,
                Parent = floorFolder,
            })
        end
    end

    print("[VaultBuilder] Created checkered floor: " .. tilesX .. "x" .. tilesZ .. " tiles")
end

--============================================================================
-- CHEST CREATION - Flat Glowing Floor Squares
--============================================================================

function VaultBuilder.CreateChest(position, chestIndex, isUnlocked, isGold)
    local chestSize = Constants.Vault.CHEST_SIZE
    local tileHeight = 0.3  -- Flush with floor, slight raise for visibility

    -- Determine chest color
    local baseColor = LOCKED_CHEST_COLOR
    if isUnlocked then
        baseColor = isGold and CHEST_COLOR_GOLD or CHEST_COLOR_UNLOCKED
    end

    -- Flat floor square
    local chest = Instance.new("Part")
    chest.Name = "VaultChest_" .. chestIndex
    chest.Size = Vector3.new(chestSize.X, tileHeight, chestSize.Z)
    chest.Position = position + Vector3.new(0, tileHeight / 2, 0)  -- Flush with floor
    chest.Anchored = true
    chest.CanCollide = false  -- No collision - walk over them
    chest.Color = baseColor
    chest.Material = isUnlocked and Enum.Material.Neon or Enum.Material.SmoothPlastic
    chest.Parent = vaultFolder

    -- Add subtle glow for unlocked chests
    if isUnlocked then
        local light = Instance.new("PointLight")
        light.Name = "Glow"
        light.Brightness = isGold and 1.5 or 0.8
        light.Range = 6
        light.Color = baseColor
        light.Shadows = false
        light.Parent = chest
    end

    -- Small chest number (BillboardGui always faces camera for readability)
    local billboard = Instance.new("BillboardGui")
    billboard.Name = "ChestLabel"
    billboard.Size = UDim2.new(0, 40, 0, 25)
    billboard.StudsOffset = Vector3.new(0, 1.5, 0)  -- Above surface, no clipping
    billboard.AlwaysOnTop = false
    billboard.LightInfluence = 0
    billboard.Parent = chest

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, 0, 1, 0)
    label.BackgroundTransparency = 1
    label.Text = tostring(chestIndex)
    label.TextColor3 = isUnlocked and Color3.fromRGB(255, 230, 150) or Color3.fromRGB(100, 100, 110)
    label.Font = Enum.Font.GothamBold
    label.TextSize = 18
    label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
    label.TextStrokeTransparency = 0.3
    label.Parent = billboard

    -- Store metadata for client interaction
    chest:SetAttribute("ChestIndex", chestIndex)
    chest:SetAttribute("IsUnlocked", isUnlocked)
    chest:SetAttribute("IsGold", isGold or false)
    chest:SetAttribute("ChestType", "Vault")

    return chest
end

--============================================================================
-- GRID CHEST LAYOUT
--============================================================================

function VaultBuilder.CreateChestGrid()
    local center = Constants.Vault.CENTER
    local grid = Constants.Vault.CHEST_GRID

    local startPos = center + grid.startOffset
    local chestIndex = 1

    for row = 0, grid.rows - 1 do
        for col = 0, grid.columns - 1 do
            local pos = startPos + Vector3.new(
                col * grid.spacingX,
                0,
                row * grid.spacingZ
            )

            -- First chest is always unlocked, mark some as gold for variety
            local isUnlocked = (chestIndex == 1)
            local isGold = (row == grid.rows - 1)  -- Bottom row is gold/premium

            VaultBuilder.CreateChest(pos, chestIndex, isUnlocked, isGold)
            chestIndex = chestIndex + 1
        end
    end

    print("[VaultBuilder] Created " .. (chestIndex - 1) .. " vault chests in grid")
end

--============================================================================
-- POTION VAULT & GIFT CHEST
--============================================================================

function VaultBuilder.CreatePotionVault(position)
    local model = Instance.new("Model")
    model.Name = "PotionVault"
    model.Parent = vaultFolder

    -- Flat rack-style storage
    local base = Instance.new("Part")
    base.Name = "Base"
    base.Size = Vector3.new(10, 2, 8)
    base.Position = position + Vector3.new(0, 1, 0)
    base.Anchored = true
    base.CanCollide = true
    base.Color = Color3.fromRGB(100, 60, 120) -- Purple tint
    base.Material = Enum.Material.Wood
    base.Parent = model

    -- Label
    local billboard = Instance.new("BillboardGui")
    billboard.Name = "Label"
    billboard.Size = UDim2.new(0, 100, 0, 30)
    billboard.StudsOffset = Vector3.new(0, 3, 0)
    billboard.AlwaysOnTop = false
    billboard.Parent = base

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, 0, 1, 0)
    label.BackgroundTransparency = 1
    label.Text = "POTIONS"
    label.TextColor3 = Color3.fromRGB(180, 120, 255)
    label.Font = Enum.Font.GothamBold
    label.TextSize = 14
    label.TextStrokeTransparency = 0.3
    label.Parent = billboard

    base:SetAttribute("ChestType", "Potion")
    model.PrimaryPart = base
    return model
end

function VaultBuilder.CreateGiftChest(position)
    local model = Instance.new("Model")
    model.Name = "GiftChest"
    model.Parent = vaultFolder

    -- Gift box style
    local base = Instance.new("Part")
    base.Name = "Base"
    base.Size = Vector3.new(8, 2, 8)
    base.Position = position + Vector3.new(0, 1, 0)
    base.Anchored = true
    base.CanCollide = true
    base.Color = Color3.fromRGB(60, 140, 60) -- Green
    base.Material = Enum.Material.SmoothPlastic
    base.Parent = model

    -- Ribbon cross pattern
    local ribbon1 = Instance.new("Part")
    ribbon1.Name = "Ribbon1"
    ribbon1.Size = Vector3.new(8.2, 0.4, 1.5)
    ribbon1.Position = position + Vector3.new(0, 2.2, 0)
    ribbon1.Anchored = true
    ribbon1.CanCollide = false
    ribbon1.Color = ACCENT_COLOR
    ribbon1.Material = Enum.Material.Fabric
    ribbon1.Parent = model

    local ribbon2 = Instance.new("Part")
    ribbon2.Name = "Ribbon2"
    ribbon2.Size = Vector3.new(1.5, 0.4, 8.2)
    ribbon2.Position = position + Vector3.new(0, 2.2, 0)
    ribbon2.Anchored = true
    ribbon2.CanCollide = false
    ribbon2.Color = ACCENT_COLOR
    ribbon2.Material = Enum.Material.Fabric
    ribbon2.Parent = model

    -- Label
    local billboard = Instance.new("BillboardGui")
    billboard.Name = "Label"
    billboard.Size = UDim2.new(0, 80, 0, 30)
    billboard.StudsOffset = Vector3.new(0, 3, 0)
    billboard.AlwaysOnTop = false
    billboard.Parent = base

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, 0, 1, 0)
    label.BackgroundTransparency = 1
    label.Text = "GIFTS"
    label.TextColor3 = Color3.fromRGB(120, 255, 120)
    label.Font = Enum.Font.GothamBold
    label.TextSize = 14
    label.TextStrokeTransparency = 0.3
    label.Parent = billboard

    base:SetAttribute("ChestType", "Gift")
    model.PrimaryPart = base
    return model
end

--============================================================================
-- AMBIENT LIGHTING
--============================================================================

function VaultBuilder.AddLighting()
    local center = Constants.Vault.CENTER

    -- Corner ambient lights
    local lightPositions = {
        Vector3.new(-50, 5, -40),
        Vector3.new(50, 5, -40),
        Vector3.new(-50, 5, 40),
        Vector3.new(50, 5, 40),
        Vector3.new(0, 5, 0),  -- Center
    }

    for i, offset in ipairs(lightPositions) do
        local lightPart = Instance.new("Part")
        lightPart.Name = "AmbientLight" .. i
        lightPart.Size = Vector3.new(2, 0.5, 2)
        lightPart.Position = center + offset
        lightPart.Anchored = true
        lightPart.CanCollide = false
        lightPart.Transparency = 1
        lightPart.Parent = vaultFolder

        local light = Instance.new("PointLight")
        light.Brightness = 1
        light.Range = 60
        light.Color = Color3.fromRGB(255, 245, 220)
        light.Shadows = false
        light.Parent = lightPart
    end
end

--============================================================================
-- LOW DECORATIVE BORDER
--============================================================================

function VaultBuilder.AddDecorativeBorder()
    local center = Constants.Vault.CENTER
    local floorSize = Constants.Vault.FLOOR_SIZE
    local borderHeight = 1.5
    local borderWidth = 2
    local borderColor = Color3.fromRGB(50, 45, 55)

    local borders = {
        -- North
        {
            Size = Vector3.new(floorSize.X + borderWidth * 2, borderHeight, borderWidth),
            Offset = Vector3.new(0, borderHeight / 2, -floorSize.Z / 2 - borderWidth / 2)
        },
        -- South
        {
            Size = Vector3.new(floorSize.X + borderWidth * 2, borderHeight, borderWidth),
            Offset = Vector3.new(0, borderHeight / 2, floorSize.Z / 2 + borderWidth / 2)
        },
        -- East
        {
            Size = Vector3.new(borderWidth, borderHeight, floorSize.Z),
            Offset = Vector3.new(floorSize.X / 2 + borderWidth / 2, borderHeight / 2, 0)
        },
        -- West
        {
            Size = Vector3.new(borderWidth, borderHeight, floorSize.Z),
            Offset = Vector3.new(-floorSize.X / 2 - borderWidth / 2, borderHeight / 2, 0)
        },
    }

    for i, border in ipairs(borders) do
        createPart({
            Name = "Border" .. i,
            Size = border.Size,
            Position = center + border.Offset,
            Color = borderColor,
            Material = Enum.Material.Concrete,
            CanCollide = true,
        })
    end
end

--============================================================================
-- VAULT ROOM CONSTRUCTION
--============================================================================

function VaultBuilder.BuildVault()
    local center = Constants.Vault.CENTER

    -- Create folder for all vault parts
    vaultFolder = Instance.new("Folder")
    vaultFolder.Name = "VaultRoom"
    vaultFolder.Parent = workspace

    -- Create checkered floor (no ceiling, no walls)
    VaultBuilder.CreateCheckeredFloor()

    -- Add low decorative border
    VaultBuilder.AddDecorativeBorder()

    -- Add ambient lighting
    VaultBuilder.AddLighting()

    -- Create vault chests in grid layout
    VaultBuilder.CreateChestGrid()

    -- Create special storage (on sides)
    local potionPos = center + Constants.Vault.POTION_VAULT_POS
    VaultBuilder.CreatePotionVault(potionPos)

    local giftPos = center + Constants.Vault.GIFT_CHEST_POS
    VaultBuilder.CreateGiftChest(giftPos)

    print("[VaultBuilder] Vault room built at " .. tostring(center))
end

--============================================================================
-- CHEST STATE UPDATE
--============================================================================

function VaultBuilder.UpdateChestUnlockState(chestIndex, isUnlocked)
    if not vaultFolder then return end

    local chest = vaultFolder:FindFirstChild("VaultChest_" .. chestIndex)
    if not chest then return end

    local isGold = chest:GetAttribute("IsGold")
    local baseColor = LOCKED_CHEST_COLOR
    if isUnlocked then
        baseColor = isGold and CHEST_COLOR_GOLD or CHEST_COLOR_UNLOCKED
    end

    chest.Color = baseColor
    chest.Material = isUnlocked and Enum.Material.Neon or Enum.Material.SmoothPlastic
    chest:SetAttribute("IsUnlocked", isUnlocked)

    -- Update or add glow
    local existingGlow = chest:FindFirstChild("Glow")
    if isUnlocked then
        if not existingGlow then
            local light = Instance.new("PointLight")
            light.Name = "Glow"
            light.Brightness = isGold and 1.5 or 0.8
            light.Range = 6
            light.Color = baseColor
            light.Shadows = false
            light.Parent = chest
        else
            existingGlow.Color = baseColor
            existingGlow.Brightness = isGold and 1.5 or 0.8
        end
    elseif existingGlow then
        existingGlow:Destroy()
    end

    -- Update label color (BillboardGui)
    local billboard = chest:FindFirstChild("ChestLabel")
    if billboard then
        local label = billboard:FindFirstChild("TextLabel")
        if label then
            label.TextColor3 = isUnlocked and Color3.fromRGB(255, 230, 150) or Color3.fromRGB(100, 100, 110)
        end
    end
end

--============================================================================
-- INITIALIZATION
--============================================================================

function VaultBuilder.Init()
    VaultBuilder.BuildVault()
    print("[VaultBuilder] Initialized")
end

return VaultBuilder
