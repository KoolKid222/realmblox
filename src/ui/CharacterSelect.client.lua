--[[
    CharacterSelect.client.lua
    Character selection and creation UI for the main gameplay loop

    Shows on:
    - Player join (before entering game)
    - After death (to select/create new character)
]]

print("!!! CharacterSelect script starting !!!")

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Check if UI already exists (StarterGui scripts re-run on respawn)
-- We need to destroy and recreate because old script's connections are gone
local existingUI = playerGui:FindFirstChild("CharacterSelectUI")
if existingUI then
    -- -- print("[CharacterSelect] Respawn detected - destroying old UI to recreate with fresh connections...")
    existingUI:Destroy()
end

-- -- print("[CharacterSelect] Initializing...")

-- -- print("[CharacterSelect] Got PlayerGui")

local Shared = ReplicatedStorage:WaitForChild("Shared")
-- -- print("[CharacterSelect] Found Shared folder")

local Remotes = require(Shared.Remotes)
local ClassDatabase = require(Shared.ClassDatabase)
-- -- print("[CharacterSelect] Loaded modules")

-- Wait for remotes to initialize
-- -- print("[CharacterSelect] Waiting for remotes...")
Remotes.Init()
-- -- print("[CharacterSelect] Remotes initialized")

--============================================================================
-- UI COLORS (RotMG Style)
--============================================================================

local COLORS = {
    Background = Color3.fromRGB(20, 20, 30),
    Panel = Color3.fromRGB(30, 30, 45),
    PanelBorder = Color3.fromRGB(60, 60, 80),
    Text = Color3.fromRGB(255, 255, 255),
    TextDim = Color3.fromRGB(180, 180, 180),
    Accent = Color3.fromRGB(100, 150, 255),
    ButtonHover = Color3.fromRGB(50, 50, 70),
    CharSlot = Color3.fromRGB(40, 40, 55),
    CharSlotHover = Color3.fromRGB(55, 55, 75),
    CharSlotSelected = Color3.fromRGB(60, 80, 120),
    CreateNew = Color3.fromRGB(40, 60, 40),
    Locked = Color3.fromRGB(50, 40, 40),
    EnterButton = Color3.fromRGB(60, 120, 60),
    EnterButtonHover = Color3.fromRGB(80, 150, 80),
}

--============================================================================
-- CREATE UI
--============================================================================

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "CharacterSelectUI"
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.IgnoreGuiInset = true
screenGui.Enabled = false  -- Start disabled, will enable after getting character list
screenGui.Parent = playerGui
-- -- print("[CharacterSelect] Created UI (disabled, waiting for data)")

-- Full screen dark background
local background = Instance.new("Frame")
background.Name = "Background"
background.Size = UDim2.new(1, 0, 1, 0)
background.BackgroundColor3 = COLORS.Background
background.BorderSizePixel = 0
background.Parent = screenGui

-- Main panel (centered)
local mainPanel = Instance.new("Frame")
mainPanel.Name = "MainPanel"
mainPanel.Size = UDim2.new(0, 600, 0, 500)
mainPanel.Position = UDim2.new(0.5, -300, 0.5, -250)
mainPanel.BackgroundColor3 = COLORS.Panel
mainPanel.BorderSizePixel = 0
mainPanel.Parent = background

local panelCorner = Instance.new("UICorner")
panelCorner.CornerRadius = UDim.new(0, 8)
panelCorner.Parent = mainPanel

local panelStroke = Instance.new("UIStroke")
panelStroke.Color = COLORS.PanelBorder
panelStroke.Thickness = 2
panelStroke.Parent = mainPanel

-- Title
local title = Instance.new("TextLabel")
title.Name = "Title"
title.Size = UDim2.new(1, 0, 0, 50)
title.Position = UDim2.new(0, 0, 0, 10)
title.BackgroundTransparency = 1
title.Text = "SELECT CHARACTER"
title.TextColor3 = COLORS.Text
title.Font = Enum.Font.GothamBold
title.TextSize = 28
title.Parent = mainPanel

-- Character slots container
local slotsContainer = Instance.new("Frame")
slotsContainer.Name = "SlotsContainer"
slotsContainer.Size = UDim2.new(1, -40, 0, 300)
slotsContainer.Position = UDim2.new(0, 20, 0, 70)
slotsContainer.BackgroundTransparency = 1
slotsContainer.Parent = mainPanel

