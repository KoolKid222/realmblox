--[[
    VaultUI.lua
    Vault chest UI - Integrates with right-side HUD

    Features:
    - Matches HUD styling (Font.Code, dark panels)
    - Position below inventory on right side
    - 8 slots in 2x4 grid layout
    - Auto-show when stepping on chest
    - Auto-hide when stepping off chest
    - No close button (auto-closes)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local ItemDatabase = require(Shared.ItemDatabase)

local VaultUI = {}

--============================================================================
-- STYLE CONSTANTS (Match HUDController exactly)
--============================================================================

local COLORS = {
    PANEL_BG = Color3.fromRGB(20, 20, 25),
    PANEL_BORDER = Color3.fromRGB(60, 60, 70),
    SLOT_BG = Color3.fromRGB(40, 40, 45),
    SLOT_BORDER = Color3.fromRGB(80, 80, 90),
    SLOT_EMPTY = Color3.fromRGB(30, 30, 35),
    SLOT_FILLED = Color3.fromRGB(50, 45, 40),
    TEXT = Color3.fromRGB(255, 255, 255),
    TEXT_GRAY = Color3.fromRGB(180, 180, 180),
    TEXT_GOLD = Color3.fromRGB(255, 215, 0),
    HEADER_BG = Color3.fromRGB(35, 35, 45),
}

local FONT = Enum.Font.Code
local SLOT_SIZE = 40
local SLOT_GAP = 6
local PANEL_WIDTH = 200
local PANEL_PADDING = 8

--============================================================================
-- STATE
--============================================================================

local screenGui = nil
local mainFrame = nil
local slotsFrame = nil
local headerLabel = nil
local chestSlots = {}
local currentChestIndex = nil
local currentContents = nil

--============================================================================
-- UI CREATION
--============================================================================

local function createSlot(parent, index)
    local slot = Instance.new("Frame")
    slot.Name = "Slot" .. index
    slot.Size = UDim2.new(0, SLOT_SIZE, 0, SLOT_SIZE)
    slot.BackgroundColor3 = COLORS.SLOT_EMPTY
    slot.BorderSizePixel = 0
    slot.Parent = parent

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 4)
    corner.Parent = slot

    local stroke = Instance.new("UIStroke")
    stroke.Color = COLORS.SLOT_BORDER
    stroke.Thickness = 1
    stroke.Parent = slot

    -- Item icon (hidden by default)
    local icon = Instance.new("ImageLabel")
    icon.Name = "Icon"
    icon.Size = UDim2.new(0.85, 0, 0.85, 0)
    icon.Position = UDim2.new(0.075, 0, 0.075, 0)
    icon.BackgroundTransparency = 1
    icon.Visible = false
    icon.ScaleType = Enum.ScaleType.Fit
    icon.Parent = slot

    -- Slot index indicator (small, bottom right)
    local indexLabel = Instance.new("TextLabel")
    indexLabel.Name = "Index"
    indexLabel.Size = UDim2.new(0, 12, 0, 10)
    indexLabel.Position = UDim2.new(1, -14, 1, -12)
    indexLabel.BackgroundTransparency = 1
    indexLabel.Text = tostring(index)
    indexLabel.TextColor3 = Color3.fromRGB(100, 100, 110)
    indexLabel.Font = FONT
    indexLabel.TextSize = 8
    indexLabel.Parent = slot

    -- Store slot index for interaction
    slot:SetAttribute("SlotIndex", index)

    -- Click handler
    local button = Instance.new("TextButton")
    button.Name = "Button"
    button.Size = UDim2.new(1, 0, 1, 0)
    button.BackgroundTransparency = 1
    button.Text = ""
    button.Parent = slot

    button.MouseButton1Click:Connect(function()
        VaultUI.OnSlotClicked(index)
    end)

    return slot
end

local function createUI()
    local playerGui = player:WaitForChild("PlayerGui")

    -- Main screen GUI
    screenGui = Instance.new("ScreenGui")
    screenGui.Name = "VaultUI"
    screenGui.ResetOnSpawn = false
    screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screenGui.Enabled = false
    screenGui.Parent = playerGui

    -- Calculate position below HUD inventory (right side of screen)
    -- HUD panel is at right edge, so we position our panel there too
    local panelHeight = SLOT_SIZE * 2 + SLOT_GAP + 30 + PANEL_PADDING * 2

    -- Main container frame (positioned on right side)
    mainFrame = Instance.new("Frame")
    mainFrame.Name = "MainFrame"
    mainFrame.Size = UDim2.new(0, PANEL_WIDTH, 0, panelHeight)
    -- Position: right side, below the HUD (approx at 60% down from top)
    mainFrame.Position = UDim2.new(1, -PANEL_WIDTH - 10, 0.6, 0)
    mainFrame.BackgroundColor3 = COLORS.PANEL_BG
    mainFrame.BackgroundTransparency = 0.1
    mainFrame.BorderSizePixel = 0
    mainFrame.Parent = screenGui

    local mainCorner = Instance.new("UICorner")
    mainCorner.CornerRadius = UDim.new(0, 6)
    mainCorner.Parent = mainFrame

    local mainStroke = Instance.new("UIStroke")
    mainStroke.Color = COLORS.PANEL_BORDER
    mainStroke.Thickness = 1
    mainStroke.Parent = mainFrame

    -- Header with chest number
    local headerFrame = Instance.new("Frame")
    headerFrame.Name = "Header"
    headerFrame.Size = UDim2.new(1, 0, 0, 24)
    headerFrame.Position = UDim2.new(0, 0, 0, 0)
    headerFrame.BackgroundColor3 = COLORS.HEADER_BG
    headerFrame.BorderSizePixel = 0
    headerFrame.Parent = mainFrame

    local headerCorner = Instance.new("UICorner")
    headerCorner.CornerRadius = UDim.new(0, 6)
    headerCorner.Parent = headerFrame

    -- Fix bottom corners of header
    local headerFix = Instance.new("Frame")
    headerFix.Size = UDim2.new(1, 0, 0, 6)
    headerFix.Position = UDim2.new(0, 0, 1, -6)
    headerFix.BackgroundColor3 = COLORS.HEADER_BG
    headerFix.BorderSizePixel = 0
    headerFix.Parent = headerFrame

    headerLabel = Instance.new("TextLabel")
    headerLabel.Name = "Title"
    headerLabel.Size = UDim2.new(1, -PANEL_PADDING * 2, 1, 0)
    headerLabel.Position = UDim2.new(0, PANEL_PADDING, 0, 0)
    headerLabel.BackgroundTransparency = 1
    headerLabel.Text = "VAULT CHEST 1"
    headerLabel.TextColor3 = COLORS.TEXT_GOLD
    headerLabel.Font = FONT
    headerLabel.TextSize = 12
    headerLabel.TextXAlignment = Enum.TextXAlignment.Left
    headerLabel.Parent = headerFrame

    -- Slots container (2 rows x 4 columns)
    slotsFrame = Instance.new("Frame")
    slotsFrame.Name = "Slots"
    slotsFrame.Size = UDim2.new(1, -PANEL_PADDING * 2, 0, SLOT_SIZE * 2 + SLOT_GAP)
    slotsFrame.Position = UDim2.new(0, PANEL_PADDING, 0, 30)
    slotsFrame.BackgroundTransparency = 1
    slotsFrame.Parent = mainFrame

    -- Create 8 slots (2x4 grid)
    for i = 1, 8 do
        local row = math.floor((i - 1) / 4)
        local col = (i - 1) % 4

        local slot = createSlot(slotsFrame, i)
        slot.Position = UDim2.new(0, col * (SLOT_SIZE + SLOT_GAP), 0, row * (SLOT_SIZE + SLOT_GAP))
        chestSlots[i] = slot
    end
end

--============================================================================
-- SLOT UPDATES
--============================================================================

local function updateSlot(slotFrame, itemId)
    local icon = slotFrame:FindFirstChild("Icon")
    if not icon then return end

    if itemId and itemId ~= false then
        local itemData = ItemDatabase.GetItem(itemId)
        if itemData then
            slotFrame.BackgroundColor3 = COLORS.SLOT_FILLED

            -- Display item icon if available
            if itemData.Icon then
                icon.Image = itemData.Icon
                icon.Visible = true
            else
                icon.Visible = false
            end

            -- Store item data for tooltips
            slotFrame:SetAttribute("ItemId", itemId)
            slotFrame:SetAttribute("ItemName", itemData.Name or "Unknown")
        else
            -- Unknown item
            slotFrame.BackgroundColor3 = COLORS.SLOT_FILLED
            slotFrame:SetAttribute("ItemId", itemId)
            slotFrame:SetAttribute("ItemName", "Item #" .. tostring(itemId))
            icon.Visible = false
        end
    else
        -- Empty slot
        slotFrame.BackgroundColor3 = COLORS.SLOT_EMPTY
        slotFrame:SetAttribute("ItemId", nil)
        slotFrame:SetAttribute("ItemName", nil)
        icon.Visible = false
    end
end

local function updateAllSlots(contents)
    for i = 1, 8 do
        local slot = chestSlots[i]
        if slot then
            local itemId = contents[i]
            updateSlot(slot, itemId)
        end
    end
end

--============================================================================
-- PUBLIC API
--============================================================================

function VaultUI.ShowChest(chestIndex, contents, unlockedCount)
    if not screenGui then
        createUI()
    end

    currentChestIndex = chestIndex
    currentContents = contents

    -- Update header
    if headerLabel then
        headerLabel.Text = "VAULT CHEST " .. chestIndex
    end

    -- Update slots
    updateAllSlots(contents)

    screenGui.Enabled = true
    -- print("[VaultUI] Showing chest " .. chestIndex)
end

function VaultUI.UpdateChest(chestIndex, contents)
    if currentChestIndex ~= chestIndex then return end

    currentContents = contents
    updateAllSlots(contents)
end

function VaultUI.Hide()
    if screenGui then
        screenGui.Enabled = false
    end
    currentChestIndex = nil
    currentContents = nil
end

function VaultUI.OnSlotClicked(slotIndex)
    if not currentChestIndex then return end

    local slot = chestSlots[slotIndex]
    if slot then
        local itemId = slot:GetAttribute("ItemId")
        local itemName = slot:GetAttribute("ItemName")
        if itemId then
            -- print("[VaultUI] Clicked slot " .. slotIndex .. ": " .. tostring(itemName))
            -- TODO: Implement drag/drop or item transfer
        else
            -- print("[VaultUI] Clicked empty slot " .. slotIndex)
        end
    end
end

function VaultUI.IsVisible()
    return screenGui and screenGui.Enabled
end

function VaultUI.GetCurrentChest()
    return currentChestIndex
end

return VaultUI
