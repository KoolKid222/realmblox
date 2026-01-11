--[[
    LazyLoader.lua
    Utility for creating lazy-loaded module getters to avoid circular dependencies

    Usage:
        local LazyLoader = require(Shared.LazyLoader)

        local getPlayerManager = LazyLoader.create(script.Parent, "PlayerManager")
        local getCombatManager = LazyLoader.create(script.Parent, "CombatManager")

        -- Later in code:
        local PM = getPlayerManager()
        PM.DoSomething()
]]

local LazyLoader = {}

-- Cache for loaded modules (prevents multiple requires of the same module)
local moduleCache = {}

-- Create a lazy loader function for a module
-- @param parent: The parent instance containing the module (e.g., script.Parent)
-- @param moduleName: The name of the module to load
-- @return: A function that returns the loaded module
function LazyLoader.create(parent, moduleName)
    local cacheKey = tostring(parent) .. "/" .. moduleName

    return function()
        if not moduleCache[cacheKey] then
            moduleCache[cacheKey] = require(parent:FindFirstChild(moduleName))
        end
        return moduleCache[cacheKey]
    end
end

-- Create multiple lazy loaders at once
-- @param parent: The parent instance containing the modules
-- @param moduleNames: Array of module names to create loaders for
-- @return: Table of getter functions keyed by module name
function LazyLoader.createMultiple(parent, moduleNames)
    local loaders = {}
    for _, name in ipairs(moduleNames) do
        loaders[name] = LazyLoader.create(parent, name)
    end
    return loaders
end

-- Clear the module cache (useful for hot-reloading in development)
function LazyLoader.clearCache()
    moduleCache = {}
end

return LazyLoader
