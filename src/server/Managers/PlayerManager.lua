--[[
    PlayerManager.lua
    Handles player data, stats, spawning, and character management
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Note: CharacterAutoLoads = false is set in Main.server.lua

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local Utilities = require(Shared.Utilities)
local ClassDatabase = require(Shared.ClassDatabase)
local ItemDatabase = require(Shared.ItemDatabase)
local Remotes = require(Shared.Remotes)
local WorldGen = require(Shared.WorldGen)
local LazyLoader = require(Shared.LazyLoader)

-- Lazy load managers using LazyLoader utility
local getDataManager = LazyLoader.create(script.Parent, "DataManager")
local getMovementValidator = LazyLoader.create(script.Parent, "MovementValidator")
local getRegenManager = LazyLoader.create(script.Parent, "RegenManager")

local PlayerManager = {}

-- Active player data cache
PlayerManager.PlayerData = {}  -- [player] = data
PlayerManager.ActiveCharacters = {}  -- [player] = characterData
PlayerManager.SpawnAllowed = {}  -- [player] = bool (prevents unwanted auto-spawns during loading)
PlayerManager.GodmodeEnabled = {}  -- [player] = true/false (debug testing)

--============================================================================
-- ADMIN SYSTEM
-- Add your Roblox UserIds to this list to grant admin privileges
--============================================================================
local ADMIN_USER_IDS = {
    -- Add admin UserIds here, e.g.:
    -- 123456789,  -- YourUsername
    -- 987654321,  -- AnotherAdmin
}

-- Check if a player is an admin
local function isAdmin(player)
    if not player then return false end

    -- Check UserId against admin list
    for _, adminId in ipairs(ADMIN_USER_IDS) do
        if player.UserId == adminId then
            return true
        end
    end

    -- Also allow Studio testing (optional - remove for production)
    if game:GetService("RunService"):IsStudio() then
        return true  -- All players are admin in Studio for testing
    end

    return false
end

-- Export for other modules
PlayerManager.IsAdmin = isAdmin

-- Default account data for new players
local function createDefaultAccountData()
    return {
        Version = Constants.DataStore.DATA_VERSION,
        Characters = {},  -- Character slots
        Vault = {},
        AccountStats = {
            TotalFame = 0,
            HighestLevelReached = 1,
            TotalDeaths = 0,
            EnemiesKilled = 0,
        },
        UnlockedClasses = ClassDatabase.GetDefaultUnlockedClasses(),
    }
end

-- Create a new character
local function createNewCharacter(className)
    local classData = ClassDatabase.GetClass(className)
    if not classData then
        warn("[PlayerManager] Invalid class: " .. tostring(className))
        return nil
    end

    -- Get base stats from new structure
    local baseStats = ClassDatabase.GetBaseStats(className)

    local character = {
        CharacterId = Utilities.GenerateUID(),
        Class = className,
        CreatedAt = os.time(),

        Level = 1,
        XP = 0,
        TotalXP = 0,

        -- Copy base stats from class (using new structure)
        Stats = baseStats,

        -- Current HP/MP (use HP/MP instead of MaxHP/MaxMP)
        CurrentHP = baseStats.HP,
        CurrentMP = baseStats.MP,

        -- Equipment (start with starter items)
        Equipment = {
            Weapon = classData.StarterWeapon,
            Ability = classData.StarterAbility,
            Armor = classData.StarterArmor,
            Ring = nil,
        },

        -- Inventory
        Backpack = {},
        HealthPotions = 1,
        ManaPotions = 1,

        -- Fame tracking
        EnemiesKilled = 0,
        GodKills = 0,
    }

    return character
end

-- Calculate effective stats (base + equipment)
-- Returns stats in a format compatible with the old system for backwards compatibility
function PlayerManager.GetEffectiveStats(player)
    local charData = PlayerManager.ActiveCharacters[player]
    if not charData then return nil end

    -- Debug: Log charData.Stats (disabled - too verbose)
    -- if charData.Stats then
    --     print("[DEBUG] charData.Stats for " .. player.Name .. ":")
    --     for k, v in pairs(charData.Stats) do
    --         print("  " .. tostring(k) .. " = " .. tostring(v))
    --     end
    -- else
    --     warn("[DEBUG] charData.Stats is nil!")
    -- end

    local stats = Utilities.DeepCopy(charData.Stats)

    -- Add equipment bonuses
    for slot, itemId in pairs(charData.Equipment) do
        if itemId then
            local item = ItemDatabase.GetItem(itemId)
            if item and item.Stats then
                for statName, value in pairs(item.Stats) do
                    if stats[statName] then
                        stats[statName] = stats[statName] + value
                    else
                        stats[statName] = value
                    end
                end
            end
        end
    end

    -- Add convenience aliases for backwards compatibility
    stats.MaxHP = stats.HP
    stats.MaxMP = stats.MP

    return stats
end

-- Replicate stats as Attributes on Character for zero-latency client reads
-- This is crucial for SPD (movement) and DEX (fire rate) to feel responsive
function PlayerManager.ReplicateStatsToCharacter(player)
    local character = player.Character
    if not character then
        warn("[PlayerManager] ReplicateStats: No character for " .. player.Name)
        return
    end

    local charData = PlayerManager.ActiveCharacters[player]
    if not charData then
        warn("[PlayerManager] ReplicateStats: No charData for " .. player.Name)
        return
    end

    local effectiveStats = PlayerManager.GetEffectiveStats(player)
    if not effectiveStats then
        warn("[PlayerManager] ReplicateStats: No effectiveStats for " .. player.Name)
        return
    end

    -- Debug: Print stats being replicated (disabled - too verbose)
    -- print("[PlayerManager] !!! Replicating stats for " .. player.Name .. " !!!")
    -- print("  HP=" .. tostring(effectiveStats.HP) .. ", ATT=" .. tostring(effectiveStats.Attack) .. ", DEX=" .. tostring(effectiveStats.Dexterity))
    -- print("  CurrentHP=" .. tostring(charData.CurrentHP) .. ", CurrentMP=" .. tostring(charData.CurrentMP))

    -- Set all stats as Attributes on the Character
    -- Clients can read these instantly with :GetAttribute()
    character:SetAttribute("HP", effectiveStats.HP)
    character:SetAttribute("MP", effectiveStats.MP)
    character:SetAttribute("Attack", effectiveStats.Attack)
    character:SetAttribute("Defense", effectiveStats.Defense)
    character:SetAttribute("Speed", effectiveStats.Speed)
    character:SetAttribute("Dexterity", effectiveStats.Dexterity)
    character:SetAttribute("Vitality", effectiveStats.Vitality)
    character:SetAttribute("Wisdom", effectiveStats.Wisdom)

    -- Also set current HP/MP for HUD
    character:SetAttribute("CurrentHP", charData.CurrentHP)
    character:SetAttribute("CurrentMP", charData.CurrentMP)

    -- Set level for display
    character:SetAttribute("Level", charData.Level)
    character:SetAttribute("Class", charData.Class)

    -- Verify attributes were set (disabled - too verbose)
    -- print("[PlayerManager] Attributes set. Verifying:")
    -- print("  Character HP Attr=" .. tostring(character:GetAttribute("HP")))
    -- print("  Character Attack Attr=" .. tostring(character:GetAttribute("Attack")))
end

-- Get equipped weapon data
function PlayerManager.GetEquippedWeapon(player)
    local charData = PlayerManager.ActiveCharacters[player]
    if not charData or not charData.Equipment.Weapon then
        return nil
    end
    return ItemDatabase.GetItem(charData.Equipment.Weapon)
end

-- Apply damage to player (using RotMG DEF formula)
function PlayerManager.DamagePlayer(player, rawDamage)
    -- Debug logging disabled for performance
    -- print("[PlayerManager] DamagePlayer called for " .. player.Name .. " with rawDamage=" .. tostring(rawDamage))

    local charData = PlayerManager.ActiveCharacters[player]
    if not charData then
        warn("[PlayerManager] DamagePlayer: No charData for " .. player.Name)
        return 0
    end

    -- Godmode check (for testing)
    if PlayerManager.GodmodeEnabled[player] then
        -- print("[PlayerManager] DamagePlayer: Godmode enabled, no damage")
        return 0  -- No damage taken
    end

    local effectiveStats = PlayerManager.GetEffectiveStats(player)
    if not effectiveStats then
        warn("[PlayerManager] DamagePlayer: No effectiveStats!")
        return 0
    end

    -- print("[PlayerManager] DamagePlayer: CurrentHP before=" .. tostring(charData.CurrentHP) .. " DEF=" .. tostring(effectiveStats.Defense))

    -- Use RotMG DEF formula: damage - DEF, with 15% minimum
    local actualDamage = math.floor(Utilities.CalculateDamageTaken(rawDamage, effectiveStats.Defense))

    charData.CurrentHP = math.max(0, charData.CurrentHP - actualDamage)

    -- Notify RegenManager that player took damage (enters combat state)
    getRegenManager().OnPlayerTookDamage(player)

    -- print("[PlayerManager] DamagePlayer: actualDamage=" .. tostring(actualDamage) .. " CurrentHP after=" .. tostring(charData.CurrentHP))

    -- Update character attribute for instant client feedback
    if player.Character then
        player.Character:SetAttribute("CurrentHP", charData.CurrentHP)
    end

    -- Send stat update to client
    Remotes.Events.StatUpdate:FireClient(player, {
        CurrentHP = charData.CurrentHP,
        MaxHP = effectiveStats.MaxHP,
    })

    -- Check for death
    if charData.CurrentHP <= 0 then
        print("[PlayerManager] DamagePlayer: HP reached 0, triggering death!")
        PlayerManager.OnPlayerDeath(player)
    end

    return actualDamage
end

-- Heal player
function PlayerManager.HealPlayer(player, amount)
    local charData = PlayerManager.ActiveCharacters[player]
    if not charData then return end

    local effectiveStats = PlayerManager.GetEffectiveStats(player)
    charData.CurrentHP = math.min(effectiveStats.MaxHP, charData.CurrentHP + amount)

    Remotes.Events.StatUpdate:FireClient(player, {
        CurrentHP = charData.CurrentHP,
        MaxHP = effectiveStats.MaxHP,
    })
end

-- Use a stat potion (permanently increases a stat)
function PlayerManager.UseStatPotion(player, backpackSlot)
    local charData = PlayerManager.ActiveCharacters[player]
    if not charData then return false, "No character" end

    -- Get item from backpack
    local itemId = charData.Backpack[backpackSlot]
    if not itemId then return false, "Empty slot" end

    local item = ItemDatabase.GetItem(itemId)
    if not item then return false, "Item not found" end

    -- Check if it's a stat potion
    if item.Subtype ~= "StatPotion" or not item.StatBoost then
        return false, "Not a stat potion"
    end

    local statName = item.StatBoost.Stat
    local amount = item.StatBoost.Amount or 1

    -- Check if stat exists
    if charData.Stats[statName] == nil then
        return false, "Invalid stat"
    end

    -- Get stat cap
    local cap = ClassDatabase.GetStatCap(charData.Class, statName)
    if not cap then
        return false, "No cap defined"
    end

    -- Check if already at max
    local currentStat = charData.Stats[statName]
    if currentStat >= cap then
        Remotes.Events.Notification:FireClient(player, {
            Message = statName .. " is already at max!",
            Type = "warning"
        })
        return false, "Already at max"
    end

    -- Apply stat boost (respect cap)
    local newValue = math.min(currentStat + amount, cap)
    local actualGain = newValue - currentStat
    charData.Stats[statName] = newValue

    -- Remove potion from backpack
    charData.Backpack[backpackSlot] = nil

    -- Update Current HP/MP if those were boosted
    if statName == "HP" or statName == "MaxHP" then
        charData.CurrentHP = math.min(charData.CurrentHP + actualGain, newValue)
    elseif statName == "MP" or statName == "MaxMP" then
        charData.CurrentMP = math.min(charData.CurrentMP + actualGain, newValue)
    end

    -- Update humanoid walk speed if Speed changed
    if statName == "Speed" and player.Character then
        local humanoid = player.Character:FindFirstChild("Humanoid")
        if humanoid then
            humanoid.WalkSpeed = Utilities.GetWalkSpeed(newValue)
        end
        -- Update movement validator with new max speed
        getMovementValidator().UpdateMaxSpeed(player, newValue)
    end

    -- Replicate stats to character attributes
    PlayerManager.ReplicateStatsToCharacter(player)

    -- Send updated stats to client
    local effectiveStats = PlayerManager.GetEffectiveStats(player)
    Remotes.Events.StatUpdate:FireClient(player, {
        CurrentHP = charData.CurrentHP,
        MaxHP = effectiveStats.MaxHP,
        CurrentMP = charData.CurrentMP,
        MaxMP = effectiveStats.MaxMP,
        Stats = effectiveStats,
    })

    -- Build backpack with false placeholders for empty slots
    local backpackData = {}
    for i = 1, 8 do
        backpackData[i] = charData.Backpack[i] or false
    end
    Remotes.Events.InventoryUpdate:FireClient(player, {
        Backpack = backpackData,
    })

    -- Notify success
    local maxedText = newValue >= cap and " (MAXED!)" or ""
    Remotes.Events.Notification:FireClient(player, {
        Message = "+" .. actualGain .. " " .. statName .. maxedText,
        Type = "success"
    })

    print("[PlayerManager] " .. player.Name .. " used " .. item.Name .. ": +" .. actualGain .. " " .. statName .. " (now " .. newValue .. "/" .. cap .. ")")

    return true
end

-- Add XP to player
function PlayerManager.AddXP(player, amount)
    local charData = PlayerManager.ActiveCharacters[player]
    if not charData then return end

    if charData.Level >= Constants.Leveling.MAX_LEVEL then
        return  -- Already max level
    end

    charData.TotalXP = charData.TotalXP + amount
    charData.XP = charData.XP + amount

    -- Show XP gain above player head (RotMG style)
    Remotes.Events.DamageNumber:FireClient(player, {
        StatusType = "XP",
        Amount = amount,
    })

    -- Check for level up
    local xpNeeded = Utilities.GetXPForLevel(charData.Level + 1)
    while charData.XP >= xpNeeded and charData.Level < Constants.Leveling.MAX_LEVEL do
        charData.XP = charData.XP - xpNeeded
        charData.Level = charData.Level + 1

        -- Roll stat gains using ClassDatabase (respects Growth ranges and Caps)
        local gains = {}
        local className = charData.Class
        local statNames = {"HP", "MP", "Attack", "Defense", "Speed", "Dexterity", "Vitality", "Wisdom"}

        for _, statName in ipairs(statNames) do
            local gain = ClassDatabase.RollStatGrowth(className, statName)
            if gain > 0 then
                local currentStat = charData.Stats[statName] or 0
                local cap = ClassDatabase.GetStatCap(className, statName) or 999

                -- Apply gain but respect cap
                local newValue = math.min(currentStat + gain, cap)
                local actualGain = newValue - currentStat

                if actualGain > 0 then
                    charData.Stats[statName] = newValue
                    gains[statName] = actualGain
                end
            end
        end

        -- Heal on level up
        local effectiveStats = PlayerManager.GetEffectiveStats(player)
        charData.CurrentHP = effectiveStats.MaxHP
        charData.CurrentMP = effectiveStats.MaxMP

        -- Replicate stats to character attributes
        PlayerManager.ReplicateStatsToCharacter(player)

        -- Notify client of level up
        Remotes.Events.LevelUp:FireClient(player, {
            NewLevel = charData.Level,
            StatGains = gains,
        })

        print("[PlayerManager] " .. player.Name .. " leveled up to " .. charData.Level)

        xpNeeded = Utilities.GetXPForLevel(charData.Level + 1)
    end

    -- Send XP update
    local effectiveStats = PlayerManager.GetEffectiveStats(player)
    Remotes.Events.StatUpdate:FireClient(player, {
        Level = charData.Level,
        XP = charData.XP,
        XPNeeded = Utilities.GetXPForLevel(charData.Level + 1),
        CurrentHP = charData.CurrentHP,
        MaxHP = effectiveStats.MaxHP,
        CurrentMP = charData.CurrentMP,
        MaxMP = effectiveStats.MaxMP,
        Stats = effectiveStats,
    })
end

-- Handle player death (permadeath)
function PlayerManager.OnPlayerDeath(player)
    print("[PlayerManager] !!! OnPlayerDeath called for " .. player.Name .. " !!!")

    local charData = PlayerManager.ActiveCharacters[player]
    if not charData then
        warn("[PlayerManager] OnPlayerDeath: No charData for " .. player.Name)
        return
    end

    local accountData = PlayerManager.PlayerData[player]
    if not accountData then
        warn("[PlayerManager] OnPlayerDeath: No accountData for " .. player.Name)
        return
    end

    print("[PlayerManager] " .. player.Name .. " died! (Permadeath)")

    -- Calculate fame earned
    local fame = charData.Level * 10 + charData.EnemiesKilled

    -- Update account stats
    accountData.AccountStats.TotalFame = accountData.AccountStats.TotalFame + fame
    accountData.AccountStats.TotalDeaths = accountData.AccountStats.TotalDeaths + 1
    if charData.Level > accountData.AccountStats.HighestLevelReached then
        accountData.AccountStats.HighestLevelReached = charData.Level
    end

    -- Remove character from slot (permadeath)
    for i, char in ipairs(accountData.Characters) do
        if char.CharacterId == charData.CharacterId then
            table.remove(accountData.Characters, i)
            break
        end
    end

    -- Clear active character
    PlayerManager.ActiveCharacters[player] = nil

    -- Notify client
    print("[PlayerManager] Firing PlayerDeath event to " .. player.Name .. " with fame=" .. fame)
    Remotes.Events.PlayerDeath:FireClient(player, {
        FameEarned = fame,
        Level = charData.Level,
        Class = charData.Class,
        EnemiesKilled = charData.EnemiesKilled,
    })
    print("[PlayerManager] PlayerDeath event fired successfully")

    -- Respawn character (they'll need to select a new one)
    if player.Character then
        player.Character:Destroy()
    end
end

-- Spawn player character in world
function PlayerManager.SpawnCharacter(player)
    print("[PlayerManager] !!! SpawnCharacter called for " .. player.Name .. " !!!")

    local charData = PlayerManager.ActiveCharacters[player]
    if not charData then
        warn("[PlayerManager] SpawnCharacter: No charData for " .. player.Name)
        return
    end

    print("[PlayerManager] SpawnCharacter: charData exists, Class=" .. tostring(charData.Class))
    print("[PlayerManager] SpawnCharacter: Stats exists=" .. tostring(charData.Stats ~= nil))

    -- Ensure Stats exists (might be missing from old saved data)
    if not charData.Stats then
        warn("[PlayerManager] SpawnCharacter: Stats is nil, creating defaults for " .. player.Name)
        local baseStats = ClassDatabase.GetBaseStats(charData.Class)
        if baseStats then
            charData.Stats = baseStats
            charData.CurrentHP = charData.CurrentHP or baseStats.HP
            charData.CurrentMP = charData.CurrentMP or baseStats.MP
            print("[PlayerManager] SpawnCharacter: Created default stats")
        else
            warn("[PlayerManager] SpawnCharacter: Could not get base stats for class: " .. tostring(charData.Class))
            return
        end
    else
        print("[PlayerManager] SpawnCharacter: Stats.HP=" .. tostring(charData.Stats.HP) .. " Stats.Attack=" .. tostring(charData.Stats.Attack))
    end

    print("[PlayerManager] SpawnCharacter: CurrentHP=" .. tostring(charData.CurrentHP) .. " CurrentMP=" .. tostring(charData.CurrentMP))

    -- Allow spawning for this player (prevents auto-destroy of this intentional spawn)
    PlayerManager.SpawnAllowed[player] = true

    -- Load character
    print("[PlayerManager] SpawnCharacter: Calling LoadCharacter...")
    player:LoadCharacter()

    -- Wait for character
    local character = player.Character or player.CharacterAdded:Wait()
    local humanoid = character:WaitForChild("Humanoid")

    -- Apply stats
    local effectiveStats = PlayerManager.GetEffectiveStats(player)
    if not effectiveStats then
        warn("[PlayerManager] SpawnCharacter: GetEffectiveStats returned nil!")
        return
    end
    humanoid.MaxHealth = effectiveStats.MaxHP
    humanoid.Health = charData.CurrentHP

    -- Use RotMG SPD formula for walk speed
    humanoid.WalkSpeed = Utilities.GetWalkSpeed(effectiveStats.Speed)

    -- Replicate stats as Attributes for zero-latency client reads
    PlayerManager.ReplicateStatsToCharacter(player)

    -- Spawn in Nexus (safe hub zone)
    task.wait(0.1)  -- Wait for character to fully load
    local spawnPos = Constants.Nexus.CENTER + Constants.Nexus.SPAWN_OFFSET
    if character.PrimaryPart then
        character:SetPrimaryPartCFrame(CFrame.new(spawnPos))
    elseif character:FindFirstChild("HumanoidRootPart") then
        character.HumanoidRootPart.CFrame = CFrame.new(spawnPos)
    end
    print("[PlayerManager] Spawned " .. player.Name .. " in Nexus: " .. tostring(spawnPos))

    -- Send initial stats to client
    Remotes.Events.StatUpdate:FireClient(player, {
        Level = charData.Level,
        XP = charData.XP,
        XPNeeded = Utilities.GetXPForLevel(charData.Level + 1),
        CurrentHP = charData.CurrentHP,
        MaxHP = effectiveStats.MaxHP,
        CurrentMP = charData.CurrentMP,
        MaxMP = effectiveStats.MaxMP,
        Stats = effectiveStats,
        Class = charData.Class,
    })

    -- Send initial inventory state
    -- Build backpack with false placeholders for empty slots (Roblox doesn't serialize nil)
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

    -- Hide loading screen after everything is ready
    task.delay(0.3, function()
        Remotes.Events.HideLoading:FireClient(player)
    end)
end

-- Initialize
function PlayerManager.Init()
    -- Handle remote functions
    Remotes.Functions.GetCharacterList.OnServerInvoke = function(player)
        -- Wait for player data to be loaded (up to 5 seconds)
        local waitTime = 0
        while not PlayerManager.PlayerData[player] and waitTime < 5 do
            task.wait(0.1)
            waitTime = waitTime + 0.1
        end

        local accountData = PlayerManager.PlayerData[player]
        if not accountData then return nil end

        -- Ensure UnlockedClasses has a valid default
        if not accountData.UnlockedClasses or #accountData.UnlockedClasses == 0 then
            accountData.UnlockedClasses = ClassDatabase.GetDefaultUnlockedClasses()
        end

        return {
            Characters = accountData.Characters,
            UnlockedClasses = accountData.UnlockedClasses,
        }
    end

    Remotes.Functions.CreateCharacter.OnServerInvoke = function(player, className)
        local accountData = PlayerManager.PlayerData[player]
        if not accountData then return false, "No account data" end

        -- Check if class is unlocked
        if not table.find(accountData.UnlockedClasses, className) then
            return false, "Class not unlocked"
        end

        -- Create character
        local newChar = createNewCharacter(className)
        if not newChar then
            return false, "Failed to create character"
        end

        table.insert(accountData.Characters, newChar)
        return true, newChar.CharacterId
    end

    Remotes.Functions.SelectCharacter.OnServerInvoke = function(player, characterId)
        print("[SelectCharacter] !!! SelectCharacter called for " .. player.Name .. " with ID: " .. tostring(characterId))

        local accountData = PlayerManager.PlayerData[player]
        if not accountData then
            warn("[SelectCharacter] No account data for " .. player.Name)
            return false, "No account data"
        end

        -- Find character
        for _, char in ipairs(accountData.Characters) do
            if char.CharacterId == characterId then
                -- Debug: Print character data
                print("[SelectCharacter] Found character for", player.Name)
                print("  CharacterId:", char.CharacterId)
                print("  Class:", char.Class)
                print("  Level:", char.Level)

                -- CRITICAL: Ensure Stats exists and has valid values
                local needsStats = false
                if not char.Stats then
                    print("[SelectCharacter] Stats is NIL - will create defaults")
                    needsStats = true
                elseif type(char.Stats) ~= "table" then
                    print("[SelectCharacter] Stats is not a table - will create defaults")
                    needsStats = true
                elseif not char.Stats.HP or char.Stats.HP == 0 then
                    print("[SelectCharacter] Stats.HP is nil or 0 - will create defaults")
                    needsStats = true
                end

                if needsStats then
                    warn("[SelectCharacter] Creating default stats for " .. player.Name)
                    local baseStats = ClassDatabase.GetBaseStats(char.Class or "Wizard")
                    if baseStats then
                        char.Stats = baseStats
                        char.CurrentHP = baseStats.HP
                        char.CurrentMP = baseStats.MP
                        print("[SelectCharacter] Created default stats - HP:", baseStats.HP, "Attack:", baseStats.Attack)
                    else
                        warn("[SelectCharacter] CRITICAL: Failed to get base stats!")
                        return false, "Failed to get base stats"
                    end
                end

                -- Print current stats
                print("[SelectCharacter] Final character stats:")
                for k, v in pairs(char.Stats) do
                    print("    " .. tostring(k) .. " = " .. tostring(v))
                end
                print("  CurrentHP:", char.CurrentHP, "CurrentMP:", char.CurrentMP)

                PlayerManager.ActiveCharacters[player] = char

                -- Spawn character in separate thread (LoadCharacter yields)
                task.spawn(function()
                    PlayerManager.SpawnCharacter(player)
                end)

                -- Tell client to hide character select and show HUD
                Remotes.Events.HideCharacterSelect:FireClient(player)
                return true
            end
        end

        warn("[SelectCharacter] Character not found with ID: " .. tostring(characterId))
        return false, "Character not found"
    end

    -- Handle return to character select (after death or manual request)
    Remotes.Events.ReturnToCharSelect.OnServerEvent:Connect(function(player)
        print("[PlayerManager] ReturnToCharSelect received from " .. player.Name)

        local accountData = PlayerManager.PlayerData[player]
        if not accountData then
            warn("[PlayerManager] ReturnToCharSelect: No account data!")
            return
        end

        -- Clear active character
        PlayerManager.ActiveCharacters[player] = nil

        -- Destroy character if exists
        if player.Character then
            print("[PlayerManager] ReturnToCharSelect: Destroying character")
            player.Character:Destroy()
        end

        -- Ensure UnlockedClasses has a valid default
        local unlockedClasses = accountData.UnlockedClasses
        if not unlockedClasses or #unlockedClasses == 0 then
            unlockedClasses = ClassDatabase.GetDefaultUnlockedClasses()
            accountData.UnlockedClasses = unlockedClasses
        end

        print("[PlayerManager] ReturnToCharSelect: Sending ShowCharacterSelect with " .. #accountData.Characters .. " characters")

        -- Send updated character list
        Remotes.Events.ShowCharacterSelect:FireClient(player, {
            Characters = accountData.Characters,
            UnlockedClasses = unlockedClasses,
        })

        -- Hide loading screen after character select is shown
        task.delay(0.3, function()
            Remotes.Events.HideLoading:FireClient(player)
        end)
    end)

    -- Handle godmode toggle (debug testing)
    Remotes.Events.ToggleGodmode.OnServerEvent:Connect(function(player)
        -- SECURITY: Admin check required
        if not isAdmin(player) then
            warn("[SECURITY] Non-admin " .. player.Name .. " attempted to toggle godmode")
            return
        end

        PlayerManager.GodmodeEnabled[player] = not PlayerManager.GodmodeEnabled[player]
        local status = PlayerManager.GodmodeEnabled[player] and "ON" or "OFF"
        print("[Admin] " .. player.Name .. " godmode: " .. status)
    end)

    -- Handle admin commands
    Remotes.Events.AdminCommand.OnServerEvent:Connect(function(player, command, data)
        -- SECURITY: Admin check required
        if not isAdmin(player) then
            warn("[SECURITY] Non-admin " .. player.Name .. " attempted admin command: " .. tostring(command))
            return
        end

        local charData = PlayerManager.ActiveCharacters[player]
        if not charData then return end

        if command == "SetStat" then
            -- Set a specific stat
            local statName = data.Stat
            local value = data.Value
            if charData.Stats[statName] ~= nil then
                charData.Stats[statName] = math.max(0, math.floor(value))

                -- Update HP/MP current if max changed
                if statName == "HP" then
                    charData.CurrentHP = math.min(charData.CurrentHP, value)
                elseif statName == "MP" then
                    charData.CurrentMP = math.min(charData.CurrentMP, value)
                end

                -- Also update humanoid walk speed if Speed changed
                if statName == "Speed" and player.Character then
                    local humanoid = player.Character:FindFirstChild("Humanoid")
                    if humanoid then
                        humanoid.WalkSpeed = Utilities.GetWalkSpeed(value)
                    end
                    -- Update movement validator with new max speed
                    getMovementValidator().UpdateMaxSpeed(player, value)
                end

                PlayerManager.ReplicateStatsToCharacter(player)
                local effectiveStats = PlayerManager.GetEffectiveStats(player)
                Remotes.Events.StatUpdate:FireClient(player, {
                    CurrentHP = charData.CurrentHP,
                    MaxHP = effectiveStats.MaxHP,
                    CurrentMP = charData.CurrentMP,
                    MaxMP = effectiveStats.MaxMP,
                    Stats = effectiveStats,
                })
                print("[Admin] " .. player.Name .. " set " .. statName .. " to " .. value)
            end

        elseif command == "MaxStats" then
            -- Max all stats to their caps
            local className = charData.Class
            for statName, _ in pairs(charData.Stats) do
                local cap = ClassDatabase.GetStatCap(className, statName) or 75
                charData.Stats[statName] = cap
            end
            charData.CurrentHP = charData.Stats.HP
            charData.CurrentMP = charData.Stats.MP

            -- Update humanoid
            if player.Character then
                local humanoid = player.Character:FindFirstChild("Humanoid")
                if humanoid then
                    humanoid.MaxHealth = charData.Stats.HP
                    humanoid.Health = charData.Stats.HP
                    humanoid.WalkSpeed = Utilities.GetWalkSpeed(charData.Stats.Speed)
                end
                -- Update movement validator with new max speed
                getMovementValidator().UpdateMaxSpeed(player, charData.Stats.Speed)
            end

            PlayerManager.ReplicateStatsToCharacter(player)
            local effectiveStats = PlayerManager.GetEffectiveStats(player)
            Remotes.Events.StatUpdate:FireClient(player, {
                CurrentHP = charData.CurrentHP,
                MaxHP = effectiveStats.MaxHP,
                CurrentMP = charData.CurrentMP,
                MaxMP = effectiveStats.MaxMP,
                Stats = effectiveStats,
            })
            print("[Admin] " .. player.Name .. " maxed all stats")

        elseif command == "SetLevel" then
            local level = math.clamp(data.Level or 1, 1, Constants.Leveling.MAX_LEVEL)
            charData.Level = level
            charData.XP = 0

            PlayerManager.ReplicateStatsToCharacter(player)
            local effectiveStats = PlayerManager.GetEffectiveStats(player)
            Remotes.Events.StatUpdate:FireClient(player, {
                Level = charData.Level,
                XP = 0,
                XPNeeded = Utilities.GetXPForLevel(charData.Level + 1),
                Stats = effectiveStats,
            })
            print("[Admin] " .. player.Name .. " set level to " .. level)

        elseif command == "Heal" then
            local effectiveStats = PlayerManager.GetEffectiveStats(player)
            charData.CurrentHP = effectiveStats.MaxHP
            charData.CurrentMP = effectiveStats.MaxMP

            if player.Character then
                local humanoid = player.Character:FindFirstChild("Humanoid")
                if humanoid then
                    humanoid.Health = effectiveStats.MaxHP
                end
                player.Character:SetAttribute("CurrentHP", charData.CurrentHP)
                player.Character:SetAttribute("CurrentMP", charData.CurrentMP)
            end

            Remotes.Events.StatUpdate:FireClient(player, {
                CurrentHP = charData.CurrentHP,
                MaxHP = effectiveStats.MaxHP,
                CurrentMP = charData.CurrentMP,
                MaxMP = effectiveStats.MaxMP,
            })
            print("[Admin] " .. player.Name .. " healed to full")

        elseif command == "AddXP" then
            local amount = data.Amount or 1000
            PlayerManager.AddXP(player, amount)
            print("[Admin] " .. player.Name .. " gained " .. amount .. " XP")

        elseif command == "SpawnEnemy" then
            -- Lazy load EnemyManager to avoid circular dependency
            local EnemyManager = require(script.Parent.EnemyManager)
            local EnemyDatabase = require(Shared.EnemyDatabase)

            local enemyName = data.Enemy or "Pirate"
            local enemyDef = EnemyDatabase.Enemies[enemyName]
            if enemyDef and player.Character then
                local rootPart = player.Character:FindFirstChild("HumanoidRootPart")
                if rootPart then
                    local spawnPos = rootPart.Position + Vector3.new(10, 0, 0)
                    EnemyManager.SpawnEnemy(enemyDef, spawnPos)
                    print("[Admin] " .. player.Name .. " spawned " .. enemyName)
                end
            end

        elseif command == "Teleport" then
            if player.Character then
                local rootPart = player.Character:FindFirstChild("HumanoidRootPart")
                if rootPart then
                    local targetPos = data.Position or Vector3.new(0, 10, 0)
                    -- Grant immunity before teleport to avoid false flags
                    getMovementValidator().GrantImmunity(player, 1.0)
                    rootPart.CFrame = CFrame.new(targetPos)
                    print("[Admin] " .. player.Name .. " teleported to " .. tostring(targetPos))
                end
            end
        end
    end)

    -- Handle player joining
    Players.PlayerAdded:Connect(function(player)
        local DM = getDataManager()

        -- Track whether this player is allowed to spawn (prevents unwanted auto-spawns)
        -- NOTE: We keep CharacterAutoLoads = true because setting it to false breaks StarterGui scripts
        PlayerManager.SpawnAllowed[player] = false

        -- Set up handler to destroy auto-spawned characters until spawn is allowed
        local autoDestroyConnection
        autoDestroyConnection = player.CharacterAdded:Connect(function(character)
            if not PlayerManager.SpawnAllowed[player] then
                -- Destroy unwanted auto-spawn immediately
                task.defer(function()
                    if character and character.Parent and not PlayerManager.SpawnAllowed[player] then
                        character:Destroy()
                    end
                end)
            end
        end)

        -- Destroy any existing auto-spawned character
        if player.Character then
            player.Character:Destroy()
        end

        -- Load from DataStore (this can take several seconds)
        local loadedData = DM.LoadPlayerData(player)
        PlayerManager.PlayerData[player] = loadedData

        -- If no characters, create starter wizard
        if #loadedData.Characters == 0 then
            print("[PlayerManager] No characters found, creating Wizard...")
            local wizardChar = createNewCharacter("Wizard")
            if wizardChar then
                table.insert(loadedData.Characters, wizardChar)
                print("[PlayerManager] Created Wizard with stats:")
                for statName, value in pairs(wizardChar.Stats) do
                    print("  " .. statName .. " = " .. tostring(value))
                end
            else
                warn("[PlayerManager] Failed to create Wizard character!")
            end
        else
            print("[PlayerManager] Found " .. #loadedData.Characters .. " character(s)")
            local char = loadedData.Characters[1]
            if char.Stats then
                print("[PlayerManager] First character stats - HP: " .. tostring(char.Stats.HP) .. ", Attack: " .. tostring(char.Stats.Attack))
            else
                warn("[PlayerManager] First character has no Stats table!")
            end
        end

        -- Ensure UnlockedClasses has a valid default
        if not loadedData.UnlockedClasses or #loadedData.UnlockedClasses == 0 then
            loadedData.UnlockedClasses = ClassDatabase.GetDefaultUnlockedClasses()
        end

        -- NOTE: We don't fire ShowCharacterSelect here anymore.
        -- The client requests GetCharacterList itself and shows the UI.
        -- ShowCharacterSelect is only fired after death (ReturnToCharSelect handler).

        -- Start auto-save
        DM.StartAutoSave(player, function()
            return PlayerManager.PlayerData[player]
        end)

        -- Wait for character then set up
        local function setupCharacter(character)
            -- Apply stats when character spawns
            task.wait(0.1)
            local charData = PlayerManager.ActiveCharacters[player]

            -- If no character is selected, destroy this auto-spawned character
            -- (This happens after death when CharacterAutoLoads respawns the player)
            if not charData then
                print("[PlayerManager] setupCharacter: No active character selected, destroying auto-spawned character")
                if character and character.Parent then
                    character:Destroy()
                end
                return
            end

            -- Ensure Stats exists
            if not charData.Stats then
                warn("[PlayerManager] setupCharacter: Stats is nil, creating defaults")
                local baseStats = ClassDatabase.GetBaseStats(charData.Class)
                if baseStats then
                    charData.Stats = baseStats
                    charData.CurrentHP = charData.CurrentHP or baseStats.HP
                    charData.CurrentMP = charData.CurrentMP or baseStats.MP
                end
            end

            local effectiveStats = PlayerManager.GetEffectiveStats(player)
            if not effectiveStats then
                warn("[PlayerManager] setupCharacter: GetEffectiveStats returned nil!")
                return
            end

            local humanoid = character:FindFirstChild("Humanoid")
            if humanoid then
                humanoid.MaxHealth = effectiveStats.MaxHP
                humanoid.Health = charData.CurrentHP
                -- Use RotMG SPD formula
                humanoid.WalkSpeed = Utilities.GetWalkSpeed(effectiveStats.Speed)
            end

            -- Update movement validator with player's max speed
            getMovementValidator().UpdateMaxSpeed(player, effectiveStats.Speed)

            -- Teleport to Nexus (safe hub zone)
            local spawnPos = Constants.Nexus.CENTER + Constants.Nexus.SPAWN_OFFSET
            local rootPart = character:FindFirstChild("HumanoidRootPart")
            if rootPart then
                rootPart.CFrame = CFrame.new(spawnPos)
                print("[PlayerManager] Teleported " .. player.Name .. " to Nexus: " .. tostring(spawnPos))
            end

            -- Replicate stats as Attributes for zero-latency client reads
            PlayerManager.ReplicateStatsToCharacter(player)

            -- Also send via RemoteEvent as backup
            Remotes.Events.StatUpdate:FireClient(player, {
                Level = charData.Level,
                XP = charData.XP,
                XPNeeded = Utilities.GetXPForLevel(charData.Level + 1),
                CurrentHP = charData.CurrentHP,
                MaxHP = effectiveStats.MaxHP,
                CurrentMP = charData.CurrentMP,
                MaxMP = effectiveStats.MaxMP,
                Stats = effectiveStats,
                Class = charData.Class,
            })

            -- Send inventory state
            -- Build backpack with false placeholders for empty slots (Roblox doesn't serialize nil)
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

        player.CharacterAdded:Connect(setupCharacter)

        -- Handle character that already exists (race condition fix)
        if player.Character then
            task.spawn(function()
                setupCharacter(player.Character)
            end)
        end

        print("[PlayerManager] Player joined: " .. player.Name)
    end)

    -- Handle player leaving
    Players.PlayerRemoving:Connect(function(player)
        local DM = getDataManager()

        -- Final save before leaving
        if PlayerManager.PlayerData[player] then
            DM.SavePlayerData(player, PlayerManager.PlayerData[player])
        end

        DM.StopAutoSave(player)
        PlayerManager.PlayerData[player] = nil
        PlayerManager.ActiveCharacters[player] = nil
        PlayerManager.SpawnAllowed[player] = nil
        print("[PlayerManager] Player left: " .. player.Name)
    end)

    -- Initialize MovementValidator (anti-cheat)
    getMovementValidator().Init()

    print("[PlayerManager] Initialized")
end

return PlayerManager
