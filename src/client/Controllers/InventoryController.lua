--[[
    InventoryController.lua
    Handles inventory UI interaction with RotMG-style slot swapping

    Slot System (1-indexed):
    - Slots 1-4: Equipment (Weapon, Ability, Armor, Ring)
    - Slots 5-12: Inventory (8 backpack slots)

    Drag and drop to swap items, with visual feedback
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local mouse = player:GetMouse()

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local ItemDatabase = require(Shared.ItemDatabase)

local InventoryController = {}

--============================================================================
-- CONSTANTS
--============================================================================

local EQUIPMENT_SLOT_NAMES = {"Weapon", "Ability", "Armor", "Ring"}
local NUM_EQUIPMENT_SLOTS = 4
local NUM_INVENTORY_SLOTS = 8
local NUM_LOOT_SLOTS = 8

-- GUI inset for ghost positioning (ScreenGui has IgnoreGuiInset=true)
local GuiService = game:GetService("GuiService")
local GUI_INSET = GuiService:GetGuiInset()

-- Colors for item rarity
local RARITY_COLORS = {
    Common = Color3.fromRGB(180, 180, 180),
    Uncommon = Color3.fromRGB(100, 255, 100),
    Rare = Color3.fromRGB(100, 180, 255),
    Epic = Color3.fromRGB(200, 100, 255),
    Legendary = Color3.fromRGB(255, 215, 0),
}

-- Match colors from HUDController
local SLOT_BG = Color3.fromRGB(40, 45, 60)
local SLOT_HIGHLIGHT = Color3.fromRGB(55, 65, 90)
local SLOT_INVALID = Color3.fromRGB(100, 40, 40)

--============================================================================
-- STATE
--============================================================================

local inventory = {
    Equipment = {Weapon = nil, Ability = nil, Armor = nil, Ring = nil},
    Backpack = {},
    HealthPotions = 0,
    ManaPotions = 0,
    Class = "Wizard",
}

local slotFrames = {}  -- Maps slot index to Frame (1-4 equipment, 5-12 inventory)
local lootSlotFrames = {}  -- Maps loot slot index (1-8) to Frame
local currentLootBagId = nil  -- Current loot bag being viewed
local lootBagItems = {}  -- Items in current loot bag

-- Vault tracking (uses same slots as loot bag)
local currentVaultChestIndex = nil  -- Current vault chest being viewed
local vaultChestItems = {}  -- Items in current vault chest
local lootUIMode = nil  -- "loot" or "vault" - tracks which mode we're in

local isDragging = false
local dragStartSlot = nil
local dragStartIsLoot = false  -- Whether drag started from loot/vault slot
local dragGhost = nil

--============================================================================
-- HELPER FUNCTIONS
--============================================================================

-- Get item ID from unified slot index
local function getItemFromSlot(slotIndex)
    if slotIndex <= NUM_EQUIPMENT_SLOTS then
        return inventory.Equipment[EQUIPMENT_SLOT_NAMES[slotIndex]]
    else
        return inventory.Backpack[slotIndex - NUM_EQUIPMENT_SLOTS]
    end
end

-- Note: UI display is handled by HUDController. InventoryController only tracks state for drag logic.

-- Get slot index from slot frame
local function getSlotIndex(slotFrame)
    for index, frame in pairs(slotFrames) do
        if frame == slotFrame then
            return index
        end
    end
    return nil
end

-- Find slot under mouse using Player:GetMouse() for accurate screen coordinates
local function getSlotUnderMouse()
    local mouseX = mouse.X
    local mouseY = mouse.Y

    for index, slot in pairs(slotFrames) do
        local absPos = slot.AbsolutePosition
        local absSize = slot.AbsoluteSize
        if mouseX >= absPos.X and mouseX <= absPos.X + absSize.X and
           mouseY >= absPos.Y and mouseY <= absPos.Y + absSize.Y then
            return index, slot
        end
    end
    return nil, nil
end

--============================================================================
-- DRAG AND DROP
--============================================================================

local function startDrag(slotIndex, slotFrame, isLootSlot)
    local itemId
    if isLootSlot then
        -- Check if we're in vault mode or loot mode
        if lootUIMode == "vault" then
            itemId = vaultChestItems[slotIndex]
        else
            itemId = lootBagItems[slotIndex]
        end
    else
        itemId = getItemFromSlot(slotIndex)
    end
    if not itemId then return end

    isDragging = true
    dragStartSlot = slotIndex
    dragStartIsLoot = isLootSlot or false

    -- Create ghost cursor
    local playerGui = player:WaitForChild("PlayerGui")
    local screenGui = playerGui:FindFirstChild("GameHUD")
    if not screenGui then return end

    dragGhost = Instance.new("Frame")
    dragGhost.Name = "DragGhost"
    dragGhost.Size = UDim2.new(0, 40, 0, 40)
    dragGhost.BackgroundTransparency = 0.5
    dragGhost.ZIndex = 100
    dragGhost.Parent = screenGui

    local item = ItemDatabase.GetItem(itemId)
    if item then
        dragGhost.BackgroundColor3 = RARITY_COLORS[item.Rarity] or RARITY_COLORS.Common

        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 4)
        corner.Parent = dragGhost

        local tierLabel = Instance.new("TextLabel")
        tierLabel.Size = UDim2.new(1, 0, 1, 0)
        tierLabel.BackgroundTransparency = 1
        tierLabel.Font = Enum.Font.GothamBold
        tierLabel.Text = "T" .. (item.Tier or 0)
        tierLabel.TextColor3 = Color3.new(1, 1, 1)
        tierLabel.TextSize = 14
        tierLabel.ZIndex = 101
        tierLabel.Parent = dragGhost
    end

    -- Dim original slot
    slotFrame.BackgroundColor3 = SLOT_HIGHLIGHT
end

-- Find loot slot under mouse
local function getLootSlotUnderMouse()
    local mouseX = mouse.X
    local mouseY = mouse.Y

    for index, slot in pairs(lootSlotFrames) do
        local absPos = slot.AbsolutePosition
        local absSize = slot.AbsoluteSize
        if mouseX >= absPos.X and mouseX <= absPos.X + absSize.X and
           mouseY >= absPos.Y and mouseY <= absPos.Y + absSize.Y then
            return index, slot
        end
    end
    return nil, nil
end

local function updateDrag()
    if not isDragging or not dragGhost then return end

    -- Use GetMouseLocation for ghost position (different coordinate space than mouse.X/Y)
    local mousePos = UserInputService:GetMouseLocation()
    dragGhost.Position = UDim2.new(0, mousePos.X - 20, 0, mousePos.Y - 20)

    -- Highlight slot under mouse
    local targetIndex, targetSlot = getSlotUnderMouse()
    local lootTargetIndex, lootTargetSlot = getLootSlotUnderMouse()

    -- Reset inventory slots
    for index, slot in pairs(slotFrames) do
        if not dragStartIsLoot and index == dragStartSlot then
            slot.BackgroundColor3 = SLOT_HIGHLIGHT
        elseif index == targetIndex then
            slot.BackgroundColor3 = SLOT_HIGHLIGHT
        else
            slot.BackgroundColor3 = SLOT_BG
        end
    end

    -- Reset loot slots
    for index, slot in pairs(lootSlotFrames) do
        if dragStartIsLoot and index == dragStartSlot then
            slot.BackgroundColor3 = SLOT_HIGHLIGHT
        elseif index == lootTargetIndex then
            slot.BackgroundColor3 = SLOT_HIGHLIGHT
        else
            slot.BackgroundColor3 = SLOT_BG
        end
    end
end

local function endDrag()
    if not isDragging then return end

    local targetIndex, targetSlot = getSlotUnderMouse()
    local lootTargetIndex, lootTargetSlot = getLootSlotUnderMouse()

    -- Cleanup ghost
    if dragGhost then
        dragGhost:Destroy()
        dragGhost = nil
    end

    -- Handle different drag scenarios
    if dragStartIsLoot then
        -- Dragging FROM loot/vault slot
        if targetIndex then
            -- Loot/Vault -> Inventory
            if lootUIMode == "vault" then
                -- Vault -> Inventory: Withdraw item
                -- Only allow dropping to backpack slots (5-12 -> backpack 1-8)
                if currentVaultChestIndex and targetIndex > NUM_EQUIPMENT_SLOTS then
                    local backpackSlot = targetIndex - NUM_EQUIPMENT_SLOTS
                    print("[InventoryController] Vault withdraw:", currentVaultChestIndex, "slot", dragStartSlot, "-> backpack", backpackSlot)
                    Remotes.Events.VaultWithdraw:FireServer(currentVaultChestIndex, dragStartSlot, backpackSlot)
                end
            else
                -- Loot -> Inventory: Request to pick up that specific item
                if currentLootBagId then
                    Remotes.Events.RequestLoot:FireServer(currentLootBagId)
                end
            end
        elseif lootTargetIndex and lootTargetIndex ~= dragStartSlot then
            -- Vault slot -> Vault slot: Swap within vault
            if lootUIMode == "vault" and currentVaultChestIndex then
                print("[InventoryController] Vault swap:", dragStartSlot, "->", lootTargetIndex)
                Remotes.Events.VaultSwap:FireServer(currentVaultChestIndex, dragStartSlot, lootTargetIndex)
            end
        end
    else
        -- Dragging FROM inventory
        if targetIndex and targetIndex ~= dragStartSlot then
            -- Inventory -> Inventory: Normal swap
            Remotes.Events.SwapInventory:FireServer(dragStartSlot, targetIndex)
        elseif lootTargetIndex then
            -- Inventory -> Loot/Vault slot
            if lootUIMode == "vault" then
                -- Inventory -> Vault: Deposit item (only from backpack slots 5-12)
                if currentVaultChestIndex and dragStartSlot > NUM_EQUIPMENT_SLOTS then
                    local backpackSlot = dragStartSlot - NUM_EQUIPMENT_SLOTS
                    print("[InventoryController] Vault deposit: backpack", backpackSlot, "->", currentVaultChestIndex, "slot", lootTargetIndex)
                    Remotes.Events.VaultDeposit:FireServer(backpackSlot, currentVaultChestIndex, lootTargetIndex)
                end
            end
            -- Loot mode: Do nothing (can't put items in loot bags)
        end
    end

    -- Reset slot colors
    for _, slot in pairs(slotFrames) do
        slot.BackgroundColor3 = SLOT_BG
    end
    for _, slot in pairs(lootSlotFrames) do
        slot.BackgroundColor3 = SLOT_BG
    end

    isDragging = false
    dragStartSlot = nil
    dragStartIsLoot = false
end

--============================================================================
-- INITIALIZATION
--============================================================================

local function findSlotFrames()
    local playerGui = player:WaitForChild("PlayerGui")

    -- Wait longer for GameHUD since HUDController may take time to create it
    local screenGui = playerGui:WaitForChild("GameHUD", 30)
    if not screenGui then
        warn("[InventoryController] GameHUD not found after 30 seconds")
        return false
    end

    local rightPanel = screenGui:WaitForChild("RightPanel", 5)
    if not rightPanel then
        warn("[InventoryController] RightPanel not found")
        return false
    end

    local content = rightPanel:WaitForChild("Content", 5)
    if not content then
        warn("[InventoryController] Content not found")
        return false
    end

    -- Find equipment slots (may be nested in EquipmentCard)
    local equipFrame = content:FindFirstChild("Equipment")
    if not equipFrame then
        local equipCard = content:FindFirstChild("EquipmentCard")
        equipFrame = equipCard and equipCard:FindFirstChild("Equipment")
    end
    if equipFrame then
        for i, slotName in ipairs(EQUIPMENT_SLOT_NAMES) do
            local slot = equipFrame:FindFirstChild(slotName)
            if slot then
                slotFrames[i] = slot
            end
        end
    end

    -- Find inventory slots (may be nested in InventoryCard)
    local invFrame = content:FindFirstChild("Inventory")
    if not invFrame then
        local invCard = content:FindFirstChild("InventoryCard")
        invFrame = invCard and invCard:FindFirstChild("Inventory")
    end
    if invFrame then
        for i = 1, NUM_INVENTORY_SLOTS do
            local slot = invFrame:FindFirstChild("Slot" .. i)
            if slot then
                slotFrames[NUM_EQUIPMENT_SLOTS + i] = slot
            end
        end
    end

    -- Find loot bag slots - wait for LootBag frame with timeout
    local lootFrame = content:WaitForChild("LootBag", 10)
    if lootFrame then
        -- Wait for the grid container inside
        local lootGridContainer = lootFrame:WaitForChild("LootGridContainer", 5)
        if lootGridContainer then
            -- Find slots directly in the grid container (more reliable than recursive search)
            for i = 1, NUM_LOOT_SLOTS do
                local slot = lootGridContainer:FindFirstChild("LootSlot" .. i)
                if slot then
                    lootSlotFrames[i] = slot
                end
            end
        else
            warn("[InventoryController] LootGridContainer not found in LootBag")
        end

        -- Count how many we actually found
        local lootCount = 0
        for _ in pairs(lootSlotFrames) do lootCount = lootCount + 1 end
        print("[InventoryController] Found " .. lootCount .. " loot slot frames")

        if lootCount == 0 then
            warn("[InventoryController] No loot slots found! Check slot naming.")
        end
    else
        warn("[InventoryController] LootBag frame not found")
    end

    -- Count inventory slots
    local invCount = 0
    for _ in pairs(slotFrames) do invCount = invCount + 1 end
    print("[InventoryController] Found " .. invCount .. " inventory/equipment slot frames")

    return invCount > 0
end

local function setupSlotInteraction()
    -- Setup inventory/equipment slot interaction
    for slotIndex, slot in pairs(slotFrames) do
        -- Check if button already exists (from HUD tooltip system)
        local existingButton = slot:FindFirstChild("SlotButton") or slot:FindFirstChild("HoverDetector")
        local button

        if existingButton then
            button = existingButton
        else
            button = Instance.new("TextButton")
            button.Name = "SlotButton"
            button.Size = UDim2.new(1, 0, 1, 0)
            button.BackgroundTransparency = 1
            button.Text = ""
            button.ZIndex = 50
            button.Parent = slot
        end

        -- Mouse events for drag
        button.MouseButton1Down:Connect(function()
            startDrag(slotIndex, slot, false)
        end)

        button.MouseEnter:Connect(function()
            if not isDragging then
                slot.BackgroundColor3 = SLOT_HIGHLIGHT
            end
        end)

        button.MouseLeave:Connect(function()
            if not isDragging then
                slot.BackgroundColor3 = SLOT_BG
            end
        end)
    end

    -- Setup loot slot interaction
    for slotIndex, slot in pairs(lootSlotFrames) do
        -- Check if button already exists (from HUD tooltip system)
        local existingButton = slot:FindFirstChild("SlotButton") or slot:FindFirstChild("HoverDetector")
        local button

        if existingButton then
            button = existingButton
        else
            button = Instance.new("TextButton")
            button.Name = "SlotButton"
            button.Size = UDim2.new(1, 0, 1, 0)
            button.BackgroundTransparency = 1
            button.Text = ""
            button.ZIndex = 50
            button.Parent = slot
        end

        -- Ensure button can receive clicks
        button.Active = true

        -- Mouse events for drag (from loot)
        button.MouseButton1Down:Connect(function()
            startDrag(slotIndex, slot, true)
        end)

        button.MouseEnter:Connect(function()
            if not isDragging then
                slot.BackgroundColor3 = SLOT_HIGHLIGHT
            end
        end)

        button.MouseLeave:Connect(function()
            if not isDragging then
                slot.BackgroundColor3 = SLOT_BG
            end
        end)
    end

    -- Global mouse up to end drag
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            endDrag()
        end
    end)

    -- Update ghost position while dragging
    UserInputService.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement then
            updateDrag()
        end
    end)
