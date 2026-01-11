--[[
    LootManager.lua
    Handles loot drops, loot bags, and item pickup
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local Utilities = require(Shared.Utilities)
local ItemDatabase = require(Shared.ItemDatabase)
local ClassDatabase = require(Shared.ClassDatabase)
local Remotes = require(Shared.Remotes)

local LootManager = {}

--============================================================================
-- BAG TYPE DETERMINATION (RotMG 6-bag system)
--============================================================================
-- Bag Types:
--   1 = Brown (HP/MP potions) - PUBLIC
--   2 = Pink (T0-6 weapons/armor, T0-1 rings, T0-2 abilities) - PUBLIC
--   3 = Purple (T7-9 weapons/armor, T2-4 rings, T3-4 abilities) - SOULBOUND
--   4 = Cyan (T10+ weapons/armor, T5+ rings/abilities) - SOULBOUND
--   5 = Blue (stat potions) - SOULBOUND
--   6 = White (UT items) - SOULBOUND

local BAG_TYPES = {
    BROWN = 1,
    PINK = 2,
    PURPLE = 3,
    CYAN = 4,
    BLUE = 5,
    WHITE = 6,
}

-- Get the bag type for a single item
local function getItemBagType(item)
    if not item then return BAG_TYPES.BROWN end

    -- White bag items (UT)
    if item.WhiteBag or item.Tier == "UT" then
        return BAG_TYPES.WHITE
    end

    -- Stat potions -> Blue bag
    if item.Subtype == "StatPotion" then
        return BAG_TYPES.BLUE
    end

    -- HP/MP potions -> Brown bag
    if item.Subtype == "Potion" then
        return BAG_TYPES.BROWN
    end

    -- Equipment tier checks
    local tier = tonumber(item.Tier) or 0

    if item.Type == "Weapon" or item.Type == "Armor" then
        if tier >= 10 then
            return BAG_TYPES.CYAN      -- T10+ weapons/armor
        elseif tier >= 7 then
            return BAG_TYPES.PURPLE    -- T7-9 weapons/armor
        else
            return BAG_TYPES.PINK      -- T0-6 weapons/armor
        end
    elseif item.Type == "Ability" then
        if tier >= 5 then
            return BAG_TYPES.CYAN      -- T5+ abilities
        elseif tier >= 3 then
            return BAG_TYPES.PURPLE    -- T3-4 abilities
        else
            return BAG_TYPES.PINK      -- T0-2 abilities
        end
    elseif item.Type == "Ring" then
        if tier >= 5 then
            return BAG_TYPES.CYAN      -- T5+ rings
        elseif tier >= 2 then
            return BAG_TYPES.PURPLE    -- T2-4 rings
        else
            return BAG_TYPES.PINK      -- T0-1 rings
        end
    end

    return BAG_TYPES.BROWN
end

-- Determine bag type based on highest priority item in the list
local function determineBagType(items)
    local highestBagType = BAG_TYPES.BROWN

    for _, itemId in ipairs(items) do
        local item = ItemDatabase.GetItem(itemId)
        local bagType = getItemBagType(item)
        if bagType > highestBagType then
            highestBagType = bagType
        end
    end

    return highestBagType
end

-- Check if bag is soulbound based on bag type
-- Brown (1) and Pink (2) are PUBLIC, everything else is SOULBOUND
local function isBagSoulbound(bagType)
    return bagType >= BAG_TYPES.PURPLE
end

-- Check if a player qualifies for soulbound loot based on damage dealt
local function playerQualifiesForSoulbound(damageDealt, enemyMaxHP, soulboundThreshold)
    if enemyMaxHP <= 0 then return false end
    local damagePercent = damageDealt / enemyMaxHP
    return damagePercent >= soulboundThreshold
end

-- Separate items into public and soulbound categories
local function categorizeItems(items)
    local publicItems = {}      -- Brown/Pink bag items
    local soulboundItems = {}   -- Purple/Cyan/Blue/White bag items

    for _, itemId in ipairs(items) do
        local item = ItemDatabase.GetItem(itemId)
        local bagType = getItemBagType(item)

        if isBagSoulbound(bagType) then
            table.insert(soulboundItems, itemId)
        else
            table.insert(publicItems, itemId)
        end
    end

    return publicItems, soulboundItems
end

-- Lazy load managers using LazyLoader utility
local LazyLoader = require(Shared.LazyLoader)
local getPlayerManager = LazyLoader.create(script.Parent, "PlayerManager")

-- Active loot bags
LootManager.LootBags = {}  -- [id] = bagData

-- Loot bag structure
--[[
    {
        Id = string,
        Position = Vector3,
        Items = {itemId, itemId, ...},
        SpawnTime = number,
        Lifetime = number,
        BagType = number,  -- 1-5 (Brown, Pink, Purple, Blue, White)
        Soulbound = boolean,  -- If true, only DamageContributors can see/pick up
        DamageContributors = {Player = true, ...},  -- Who dealt damage to the enemy
    }
]]

local LOOT_BAG_LIFETIME = 60  -- Seconds before despawn
local PICKUP_RADIUS = 8

-- Drop loot from an enemy with proper soulbound threshold system
-- enemyData contains: MaxHP, SoulboundThreshold, IsBoss, IsGod, LootTable
function LootManager.DropLoot(position, lootTableName, damageContributors, enemyData)
    enemyData = enemyData or {}
    local enemyMaxHP = enemyData.MaxHP or 100
    local soulboundThreshold = enemyData.SoulboundThreshold or 0.15

    -- Determine which players qualify for soulbound loot
    local qualifyingPlayers = {}
    for player, damage in pairs(damageContributors) do
        if player.Parent then
            if playerQualifiesForSoulbound(damage, enemyMaxHP, soulboundThreshold) then
                qualifyingPlayers[player] = true
                print(string.format("[LootManager] %s qualifies for soulbound (%.1f%% damage, threshold %.1f%%)",
                    player.Name, (damage / enemyMaxHP) * 100, soulboundThreshold * 100))
            else
                print(string.format("[LootManager] %s does NOT qualify (%.1f%% damage, needed %.1f%%)",
                    player.Name, (damage / enemyMaxHP) * 100, soulboundThreshold * 100))
            end
        end
    end

    local createdBags = {}

    -- Roll public loot once (shared by everyone)
    local publicItems, _ = {}, {}
    local allDroppedItems = ItemDatabase.RollLoot(lootTableName)

    -- Separate rolled items into public and soulbound
    for _, itemId in ipairs(allDroppedItems) do
        local item = ItemDatabase.GetItem(itemId)
        local bagType = getItemBagType(item)
        if not isBagSoulbound(bagType) then
            table.insert(publicItems, itemId)
        end
    end

    -- Create public bag if there are public items (visible to everyone)
    if #publicItems > 0 then
        local bagType = determineBagType(publicItems)
        local publicBag = {
            Id = Utilities.GenerateUID(),
            Position = position,
            Items = publicItems,
            SpawnTime = tick(),
            Lifetime = LOOT_BAG_LIFETIME,
            BagType = bagType,
            Soulbound = false,
            DamageContributors = {},
            Owner = nil,  -- Public bag has no owner
        }

        LootManager.LootBags[publicBag.Id] = publicBag
        table.insert(createdBags, publicBag)

        -- Notify ALL clients about public bag
        Remotes.Events.LootDrop:FireAllClients({
            Id = publicBag.Id,
            Position = position,
            Items = publicItems,
            BagType = bagType,
            Soulbound = false,
        })
    end

    -- Roll soulbound loot INDEPENDENTLY for each qualifying player
    for player in pairs(qualifyingPlayers) do
        -- Each player gets their own independent loot roll
        local playerDrops = ItemDatabase.RollLoot(lootTableName)

        -- Filter to only soulbound items
        local soulboundItems = {}
        for _, itemId in ipairs(playerDrops) do
            local item = ItemDatabase.GetItem(itemId)
            local bagType = getItemBagType(item)
            if isBagSoulbound(bagType) then
                table.insert(soulboundItems, itemId)
            end
        end

        -- Create soulbound bag for this player if they got soulbound items
        if #soulboundItems > 0 then
            local bagType = determineBagType(soulboundItems)
            local soulboundBag = {
                Id = Utilities.GenerateUID(),
                Position = position + Vector3.new(math.random(-2, 2) * 0.1, 0, math.random(-2, 2) * 0.1),
                Items = soulboundItems,
                SpawnTime = tick(),
                Lifetime = LOOT_BAG_LIFETIME,
                BagType = bagType,
                Soulbound = true,
                DamageContributors = {[player] = true},
                Owner = player,  -- Only this player can see/loot
            }

            LootManager.LootBags[soulboundBag.Id] = soulboundBag
            table.insert(createdBags, soulboundBag)

            -- Notify ONLY this player about their soulbound bag
            Remotes.Events.LootDrop:FireClient(player, {
                Id = soulboundBag.Id,
                Position = soulboundBag.Position,
                Items = soulboundItems,
                BagType = bagType,
                Soulbound = true,
            })

            print(string.format("[LootManager] Created %s bag for %s with %d items",
                bagType == BAG_TYPES.WHITE and "WHITE" or
                bagType == BAG_TYPES.BLUE and "BLUE" or
                bagType == BAG_TYPES.CYAN and "CYAN" or "PURPLE",
                player.Name, #soulboundItems))
        end
    end

    return createdBags
end

-- Try to pick up loot
function LootManager.TryPickupLoot(player, bagId)
    local PM = getPlayerManager()
    local charData = PM.ActiveCharacters[player]
    if not charData then return false, "No character" end

    local bag = LootManager.LootBags[bagId]
    if not bag then return false, "Bag not found" end

    -- Check if player is close enough
    if player.Character then
        local rootPart = player.Character:FindFirstChild("HumanoidRootPart")
        if rootPart then
            local dist = (bag.Position - rootPart.Position).Magnitude
            if dist > PICKUP_RADIUS then
                return false, "Too far away"
            end
        end
    end

    -- Check soulbound status
    if bag.Soulbound and not bag.DamageContributors[player] then
        return false, "Not your loot"
    end

    -- Try to add items to inventory
    local pickedUp = {}
    local remaining = {}

    for _, itemId in ipairs(bag.Items) do
        local item = ItemDatabase.GetItem(itemId)
        if not item then
            table.insert(remaining, itemId)
        elseif item.Type == "Consumable" and item.Subtype == "Potion" then
            -- Handle HP/MP potions specially (go to potion counter, not backpack)
            if item.Id == "HealthPotion" then
                if charData.HealthPotions < Constants.Inventory.MAX_HP_POTIONS then
                    charData.HealthPotions = charData.HealthPotions + 1
                    table.insert(pickedUp, itemId)
                else
                    table.insert(remaining, itemId)
                end
            elseif item.Id == "ManaPotion" then
                if charData.ManaPotions < Constants.Inventory.MAX_MP_POTIONS then
                    charData.ManaPotions = charData.ManaPotions + 1
                    table.insert(pickedUp, itemId)
                else
                    table.insert(remaining, itemId)
                end
            else
                table.insert(remaining, itemId)
            end
        else
            -- Regular item or stat potion - try backpack
            local added = false
            for i = 1, Constants.Inventory.BACKPACK_SLOTS do
                if not charData.Backpack[i] then
                    charData.Backpack[i] = itemId
                    table.insert(pickedUp, itemId)
                    added = true
                    break
                end
            end
            if not added then
                table.insert(remaining, itemId)
            end
        end
    end

    -- Update bag or remove it
    if #remaining == 0 then
        LootManager.LootBags[bagId] = nil
        Remotes.Events.LootPickup:FireAllClients({
            BagId = bagId,
            Removed = true,
        })
    else
        bag.Items = remaining
        Remotes.Events.LootPickup:FireAllClients({
            BagId = bagId,
            RemainingItems = remaining,
        })
    end

    -- Update player inventory
    if #pickedUp > 0 then
        -- Build backpack with false placeholders for empty slots (Roblox doesn't serialize nil)
        local backpackData = {}
        for i = 1, 8 do
            backpackData[i] = charData.Backpack[i] or false
        end
        Remotes.Events.InventoryUpdate:FireClient(player, {
            Backpack = backpackData,
            HealthPotions = charData.HealthPotions,
            ManaPotions = charData.ManaPotions,
        })

        -- Notify success
        Remotes.Events.Notification:FireClient(player, {
            Message = "Picked up " .. #pickedUp .. " item(s)",
            Type = "success"
        })
    end

    -- Return appropriate error if nothing was picked up
    if #pickedUp == 0 and #remaining > 0 then
        return false, "Inventory full!"
    end

    return #pickedUp > 0, nil
end

-- Equip an item from backpack
function LootManager.EquipItem(player, backpackSlot)
    local PM = getPlayerManager()
    local charData = PM.ActiveCharacters[player]
    if not charData then return false end

    local itemId = charData.Backpack[backpackSlot]
    if not itemId then return false end

    local item = ItemDatabase.GetItem(itemId)
    if not item then return false end

    -- Determine equipment slot
    local equipSlot = nil
    if item.Type == "Weapon" then
        equipSlot = "Weapon"
    elseif item.Type == "Armor" then
        equipSlot = "Armor"
    elseif item.Type == "Ring" then
        equipSlot = "Ring"
    elseif item.Type == "Ability" then
        equipSlot = "Ability"
    end

    if not equipSlot then return false end

    -- Swap items
    local oldEquipped = charData.Equipment[equipSlot]
    charData.Equipment[equipSlot] = itemId
    charData.Backpack[backpackSlot] = oldEquipped

    -- Update client
    Remotes.Events.InventoryUpdate:FireClient(player, {
        Equipment = charData.Equipment,
        Backpack = charData.Backpack,
    })

    -- Update stats (equipment changed)
    local effectiveStats = PM.GetEffectiveStats(player)
    Remotes.Events.StatUpdate:FireClient(player, {
        Stats = effectiveStats,
    })

    return true
end

-- Drop an item from backpack
function LootManager.DropItem(player, backpackSlot)
    local PM = getPlayerManager()
    local charData = PM.ActiveCharacters[player]
    if not charData then return false end

    local itemId = charData.Backpack[backpackSlot]
    if not itemId then return false end

    -- Get drop position
    local dropPos = Vector3.new(0, 3, 0)
    if player.Character then
        local rootPart = player.Character:FindFirstChild("HumanoidRootPart")
        if rootPart then
            dropPos = rootPart.Position + Vector3.new(0, 0, 3)
        end
    end

    -- Remove from backpack
    charData.Backpack[backpackSlot] = nil

    -- Create loot bag (player-dropped items are always public)
    local bagType = determineBagType({itemId})

    local bag = {
        Id = Utilities.GenerateUID(),
        Position = dropPos,
        Items = {itemId},
        SpawnTime = tick(),
        Lifetime = LOOT_BAG_LIFETIME,
        BagType = bagType,
        Soulbound = false,  -- Dropped items are always public
        DamageContributors = {},
    }

    LootManager.LootBags[bag.Id] = bag

    -- Notify clients
    Remotes.Events.LootDrop:FireAllClients({
        Id = bag.Id,
        Position = dropPos,
        Items = {itemId},
        BagType = bagType,
        Soulbound = false,
    })

    -- Update inventory
    -- Build backpack with false placeholders for empty slots (Roblox doesn't serialize nil)
    local backpackData = {}
    for i = 1, 8 do
        backpackData[i] = charData.Backpack[i] or false
    end
    Remotes.Events.InventoryUpdate:FireClient(player, {
        Backpack = backpackData,
    })

    return true
end

-- Use a potion
function LootManager.UsePotion(player, potionType)
    local PM = getPlayerManager()
    local charData = PM.ActiveCharacters[player]
    if not charData then return false end

    if potionType == "Health" then
        if charData.HealthPotions <= 0 then return false end

        local effectiveStats = PM.GetEffectiveStats(player)
        if charData.CurrentHP >= effectiveStats.MaxHP then return false end

        charData.HealthPotions = charData.HealthPotions - 1

        -- Calculate actual heal amount (capped at max HP)
        local healAmount = math.min(100, effectiveStats.MaxHP - charData.CurrentHP)
        PM.HealPlayer(player, 100)

        -- Show "+X HP" above player head (RotMG style)
        Remotes.Events.DamageNumber:FireClient(player, {
            StatusType = "HP",
            Amount = healAmount,
        })

        Remotes.Events.InventoryUpdate:FireClient(player, {
            HealthPotions = charData.HealthPotions,
        })

        return true

    elseif potionType == "Mana" then
        if charData.ManaPotions <= 0 then return false end

        local effectiveStats = PM.GetEffectiveStats(player)
        if charData.CurrentMP >= effectiveStats.MaxMP then return false end

        charData.ManaPotions = charData.ManaPotions - 1

        -- Calculate actual mana restored (capped at max MP)
        local manaAmount = math.min(100, effectiveStats.MaxMP - charData.CurrentMP)
        charData.CurrentMP = math.min(effectiveStats.MaxMP, charData.CurrentMP + 100)

        -- Show "+X MP" above player head (RotMG style)
        Remotes.Events.DamageNumber:FireClient(player, {
            StatusType = "MP",
            Amount = manaAmount,
        })

        Remotes.Events.StatUpdate:FireClient(player, {
            CurrentMP = charData.CurrentMP,
        })
        Remotes.Events.InventoryUpdate:FireClient(player, {
            ManaPotions = charData.ManaPotions,
        })

        return true
    end

    return false
end

--============================================================================
-- ROTMG-STYLE SLOT SYSTEM
-- Slot mapping (1-indexed for Lua):
--   Slot 1 = Equipment.Weapon
--   Slot 2 = Equipment.Ability
--   Slot 3 = Equipment.Armor
--   Slot 4 = Equipment.Ring
--   Slots 5-12 = Backpack[1-8]
--============================================================================

local SLOT_NAMES = {"Weapon", "Ability", "Armor", "Ring"}
local NUM_EQUIPMENT_SLOTS = 4
local NUM_INVENTORY_SLOTS = 8

-- Get item from unified slot index
local function getItemFromSlot(charData, slotIndex)
    if slotIndex <= NUM_EQUIPMENT_SLOTS then
        return charData.Equipment[SLOT_NAMES[slotIndex]]
    else
        return charData.Backpack[slotIndex - NUM_EQUIPMENT_SLOTS]
    end
end

-- Set item in unified slot index
local function setItemInSlot(charData, slotIndex, itemId)
    if slotIndex <= NUM_EQUIPMENT_SLOTS then
        charData.Equipment[SLOT_NAMES[slotIndex]] = itemId
    else
        charData.Backpack[slotIndex - NUM_EQUIPMENT_SLOTS] = itemId
    end
end

-- Check if an item can be placed in a slot (slot type validation)
local function canPlaceInSlot(className, slotIndex, itemId)
    -- Inventory slots accept any item
    if slotIndex > NUM_EQUIPMENT_SLOTS then
        return true
    end

    -- Empty slot always valid
    if not itemId then
        return true
    end

    -- Get item data
    local item = ItemDatabase.GetItem(itemId)
    if not item then
        return false
    end

    -- Get item's slot type
    local itemSlotType = item.SlotType
    if not itemSlotType then
        return false
    end

    -- Use ClassDatabase to validate
    return ClassDatabase.CanEquipInSlot(className, slotIndex, itemSlotType)
end

-- Swap two inventory slots (RotMG InvSwap)
-- fromSlot/toSlot are 1-indexed (1-4 equipment, 5-12 inventory)
function LootManager.SwapInventory(player, fromSlot, toSlot)
    local PM = getPlayerManager()
    local charData = PM.ActiveCharacters[player]
    if not charData then return false, "No character" end

    -- Validate slot indices
    local totalSlots = NUM_EQUIPMENT_SLOTS + NUM_INVENTORY_SLOTS
    if fromSlot < 1 or fromSlot > totalSlots then
        return false, "Invalid from slot"
    end
    if toSlot < 1 or toSlot > totalSlots then
        return false, "Invalid to slot"
    end

    -- Get items in both slots
    local fromItem = getItemFromSlot(charData, fromSlot)
    local toItem = getItemFromSlot(charData, toSlot)

    -- Check if swap is valid (both items can go in their destination slots)
    local className = charData.Class
    if not canPlaceInSlot(className, toSlot, fromItem) then
        return false, "Cannot equip item in target slot"
    end
    if not canPlaceInSlot(className, fromSlot, toItem) then
        return false, "Cannot equip item in source slot"
    end

    -- Perform the swap
    setItemInSlot(charData, fromSlot, toItem)
    setItemInSlot(charData, toSlot, fromItem)

    -- Build explicit backpack array - use false as placeholder for empty slots
    -- (Roblox doesn't serialize nil values in arrays)
    local backpackData = {}
    for i = 1, NUM_INVENTORY_SLOTS do
        backpackData[i] = charData.Backpack[i] or false
    end

    -- Send full inventory update to client
    Remotes.Events.InventoryUpdate:FireClient(player, {
        Equipment = charData.Equipment,
        Backpack = backpackData,
    })

    -- If equipment changed, update stats
    if fromSlot <= NUM_EQUIPMENT_SLOTS or toSlot <= NUM_EQUIPMENT_SLOTS then
        local effectiveStats = PM.GetEffectiveStats(player)
        Remotes.Events.StatUpdate:FireClient(player, {
            Stats = effectiveStats,
            CurrentHP = charData.CurrentHP,
            MaxHP = effectiveStats.MaxHP,
            CurrentMP = charData.CurrentMP,
            MaxMP = effectiveStats.MaxMP,
        })

        -- Update humanoid walk speed if equipment affects SPD
        if player.Character then
            local humanoid = player.Character:FindFirstChild("Humanoid")
            if humanoid then
                humanoid.WalkSpeed = Utilities.GetWalkSpeed(effectiveStats.Speed)
            end
        end

        PM.ReplicateStatsToCharacter(player)
    end

    return true
end

-- Get full inventory data for client
function LootManager.GetInventoryData(player)
    local PM = getPlayerManager()
    local charData = PM.ActiveCharacters[player]
    if not charData then return nil end

    return {
        Equipment = charData.Equipment,
        Backpack = charData.Backpack,
        HealthPotions = charData.HealthPotions,
        ManaPotions = charData.ManaPotions,
        Class = charData.Class,
    }
end

-- Clean up old loot bags
local function cleanupOldBags()
    local currentTime = tick()
    local toRemove = {}

    for id, bag in pairs(LootManager.LootBags) do
        if currentTime - bag.SpawnTime > bag.Lifetime then
            table.insert(toRemove, id)
        end
    end

    for _, id in ipairs(toRemove) do
        LootManager.LootBags[id] = nil
        Remotes.Events.LootPickup:FireAllClients({
            BagId = id,
            Removed = true,
        })
    end
end

-- Initialize
function LootManager.Init()
    -- Handle loot pickup requests
    Remotes.Events.RequestLoot.OnServerEvent:Connect(function(player, bagId)
        local success, errorMsg = LootManager.TryPickupLoot(player, bagId)
        if not success and errorMsg then
            Remotes.Events.InventoryError:FireClient(player, {
                Message = errorMsg
            })
        end
    end)

    -- Handle SwapInventory (RotMG-style slot swap)
    Remotes.Events.SwapInventory.OnServerEvent:Connect(function(player, fromSlot, toSlot)
        local success, errorMsg = LootManager.SwapInventory(player, fromSlot, toSlot)
        if not success then
            Remotes.Events.InventoryError:FireClient(player, {
                Message = errorMsg or "Swap failed"
            })
        end
    end)

    -- Handle equip requests (legacy - use SwapInventory instead)
    Remotes.Events.EquipItem.OnServerEvent:Connect(function(player, backpackSlot)
        LootManager.EquipItem(player, backpackSlot)
    end)

    -- Handle drop requests
    Remotes.Events.DropItem.OnServerEvent:Connect(function(player, backpackSlot)
        LootManager.DropItem(player, backpackSlot)
    end)

    -- Handle potion use
    Remotes.Events.UsePotion.OnServerEvent:Connect(function(player, potionType)
        LootManager.UsePotion(player, potionType)
    end)

    -- Handle stat potion use
    Remotes.Events.UseStatPotion.OnServerEvent:Connect(function(player, backpackSlot)
        local PM = getPlayerManager()
        PM.UseStatPotion(player, backpackSlot)
    end)

    -- Handle bag contents request (for late-arriving players)
    Remotes.Events.GetBagContents.OnServerEvent:Connect(function(player, bagId)
        local bag = LootManager.LootBags[bagId]
        if bag then
            -- Check if player can see this bag (soulbound check)
            if bag.Soulbound and not bag.DamageContributors[player] then
                return -- Don't send contents to non-contributors
            end
            Remotes.Events.LootBagContents:FireClient(player, {
                BagId = bagId,
                Items = bag.Items,
                BagType = bag.BagType,
                Soulbound = bag.Soulbound,
            })
        end
    end)

    -- Cleanup timer
    RunService.Heartbeat:Connect(function()
        -- Check every ~5 seconds (use frame counting)
    end)

    task.spawn(function()
        while true do
            task.wait(5)
            cleanupOldBags()
        end
    end)

    print("[LootManager] Initialized")
end

return LootManager