local slotsLayout = Instance.new("UIGridLayout")
slotsLayout.CellSize = UDim2.new(0, 170, 0, 140)
slotsLayout.CellPadding = UDim2.new(0, 15, 0, 15)
slotsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
slotsLayout.Parent = slotsContainer

-- Enter Game button
local enterButton = Instance.new("TextButton")
enterButton.Name = "EnterButton"
enterButton.Size = UDim2.new(0, 250, 0, 50)
enterButton.Position = UDim2.new(0.5, -125, 1, -70)
enterButton.BackgroundColor3 = COLORS.EnterButton
enterButton.Text = "ENTER GAME"
enterButton.TextColor3 = COLORS.Text
enterButton.Font = Enum.Font.GothamBold
enterButton.TextSize = 20
enterButton.AutoButtonColor = false
enterButton.Parent = mainPanel

local enterCorner = Instance.new("UICorner")
enterCorner.CornerRadius = UDim.new(0, 6)
enterCorner.Parent = enterButton

local enterStroke = Instance.new("UIStroke")
enterStroke.Color = Color3.fromRGB(80, 160, 80)
enterStroke.Thickness = 2
enterStroke.Parent = enterButton

-- Class selection popup (hidden by default)
local classPopup = Instance.new("Frame")
classPopup.Name = "ClassPopup"
classPopup.Size = UDim2.new(0, 400, 0, 350)
classPopup.Position = UDim2.new(0.5, -200, 0.5, -175)
classPopup.BackgroundColor3 = COLORS.Panel
classPopup.BorderSizePixel = 0
classPopup.Visible = false
classPopup.ZIndex = 10
classPopup.Parent = background

local popupCorner = Instance.new("UICorner")
popupCorner.CornerRadius = UDim.new(0, 8)
popupCorner.Parent = classPopup

local popupStroke = Instance.new("UIStroke")
popupStroke.Color = COLORS.Accent
popupStroke.Thickness = 2
popupStroke.Parent = classPopup

local popupTitle = Instance.new("TextLabel")
popupTitle.Name = "Title"
popupTitle.Size = UDim2.new(1, 0, 0, 40)
popupTitle.Position = UDim2.new(0, 0, 0, 10)
popupTitle.BackgroundTransparency = 1
popupTitle.Text = "SELECT CLASS"
popupTitle.TextColor3 = COLORS.Text
popupTitle.Font = Enum.Font.GothamBold
popupTitle.TextSize = 22
popupTitle.ZIndex = 11
popupTitle.Parent = classPopup

local classContainer = Instance.new("Frame")
classContainer.Name = "ClassContainer"
classContainer.Size = UDim2.new(1, -30, 0, 220)
classContainer.Position = UDim2.new(0, 15, 0, 55)
classContainer.BackgroundTransparency = 1
classContainer.ZIndex = 11
classContainer.Parent = classPopup

local classLayout = Instance.new("UIGridLayout")
classLayout.CellSize = UDim2.new(0, 110, 0, 100)
classLayout.CellPadding = UDim2.new(0, 10, 0, 10)
classLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
classLayout.Parent = classContainer

local cancelButton = Instance.new("TextButton")
cancelButton.Name = "CancelButton"
cancelButton.Size = UDim2.new(0, 120, 0, 35)
cancelButton.Position = UDim2.new(0.5, -60, 1, -50)
cancelButton.BackgroundColor3 = Color3.fromRGB(80, 40, 40)
cancelButton.Text = "CANCEL"
cancelButton.TextColor3 = COLORS.Text
cancelButton.Font = Enum.Font.GothamBold
cancelButton.TextSize = 16
cancelButton.ZIndex = 11
cancelButton.Parent = classPopup

local cancelCorner = Instance.new("UICorner")
cancelCorner.CornerRadius = UDim.new(0, 4)
cancelCorner.Parent = cancelButton

--============================================================================
-- STATE
--============================================================================

local selectedCharacterId = nil
local characterData = {}
local unlockedClasses = {}

-- Check if player already has an active character (script re-runs on respawn)
-- If character has stats attributes, they've already selected and entered the game
local function hasActiveCharacter()
    local character = player.Character
    if character and character:GetAttribute("Class") then
        return true
    end
    return false
end

local hasEnteredGame = hasActiveCharacter()  -- Initialize based on current state
-- -- print("[CharacterSelect] Initial hasEnteredGame = " .. tostring(hasEnteredGame))

--============================================================================
-- HELPER FUNCTIONS
--============================================================================

