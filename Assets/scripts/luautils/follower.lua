local Utilities = require "scripts.luautils.utilities"
local Events = require "scripts.luautils.events"

local Follower = {
    Properties = {
        Debug = false,
        MoveSpeed = 10,
        Hop = false,
        HopVelocity = 100.0,
        HopWaitTime = { default = 1, description = "time to wait between hops in seconds"},
        PathTargetRange = { default = 1.0, description = "acceptable range to next path location before moving to next path point"},
        TargetRange =  { default=2.0, description = "acceptable range to target to stop following" },
        FollowTag={ default="player", description="The tag of the entity to follow" },
        NavMeshTag={ default="NavMesh", description="The tag of the NavMesh entity" },
        VisibleRange = { default=20, suffix = " m"},
        CheckVisibility = true,
        FollowCollisionGroup = "FollowerCollision",
        EyeOffset = { default = Vector3(0.0, 0.0, 0.3), description="eye offset"},
        NavOffset = { default = 0.3, description="nav mesh offset"},
    },
    FollowerTagListener = {},
    NavMeshTagListener = {},
}

function Follower:OnActivate()
    Utilities:InitLogging(self)

    self.pathTargetRangeSq = self.Properties.PathTargetRange * self.Properties.PathTargetRange
    self.targetRangeSq = self.Properties.TargetRange * self.Properties.TargetRange
    self.playerMoveThresholdSq = 4
    self.nextAllowedPathUpdateThreshold = 0.25 -- allow updating once per second

    local physicsSystem = GetPhysicsSystem()
    local physicsSceneHandle = physicsSystem:GetSceneHandle(DefaultPhysicsSceneName)
    self.scene = physicsSystem:GetScene(physicsSceneHandle)

    self.spawnTM = TransformBus.Event.GetWorldTM(self.entityId)
    self.visibleRangeSq = tonumber(self.Properties.VisibleRange) * tonumber(self.Properties.VisibleRange)

    -- we must set tickListener to nil BEFORE connecting to the tag bus because 
    -- onentitytagadded might get called immediately so we'd be wiping out the tick listener
    -- which gets garbage collected eventually and stops calling OnTick, VERY difficult to figure out
    self.tickListener = nil
    self.transformListener = nil
    self.navmesh = nil

    self:Reset()
    Events:Connect(self, Events.OnStateChange)
    Events:Connect(self, Events.OnVisibileToFlashLightChanged, self.entityId)

    self.FollowerTagListener.component = self
    self.FollowerTagListener.listener = TagGlobalNotificationBus.Connect(self.FollowerTagListener, Crc32(self.Properties.FollowTag))
    self.NavMeshTagListener.component = self
    self.NavMeshTagListener.listener = TagGlobalNotificationBus.Connect(self.NavMeshTagListener, Crc32(self.Properties.NavMeshTag))
end

function Follower.FollowerTagListener:OnEntityTagAdded(entityId)
    -- you cannot disconnect from any listeners in here because 
    -- this method can get called during connect before the listener is returned
    self.component:Log("Entity added with follower tag")
    self.component.player = entityId
    self.component.playerLastPosition = TransformBus.Event.GetWorldTranslation(self.component.player)
    self.component.tickListener = TickBus.Connect(self.component, 0)
end

function Follower.NavMeshTagListener:OnEntityTagAdded(entityId)
    self.component:Log("Entity added with NavMesh tag")
    self.component.navmesh = entityId
end

function Follower:OnStateChange(value)
    if value == 'Reset' then
        self:Reset()
    end
    self.enabled = value == 'InGame'
    self:Log("enabled: "..tostring(self.enabled))
end

function Follower:Reset()
    self:Log("Reset")
    TransformBus.Event.SetWorldTM(self.entityId, self.spawnTM)
    AudioTriggerComponentRequestBus.Event.KillAllTriggers(self.entityId)

    self.nextAllowedPathUpdate = 0
    self.nextHopTime = 0
    self.footStepTimeWait = 0.5
    self.nextFootStepTime = 0
    self.nextPathUpdate = 0
    self.path = {} 
    self.nextPathIndex = 1
    self.destination = nil
    self.playerLastPosition = nil
    self.visibleToFlashLight = false
    self.canSeePlayer = false
    self.enabled = true
    self.visibilityBlocker = nil
    self.closeToPlayer = false
end

function Follower:OnVisibileToFlashLightChanged(value)
    self.visibleToFlashLight = value
    self:Log("OnVisibileToFlashLightChanged")
end

