--[[
    UIUtils.lua
    Shared UI utility functions to reduce code duplication across UI files

    Usage:
        local UIUtils = require(Shared.UIUtils)

        UIUtils.styleFrame(frame, {
            cornerRadius = 6,
            strokeColor = Color3.fromRGB(80, 80, 80),
            strokeThickness = 1
        })

        local slots = UIUtils.createGrid(parent, {
            numSlots = 8,
            columns = 4,
            slotSize = 40,
            gap = 6,
            slotColor = Color3.fromRGB(40, 40, 45),
            borderColor = Color3.fromRGB(80, 80, 90)
        })
]]

local UIUtils = {}

--============================================================================
-- STYLE UTILITIES
--============================================================================

-- Add UICorner to a frame
-- @param frame: The frame to add corner radius to
-- @param radius: Corner radius in pixels (default: 6)
-- @return: The created UICorner instance
function UIUtils.addCorner(frame, radius)
    radius = radius or 6
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, radius)
    corner.Parent = frame
    return corner
end

-- Add UIStroke to a frame
-- @param frame: The frame to add stroke to
-- @param color: Stroke color (default: gray)
-- @param thickness: Stroke thickness (default: 1)
-- @param transparency: Stroke transparency (default: 0)
-- @return: The created UIStroke instance
function UIUtils.addStroke(frame, color, thickness, transparency)
    color = color or Color3.fromRGB(80, 80, 80)
    thickness = thickness or 1
    transparency = transparency or 0

    local stroke = Instance.new("UIStroke")
    stroke.Color = color
    stroke.Thickness = thickness
    stroke.Transparency = transparency
    stroke.Parent = frame
    return stroke
end

-- Style a frame with corner radius and stroke in one call
-- @param frame: The frame to style
-- @param options: Table with optional keys:
--   - cornerRadius: number (default: 6)
--   - strokeColor: Color3 (default: gray)
--   - strokeThickness: number (default: 1)
--   - strokeTransparency: number (default: 0)
-- @return: corner, stroke instances
function UIUtils.styleFrame(frame, options)
    options = options or {}

    local corner = UIUtils.addCorner(frame, options.cornerRadius)
    local stroke = UIUtils.addStroke(
        frame,
        options.strokeColor,
        options.strokeThickness,
        options.strokeTransparency
    )

    return corner, stroke
end

--============================================================================
-- GRID UTILITIES
--============================================================================

-- Create a grid of slots (for inventory, equipment, loot bags, etc.)
-- @param parent: Parent frame to add slots to
-- @param options: Table with keys:
--   - numSlots: Total number of slots to create
--   - columns: Number of columns in the grid
--   - slotSize: Size of each slot in pixels
--   - gap: Gap between slots in pixels (default: 6)
--   - slotColor: Background color of slots
--   - borderColor: Border/stroke color of slots
--   - cornerRadius: Corner radius of slots (default: 4)
--   - startIndex: Starting index for slot names (default: 1)
--   - namePrefix: Prefix for slot names (default: "Slot")
--   - showNumbers: Whether to show slot numbers (default: false)
--   - numberFont: Font for slot numbers (default: Code)
--   - numberColor: Color for slot numbers (default: dark gray)
--   - numberSize: Size of slot numbers (default: 10)
-- @return: Array of created slot frames
function UIUtils.createGrid(parent, options)
    local numSlots = options.numSlots or 8
    local columns = options.columns or 4
    local slotSize = options.slotSize or 40
    local gap = options.gap or 6
    local slotColor = options.slotColor or Color3.fromRGB(40, 40, 45)
    local borderColor = options.borderColor or Color3.fromRGB(80, 80, 90)
    local cornerRadius = options.cornerRadius or 4
    local startIndex = options.startIndex or 1
    local namePrefix = options.namePrefix or "Slot"
    local showNumbers = options.showNumbers or false
    local numberFont = options.numberFont or Enum.Font.Code
    local numberColor = options.numberColor or Color3.fromRGB(80, 80, 90)
    local numberSize = options.numberSize or 10

    local slots = {}

    for i = 1, numSlots do
        local index = startIndex + i - 1
        local col = (i - 1) % columns
        local row = math.floor((i - 1) / columns)

        local slot = Instance.new("Frame")
        slot.Name = namePrefix .. index
        slot.Size = UDim2.new(0, slotSize, 0, slotSize)
        slot.Position = UDim2.new(0, col * (slotSize + gap), 0, row * (slotSize + gap))
        slot.BackgroundColor3 = slotColor
        slot.BorderSizePixel = 0
        slot.Parent = parent

        UIUtils.styleFrame(slot, {
            cornerRadius = cornerRadius,
            strokeColor = borderColor,
            strokeThickness = 1
        })

        -- Add slot number label if requested
        if showNumbers then
            local numLabel = Instance.new("TextLabel")
            numLabel.Name = "Number"
            numLabel.Size = UDim2.new(0, 12, 0, 12)
            numLabel.Position = UDim2.new(1, -14, 1, -14)
            numLabel.BackgroundTransparency = 1
            numLabel.Font = numberFont
            numLabel.Text = tostring(index)
            numLabel.TextColor3 = numberColor
            numLabel.TextSize = numberSize
            numLabel.Parent = slot
        end

        slots[i] = slot
    end

    return slots
end

-- Calculate grid dimensions
-- @param numSlots: Total number of slots
-- @param columns: Number of columns
-- @param slotSize: Size of each slot
-- @param gap: Gap between slots
-- @return: width, height of the grid
function UIUtils.getGridSize(numSlots, columns, slotSize, gap)
    gap = gap or 6
    local rows = math.ceil(numSlots / columns)
    local width = columns * slotSize + (columns - 1) * gap
    local height = rows * slotSize + (rows - 1) * gap
    return width, height
end

--============================================================================
-- LABEL UTILITIES
--============================================================================

-- Create a simple text label
-- @param parent: Parent instance
-- @param options: Table with optional keys:
--   - name: Label name
--   - text: Initial text
--   - size: UDim2 size
--   - position: UDim2 position
--   - font: Font enum
--   - textSize: Text size
--   - textColor: Text color
--   - xAlignment: TextXAlignment
--   - yAlignment: TextYAlignment
-- @return: The created TextLabel
function UIUtils.createLabel(parent, options)
    options = options or {}

    local label = Instance.new("TextLabel")
    label.Name = options.name or "Label"
    label.Size = options.size or UDim2.new(1, 0, 0, 20)
    label.Position = options.position or UDim2.new(0, 0, 0, 0)
    label.BackgroundTransparency = 1
    label.Font = options.font or Enum.Font.Code
    label.Text = options.text or ""
    label.TextColor3 = options.textColor or Color3.new(1, 1, 1)
    label.TextSize = options.textSize or 14
    label.TextXAlignment = options.xAlignment or Enum.TextXAlignment.Left
    label.TextYAlignment = options.yAlignment or Enum.TextYAlignment.Center
    label.Parent = parent

    return label
end

return UIUtils