local function clearSlots()
    for _, child in ipairs(slotsContainer:GetChildren()) do
        if child:IsA("Frame") then
            child:Destroy()
        end
    end
end

local function createCharacterSlot(charData, index)
    local slot = Instance.new("Frame")
    slot.Name = "CharSlot_" .. index
    slot.BackgroundColor3 = COLORS.CharSlot
    slot.BorderSizePixel = 0
    slot.LayoutOrder = index

    local slotCorner = Instance.new("UICorner")
    slotCorner.CornerRadius = UDim.new(0, 6)
    slotCorner.Parent = slot

    local slotStroke = Instance.new("UIStroke")
    slotStroke.Color = COLORS.PanelBorder
    slotStroke.Thickness = 2
    slotStroke.Parent = slot

    -- Class name
    local className = Instance.new("TextLabel")
    className.Name = "ClassName"
    className.Size = UDim2.new(1, 0, 0, 30)
    className.Position = UDim2.new(0, 0, 0, 10)
    className.BackgroundTransparency = 1
    className.Text = charData.Class or "Unknown"
    className.TextColor3 = COLORS.Text
    className.Font = Enum.Font.GothamBold
    className.TextSize = 18
    className.Parent = slot

    -- Level
    local levelLabel = Instance.new("TextLabel")
    levelLabel.Name = "Level"
    levelLabel.Size = UDim2.new(1, 0, 0, 25)
    levelLabel.Position = UDim2.new(0, 0, 0, 40)
    levelLabel.BackgroundTransparency = 1
    levelLabel.Text = "Level " .. (charData.Level or 1)
    levelLabel.TextColor3 = COLORS.TextDim
    levelLabel.Font = Enum.Font.Gotham
    levelLabel.TextSize = 14
    levelLabel.Parent = slot

    -- Stats preview
    local stats = charData.Stats or {}
    local statsText = string.format("HP:%d ATT:%d DEF:%d",
        stats.HP or 100, stats.Attack or 10, stats.Defense or 0)
    local statsLabel = Instance.new("TextLabel")
    statsLabel.Name = "Stats"
    statsLabel.Size = UDim2.new(1, -10, 0, 20)
    statsLabel.Position = UDim2.new(0, 5, 0, 70)
    statsLabel.BackgroundTransparency = 1
    statsLabel.Text = statsText
    statsLabel.TextColor3 = COLORS.TextDim
    statsLabel.Font = Enum.Font.Gotham
    statsLabel.TextSize = 11
    statsLabel.TextXAlignment = Enum.TextXAlignment.Center
    statsLabel.Parent = slot

    -- Fame/kills
    local fameLabel = Instance.new("TextLabel")
    fameLabel.Name = "Fame"
    fameLabel.Size = UDim2.new(1, 0, 0, 20)
    fameLabel.Position = UDim2.new(0, 0, 0, 95)
    fameLabel.BackgroundTransparency = 1
    fameLabel.Text = (charData.EnemiesKilled or 0) .. " kills"
    fameLabel.TextColor3 = Color3.fromRGB(255, 200, 100)
    fameLabel.Font = Enum.Font.Gotham
    fameLabel.TextSize = 12
    fameLabel.Parent = slot

    -- Click to select
    local button = Instance.new("TextButton")
    button.Name = "SelectButton"
    button.Size = UDim2.new(1, 0, 1, 0)
    button.BackgroundTransparency = 1
    button.Text = ""
    button.Parent = slot

    button.MouseEnter:Connect(function()
        if selectedCharacterId ~= charData.CharacterId then
            slot.BackgroundColor3 = COLORS.CharSlotHover
        end
    end)

    button.MouseLeave:Connect(function()
        if selectedCharacterId ~= charData.CharacterId then
            slot.BackgroundColor3 = COLORS.CharSlot
        end
    end)

    button.MouseButton1Click:Connect(function()
        -- Deselect previous
        for _, child in ipairs(slotsContainer:GetChildren()) do
            if child:IsA("Frame") then
                child.BackgroundColor3 = COLORS.CharSlot
                local stroke = child:FindFirstChildOfClass("UIStroke")
                if stroke then
                    stroke.Color = COLORS.PanelBorder
                end
            end
        end

        -- Select this one
        selectedCharacterId = charData.CharacterId
        slot.BackgroundColor3 = COLORS.CharSlotSelected
        slotStroke.Color = COLORS.Accent
    end)

    slot.Parent = slotsContainer
    return slot
