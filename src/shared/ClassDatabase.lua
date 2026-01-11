--[[
    ClassDatabase.lua
    Definitions for all player classes with RotMG-style stat progression

    Stat Structure:
    - Base: Starting value at level 1
    - Growth: {Min, Max} stat gain per level-up (random in range)
    - Cap: Maximum unboosted value (can be exceeded with equipment bonuses)

    Equipment Slots (RotMG style):
    - Slot 0: Weapon
    - Slot 1: Ability
    - Slot 2: Armor
    - Slot 3: Ring
    - Slots 4-11: Inventory (8 slots)
]]

local ClassDatabase = {}

--============================================================================
-- SLOT TYPE CONSTANTS (from RotMG ItemConstants.as)
-- These define what items can go in each equipment slot
--============================================================================
local SlotTypes = {
    NO_ITEM = -1,
    ALL_TYPE = 0,
    SWORD_TYPE = 1,
    DAGGER_TYPE = 2,
    BOW_TYPE = 3,
    TOME_TYPE = 4,
    SHIELD_TYPE = 5,
    LEATHER_TYPE = 6,
    PLATE_TYPE = 7,
    WAND_TYPE = 8,
    RING_TYPE = 9,
    POTION_TYPE = 10,
    SPELL_TYPE = 11,
    SEAL_TYPE = 12,
    CLOAK_TYPE = 13,
    ROBE_TYPE = 14,
    QUIVER_TYPE = 15,
    HELM_TYPE = 16,
    STAFF_TYPE = 17,
    POISON_TYPE = 18,
    SKULL_TYPE = 19,
    TRAP_TYPE = 20,
    ORB_TYPE = 21,
    PRISM_TYPE = 22,
    SCEPTER_TYPE = 23,
    KATANA_TYPE = 24,
    SHURIKEN_TYPE = 25,
}

ClassDatabase.SlotTypes = SlotTypes