end

local function setupRemoteListeners()
    -- Listen for inventory updates from server
    Remotes.Events.InventoryUpdate.OnClientEvent:Connect(function(data)
        if data.Equipment then
            inventory.Equipment = data.Equipment
        end
        if data.Backpack then
            inventory.Backpack = data.Backpack
        end
        if data.HealthPotions then
            inventory.HealthPotions = data.HealthPotions
        end
        if data.ManaPotions then
            inventory.ManaPotions = data.ManaPotions
        end
        -- Note: UI display is updated by HUDController, not here
    end)

    -- Listen for stat updates that include class
    Remotes.Events.StatUpdate.OnClientEvent:Connect(function(data)
        if data.Class then
            inventory.Class = data.Class
        end
    end)

    -- Listen for loot bag drops (to track items)
    Remotes.Events.LootDrop.OnClientEvent:Connect(function(data)
        -- Store items for this bag (will be used when we open it)
    end)

    -- Listen for loot bag contents (for late arrivals or refresh)
    Remotes.Events.LootBagContents.OnClientEvent:Connect(function(data)
        if data.BagId == currentLootBagId then
            lootBagItems = data.Items or {}
        end
    end)

    -- Listen for loot pickup updates
    Remotes.Events.LootPickup.OnClientEvent:Connect(function(data)
        if data.BagId == currentLootBagId then
            if data.Removed then
                lootBagItems = {}
                currentLootBagId = nil
            elseif data.RemainingItems then
                lootBagItems = data.RemainingItems
            end
        end
    end)