end

local function createNewCharacterSlot(index)
    local slot = Instance.new("Frame")
    slot.Name = "NewCharSlot"
    slot.BackgroundColor3 = COLORS.CreateNew
    slot.BorderSizePixel = 0
    slot.LayoutOrder = index

    local slotCorner = Instance.new("UICorner")
    slotCorner.CornerRadius = UDim.new(0, 6)
    slotCorner.Parent = slot

    local slotStroke = Instance.new("UIStroke")
    slotStroke.Color = Color3.fromRGB(60, 100, 60)
    slotStroke.Thickness = 2
    slotStroke.Parent = slot

    -- Plus icon
    local plusLabel = Instance.new("TextLabel")
    plusLabel.Name = "Plus"
    plusLabel.Size = UDim2.new(1, 0, 0, 50)
    plusLabel.Position = UDim2.new(0, 0, 0, 25)
    plusLabel.BackgroundTransparency = 1
    plusLabel.Text = "+"
    plusLabel.TextColor3 = Color3.fromRGB(100, 180, 100)
    plusLabel.Font = Enum.Font.GothamBold
    plusLabel.TextSize = 40
    plusLabel.Parent = slot

    -- Text
    local newLabel = Instance.new("TextLabel")
    newLabel.Name = "NewLabel"
    newLabel.Size = UDim2.new(1, 0, 0, 25)
    newLabel.Position = UDim2.new(0, 0, 0, 80)
    newLabel.BackgroundTransparency = 1
    newLabel.Text = "NEW CHARACTER"
    newLabel.TextColor3 = Color3.fromRGB(100, 180, 100)
    newLabel.Font = Enum.Font.GothamBold
    newLabel.TextSize = 12
    newLabel.Parent = slot

    -- Click to create
    local button = Instance.new("TextButton")
    button.Name = "CreateButton"
    button.Size = UDim2.new(1, 0, 1, 0)
    button.BackgroundTransparency = 1
    button.Text = ""
    button.Parent = slot

    button.MouseEnter:Connect(function()
        slot.BackgroundColor3 = Color3.fromRGB(50, 80, 50)
    end)

    button.MouseLeave:Connect(function()
        slot.BackgroundColor3 = COLORS.CreateNew
    end)

    button.MouseButton1Click:Connect(function()
        -- -- print("[CharacterSelect] New Character button clicked!")
        showClassSelection()
    end)

    slot.Parent = slotsContainer
    return slot
end

local function populateClassSelection()
    -- -- print("[CharacterSelect] populateClassSelection called")

    -- Clear existing
    for _, child in ipairs(classContainer:GetChildren()) do
        if child:IsA("Frame") then
            child:Destroy()
        end
    end

    local allClasses = ClassDatabase.Classes  -- Use .Classes directly instead of GetAllClasses
    -- -- print("[CharacterSelect] Found classes:", allClasses and "yes" or "nil")

    if not allClasses then
        warn("[CharacterSelect] No classes found in ClassDatabase!")
        return
    end

    local index = 1

    for className, classData in pairs(allClasses) do
        -- -- print("[CharacterSelect] Creating class button for:", className)
        local isUnlocked = table.find(unlockedClasses, className) ~= nil
        -- -- print("[CharacterSelect]   isUnlocked:", isUnlocked)

        local classSlot = Instance.new("Frame")
        classSlot.Name = "Class_" .. className
        classSlot.BackgroundColor3 = isUnlocked and COLORS.CharSlot or COLORS.Locked
        classSlot.BorderSizePixel = 0
        classSlot.LayoutOrder = index
        classSlot.ZIndex = 12

        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 4)
        corner.Parent = classSlot

        local stroke = Instance.new("UIStroke")
        stroke.Color = isUnlocked and COLORS.PanelBorder or Color3.fromRGB(80, 50, 50)
        stroke.Thickness = 1
        stroke.Parent = classSlot

        local nameLabel = Instance.new("TextLabel")
        nameLabel.Size = UDim2.new(1, 0, 0, 30)
        nameLabel.Position = UDim2.new(0, 0, 0, 15)
        nameLabel.BackgroundTransparency = 1
        nameLabel.Text = className
        nameLabel.TextColor3 = isUnlocked and COLORS.Text or Color3.fromRGB(120, 80, 80)
        nameLabel.Font = Enum.Font.GothamBold
        nameLabel.TextSize = 16
        nameLabel.ZIndex = 12
        nameLabel.Parent = classSlot

        local descLabel = Instance.new("TextLabel")
        descLabel.Size = UDim2.new(1, -10, 0, 40)
        descLabel.Position = UDim2.new(0, 5, 0, 50)
        descLabel.BackgroundTransparency = 1
        descLabel.Text = isUnlocked and (classData.Description or "A brave hero") or "LOCKED"
        descLabel.TextColor3 = isUnlocked and COLORS.TextDim or Color3.fromRGB(100, 60, 60)
        descLabel.Font = Enum.Font.Gotham
        descLabel.TextSize = 10
        descLabel.TextWrapped = true
        descLabel.ZIndex = 12
        descLabel.Parent = classSlot

        if isUnlocked then
            local button = Instance.new("TextButton")
            button.Size = UDim2.new(1, 0, 1, 0)
            button.BackgroundTransparency = 1
            button.Text = ""
            button.ZIndex = 13
            button.Parent = classSlot

            button.MouseEnter:Connect(function()
                classSlot.BackgroundColor3 = COLORS.CharSlotHover
            end)

            button.MouseLeave:Connect(function()
                classSlot.BackgroundColor3 = COLORS.CharSlot
            end)

            button.MouseButton1Click:Connect(function()
                createCharacter(className)
            end)
        end

        classSlot.Parent = classContainer
        index = index + 1
    end