ClassDatabase.Classes = {
    Wizard = {
        Name = "Wizard",
        Description = "High damage, fragile spellcaster",

        -- Equipment slot types (what this class can equip in each slot)
        -- Indices: [1]=Weapon, [2]=Ability, [3]=Armor, [4]=Ring
        EquipmentSlotTypes = {
            SlotTypes.STAFF_TYPE,   -- Slot 0: Weapon
            SlotTypes.SPELL_TYPE,   -- Slot 1: Ability
            SlotTypes.ROBE_TYPE,    -- Slot 2: Armor
            SlotTypes.RING_TYPE,    -- Slot 3: Ring
        },

        -- RotMG-style stat definitions with Base/Growth/Cap
        Stats = {
            HP = {
                Base = 100,
                Growth = {20, 30},  -- Gain 20-30 HP per level
                Cap = 670,
            },
            MP = {
                Base = 100,
                Growth = {5, 15},
                Cap = 385,
            },
            Attack = {
                Base = 12,
                Growth = {1, 2},
                Cap = 75,  -- At 75 ATT = 200% damage multiplier
            },
            Defense = {
                Base = 0,
                Growth = {0, 0},  -- Wizards don't gain DEF naturally
                Cap = 25,
            },
            Speed = {
                Base = 10,
                Growth = {0, 2},
                Cap = 50,
            },
            Dexterity = {
                Base = 15,
                Growth = {0, 2},
                Cap = 75,  -- Max fire rate at 75 DEX
            },
            Vitality = {
                Base = 10,
                Growth = {0, 2},
                Cap = 40,  -- HP regen rate
            },
            Wisdom = {
                Base = 12,
                Growth = {1, 2},
                Cap = 75,  -- MP regen rate
            },
        },

        -- Equipment types
        WeaponType = "Staff",
        AbilityType = "Spell",
        ArmorType = "Robe",

        -- Special ability (RotMG BulletNova - fires 20 projectiles outward)
        Ability = {
            Name = "Magic Nova",
            ManaCost = 20,
            Cooldown = 1.0,
            Effect = "BulletNova",  -- Fire projectiles outward from target
            NumProjectiles = 20,    -- Standard spell fires 20 projectiles
            ProjectileSpeed = 16,   -- 16 tiles/second
            Range = 16,             -- 16 tile range
            Damage = {Min = 70, Max = 105},  -- Per projectile damage
        },

        -- Starting equipment IDs
        StarterWeapon = "T0_Staff",
        StarterAbility = nil,
        StarterArmor = "T0_Robe",

        -- Unlock requirement (nil = unlocked by default)
        UnlockRequirement = nil,
    },

    Archer = {
        Name = "Archer",
        Description = "Ranged attacker with piercing arrows",

        -- Equipment slot types
        EquipmentSlotTypes = {
            SlotTypes.BOW_TYPE,     -- Slot 0: Weapon
            SlotTypes.QUIVER_TYPE,  -- Slot 1: Ability
            SlotTypes.LEATHER_TYPE, -- Slot 2: Armor
            SlotTypes.RING_TYPE,    -- Slot 3: Ring
        },

        Stats = {
            HP = {
                Base = 130,
                Growth = {20, 30},
                Cap = 700,
            },
            MP = {
                Base = 100,
                Growth = {2, 8},
                Cap = 252,
            },
            Attack = {
                Base = 10,
                Growth = {1, 2},
                Cap = 75,
            },
            Defense = {
                Base = 0,
                Growth = {0, 0},
                Cap = 25,
            },
            Speed = {
                Base = 12,
                Growth = {0, 2},
                Cap = 55,
            },
            Dexterity = {
                Base = 10,
                Growth = {0, 2},
                Cap = 50,
            },
            Vitality = {
                Base = 10,
                Growth = {0, 2},
                Cap = 40,
            },
            Wisdom = {
                Base = 10,
                Growth = {0, 2},
                Cap = 50,
            },
        },

        WeaponType = "Bow",
        AbilityType = "Quiver",
        ArmorType = "Leather",

        Ability = {
            Name = "Piercing Arrow",
            ManaCost = 25,
            Cooldown = 0.5,
            Effect = "PiercingShot",  -- High damage piercing projectile
            Damage = 150,
            Pierce = true,
            Range = 10,
        },

        StarterWeapon = "T0_Bow",
        StarterAbility = nil,
        StarterArmor = "T0_Leather",

        UnlockRequirement = nil,
    },

    Knight = {
        Name = "Knight",
        Description = "Heavily armored frontline tank",

        -- Equipment slot types
        EquipmentSlotTypes = {
            SlotTypes.SWORD_TYPE,   -- Slot 0: Weapon
            SlotTypes.SHIELD_TYPE,  -- Slot 1: Ability
            SlotTypes.PLATE_TYPE,   -- Slot 2: Armor
            SlotTypes.RING_TYPE,    -- Slot 3: Ring
        },

        Stats = {
            HP = {
                Base = 200,
                Growth = {20, 30},
                Cap = 770,
            },
            MP = {
                Base = 100,
                Growth = {2, 8},
                Cap = 252,
            },
            Attack = {
                Base = 10,
                Growth = {1, 2},
                Cap = 50,
            },
            Defense = {
                Base = 10,
                Growth = {0, 2},
                Cap = 40,  -- Highest DEF cap
            },
            Speed = {
                Base = 8,
                Growth = {0, 2},
                Cap = 50,
            },
            Dexterity = {
                Base = 10,
                Growth = {0, 2},
                Cap = 50,
            },
            Vitality = {
                Base = 15,
                Growth = {1, 2},
                Cap = 75,  -- Highest VIT cap
            },
            Wisdom = {
                Base = 10,
                Growth = {0, 2},
                Cap = 50,
            },
        },

        WeaponType = "Sword",
        AbilityType = "Shield",
        ArmorType = "Heavy",

        Ability = {
            Name = "Shield Bash",
            ManaCost = 30,
            Cooldown = 2.0,
            Effect = "Stun",
            Duration = 2.0,
            Radius = 8,
        },

        StarterWeapon = "T0_Sword",
        StarterAbility = nil,
        StarterArmor = "T0_Heavy",

        UnlockRequirement = nil,
    },

    Priest = {
        Name = "Priest",
        Description = "Support class with healing abilities",

        -- Equipment slot types
        EquipmentSlotTypes = {
            SlotTypes.WAND_TYPE,    -- Slot 0: Weapon
            SlotTypes.TOME_TYPE,    -- Slot 1: Ability
            SlotTypes.ROBE_TYPE,    -- Slot 2: Armor
            SlotTypes.RING_TYPE,    -- Slot 3: Ring
        },

        Stats = {
            HP = {
                Base = 100,
                Growth = {20, 30},
                Cap = 670,
            },
            MP = {
                Base = 100,
                Growth = {5, 15},
                Cap = 385,
            },
            Attack = {
                Base = 10,
                Growth = {0, 2},
                Cap = 60,
            },
            Defense = {
                Base = 0,
                Growth = {0, 0},
                Cap = 25,
            },
            Speed = {
                Base = 10,
                Growth = {0, 2},
                Cap = 55,
            },
            Dexterity = {
                Base = 15,
                Growth = {0, 2},
                Cap = 75,
            },
            Vitality = {
                Base = 10,
                Growth = {0, 2},
                Cap = 40,
            },
            Wisdom = {
                Base = 15,
                Growth = {1, 2},
                Cap = 75,  -- High WIS for healing
            },
        },

        WeaponType = "Wand",
        AbilityType = "Tome",
        ArmorType = "Robe",

        Ability = {
            Name = "Holy Heal",
            ManaCost = 35,
            Cooldown = 1.5,
            Effect = "Heal",
            HealAmount = 100,
            Radius = 20,
        },

        StarterWeapon = "T0_Wand",
        StarterAbility = nil,
        StarterArmor = "T0_Robe",

        UnlockRequirement = nil,
    },
}

