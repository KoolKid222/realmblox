--[[
    VaultManager.lua
    Handles vault operations and storage management

    Features:
    - Open/close vault chests
    - Move items between inventory and vault
    - Unlock new vault chests
    - Potion vault storage
    - Gift chest retrieval
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local Remotes = require(Shared.Remotes)
local ItemDatabase = require(Shared.ItemDatabase)
local LazyLoader = require(Shared.LazyLoader)

-- Lazy load managers using LazyLoader utility
local getProfileManager = LazyLoader.create(script.Parent, "ProfileManager")
local getPlayerManager = LazyLoader.create(script.Parent, "PlayerManager")
local getMovementValidator = LazyLoader.create(script.Parent, "MovementValidator")

local VaultManager = {}

--============================================================================
-- VAULT DATA ACCESS
--============================================================================

function VaultManager.GetVaultData(player)
    local profile = getProfileManager().GetProfile(player)
    if profile then
        return profile.Data.Vault
    end
    return nil
end

function VaultManager.GetChestContents(player, chestIndex)
    local vault = VaultManager.GetVaultData(player)
    if not vault then return nil end

    -- Check if chest is unlocked
    if chestIndex > vault.UnlockedChestCount then
        return nil, "Chest is locked"
    end

    -- Ensure chest exists in data
    if not vault.Chests[chestIndex] then
        vault.Chests[chestIndex] = {false, false, false, false, false, false, false, false}
    end

    return vault.Chests[chestIndex]
end

--============================================================================
-- ITEM OPERATIONS
--============================================================================

-- Move item from character inventory to vault chest
function VaultManager.DepositItem(player, inventorySlot, chestIndex, chestSlot)
    local vault = VaultManager.GetVaultData(player)
    if not vault then return false, "No vault data" end

    -- Check chest is unlocked
    if chestIndex > vault.UnlockedChestCount then
        return false, "Chest is locked"
    end

    -- Ensure chest exists
    if not vault.Chests[chestIndex] then
        vault.Chests[chestIndex] = {false, false, false, false, false, false, false, false}
    end

    -- Check vault slot is empty
    if vault.Chests[chestIndex][chestSlot] then
        return false, "Vault slot is not empty"
    end

    -- Get player's character data
    local charData = getPlayerManager().ActiveCharacters[player]
    if not charData then return false, "No active character" end

    -- Get item from inventory (backpack slot)
    local item = charData.Backpack[inventorySlot]
    if not item then return false, "No item in inventory slot" end

    -- Move item
    vault.Chests[chestIndex][chestSlot] = item
    charData.Backpack[inventorySlot] = nil

    -- Notify client of inventory change
    VaultManager.SendInventoryUpdate(player)

    print("[VaultManager] " .. player.Name .. " deposited item to chest " .. chestIndex .. " slot " .. chestSlot)
    return true
end

-- Move item from vault chest to character inventory
function VaultManager.WithdrawItem(player, chestIndex, chestSlot, inventorySlot)
    local vault = VaultManager.GetVaultData(player)
    if not vault then return false, "No vault data" end

    -- Check chest is unlocked
    if chestIndex > vault.UnlockedChestCount then
        return false, "Chest is locked"
    end

    -- Check vault slot has item
    if not vault.Chests[chestIndex] or not vault.Chests[chestIndex][chestSlot] then
        return false, "No item in vault slot"
    end

    -- Get player's character data
    local charData = getPlayerManager().ActiveCharacters[player]
    if not charData then return false, "No active character" end

    -- Check inventory slot is empty
    if charData.Backpack[inventorySlot] then
        return false, "Inventory slot is not empty"
    end

    -- Move item
    local item = vault.Chests[chestIndex][chestSlot]
    charData.Backpack[inventorySlot] = item
    vault.Chests[chestIndex][chestSlot] = false

    -- Notify client of inventory change
    VaultManager.SendInventoryUpdate(player)

    print("[VaultManager] " .. player.Name .. " withdrew item from chest " .. chestIndex .. " slot " .. chestSlot)
    return true
end

-- Swap items between vault and inventory
function VaultManager.SwapItem(player, inventorySlot, chestIndex, chestSlot)
    local vault = VaultManager.GetVaultData(player)
    if not vault then return false, "No vault data" end

    if chestIndex > vault.UnlockedChestCount then
        return false, "Chest is locked"
    end

    local charData = getPlayerManager().ActiveCharacters[player]
    if not charData then return false, "No active character" end

    -- Ensure chest exists
    if not vault.Chests[chestIndex] then
        vault.Chests[chestIndex] = {false, false, false, false, false, false, false, false}
    end

    -- Swap
    local invItem = charData.Backpack[inventorySlot]
    local vaultItem = vault.Chests[chestIndex][chestSlot]

    charData.Backpack[inventorySlot] = vaultItem or nil
    vault.Chests[chestIndex][chestSlot] = invItem or false

    VaultManager.SendInventoryUpdate(player)

    print("[VaultManager] " .. player.Name .. " swapped items with chest " .. chestIndex)
    return true
end

-- Swap items within the same vault chest
function VaultManager.SwapWithinChest(player, chestIndex, fromSlot, toSlot)
    local vault = VaultManager.GetVaultData(player)
    if not vault then return false, "No vault data" end

    if chestIndex > vault.UnlockedChestCount then
        return false, "Chest is locked"
    end

    -- Ensure chest exists
    if not vault.Chests[chestIndex] then
        vault.Chests[chestIndex] = {false, false, false, false, false, false, false, false}
    end

    -- Swap within chest
    local fromItem = vault.Chests[chestIndex][fromSlot]
    local toItem = vault.Chests[chestIndex][toSlot]

    vault.Chests[chestIndex][fromSlot] = toItem or false
    vault.Chests[chestIndex][toSlot] = fromItem or false

    print("[VaultManager] " .. player.Name .. " swapped slots in chest " .. chestIndex .. ": " .. fromSlot .. " <-> " .. toSlot)
    return true
end

--============================================================================
-- CHEST UNLOCKING
--============================================================================

function VaultManager.UnlockChest(player)
    local vault = VaultManager.GetVaultData(player)
    if not vault then return false, "No vault data" end

    local profile = getProfileManager().GetProfile(player)
    if not profile then return false, "No profile" end

    -- Check if at max chests
    if vault.UnlockedChestCount >= vault.MaxChests then
        return false, "Maximum chests unlocked"
    end

    -- Check if player has enough gold (500 per chest in RotMG)
    local cost = 500
    if profile.Data.Currency.RealmGold < cost then
        return false, "Not enough Realm Gold (need " .. cost .. ")"
    end

    -- Deduct gold and unlock chest
    profile.Data.Currency.RealmGold = profile.Data.Currency.RealmGold - cost
    vault.UnlockedChestCount = vault.UnlockedChestCount + 1

    -- Initialize the new chest
    vault.Chests[vault.UnlockedChestCount] = {false, false, false, false, false, false, false, false}

    print("[VaultManager] " .. player.Name .. " unlocked chest " .. vault.UnlockedChestCount)
    return true, vault.UnlockedChestCount
end

--============================================================================
-- POTION VAULT
--============================================================================

function VaultManager.DepositPotion(player, potionItemId, count)
    local vault = VaultManager.GetVaultData(player)
    if not vault then return false, "No vault data" end

    -- Verify it's a potion item
    local itemData = ItemDatabase.GetItem(potionItemId)
    if not itemData or itemData.Type ~= "Potion" then
        return false, "Not a potion item"
    end

    -- Check capacity
    local currentTotal = 0
    for _, amount in pairs(vault.PotionVault) do
        currentTotal = currentTotal + amount
    end

    if currentTotal + count > vault.PotionVaultCapacity then
        return false, "Potion vault is full"
    end

    -- Add potions
    vault.PotionVault[potionItemId] = (vault.PotionVault[potionItemId] or 0) + count

    print("[VaultManager] " .. player.Name .. " deposited " .. count .. " potions")
    return true
end

function VaultManager.WithdrawPotion(player, potionItemId, count)
    local vault = VaultManager.GetVaultData(player)
    if not vault then return false, "No vault data" end

    local available = vault.PotionVault[potionItemId] or 0
    if available < count then
        return false, "Not enough potions"
    end

    vault.PotionVault[potionItemId] = available - count
    if vault.PotionVault[potionItemId] <= 0 then
        vault.PotionVault[potionItemId] = nil
    end

    print("[VaultManager] " .. player.Name .. " withdrew " .. count .. " potions")
    return true
end

--============================================================================
-- GIFT CHEST
--============================================================================

function VaultManager.AddGift(player, itemId)
    local vault = VaultManager.GetVaultData(player)
    if not vault then return false end

    table.insert(vault.GiftChest, itemId)
    return true
end

function VaultManager.ClaimGift(player, giftIndex, inventorySlot)
    local vault = VaultManager.GetVaultData(player)
    if not vault then return false, "No vault data" end

    local charData = getPlayerManager().ActiveCharacters[player]
    if not charData then return false, "No active character" end

    -- Check gift exists
    if not vault.GiftChest[giftIndex] then
        return false, "No gift at index"
    end

    -- Check inventory slot is empty
    if charData.Backpack[inventorySlot] then
        return false, "Inventory slot is not empty"
    end

    -- Move gift to inventory
    local itemId = vault.GiftChest[giftIndex]
    charData.Backpack[inventorySlot] = itemId
    table.remove(vault.GiftChest, giftIndex)

    VaultManager.SendInventoryUpdate(player)

    print("[VaultManager] " .. player.Name .. " claimed gift: " .. tostring(itemId))
    return true
end

--============================================================================
-- UTILITY
--============================================================================

function VaultManager.SendInventoryUpdate(player)
    local charData = getPlayerManager().ActiveCharacters[player]
    if not charData then return end

    local backpackData = {}
    for i = 1, 8 do
        backpackData[i] = charData.Backpack[i] or false
    end

    Remotes.Events.InventoryUpdate:FireClient(player, {
        Equipment = charData.Equipment,
        Backpack = backpackData,
        HealthPotions = charData.HealthPotions,
        ManaPotions = charData.ManaPotions,
    })
end

--============================================================================
-- INITIALIZATION
--============================================================================

function VaultManager.Init()
    -- Open chest request
    Remotes.Events.OpenVaultChest.OnServerEvent:Connect(function(player, chestIndex)
        local contents, err = VaultManager.GetChestContents(player, chestIndex)
        if contents then
            local vault = VaultManager.GetVaultData(player)
            Remotes.Events.VaultChestOpened:FireClient(player, {
                ChestIndex = chestIndex,
                Contents = contents,
                UnlockedCount = vault.UnlockedChestCount,
            })
        else
            Remotes.Events.Notification:FireClient(player, {
                Message = err or "Cannot open chest",
                Type = "error",
            })
        end
    end)

    -- Deposit item request
    Remotes.Events.VaultDeposit.OnServerEvent:Connect(function(player, inventorySlot, chestIndex, chestSlot)
        local success, err = VaultManager.DepositItem(player, inventorySlot, chestIndex, chestSlot)
        if success then
            -- Send updated chest contents
            local contents = VaultManager.GetChestContents(player, chestIndex)
            Remotes.Events.VaultChestUpdated:FireClient(player, {
                ChestIndex = chestIndex,
                Contents = contents,
            })
        else
            Remotes.Events.Notification:FireClient(player, {
                Message = err or "Failed to deposit",
                Type = "error",
            })
        end
    end)

    -- Withdraw item request
    Remotes.Events.VaultWithdraw.OnServerEvent:Connect(function(player, chestIndex, chestSlot, inventorySlot)
        local success, err = VaultManager.WithdrawItem(player, chestIndex, chestSlot, inventorySlot)
        if success then
            local contents = VaultManager.GetChestContents(player, chestIndex)
            Remotes.Events.VaultChestUpdated:FireClient(player, {
                ChestIndex = chestIndex,
                Contents = contents,
            })
        else
            Remotes.Events.Notification:FireClient(player, {
                Message = err or "Failed to withdraw",
                Type = "error",
            })
        end
    end)

    -- Swap items within vault chest
    Remotes.Events.VaultSwap.OnServerEvent:Connect(function(player, chestIndex, fromSlot, toSlot)
        local success, err = VaultManager.SwapWithinChest(player, chestIndex, fromSlot, toSlot)
        if success then
            local contents = VaultManager.GetChestContents(player, chestIndex)
            Remotes.Events.VaultChestUpdated:FireClient(player, {
                ChestIndex = chestIndex,
                Contents = contents,
            })
        else
            Remotes.Events.Notification:FireClient(player, {
                Message = err or "Failed to swap",
                Type = "error",
            })
        end
    end)

    -- Close vault chest (just echo back to close UI)
    Remotes.Events.CloseVaultChest.OnServerEvent:Connect(function(player)
        Remotes.Events.VaultChestClosed:FireClient(player)
    end)

    -- Unlock chest request
    Remotes.Events.UnlockVaultChest.OnServerEvent:Connect(function(player)
        local success, result = VaultManager.UnlockChest(player)
        if success then
            Remotes.Events.VaultChestUnlocked:FireClient(player, {
                NewChestIndex = result,
            })
        else
            Remotes.Events.Notification:FireClient(player, {
                Message = result or "Failed to unlock",
                Type = "error",
            })
        end
    end)

    print("[VaultManager] Initialized")
end

return VaultManager