end

function showClassSelection()
    -- -- print("[CharacterSelect] showClassSelection called")
    -- -- print("[CharacterSelect] classPopup exists:", classPopup ~= nil)
    -- -- print("[CharacterSelect] classPopup.Parent:", classPopup and classPopup.Parent and classPopup.Parent.Name or "nil")
    populateClassSelection()
    classPopup.Visible = true
    -- -- print("[CharacterSelect] classPopup.Visible set to true")
end

function hideClassSelection()
    classPopup.Visible = false
end

function createCharacter(className)
    hideClassSelection()

    local success, result = Remotes.Functions.CreateCharacter:InvokeServer(className)
    if success then
        -- -- print("[CharacterSelect] Created character: " .. className)
        -- Request updated character list
        local charList = Remotes.Functions.GetCharacterList:InvokeServer()
        if charList then
            refreshUI(charList.Characters, charList.UnlockedClasses)
        end
    else
        warn("[CharacterSelect] Failed to create character: " .. tostring(result))
    end
end

function refreshUI(characters, unlocked)
    characterData = characters or {}
    unlockedClasses = unlocked or {"Wizard"}

    -- Debug: Log what we received
    -- -- print("[CharacterSelect] refreshUI - Characters: " .. #characterData .. ", UnlockedClasses: " .. #unlockedClasses)
    for i, className in ipairs(unlockedClasses) do
        print("  Unlocked[" .. i .. "]: " .. tostring(className))
    end

    clearSlots()

    -- Create slots for existing characters
    for i, charData in ipairs(characterData) do
        createCharacterSlot(charData, i)
    end

    -- Add "New Character" slot
    createNewCharacterSlot(#characterData + 1)

    -- Auto-select first character if exists
    if #characterData > 0 then
        if not selectedCharacterId then
            selectedCharacterId = characterData[1].CharacterId
            local firstSlot = slotsContainer:FindFirstChild("CharSlot_1")
            if firstSlot then
                firstSlot.BackgroundColor3 = COLORS.CharSlotSelected
                local stroke = firstSlot:FindFirstChildOfClass("UIStroke")
                if stroke then
                    stroke.Color = COLORS.Accent
                end
            end
        end
    else
        -- No characters exist, auto-show class selection for convenience
        -- But only if player hasn't already entered game
        if not hasEnteredGame then
            -- -- print("[CharacterSelect] No characters, auto-showing class selection")
            task.defer(function()
                if not hasEnteredGame then
                    showClassSelection()
                end
            end)
        end
    end
end

--============================================================================
-- EVENT HANDLERS
--============================================================================

-- Enter game button
enterButton.MouseEnter:Connect(function()
    enterButton.BackgroundColor3 = COLORS.EnterButtonHover
end)

enterButton.MouseLeave:Connect(function()
    enterButton.BackgroundColor3 = COLORS.EnterButton
end)

-- Helper to show loading screen
local function showLoading(message)
    local loadingAPI = playerGui:FindFirstChild("LoadingScreenAPI")
    if loadingAPI then
        loadingAPI:Fire("Show", message)
    end
end

local function hideLoading()
    local loadingAPI = playerGui:FindFirstChild("LoadingScreenAPI")
    if loadingAPI then
        loadingAPI:Fire("Hide")
    end
end

enterButton.MouseButton1Click:Connect(function()
    -- -- print("[CharacterSelect] Enter button clicked, selectedCharacterId = " .. tostring(selectedCharacterId))

    if selectedCharacterId then
        -- -- print("[CharacterSelect] Calling SelectCharacter...")
        hasEnteredGame = true  -- Prevent UI from showing again

        -- Show loading screen
        showLoading("Entering the Realm...")

        -- Hide character select immediately
        screenGui.Enabled = false
        hideClassSelection()

        local success, errorMsg = pcall(function()
            return Remotes.Functions.SelectCharacter:InvokeServer(selectedCharacterId)
        end)

        -- -- print("[CharacterSelect] SelectCharacter returned - success: " .. tostring(success) .. ", errorMsg: " .. tostring(errorMsg))

        -- Loading will be hidden by server after spawn completes
    else
        -- -- print("[CharacterSelect] No character selected, showing class selection")
        -- No character selected, prompt to create
        showClassSelection()
    end
end)

-- Cancel button in class popup
cancelButton.MouseButton1Click:Connect(function()
    hideClassSelection()
end)

-- Show character select event (from server, e.g., after death)
Remotes.Events.ShowCharacterSelect.OnClientEvent:Connect(function(data)
    -- -- print("[CharacterSelect] ShowCharacterSelect event received")

    -- Check if this script instance's UI is still valid
    -- (Another script instance might have destroyed and recreated it)
    if not screenGui or not screenGui.Parent then
        warn("[CharacterSelect] ShowCharacterSelect: UI was destroyed, ignoring event")
        return
    end

    hasEnteredGame = false  -- Reset flag so UI can show
    selectedCharacterId = nil
    refreshUI(data.Characters, data.UnlockedClasses)
    screenGui.Enabled = true
    -- -- print("[CharacterSelect] UI enabled after ShowCharacterSelect")
end)

-- Hide character select event
Remotes.Events.HideCharacterSelect.OnClientEvent:Connect(function()
    -- -- print("[CharacterSelect] HideCharacterSelect event received")

    -- Check if this script instance's UI is still valid
    if not screenGui or not screenGui.Parent then
        warn("[CharacterSelect] HideCharacterSelect: UI was destroyed, ignoring event")
        return
    end

    hasEnteredGame = true
    screenGui.Enabled = false
    hideClassSelection()
end)

-- Request initial character list on startup
task.defer(function()
    -- Skip if player already entered game (either from initial check or during load)
    if hasEnteredGame or hasActiveCharacter() then
        -- -- print("[CharacterSelect] Already entered game, skipping initial request")
        hasEnteredGame = true
        return
    end

    -- -- print("[CharacterSelect] Requesting initial character list...")

    -- Retry loop - server may still be loading player data
    local charList = nil
    for attempt = 1, 5 do
        -- Check again in case player entered game during retries
        if hasEnteredGame or hasActiveCharacter() then
            -- -- print("[CharacterSelect] Entered game during retry, aborting")
            hasEnteredGame = true
            return
        end

        charList = Remotes.Functions.GetCharacterList:InvokeServer()
        if charList and charList.Characters then
            -- -- print("[CharacterSelect] Got character list on attempt " .. attempt)
            break
        end
        -- -- print("[CharacterSelect] Attempt " .. attempt .. " failed, retrying...")
        task.wait(0.5)
    end

    -- Skip if player entered game while we were fetching
    if hasEnteredGame or hasActiveCharacter() then
        -- -- print("[CharacterSelect] Entered game while fetching, not showing UI")
        hasEnteredGame = true
        return
    end

    -- Refresh UI with whatever we got (or defaults)
    if charList and charList.Characters then
        refreshUI(charList.Characters, charList.UnlockedClasses or {"Wizard"})
    else
        warn("[CharacterSelect] Could not get character list, using defaults")
        refreshUI({}, {"Wizard"})
    end

    -- NOW enable the UI (only once, only if we haven't entered game)
    if not hasEnteredGame and not hasActiveCharacter() then
        -- -- print("[CharacterSelect] Enabling UI for first time")
        screenGui.Enabled = true
    else
        -- -- print("[CharacterSelect] Skipping UI enable - already in game")
    end
end)

-- -- print("[CharacterSelect] Initialized")
