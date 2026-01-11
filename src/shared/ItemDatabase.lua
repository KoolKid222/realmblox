--[[
    ItemDatabase.lua
    Definitions for all items, weapons, armor, and loot tables

    RANGE VALUES ARE IN GAME UNITS (1 unit = 4 studs)
    At max zoom, ~9 units are visible from center to edge
    Wizard staff (8 units) = 90% screen distance

    SLOT TYPES (from RotMG ItemConstants.as):
    Equipment slots: [0]=Weapon, [1]=Ability, [2]=Armor, [3]=Ring
    Inventory slots: [4-11] = 8 inventory slots
]]

local ItemDatabase = {}

--============================================================================
-- ROTMG CONSTANTS (from GeneralConstants.as and ItemConstants.as)
--============================================================================

ItemDatabase.NUM_EQUIPMENT_SLOTS = 4   -- Weapon, Ability, Armor, Ring
ItemDatabase.NUM_INVENTORY_SLOTS = 8   -- 8 inventory bag slots

-- Slot indices
ItemDatabase.Slots = {
    Weapon = 0,
    Ability = 1,
    Armor = 2,
    Ring = 3,
    -- Inventory starts at index 4
}

-- RotMG Item Slot Types (from ItemConstants.as)
ItemDatabase.SlotTypes = {
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

-- Loot bag types (RotMG style - 5 bags)
ItemDatabase.BagTypes = {
    BROWN = 1,      -- HP/MP potions only (tradeable)
    PINK = 2,       -- Low tier gear T0-T7/T0-T2 (tradeable)
    PURPLE = 3,     -- High tier gear T8+/T3+ (soulbound)
    BLUE = 4,       -- Stat potions (soulbound, bosses/gods only)
    WHITE = 5,      -- Ultra-rare untiered drops (soulbound, bosses only)
}

-- Item types
ItemDatabase.Types = {
    Weapon = "Weapon",
    Ability = "Ability",
    Armor = "Armor",
    Ring = "Ring",
    Consumable = "Consumable",
}

-- Weapon subtypes with slot types
ItemDatabase.WeaponTypes = {
    Staff = {Name = "Staff", SlotType = 17},
    Bow = {Name = "Bow", SlotType = 3},
    Sword = {Name = "Sword", SlotType = 1},
    Wand = {Name = "Wand", SlotType = 8},
    Dagger = {Name = "Dagger", SlotType = 2},
    Katana = {Name = "Katana", SlotType = 24},
}

-- Armor subtypes with slot types
ItemDatabase.ArmorTypes = {
    Robe = {Name = "Robe", SlotType = 14},
    Leather = {Name = "Leather", SlotType = 6},
    Heavy = {Name = "Heavy", SlotType = 7},  -- Plate
}

-- Ability subtypes with slot types
ItemDatabase.AbilityTypes = {
    Spell = {Name = "Spell", SlotType = 11},      -- Wizard
    Tome = {Name = "Tome", SlotType = 4},         -- Priest
    Quiver = {Name = "Quiver", SlotType = 15},    -- Archer
    Shield = {Name = "Shield", SlotType = 5},     -- Knight
    Cloak = {Name = "Cloak", SlotType = 13},      -- Rogue
    Helm = {Name = "Helm", SlotType = 16},        -- Warrior
    Seal = {Name = "Seal", SlotType = 12},        -- Paladin
    Poison = {Name = "Poison", SlotType = 18},    -- Assassin
    Skull = {Name = "Skull", SlotType = 19},      -- Necromancer
    Trap = {Name = "Trap", SlotType = 20},        -- Huntress
    Orb = {Name = "Orb", SlotType = 21},          -- Mystic
    Prism = {Name = "Prism", SlotType = 22},      -- Trickster
    Scepter = {Name = "Scepter", SlotType = 23},  -- Sorcerer
    Shuriken = {Name = "Shuriken", SlotType = 25}, -- Ninja
}

-- All items
ItemDatabase.Items = {
    --========================================================================
    -- STAFFS (Wizard weapon) - SlotType 17
    --========================================================================
    T0_Staff = {
        Id = "T0_Staff", Name = "Starter Staff", Type = "Weapon", Subtype = "Staff",
        SlotType = 17, Tier = 0, Rarity = "Common",
        Stats = {}, Damage = {Min = 40, Max = 65}, Range = 8.6, RateOfFire = 5.5,
        NumProjectiles = 2, ProjectileSpeed = 20, ProjectileColor = Color3.fromRGB(150, 100, 255),
        Pierce = false, WavePattern = true, WaveAmplitude = 0.35, WaveFrequency = 6,
        Description = "A basic wooden staff.",
    },
    T1_Staff = {
        Id = "T1_Staff", Name = "Fire Staff", Type = "Weapon", Subtype = "Staff",
        SlotType = 17, Tier = 1, Rarity = "Common",
        Stats = {Attack = 1}, Damage = {Min = 45, Max = 75}, Range = 8.6, RateOfFire = 5.5,
        NumProjectiles = 2, ProjectileSpeed = 20, ProjectileColor = Color3.fromRGB(255, 100, 50),
        Pierce = false, WavePattern = true, WaveAmplitude = 0.35, WaveFrequency = 6,
        Description = "A staff imbued with fire magic.",
    },
    T2_Staff = {
        Id = "T2_Staff", Name = "Frost Staff", Type = "Weapon", Subtype = "Staff",
        SlotType = 17, Tier = 2, Rarity = "Uncommon",
        Stats = {Attack = 2}, Damage = {Min = 50, Max = 85}, Range = 8.6, RateOfFire = 5.5,
        NumProjectiles = 2, ProjectileSpeed = 20, ProjectileColor = Color3.fromRGB(100, 200, 255),
        Pierce = false, WavePattern = true, WaveAmplitude = 0.35, WaveFrequency = 6,
        Description = "Chilling power flows through this staff.",
    },
    T3_Staff = {
        Id = "T3_Staff", Name = "Arcane Staff", Type = "Weapon", Subtype = "Staff",
        SlotType = 17, Tier = 3, Rarity = "Rare",
        Stats = {Attack = 3, Dexterity = 1}, Damage = {Min = 55, Max = 95}, Range = 8.6, RateOfFire = 5.5,
        NumProjectiles = 2, ProjectileSpeed = 20, ProjectileColor = Color3.fromRGB(200, 50, 255),
        Pierce = false, WavePattern = true, WaveAmplitude = 0.35, WaveFrequency = 6,
        Description = "Crackling with arcane energy.",
    },
    T4_Staff = {
        Id = "T4_Staff", Name = "Staff of Destruction", Type = "Weapon", Subtype = "Staff",
        SlotType = 17, Tier = 4, Rarity = "Epic",
        Stats = {Attack = 5, Dexterity = 2}, Damage = {Min = 60, Max = 105}, Range = 8.6, RateOfFire = 5.5,
        NumProjectiles = 2, ProjectileSpeed = 20, ProjectileColor = Color3.fromRGB(255, 0, 100),
        Pierce = false, WavePattern = true, WaveAmplitude = 0.35, WaveFrequency = 6,
        Description = "Channels devastating magical power.",
    },

    --========================================================================
    -- BOWS (Archer weapon) - SlotType 3
    --========================================================================
    T0_Bow = {
        Id = "T0_Bow", Name = "Starter Bow", Type = "Weapon", Subtype = "Bow",
        SlotType = 3, Tier = 0, Rarity = "Common",
        Stats = {}, Damage = {Min = 20, Max = 35}, Range = 9, RateOfFire = 1.2,
        NumProjectiles = 1, ProjectileSpeed = 22, ProjectileColor = Color3.fromRGB(139, 90, 43),
        Description = "A simple wooden bow.",
    },
    T1_Bow = {
        Id = "T1_Bow", Name = "Short Bow", Type = "Weapon", Subtype = "Bow",
        SlotType = 3, Tier = 1, Rarity = "Common",
        Stats = {Dexterity = 1}, Damage = {Min = 30, Max = 50}, Range = 9.2, RateOfFire = 1.3,
        NumProjectiles = 1, ProjectileSpeed = 23, ProjectileColor = Color3.fromRGB(139, 90, 43),
        Description = "A well-crafted short bow.",
    },

    --========================================================================
    -- SWORDS (Knight weapon) - SlotType 1
    --========================================================================
    T0_Sword = {
        Id = "T0_Sword", Name = "Starter Sword", Type = "Weapon", Subtype = "Sword",
        SlotType = 1, Tier = 0, Rarity = "Common",
        Stats = {}, Damage = {Min = 40, Max = 60}, Range = 1.2, RateOfFire = 2.0,
        NumProjectiles = 1, IsMelee = true, ArcAngle = 90,
        Description = "A basic iron sword.",
    },

    --========================================================================
    -- WANDS (Priest weapon) - SlotType 8
    --========================================================================
    T0_Wand = {
        Id = "T0_Wand", Name = "Starter Wand", Type = "Weapon", Subtype = "Wand",
        SlotType = 8, Tier = 0, Rarity = "Common",
        Stats = {}, Damage = {Min = 25, Max = 45}, Range = 7, RateOfFire = 1.8,
        NumProjectiles = 1, ProjectileSpeed = 18, ProjectileColor = Color3.fromRGB(255, 255, 150),
        Description = "A simple magical wand.",
    },

    --========================================================================
    -- SPELLS (Wizard ability) - SlotType 11
    --========================================================================
    T0_Spell = {
        Id = "T0_Spell", Name = "Apprentice Spell", Type = "Ability", Subtype = "Spell",
        SlotType = 11, Tier = 0, Rarity = "Common",
        Stats = {}, MPCost = 20, Damage = {Min = 80, Max = 120}, Range = 8,
        Effect = "SpellBomb", Radius = 3,
        Description = "Creates a damaging explosion.",
    },
    T1_Spell = {
        Id = "T1_Spell", Name = "Destruction Spell", Type = "Ability", Subtype = "Spell",
        SlotType = 11, Tier = 1, Rarity = "Common",
        Stats = {Attack = 1}, MPCost = 30, Damage = {Min = 120, Max = 180}, Range = 8,
        Effect = "SpellBomb", Radius = 3.5,
        Description = "A more powerful magical explosion.",
    },
    T2_Spell = {
        Id = "T2_Spell", Name = "Arcane Spell", Type = "Ability", Subtype = "Spell",
        SlotType = 11, Tier = 2, Rarity = "Uncommon",
        Stats = {Attack = 2}, MPCost = 40, Damage = {Min = 160, Max = 240}, Range = 9,
        Effect = "SpellBomb", Radius = 4,
        Description = "Unleashes devastating arcane power.",
    },

    --========================================================================
    -- ROBES (Wizard/Priest armor) - SlotType 14
    --========================================================================
    T0_Robe = {
        Id = "T0_Robe", Name = "Starter Robe", Type = "Armor", Subtype = "Robe",
        SlotType = 14, Tier = 0, Rarity = "Common",
        Stats = {MaxMP = 10}, Description = "A basic cloth robe.",
    },
    T1_Robe = {
        Id = "T1_Robe", Name = "Apprentice Robe", Type = "Armor", Subtype = "Robe",
        SlotType = 14, Tier = 1, Rarity = "Common",
        Stats = {Defense = 2, MaxMP = 15}, Description = "A robe worn by apprentice mages.",
    },
    T2_Robe = {
        Id = "T2_Robe", Name = "Magician Robe", Type = "Armor", Subtype = "Robe",
        SlotType = 14, Tier = 2, Rarity = "Uncommon",
        Stats = {Defense = 5, MaxMP = 25, Attack = 1}, Description = "A robe of considerable magical protection.",
    },

    --========================================================================
    -- HEAVY ARMOR (Knight/Paladin/Warrior) - SlotType 7
    --========================================================================
    T0_Heavy = {
        Id = "T0_Heavy", Name = "Starter Armor", Type = "Armor", Subtype = "Heavy",
        SlotType = 7, Tier = 0, Rarity = "Common",
        Stats = {Defense = 5}, Description = "Basic iron armor.",
    },

    --========================================================================
    -- LEATHER ARMOR (Archer/Rogue/etc) - SlotType 6
    --========================================================================
    T0_Leather = {
        Id = "T0_Leather", Name = "Starter Leather", Type = "Armor", Subtype = "Leather",
        SlotType = 6, Tier = 0, Rarity = "Common",
        Stats = {Defense = 2, Speed = 1}, Description = "Basic leather armor.",
    },

    --========================================================================
    -- RINGS - SlotType 9
    --========================================================================
    T0_Ring_HP = {
        Id = "T0_Ring_HP", Name = "Ring of Minor Health", Type = "Ring", Subtype = "Ring",
        SlotType = 9, Tier = 0, Rarity = "Common",
        Stats = {MaxHP = 20}, Description = "A simple ring that boosts vitality.",
    },
    T1_Ring_HP = {
        Id = "T1_Ring_HP", Name = "Ring of Health", Type = "Ring", Subtype = "Ring",
        SlotType = 9, Tier = 1, Rarity = "Common",
        Stats = {MaxHP = 40}, Description = "A ring imbued with life energy.",
    },
    T0_Ring_MP = {
        Id = "T0_Ring_MP", Name = "Ring of Minor Magic", Type = "Ring", Subtype = "Ring",
        SlotType = 9, Tier = 0, Rarity = "Common",
        Stats = {MaxMP = 20}, Description = "A simple ring that boosts mana.",
    },
    T1_Ring_MP = {
        Id = "T1_Ring_MP", Name = "Ring of Magic", Type = "Ring", Subtype = "Ring",
        SlotType = 9, Tier = 1, Rarity = "Common",
        Stats = {MaxMP = 40}, Description = "A ring crackling with magical energy.",
    },
    T0_Ring_ATT = {
        Id = "T0_Ring_ATT", Name = "Ring of Minor Attack", Type = "Ring", Subtype = "Ring",
        SlotType = 9, Tier = 0, Rarity = "Common",
        Stats = {Attack = 2}, Description = "A ring that sharpens your strikes.",
    },
    T0_Ring_DEF = {
        Id = "T0_Ring_DEF", Name = "Ring of Minor Defense", Type = "Ring", Subtype = "Ring",
        SlotType = 9, Tier = 0, Rarity = "Common",
        Stats = {Defense = 2}, Description = "A ring that hardens your skin.",
    },
    T0_Ring_SPD = {
        Id = "T0_Ring_SPD", Name = "Ring of Minor Speed", Type = "Ring", Subtype = "Ring",
        SlotType = 9, Tier = 0, Rarity = "Common",
        Stats = {Speed = 2}, Description = "A ring that quickens your step.",
    },
    T0_Ring_DEX = {
        Id = "T0_Ring_DEX", Name = "Ring of Minor Dexterity", Type = "Ring", Subtype = "Ring",
        SlotType = 9, Tier = 0, Rarity = "Common",
        Stats = {Dexterity = 2}, Description = "A ring that steadies your aim.",
    },

    --========================================================================
    -- CONSUMABLES - SlotType 10
    --========================================================================
    HealthPotion = {
        Id = "HealthPotion", Name = "Health Potion", Type = "Consumable", Subtype = "Potion",
        SlotType = 10, Tier = 0, Rarity = "Common",
        HealAmount = 100, Soulbound = false,
        Description = "Restores 100 HP.",
    },
    ManaPotion = {
        Id = "ManaPotion", Name = "Mana Potion", Type = "Consumable", Subtype = "Potion",
        SlotType = 10, Tier = 0, Rarity = "Common",
        ManaAmount = 100, Soulbound = false,
        Description = "Restores 100 MP.",
    },

    --========================================================================
    -- STAT POTIONS (Soulbound, drop from bosses/gods) - SlotType 10
    --========================================================================
    Potion_Attack = {
        Id = "Potion_Attack", Name = "Potion of Attack", Type = "Consumable", Subtype = "StatPotion",
        SlotType = 10, Tier = 0, Rarity = "Rare",
        StatBoost = {Stat = "Attack", Amount = 1}, Soulbound = true,
        Description = "Permanently increases Attack by 1.",
    },
    Potion_Defense = {
        Id = "Potion_Defense", Name = "Potion of Defense", Type = "Consumable", Subtype = "StatPotion",
        SlotType = 10, Tier = 0, Rarity = "Rare",
        StatBoost = {Stat = "Defense", Amount = 1}, Soulbound = true,
        Description = "Permanently increases Defense by 1.",
    },
    Potion_Speed = {
        Id = "Potion_Speed", Name = "Potion of Speed", Type = "Consumable", Subtype = "StatPotion",
        SlotType = 10, Tier = 0, Rarity = "Rare",
        StatBoost = {Stat = "Speed", Amount = 1}, Soulbound = true,
        Description = "Permanently increases Speed by 1.",
    },
    Potion_Dexterity = {
        Id = "Potion_Dexterity", Name = "Potion of Dexterity", Type = "Consumable", Subtype = "StatPotion",
        SlotType = 10, Tier = 0, Rarity = "Rare",
        StatBoost = {Stat = "Dexterity", Amount = 1}, Soulbound = true,
        Description = "Permanently increases Dexterity by 1.",
    },
    Potion_Vitality = {
        Id = "Potion_Vitality", Name = "Potion of Vitality", Type = "Consumable", Subtype = "StatPotion",
        SlotType = 10, Tier = 0, Rarity = "Rare",
        StatBoost = {Stat = "Vitality", Amount = 1}, Soulbound = true,
        Description = "Permanently increases Vitality by 1.",
    },
    Potion_Wisdom = {
        Id = "Potion_Wisdom", Name = "Potion of Wisdom", Type = "Consumable", Subtype = "StatPotion",
        SlotType = 10, Tier = 0, Rarity = "Rare",
        StatBoost = {Stat = "Wisdom", Amount = 1}, Soulbound = true,
        Description = "Permanently increases Wisdom by 1.",
    },
    Potion_Life = {
        Id = "Potion_Life", Name = "Potion of Life", Type = "Consumable", Subtype = "StatPotion",
        SlotType = 10, Tier = 0, Rarity = "Epic",
        StatBoost = {Stat = "MaxHP", Amount = 5}, Soulbound = true,
        Description = "Permanently increases Max HP by 5.",
    },
    Potion_Mana = {
        Id = "Potion_Mana", Name = "Potion of Mana", Type = "Consumable", Subtype = "StatPotion",
        SlotType = 10, Tier = 0, Rarity = "Epic",
        StatBoost = {Stat = "MaxMP", Amount = 5}, Soulbound = true,
        Description = "Permanently increases Max MP by 5.",
    },

    --========================================================================
    -- WHITE BAG ITEMS (Untiered, special effects) - Various SlotTypes
    --========================================================================
    UT_StaffOfExtremePrejudice = {
        Id = "UT_StaffOfExtremePrejudice", Name = "Staff of Extreme Prejudice", Type = "Weapon", Subtype = "Staff",
        SlotType = 17, Tier = "UT", Rarity = "Legendary", WhiteBag = true,
        Stats = {}, Damage = {Min = 55, Max = 70}, Range = 5.6, RateOfFire = 5.5,
        NumProjectiles = 20, ProjectileSpeed = 10, ProjectileColor = Color3.fromRGB(255, 255, 255),
        Pierce = true, SpreadAngle = 45,
        Description = "Fires a devastating cone of 20 shots. Short range but immense damage up close.",
        Soulbound = true,
    },
    UT_CrownOfTheForest = {
        Id = "UT_CrownOfTheForest", Name = "Crown of the Forest", Type = "Ring", Subtype = "Ring",
        SlotType = 9, Tier = "UT", Rarity = "Legendary", WhiteBag = true,
        Stats = {MaxHP = 110, MaxMP = 10, Attack = 6, Defense = 6, Speed = 6, Dexterity = 6, Vitality = 6, Wisdom = 6},
        Description = "An ancient crown radiating immense power.",
        Soulbound = true,
    },
}

-- Loot tables
ItemDatabase.LootTables = {
    Beach_Common = {
        XP = {Min = 5, Max = 15},
        Drops = {
            {Item = "T0_Staff", Chance = 0.02},
            {Item = "T1_Staff", Chance = 0.01},
            {Item = "T0_Robe", Chance = 0.02},
            {Item = "HealthPotion", Chance = 0.05},
        },
    },

    Beach_Rare = {
        XP = {Min = 20, Max = 50},
        Drops = {
            {Item = "T1_Staff", Chance = 0.05},
            {Item = "T1_Robe", Chance = 0.03},
            {Item = "T1_Bow", Chance = 0.05},
            {Item = "HealthPotion", Chance = 0.15},
            {Item = "ManaPotion", Chance = 0.10},
        },
    },

    Midlands_Common = {
        XP = {Min = 15, Max = 35},
        Drops = {
            {Item = "T1_Staff", Chance = 0.03},
            {Item = "T2_Staff", Chance = 0.01},
            {Item = "T1_Robe", Chance = 0.03},
            {Item = "HealthPotion", Chance = 0.08},
            {Item = "ManaPotion", Chance = 0.05},
        },
    },

    Midlands_Rare = {
        XP = {Min = 30, Max = 60},
        Drops = {
            {Item = "T2_Staff", Chance = 0.05},
            {Item = "T2_Robe", Chance = 0.04},
            {Item = "HealthPotion", Chance = 0.15},
            {Item = "ManaPotion", Chance = 0.10},
        },
    },

    Godlands_God = {
        XP = {Min = 50, Max = 100},
        Drops = {
            {Item = "T2_Staff", Chance = 0.08},
            {Item = "T3_Staff", Chance = 0.03},
            {Item = "T4_Staff", Chance = 0.01},
            {Item = "T2_Robe", Chance = 0.06},
            {Item = "HealthPotion", Chance = 0.20},
            {Item = "ManaPotion", Chance = 0.15},
            -- Stat potions (blue bag drops from gods)
            {Item = "Potion_Attack", Chance = 0.02},
            {Item = "Potion_Defense", Chance = 0.02},
            {Item = "Potion_Speed", Chance = 0.02},
            {Item = "Potion_Dexterity", Chance = 0.02},
            {Item = "Potion_Vitality", Chance = 0.02},
            {Item = "Potion_Wisdom", Chance = 0.02},
        },
    },

    -- Boss loot table (can drop white bags)
    Boss_Common = {
        XP = {Min = 100, Max = 200},
        Drops = {
            {Item = "T3_Staff", Chance = 0.15},
            {Item = "T4_Staff", Chance = 0.08},
            {Item = "T2_Robe", Chance = 0.10},
            {Item = "HealthPotion", Chance = 0.50},
            {Item = "ManaPotion", Chance = 0.40},
            -- Stat potions (guaranteed at least one from bosses)
            {Item = "Potion_Attack", Chance = 0.15},
            {Item = "Potion_Defense", Chance = 0.15},
            {Item = "Potion_Speed", Chance = 0.10},
            {Item = "Potion_Dexterity", Chance = 0.10},
            {Item = "Potion_Vitality", Chance = 0.08},
            {Item = "Potion_Wisdom", Chance = 0.08},
            {Item = "Potion_Life", Chance = 0.03},
            {Item = "Potion_Mana", Chance = 0.03},
            -- White bag items (very rare)
            {Item = "UT_StaffOfExtremePrejudice", Chance = 0.005},
            {Item = "UT_CrownOfTheForest", Chance = 0.003},
        },
    },
}

-- Get item by ID
function ItemDatabase.GetItem(itemId)
    return ItemDatabase.Items[itemId]
end

-- Get loot table by name
function ItemDatabase.GetLootTable(tableName)
    return ItemDatabase.LootTables[tableName]
end

-- Roll loot from a table
function ItemDatabase.RollLoot(tableName)
    local lootTable = ItemDatabase.LootTables[tableName]
    if not lootTable then return {}, 0 end

    local droppedItems = {}

    -- Roll XP
    local xpReward = math.random(lootTable.XP.Min, lootTable.XP.Max)

    -- Roll each item independently
    for _, drop in ipairs(lootTable.Drops) do
        if math.random() <= drop.Chance then
            table.insert(droppedItems, drop.Item)
        end
    end

    return droppedItems, xpReward
end

return ItemDatabase