function Follower:CalculatePath(fromPosition, toPosition)
    local scriptTime = TickRequestBus.Broadcast.GetTimeAtCurrentTick()
    if self.nextAllowedPathUpdate < scriptTime:GetSeconds() then
        local offset = Vector3(0,0,self.Properties.NavOffset)
        if self.navmesh ~= nil then
            -- set the navmesh before trying to find paths
            DetourNavigationRequestBus.Event.SetNavigationMeshEntity(self.entityId, self.navmesh)
            self.path = DetourNavigationRequestBus.Event.FindPathBetweenPositions(self.entityId, fromPosition + offset, toPosition + offset)
            self.nextPathIndex = 1
            self:Log("path to player has ".. tostring(#self.path) .. " path points from " .. tostring(fromPosition + offset) .. " to " .. tostring(toPosition + offset))
        else
            self:Log("Missing navmesh entity")
        end
        self.nextAllowedPathUpdate = scriptTime:GetSeconds() + self.nextAllowedPathUpdateThreshold
    end
end

function Follower:CanSeePlayer(selfTm, playerTm)
    if not self.Properties.CheckVisibility then
        return true
    end

    local selfToPlayer = playerTm:GetTranslation() - selfTm:GetTranslation()
    local distanceSq = selfToPlayer:GetLengthSq()
    if distanceSq <= self.targetRangeSq then
        if not self.closeToPlayer then
            self.closeToPlayer = true
            self:Log("player in close proximity")
        end
        return true
    elseif distanceSq <= self.visibleRangeSq then
        self.closeToPlayer = false 
        local request = SceneQueries.CreateRayCastRequest(
            selfTm:GetTranslation() + self.Properties.EyeOffset,
            selfToPlayer:GetNormalized(),
            --selfToPlayer:GetLength() + 1,
            self.Properties.VisibleRange,
            self.Properties.FollowCollisionGroup
            )
        local hits = PhysicsScene.QueryScene(self.scene, request)
        if #hits.HitArray > 0 then
            if hits.HitArray[1].EntityId == self.player then
                return true
            end
            if self.Properties.Debug then
                if hits.HitArray[1].EntityId:IsValid() then
                    if self.visibilityBlocker ~= hits.HitArray[1].EntityId then
                        self.visibilityBlocker = hits.HitArray[1].EntityId
                        local name = GameEntityContextRequestBus.Broadcast.GetEntityName(self.visibilityBlocker)
                        self:Log("player vision blocked by " .. tostring(name))
                    end
                else
                    self:Log("player vision blocked by invalid entity/terrain?")
                end 
            end
        else
            self:Log("player vision query hit nothing")
        end
    else
        self.closeToPlayer = false
        self:Log("player outside visible range")
    end
    return false
end

function Follower:FaceDirection(direction)
	local rotation = Math.ArcTan2(direction.y, direction.x)
	local worldRotation = Vector3(0,0,rotation - math.pi)
	TransformBus.Event.SetWorldRotation(self.entityId, worldRotation)
end

function Follower:OnTick(deltaTime, scriptTime)
    if not self.enabled then
        return
    end

    local playerTm = TransformBus.Event.GetWorldTM(self.player)
    local selfTm =  TransformBus.Event.GetWorldTM(self.entityId)

    local couldSeePlayer = self.canSeePlayer
    --self:Log("checking visibility could see player: ".. tostring(couldSeePlayer))
    self.canSeePlayer = self:CanSeePlayer(selfTm, playerTm)
    --self:Log("can see player: ".. tostring(self.canSeePlayer))
    if self.canSeePlayer ~= couldSeePlayer then
        self:Log(tostring(self.canSeePlayer) .. " vs " ..tostring(couldSeePlayer))
        if self.canSeePlayer then
            self:Log("Can see player")
            -- we can update the path now
            self.nextAllowedPathUpdate = 0
            self.transformListener = TransformNotificationBus.Connect(self, self.player)
        elseif self.transformListener then
            self:Log("Can no longer see player")
            self.transformListener:Disconnect(self.player)
        else
            self:Log("Cannot see player")
        end
    end

    --RenderMeshComponentRequestBus.Event.SetVisibility(self.entityId, self.visibleToFlashLight)

    -- always face the player
    if self.canSeePlayer then
        local direction = playerTm:GetTranslation() - selfTm:GetTranslation()
        direction = direction:GetNormalized()
        self:FaceDirection(direction)
    end

    -- if we're supposed to hop then wait
    if self.Properties.Hop and self.nextHopTime > scriptTime:GetSeconds()  then
        return
    end

    if self.canSeePlayer then
        -- update our path if we can see the player
        if #self.path == 0 and self.nextPathUpdate < scriptTime:GetSeconds() then
            self.nextPathUpdate = scriptTime:GetSeconds() + 1.0
            self:CalculatePath(selfTm:GetTranslation(), playerTm:GetTranslation())
        end
    end

    -- travel to next point in path
    if #self.path > 0 and self.nextPathIndex < #self.path then
        self:Log("moving to path index " ..tostring(self.nextPathIndex))
        self.destination = self.path[self.nextPathIndex]
        if self.destination == nil then
            self:Log("next path index destination is nil!")
        end
    end

    if self.destination ~= nil then
        local delta =  self.destination - selfTm:GetTranslation()
        self:Log("Checking distance delta: " ..  tostring(delta))
        if delta:GetLengthSq() <= self.pathTargetRangeSq then
            self:Log("Updating path point")
            if self.nextPathIndex < #self.path then
                self.nextPathIndex = self.nextPathIndex + 1
                self.destination = self.path[self.nextPathIndex]

                delta =  self.destination - selfTm:GetTranslation()
            else
                local targetDelta = playerTm:GetTranslation() - selfTm:GetTranslation()
                if targetDelta:GetLengthSq() > self.targetRangeSq then
                    if self.canSeePlayer then
                        self:Log("Moving closer")
                        self:CalculatePath(selfTm:GetTranslation(), playerTm:GetTranslation())
                    end
                else
                    self:Log("Arrived at ".. tostring(self.nextPathIndex))
                end

                self.destination = nil
            end
        end

        if self.destination ~= nil then
            local isOnGround = CharacterGameplayRequestBus.Event.IsOnGround(self.entityId) 
            if isOnGround then
                if self.Properties.Hop then
                    self.nextHopTime = scriptTime:GetSeconds() + self.Properties.HopWaitTime
                    self:Log("Hopping ".. tostring(self.Properties.HopVelocity))
                    delta.z = 0
                    local direction = delta:GetNormalized()
                    direction.z = 0.2
                    local moveAmount = direction * self.Properties.HopVelocity;
                    CharacterControllerRequestBus.Event.AddVelocityForPhysicsTimestep(self.entityId, moveAmount, 1.0)
                else
                    local moveAmount = delta:GetNormalized() * self.Properties.MoveSpeed * deltaTime;
                    self:PlayFootstep(moveAmount:GetLength(), scriptTime:GetSeconds())

                    self:Log("Moving ".. tostring(moveAmount))
                    CharacterControllerRequestBus.Event.AddVelocityForTick(self.entityId, moveAmount)
                end
            end
        end
    end

end

function Follower:PlayFootstep(speed, currentTime)
    if self.nextFootStepTime < currentTime then
        if speed <= 5.0 then
            self.nextFootStepTime = currentTime + self.footStepTimeWait
            AudioTriggerComponentRequestBus.Event.Play(self.entityId)
        else
            self.nextFootStepTime = currentTime + self.footStepTimeWait * 0.75 
            AudioTriggerComponentRequestBus.Event.Play(self.entityId)
        end
    end
end

function Follower:OnTransformChanged(localTm, worldTm)
    local newPosition = worldTm:GetTranslation()
    local selfPos =  TransformBus.Event.GetWorldTranslation(self.entityId)

    if self.playerLastPosition == nil then
        --self:Log("player moved (nil)")
        self.playerLastPosition = newPosition
        self:CalculatePath(selfPos, newPosition)
    elseif newPosition:GetDistanceSq(self.playerLastPosition) > self.playerMoveThresholdSq then
        --self:Log("player moved (move threshold)")
        self:CalculatePath(selfPos, newPosition)
        self.playerLastPosition = newPosition
    elseif self.playerLastPosition ~= newPosition and newPosition:GetDistanceSq(selfPos) > self.pathTargetRangeSq then
        --self:Log("player moved (pathTargetRange)")
        self:CalculatePath(selfPos, newPosition)
        self.playerLastPosition = newPosition
    end
end

function Follower:OnDeactivate()
    self:Log('OnDeactivate')
    self.FollowerTagListener.listener:Disconnect()
    self.NavMeshTagListener.listener:Disconnect()
    if self.transformListener ~= nil then
        self.transformListener:Disconnect()
    end
    if self.tickListener ~= nil then
        self:Log("disconnecting")
        self.tickListener:Disconnect()
    end

    Events:Disconnect(self)
end

return Follower