end

-- Called by other systems to update current loot bag
function InventoryController.SetCurrentLootBag(bagId, items)
    currentLootBagId = bagId
    lootBagItems = items or {}
    lootUIMode = "loot"  -- Set mode to loot (not vault)
end

function InventoryController.ClearCurrentLootBag()
    currentLootBagId = nil
    lootBagItems = {}
    lootUIMode = nil  -- Clear mode
end

-- Called by HUDController to set current vault chest
function InventoryController.SetCurrentVaultChest(chestIndex, items)
    currentVaultChestIndex = chestIndex
    vaultChestItems = items or {}
    -- Only set vault mode if actually opening a vault (not clearing)
    if chestIndex then
        lootUIMode = "vault"
    end
end

function InventoryController.ClearCurrentVaultChest()
    currentVaultChestIndex = nil
    vaultChestItems = {}
    lootUIMode = nil
end

-- Get current UI mode (for external access)
function InventoryController.GetLootUIMode()
    return lootUIMode
end

function InventoryController.Init()
    -- Wait for HUD to be created
    task.wait(0.5)

    if not findSlotFrames() then
        warn("[InventoryController] Failed to find slot frames, retrying...")
        task.wait(1)
        if not findSlotFrames() then
            warn("[InventoryController] Could not initialize - slots not found")
            return
        end
    end

    -- Check if loot slots were found, retry if not
    local lootCount = 0
    for _ in pairs(lootSlotFrames) do lootCount = lootCount + 1 end

    if lootCount == 0 then
        warn("[InventoryController] No loot slots found on first attempt, retrying...")
        for attempt = 1, 5 do
            task.wait(0.5)
            -- Try to find loot slots again
            local playerGui = player:WaitForChild("PlayerGui")
            local screenGui = playerGui:FindFirstChild("GameHUD")
            if screenGui then
                local rightPanel = screenGui:FindFirstChild("RightPanel")
                local content = rightPanel and rightPanel:FindFirstChild("Content")
                local lootFrame = content and content:FindFirstChild("LootBag")
                local lootGridContainer = lootFrame and lootFrame:FindFirstChild("LootGridContainer")

                if lootGridContainer then
                    for i = 1, NUM_LOOT_SLOTS do
                        local slot = lootGridContainer:FindFirstChild("LootSlot" .. i)
                        if slot then
                            lootSlotFrames[i] = slot
                        end
                    end

                    -- Recount
                    lootCount = 0
                    for _ in pairs(lootSlotFrames) do lootCount = lootCount + 1 end

                    if lootCount > 0 then
                        print("[InventoryController] Found " .. lootCount .. " loot slots on retry attempt " .. attempt)
                        break
                    end
                end
            end
        end
    end

    setupSlotInteraction()
    setupRemoteListeners()

    print("[InventoryController] Initialized with drag-and-drop")