-- Get a class by name
function ClassDatabase.GetClass(className)
    return ClassDatabase.Classes[className]
end

-- Get base stats for a class (returns flat table for initialization)
function ClassDatabase.GetBaseStats(className)
    local class = ClassDatabase.Classes[className]
    if not class then
        warn("[ClassDatabase] GetBaseStats: Class not found: " .. tostring(className))
        return nil
    end

    if not class.Stats then
        warn("[ClassDatabase] GetBaseStats: Class has no Stats table!")
        return nil
    end

    local stats = {}
    for statName, statData in pairs(class.Stats) do
        if type(statData) == "table" and statData.Base then
            stats[statName] = statData.Base
        else
            warn("[ClassDatabase] GetBaseStats: Invalid stat structure for " .. statName)
            stats[statName] = 0
        end
    end

    print("[ClassDatabase] GetBaseStats for " .. className .. ":")
    for k, v in pairs(stats) do
        print("  " .. k .. " = " .. tostring(v))
    end

    return stats
end

-- Get stat cap for a specific stat
function ClassDatabase.GetStatCap(className, statName)
    local class = ClassDatabase.Classes[className]
    if not class or not class.Stats[statName] then return nil end
    return class.Stats[statName].Cap
end

-- Roll stat growth for level up (returns random value in growth range)
function ClassDatabase.RollStatGrowth(className, statName)
    local class = ClassDatabase.Classes[className]
    if not class or not class.Stats[statName] then return 0 end

    local growth = class.Stats[statName].Growth
    return math.random(growth[1], growth[2])
end

-- Get all unlocked classes for a player
function ClassDatabase.GetUnlockedClasses(unlockedList)
    local result = {}
    for name, class in pairs(ClassDatabase.Classes) do
        if class.UnlockRequirement == nil or table.find(unlockedList, name) then
            result[name] = class
        end
    end
    return result
end

-- Get default unlocked class names
function ClassDatabase.GetDefaultUnlockedClasses()
    local result = {}
    for name, class in pairs(ClassDatabase.Classes) do
        if class.UnlockRequirement == nil then
            table.insert(result, name)
        end
    end
    return result
end

-- Get the slot types array for a class (what each equipment slot accepts)
-- Returns: {[1]=WeaponSlotType, [2]=AbilitySlotType, [3]=ArmorSlotType, [4]=RingSlotType}
function ClassDatabase.GetEquipmentSlotTypes(className)
    local class = ClassDatabase.Classes[className]
    if not class then return nil end
    return class.EquipmentSlotTypes
end

-- Check if an item can be equipped in a specific slot for a class
-- slotIndex: 1-4 for equipment slots (Lua 1-indexed)
-- itemSlotType: the SlotType of the item being equipped
function ClassDatabase.CanEquipInSlot(className, slotIndex, itemSlotType)
    -- Inventory slots (5+) accept any item
    if slotIndex > 4 then
        return true
    end

    local class = ClassDatabase.Classes[className]
    if not class or not class.EquipmentSlotTypes then
        return false
    end

    -- Check if the item's slot type matches the class's slot type for this position
    local requiredSlotType = class.EquipmentSlotTypes[slotIndex]
    if not requiredSlotType then
        return false
    end

    -- Exact match required for equipment slots
    return itemSlotType == requiredSlotType
end

-- Get the slot type name as a string (for debugging/UI)
function ClassDatabase.GetSlotTypeName(slotType)
    for name, value in pairs(SlotTypes) do
        if value == slotType then
            return name
        end
    end
    return "UNKNOWN"
end

return ClassDatabase
