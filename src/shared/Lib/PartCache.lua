--[[
    PartCache
    High-performance object pooling for projectile parts

    Usage:
        local cache = PartCache.new(templatePart, 100, containerFolder)
        local part = cache:GetPart()
        cache:ReturnPart(part)
]]

local PartCache = {}
PartCache.__index = PartCache

-- Storage location for inactive parts
local CF_STORAGE = CFrame.new(0, -5000, 0)

function PartCache.new(template: BasePart, precreate: number, container: Instance?)
    assert(template:IsA("BasePart"), "Template must be a BasePart")

    local self = setmetatable({}, PartCache)

    self.Template = template
    self.Container = container or workspace
    self.Open = {}       -- Available parts
    self.InUse = {}      -- Currently active parts
    self.ExpansionSize = 10

    -- Pre-create parts
    for i = 1, (precreate or 50) do
        local part = template:Clone()
        part.CFrame = CF_STORAGE
        part.Anchored = true
        part.CanCollide = false
        part.Parent = self.Container
        table.insert(self.Open, part)
    end

    return self
end

function PartCache:GetPart(): BasePart
    local part

    if #self.Open > 0 then
        part = table.remove(self.Open)
    else
        -- Pool exhausted, expand
        for i = 1, self.ExpansionSize do
            local newPart = self.Template:Clone()
            newPart.CFrame = CF_STORAGE
            newPart.Anchored = true
            newPart.CanCollide = false
            newPart.Parent = self.Container
            table.insert(self.Open, newPart)
        end
        part = table.remove(self.Open)
    end

    self.InUse[part] = true
    return part
end

function PartCache:ReturnPart(part: BasePart)
    if not self.InUse[part] then
        warn("[PartCache] Attempted to return part not in use")
        return
    end

    self.InUse[part] = nil
    part.CFrame = CF_STORAGE
    table.insert(self.Open, part)
end

function PartCache:SetContainer(container: Instance)
    self.Container = container
    for part, _ in pairs(self.InUse) do
        part.Parent = container
    end
    for _, part in ipairs(self.Open) do
        part.Parent = container
    end
end

function PartCache:Dispose()
    for part, _ in pairs(self.InUse) do
        part:Destroy()
    end
    for _, part in ipairs(self.Open) do
        part:Destroy()
    end
    self.Open = {}
    self.InUse = {}
end

function PartCache:GetStats()
    local inUseCount = 0
    for _ in pairs(self.InUse) do
        inUseCount = inUseCount + 1
    end
    return {
        Open = #self.Open,
        InUse = inUseCount,
        Total = #self.Open + inUseCount,
    }
end

return PartCache