end

-- Reinitialize slot references when HUD is recreated (e.g., on respawn)
function InventoryController.Reinitialize()
    print("[InventoryController] Reinitializing slot references...")

    -- Clear old references
    slotFrames = {}
    lootSlotFrames = {}

    -- Wait a moment for new UI to be fully created
    task.wait(0.5)

    if not findSlotFrames() then
        warn("[InventoryController] Reinitialize: Failed to find slot frames")
        return false
    end

    -- Check if loot slots were found, retry if not
    local lootCount = 0
    for _ in pairs(lootSlotFrames) do lootCount = lootCount + 1 end

    if lootCount == 0 then
        for attempt = 1, 3 do
            task.wait(0.3)
            local playerGui = player:WaitForChild("PlayerGui")
            local screenGui = playerGui:FindFirstChild("GameHUD")
            if screenGui then
                local rightPanel = screenGui:FindFirstChild("RightPanel")
                local content = rightPanel and rightPanel:FindFirstChild("Content")
                local lootFrame = content and content:FindFirstChild("LootBag")
                local lootGridContainer = lootFrame and lootFrame:FindFirstChild("LootGridContainer")

                if lootGridContainer then
                    for i = 1, NUM_LOOT_SLOTS do
                        local slot = lootGridContainer:FindFirstChild("LootSlot" .. i)
                        if slot then
                            lootSlotFrames[i] = slot
                        end
                    end

                    lootCount = 0
                    for _ in pairs(lootSlotFrames) do lootCount = lootCount + 1 end
                    if lootCount > 0 then break end
                end
            end
        end
    end

    setupSlotInteraction()
    print("[InventoryController] Reinitialized successfully with " .. lootCount .. " loot slots")
    return true
end

-- Get current inventory state (for other systems)
function InventoryController.GetInventory()
    return inventory
end

-- Get item in a specific slot
function InventoryController.GetItemInSlot(slotIndex)
    return getItemFromSlot(slotIndex)
end

return InventoryController
