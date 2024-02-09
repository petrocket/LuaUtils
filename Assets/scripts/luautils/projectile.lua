local Events = require "Scripts.events"
local Utilities = require "Scripts.utilities"

local Projectile = {
    Properties = {
        Velocity = 100.0,
        MaxDistance = 30
    }
}

function Projectile:OnActivate()
    -- really we shouldn't have every bullet do this
    -- bulletspawner should
    self.startPosition = TransformBus.Event.GetWorldTranslation(self.entityId)
    --Debug.Log("Start Position " .. tostring(self.startPosition))
    self.MaxDistanceSq = self.Properties.MaxDistance * self.Properties.MaxDistance
    self.tickHandler = TickBus.Connect(self)

    Utilities:ExecuteOnNextTick(self, function()
        --self.collisionEvent = SimulatedBody.GetOnCollisionBeginEvent(self.entityId)
        --if self.collisionEvent ~= nil then
        --    Debug.Log("Adding collision handler")
        --    self.collisionHandler = self.collisionEvent:Connect(function(body, collisionEvent)
        --       Debug.Log("Collision")
        --    end)
        --end
        --local nextPosition = TransformBus.Event.GetWorldTranslation(self.entityId)
        --Debug.Log("Next Position " .. tostring(nextPosition))

        self.triggerEvent = SimulatedBody.GetOnTriggerEnterEvent(self.entityId)
        if self.triggerEvent ~= nil then
            self.triggerHandler = self.triggerEvent:Connect(function()
                --Debug.Log("Trigger ")
                GameEntityContextRequestBus.Broadcast.DestroyGameEntityAndDescendants(self.entityId)
            end)
        end
    end)
end

function Projectile:OnTick(deltaTime, scriptTime)
    local position = TransformBus.Event.GetWorldTranslation(self.entityId)

    local tm = TransformBus.Event.GetWorldTM(self.entityId)
    local velocity = self.Properties.Velocity * deltaTime
    --Debug.Log("velocity is " .. tostring(velocity))
    tm:SetTranslation(tm:GetTranslation() + tm:GetBasisY() * velocity)
    RigidBodyRequestBus.Event.SetKinematicTarget(self.entityId, tm)

    if position:GetDistanceSq(self.startPosition) >= self.MaxDistanceSq then
        --Debug.Log("Destroy on too far")
        GameEntityContextRequestBus.Broadcast.DestroyGameEntityAndDescendants(self.entityId)
    end
end

function Projectile:OnDeactivate()
    if self.tickHandler ~= nil then
        self.tickHandler:Disconnect()
        self.tickHandler = nil
    end
    if self.collisionHandler ~= nil then
        self.collisionHandler:Disconnect()
    end
    self.collisionEvent = nil
    if self.triggerHandler ~= nil then
        self.triggerHandler:Disconnect()
    end
    self.collisionEvent = nil
end

return Projectile