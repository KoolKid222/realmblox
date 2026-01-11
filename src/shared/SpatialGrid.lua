--[[
    SpatialGrid.lua
    High-performance spatial partitioning for projectile/enemy hit detection

    Divides the world into cells for O(1) lookup of nearby entities
    instead of O(n) iteration through all entities.

    Usage:
        local grid = SpatialGrid.new(cellSize)
        grid:Insert(entity, position)
        grid:Remove(entity)
        grid:Update(entity, newPosition)
        local nearby = grid:GetNearby(position, radius)
]]

local SpatialGrid = {}
SpatialGrid.__index = SpatialGrid

--============================================================================
-- CONSTRUCTOR
--============================================================================

function SpatialGrid.new(cellSize)
    local self = setmetatable({}, SpatialGrid)

    self.CellSize = cellSize or 20  -- Default 20 studs per cell
    self.Cells = {}                  -- [cellKey] = {entities}
    self.EntityCells = {}            -- [entity] = cellKey (for fast removal)
    self.EntityPositions = {}        -- [entity] = position (for updates)

    return self
end

--============================================================================
-- HELPER FUNCTIONS
--============================================================================

-- Convert world position to cell key
function SpatialGrid:GetCellKey(position)
    local cellX = math.floor(position.X / self.CellSize)
    local cellZ = math.floor(position.Z / self.CellSize)
    return cellX .. "," .. cellZ
end

-- Get cell coordinates from position
function SpatialGrid:GetCellCoords(position)
    return math.floor(position.X / self.CellSize), math.floor(position.Z / self.CellSize)
end

-- Get or create a cell
function SpatialGrid:GetOrCreateCell(cellKey)
    if not self.Cells[cellKey] then
        self.Cells[cellKey] = {}
    end
    return self.Cells[cellKey]
end

--============================================================================
-- INSERTION / REMOVAL / UPDATE
--============================================================================

function SpatialGrid:Insert(entity, position)
    local cellKey = self:GetCellKey(position)
    local cell = self:GetOrCreateCell(cellKey)

    cell[entity] = true
    self.EntityCells[entity] = cellKey
    self.EntityPositions[entity] = position
end

function SpatialGrid:Remove(entity)
    local cellKey = self.EntityCells[entity]
    if cellKey and self.Cells[cellKey] then
        self.Cells[cellKey][entity] = nil

        -- Clean up empty cells periodically (not every removal for performance)
        -- This is optional - empty cells use minimal memory
    end

    self.EntityCells[entity] = nil
    self.EntityPositions[entity] = nil
end

function SpatialGrid:Update(entity, newPosition)
    local oldCellKey = self.EntityCells[entity]
    local newCellKey = self:GetCellKey(newPosition)

    self.EntityPositions[entity] = newPosition

    -- Only update cells if entity moved to a different cell
    if oldCellKey ~= newCellKey then
        -- Remove from old cell
        if oldCellKey and self.Cells[oldCellKey] then
            self.Cells[oldCellKey][entity] = nil
        end

        -- Add to new cell
        local newCell = self:GetOrCreateCell(newCellKey)
        newCell[entity] = true
        self.EntityCells[entity] = newCellKey
    end
end

--============================================================================
-- QUERIES
--============================================================================

-- Get all entities in nearby cells (within radius)
-- Returns a table of entities that MIGHT be within radius (broad phase)
-- Caller should do fine-grained distance check (narrow phase)
function SpatialGrid:GetNearby(position, radius)
    local results = {}

    -- Calculate how many cells the radius spans
    local cellRadius = math.ceil(radius / self.CellSize)
    local centerX, centerZ = self:GetCellCoords(position)

    -- Check all cells within range
    for dx = -cellRadius, cellRadius do
        for dz = -cellRadius, cellRadius do
            local cellKey = (centerX + dx) .. "," .. (centerZ + dz)
            local cell = self.Cells[cellKey]

            if cell then
                for entity in pairs(cell) do
                    results[entity] = true
                end
            end
        end
    end

    return results
end

-- Get entities in nearby cells with their positions (avoids extra lookup)
function SpatialGrid:GetNearbyWithPositions(position, radius)
    local results = {}

    local cellRadius = math.ceil(radius / self.CellSize)
    local centerX, centerZ = self:GetCellCoords(position)

    for dx = -cellRadius, cellRadius do
        for dz = -cellRadius, cellRadius do
            local cellKey = (centerX + dx) .. "," .. (centerZ + dz)
            local cell = self.Cells[cellKey]

            if cell then
                for entity in pairs(cell) do
                    local entityPos = self.EntityPositions[entity]
                    if entityPos then
                        results[entity] = entityPos
                    end
                end
            end
        end
    end

    return results
end

-- Get count of entities in grid (for debugging)
function SpatialGrid:GetEntityCount()
    local count = 0
    for _ in pairs(self.EntityCells) do
        count = count + 1
    end
    return count
end

-- Clear all entities
function SpatialGrid:Clear()
    self.Cells = {}
    self.EntityCells = {}
    self.EntityPositions = {}
end

return SpatialGrid
