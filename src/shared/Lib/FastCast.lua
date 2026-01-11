--[[
    FastCast
    High-performance projectile raycasting system

    Features:
    - Stepped raycasting (no missed collisions at high speeds)
    - Piercing support via CanPierceFunction
    - Automatic gravity/acceleration
    - Event-based hit detection

    Usage:
        local caster = FastCast.new()
        caster.RayHit:Connect(function(cast, result, velocity, bullet)
            -- Handle hit
        end)
        caster:Fire(origin, direction, velocity, castBehavior)
]]

local RunService = game:GetService("RunService")

--============================================================================
-- SIGNAL CLASS (Simple event system)
--============================================================================
local Signal = {}
Signal.__index = Signal

function Signal.new()
    return setmetatable({_connections = {}}, Signal)
end

function Signal:Connect(callback)
    local connection = {
        Callback = callback,
        Disconnect = function(self)
            self.Connected = false
        end,
        Connected = true,
    }
    table.insert(self._connections, connection)
    return connection
end

function Signal:Fire(...)
    for _, conn in ipairs(self._connections) do
        if conn.Connected then
            task.spawn(conn.Callback, ...)
        end
    end
end

--============================================================================
-- CAST BEHAVIOR
--============================================================================
local CastBehavior = {}
CastBehavior.__index = CastBehavior

function CastBehavior.new()
    return setmetatable({
        RaycastParams = nil,
        MaxDistance = 1000,
        HighFidelityBehavior = 1,   -- 1 = Default, 2 = Always
        HighFidelitySegmentSize = 4,
        Acceleration = Vector3.zero,
        AutoIgnoreContainer = true,
        CosmeticBulletContainer = workspace,
        CosmeticBulletTemplate = nil,
        CosmeticBulletProvider = nil,  -- PartCache instance
        CanPierceFunction = nil,       -- function(cast, result, velocity) -> bool
    }, CastBehavior)
end

--============================================================================
-- ACTIVE CAST
--============================================================================
local ActiveCast = {}
ActiveCast.__index = ActiveCast

function ActiveCast.new(caster, origin, direction, velocity, behavior, userData)
    local self = setmetatable({}, ActiveCast)

    self.Caster = caster
    self.Origin = origin
    self.Direction = direction.Unit
    self.Velocity = direction.Unit * velocity
    self.Position = origin
    self.Behavior = behavior
    self.UserData = userData or {}
    self.StateInfo = {
        TotalRuntime = 0,
        DistanceCovered = 0,
        IsActive = true,
        Paused = false,
        HitList = {},   -- Track pierced targets
    }
    self.RayInfo = {
        Parameters = behavior.RaycastParams or RaycastParams.new(),
    }
    self.CosmeticBullet = nil

    -- Get cosmetic bullet from cache or create
    if behavior.CosmeticBulletProvider then
        self.CosmeticBullet = behavior.CosmeticBulletProvider:GetPart()
        self.CosmeticBullet.CFrame = CFrame.new(origin, origin + direction)
    elseif behavior.CosmeticBulletTemplate then
        self.CosmeticBullet = behavior.CosmeticBulletTemplate:Clone()
        self.CosmeticBullet.CFrame = CFrame.new(origin, origin + direction)
        self.CosmeticBullet.Parent = behavior.CosmeticBulletContainer
    end

    return self
end

function ActiveCast:Terminate()
    self.StateInfo.IsActive = false

    -- Return bullet to cache
    if self.CosmeticBullet then
        if self.Behavior.CosmeticBulletProvider then
            self.Behavior.CosmeticBulletProvider:ReturnPart(self.CosmeticBullet)
        else
            self.CosmeticBullet:Destroy()
        end
        self.CosmeticBullet = nil
    end
end

function ActiveCast:Pause()
    self.StateInfo.Paused = true
end

function ActiveCast:Resume()
    self.StateInfo.Paused = false
end

function ActiveCast:GetPosition()
    return self.Position
end

function ActiveCast:GetVelocity()
    return self.Velocity
end

function ActiveCast:SetVelocity(newVelocity)
    self.Velocity = newVelocity
end

function ActiveCast:SetAcceleration(newAcceleration)
    self.Behavior.Acceleration = newAcceleration
end

--============================================================================
-- FASTCAST MAIN
--============================================================================
local FastCast = {}
FastCast.__index = FastCast

-- Class method to create new behavior
FastCast.newBehavior = CastBehavior.new

