--[[
    VaultController.lua
    Client-side vault chest interaction (walk-over detection)

    Features:
    - Automatic walk-over detection (no "Press E" needed)
    - Auto-open chest when stepping on glowing floor square
    - Auto-close chest when stepping off

    Note: UI is handled by HUDController (reuses loot bag UI)
          Chests are flat glowing squares flush with floor
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local Remotes = require(Shared.Remotes)

local VaultController = {}

--============================================================================
-- CONFIGURATION
--============================================================================

local CHEST_INTERACT_RADIUS = Constants.Vault.CHEST_INTERACT_RADIUS

--============================================================================
-- STATE
--============================================================================

local currentStandingChest = nil  -- Chest player is standing on (auto-opened)
local isVaultUIOpen = false
local currentOpenChest = nil

--============================================================================
-- PERFORMANCE OPTIMIZATION: Cached references and throttling
--============================================================================

-- Cached references (avoid repeated lookups)
local cachedVaultRoom = nil
local cachedChests = {}  -- {Part, ChestIndex, X, Z} - pre-extracted data
local cachedCharacter = nil
local cachedRootPart = nil

-- Vault area bounds (pre-calculated, avoid per-frame math)
local vaultCenterX = 0
local vaultCenterZ = 0
local vaultRadiusSq = 0  -- Squared radius for fast comparison

-- Throttling
local UPDATE_INTERVAL = 0.1  -- Check every 100ms instead of every frame (60fps → 10fps for this check)
local lastUpdateTime = 0

-- Pre-calculate squared interact radius (avoid sqrt in distance check)
local CHEST_INTERACT_RADIUS_SQ = CHEST_INTERACT_RADIUS * CHEST_INTERACT_RADIUS

--============================================================================
-- HELPER FUNCTIONS (Optimized)
--============================================================================

local function getPlayerPosition()
    local character = player.Character
    if character ~= cachedCharacter then
        cachedCharacter = character
        cachedRootPart = character and character:FindFirstChild("HumanoidRootPart")
    end
    return cachedRootPart and cachedRootPart.Position
end

local function isInVaultArea(playerPos)
    if not playerPos then return false end
    -- Use squared distance (no sqrt)
    local dx = playerPos.X - vaultCenterX
    local dz = playerPos.Z - vaultCenterZ
    return (dx * dx + dz * dz) < vaultRadiusSq
end

-- Cache vault room and chest data (call once, or when vault changes)
local function cacheVaultData()
    cachedVaultRoom = workspace:FindFirstChild("VaultRoom")
    if not cachedVaultRoom then return end

    cachedChests = {}
    for _, child in ipairs(cachedVaultRoom:GetChildren()) do
        if child:IsA("BasePart") and child:GetAttribute("ChestType") == "Vault" then
            table.insert(cachedChests, {
                Part = child,
                ChestIndex = child:GetAttribute("ChestIndex"),
                X = child.Position.X,
                Z = child.Position.Z,
            })
        end
    end

    -- Pre-calculate vault area bounds
    local vaultCenter = Constants.Vault.CENTER
    local floorSize = Constants.Vault.FLOOR_SIZE
    vaultCenterX = vaultCenter.X
    vaultCenterZ = vaultCenter.Z
    local radius = math.max(floorSize.X, floorSize.Z) / 2 + 20
    vaultRadiusSq = radius * radius

    print("[VaultController] Cached " .. #cachedChests .. " vault chests")
end

--============================================================================
-- CHEST DETECTION (Optimized - uses cached data)
--============================================================================

local function findChestAtPosition(playerPos)
    if not playerPos or #cachedChests == 0 then return nil end

    local playerX, playerZ = playerPos.X, playerPos.Z
    local closestChest = nil
    local closestDistSq = CHEST_INTERACT_RADIUS_SQ

    for _, chest in ipairs(cachedChests) do
        -- Use squared distance (no sqrt, no Vector3 allocation)
        local dx = playerX - chest.X
        local dz = playerZ - chest.Z
        local distSq = dx * dx + dz * dz

        if distSq < closestDistSq then
            closestDistSq = distSq
            closestChest = {
                Part = chest.Part,
                ChestIndex = chest.ChestIndex,
                -- Read attributes only when we need them (found closest)
                IsUnlocked = chest.Part:GetAttribute("IsUnlocked"),
                IsGold = chest.Part:GetAttribute("IsGold"),
            }
        end
    end

    return closestChest
end


--============================================================================
-- AUTO-OPEN/CLOSE CHEST
--============================================================================

local function openChest(chest)
    if isVaultUIOpen and currentOpenChest == chest.ChestIndex then
        return -- Already open for this chest
    end

    -- Let server decide if chest is accessible (checks player's UnlockedChestCount)
    -- Server will send VaultChestOpened if unlocked, or Notification if locked
    print("[VaultController] Auto-opening vault chest " .. chest.ChestIndex)
    Remotes.Events.OpenVaultChest:FireServer(chest.ChestIndex)
    isVaultUIOpen = true
    currentOpenChest = chest.ChestIndex
end

local function closeChest()
    if not isVaultUIOpen then return end

    print("[VaultController] Auto-closing vault chest UI")
    -- Fire to server - HUDController will receive VaultChestClosed
    Remotes.Events.CloseVaultChest:FireServer()
    isVaultUIOpen = false
    currentOpenChest = nil
end

--============================================================================
-- UPDATE LOOP (Throttled for performance)
--============================================================================

local function update()
    -- Throttle: Only check every UPDATE_INTERVAL seconds
    local now = tick()
    if now - lastUpdateTime < UPDATE_INTERVAL then
        return
    end
    lastUpdateTime = now

    local playerPos = getPlayerPosition()

    if not isInVaultArea(playerPos) then
        -- Close UI if player leaves vault area
        if isVaultUIOpen then
            closeChest()
        end
        currentStandingChest = nil
        return
    end

    -- Lazy-cache vault data on first vault entry
    if #cachedChests == 0 then
        cacheVaultData()
    end

    -- Find chest player is standing on
    local chestAtPos = findChestAtPosition(playerPos)

    if chestAtPos then
        -- Player is standing on a chest
        if currentStandingChest ~= chestAtPos.ChestIndex then
            -- Moved to a new chest
            currentStandingChest = chestAtPos.ChestIndex
            openChest(chestAtPos)
        end
    else
        -- Player stepped off chest
        if currentStandingChest then
            currentStandingChest = nil
            closeChest()
        end
    end
end

--============================================================================
-- INITIALIZATION
--============================================================================

function VaultController.Init()
    Remotes.Init()

    -- Connect update loop (throttled internally)
    RunService.Heartbeat:Connect(update)

    -- Listen for vault room changes (re-cache if chests are added/unlocked)
    workspace.ChildAdded:Connect(function(child)
        if child.Name == "VaultRoom" then
            task.wait(0.5)  -- Wait for children to be added
            cacheVaultData()
        end
    end)

    print("[VaultController] Initialized (walk-over floor squares, optimized)")
end

--============================================================================
-- PUBLIC API
--============================================================================

function VaultController.IsChestOpen()
    return isVaultUIOpen
end

function VaultController.GetCurrentChest()
    return currentOpenChest
end

function VaultController.CloseChest()
    closeChest()
end

-- Get the chest the player is currently standing on
function VaultController.GetStandingChest()
    return currentStandingChest
end

return VaultController