function FastCast.new()
    local self = setmetatable({}, FastCast)

    -- Events
    self.RayHit = Signal.new()
    self.RayPierced = Signal.new()
    self.LengthChanged = Signal.new()
    self.CastTerminating = Signal.new()

    -- Active casts
    self._activeCasts = {}
    self._connection = nil

    return self
end

function FastCast:Fire(origin: Vector3, direction: Vector3, velocity: number, behavior: table, userData: table?)
    local cast = ActiveCast.new(self, origin, direction, velocity, behavior, userData)
    table.insert(self._activeCasts, cast)

    -- Start update loop if not running
    if not self._connection then
        self._connection = RunService.Heartbeat:Connect(function(dt)
            self:_update(dt)
        end)
    end

    return cast
end

function FastCast:_update(deltaTime: number)
    local castsToRemove = {}

    for i, cast in ipairs(self._activeCasts) do
        if not cast.StateInfo.IsActive or cast.StateInfo.Paused then
            if not cast.StateInfo.IsActive then
                table.insert(castsToRemove, i)
            end
            continue
        end

        local behavior = cast.Behavior
        local acceleration = behavior.Acceleration or Vector3.zero

        -- Update velocity with acceleration
        cast.Velocity = cast.Velocity + acceleration * deltaTime

        -- Calculate movement this frame
        local movement = cast.Velocity * deltaTime
        local segmentLength = movement.Magnitude

        -- High fidelity: break into smaller segments for fast projectiles
        local segmentSize = behavior.HighFidelitySegmentSize or 4
        local numSegments = math.max(1, math.ceil(segmentLength / segmentSize))

        local terminated = false

        for seg = 1, numSegments do
            if terminated then break end

            local segmentMovement = movement / numSegments
            local segmentStart = cast.Position
            local segmentEnd = segmentStart + segmentMovement

            -- Raycast this segment
            local result = workspace:Raycast(segmentStart, segmentMovement, cast.RayInfo.Parameters)

            if result then
                local hitPart = result.Instance
                local hitPoint = result.Position

                -- Check if already hit this target
                if not cast.StateInfo.HitList[hitPart] then
                    -- Check pierce function
                    local shouldPierce = false
                    if behavior.CanPierceFunction then
                        shouldPierce = behavior.CanPierceFunction(cast, result, cast.Velocity)
                    end

                    if shouldPierce then
                        -- Mark as hit and continue
                        cast.StateInfo.HitList[hitPart] = true
                        self.RayPierced:Fire(cast, result, cast.Velocity, cast.CosmeticBullet)
                    else
                        -- Hit and stop
                        cast.StateInfo.HitList[hitPart] = true
                        cast.Position = hitPoint

                        -- Update cosmetic bullet
                        if cast.CosmeticBullet then
                            local lookDir = cast.Velocity.Unit
                            cast.CosmeticBullet.CFrame = CFrame.new(hitPoint, hitPoint + lookDir)
                        end

                        -- Fire hit event
                        self.RayHit:Fire(cast, result, cast.Velocity, cast.CosmeticBullet)
                        self.CastTerminating:Fire(cast)
                        cast:Terminate()
                        terminated = true
                    end
                end
            end

            if not terminated then
                cast.Position = segmentEnd
            end
        end

        if not terminated then
            -- Update cosmetic bullet position
            if cast.CosmeticBullet then
                local lookDir = cast.Velocity.Unit
                cast.CosmeticBullet.CFrame = CFrame.new(cast.Position, cast.Position + lookDir)
            end

            -- Check max distance
            cast.StateInfo.DistanceCovered = cast.StateInfo.DistanceCovered + segmentLength
            cast.StateInfo.TotalRuntime = cast.StateInfo.TotalRuntime + deltaTime

            -- Fire length changed event
            self.LengthChanged:Fire(cast, cast.Origin, cast.Position, cast.Velocity, cast.CosmeticBullet)

            if cast.StateInfo.DistanceCovered >= (behavior.MaxDistance or 1000) then
                self.CastTerminating:Fire(cast)
                cast:Terminate()
            end
        end
    end

    -- Remove terminated casts (reverse order)
    for i = #castsToRemove, 1, -1 do
        table.remove(self._activeCasts, castsToRemove[i])
    end

    -- Stop update loop if no active casts
    if #self._activeCasts == 0 and self._connection then
        self._connection:Disconnect()
        self._connection = nil
    end
end

function FastCast:Destroy()
    if self._connection then
        self._connection:Disconnect()
        self._connection = nil
    end

    for _, cast in ipairs(self._activeCasts) do
        cast:Terminate()
    end
    self._activeCasts = {}
end

return FastCast
