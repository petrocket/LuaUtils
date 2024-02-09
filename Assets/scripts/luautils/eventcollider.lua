local Events = require "scripts.luautils.events"
local Utilities = require "scripts.luautils.utilities"

local EventCollider = {
    Properties = {
        Debug=false,
        Event = { default="Event"},
        Arg1 = { default="Value1"},
        Arg2 = { default=""},
        TriggerAudio = false,
		RequiredResource = "",
		TriggerLimit = 0,
        Broadcast=true,
        TriggerPeriod={default=0,suffix="sec",description="Keep sending the event while triggered at this frequencey."},
        CollisionGroup="PlayerOnly",
        TriggerEvent={default="",description="Optional event that will trigger this collider"}
    }
}

function EventCollider:OnActivate()
    Utilities:InitLogging(self, "EventCollider")

    self.numTriggeredTimes = 0
    self.nextTriggerTime = 0
    self.triggerTarget = nil
    self.tickHandler = nil
    self.nextAudioTriggerTime = 0

    if self.Properties.CollisionGroup ~= "" then
        self.collisionGroup = CollisionGroup(self.Properties.CollisionGroup)
    end

    local physicsSystem = GetPhysicsSystem()
    local sceneHandle = physicsSystem:GetSceneHandle(DefaultPhysicsSceneName)
    self.scene = physicsSystem:GetScene(sceneHandle)

    Events:Connect(self, Events.OnStateChange)

    if self.Properties.TriggerEvent then
        self[self.Properties.TriggerEvent] = function(self, value)
            self:DetectEntitiesInTrigger()
        end
        Events:Connect(self, self.Properties.TriggerEvent, self.entityId)
    end

    Utilities:ExecuteOnNextTick(self, function()
        self.triggerEvent = SimulatedBody.GetOnTriggerEnterEvent(self.entityId)
        if self.triggerEvent ~= nil then
            self.triggerHandler = self.triggerEvent:Connect(function(type, triggerEvent)
                if triggerEvent ~= nil then
                    self:OnTrigger(triggerEvent:GetOtherEntityId())
                else
                    self:Log("Received nil triggerEvent")
                end
            end)
        end
        self.triggerExitEvent = SimulatedBody.GetOnTriggerExitEvent(self.entityId)
        if self.triggerExitEvent ~= nil then
            self.triggerExitHandler = self.triggerExitEvent:Connect(function(type, triggerEvent)
                self:Log("Target left trigger")
                if self.tickHandler ~= nil then
                    self.tickHandler:Disconnect()
                    self.tickHandler = nil
                end
            end)
        end
    end)
end

function EventCollider:OnStateChange(stateName)
    if stateName == "Reset" or stateName == "InGame" then
        self.numTriggeredTimes = 0
    end
    if self.tickHandler ~= nil then
        self.tickHandler:Disconnect()
        self.tickHandler = nil
    end
end

function EventCollider:SendEvents(entityId)
    if self.Properties.Broadcast then
        self:Log("Broadcasting event " ..self.Properties.Event)
        if self.Properties.Arg2 ~= "" then
            Events:Send(self.Properties.Event, self.Properties.Arg1, self.Properties.Arg2)
        else
            Events:Send(self.Properties.Event, self.Properties.Arg1)
        end
    else
        if self.Properties.Debug then
            local name = GameEntityContextRequestBus.Broadcast.GetEntityName(entityId)
            self:Log("Sending event " .. self.Properties.Event .. " to other entity " .. name)
        end
        if self.Properties.Arg2 ~= "" then
            Events:SendTo(self.Properties.Event, entityId, self.Properties.Arg1, self.Properties.Arg2)
        else
            Events:SendTo(self.Properties.Event, entityId, self.Properties.Arg1)
        end
    end
end

function EventCollider:DetectEntitiesInTrigger()
    local sentTrigger = false
    local request = nil
    local boxDimensions = BoxShapeComponentRequestsBus.Event.GetBoxDimensions(self.entityId)
    local pose = TransformBus.Event.GetWorldTM(self.entityId)
    if boxDimensions ~= nil then
        self:Log("Box " .. tostring(boxDimensions))
        request = CreateBoxOverlapRequest(boxDimensions * 2.0, pose)
    else
        local config = SphereShapeComponentRequestsBus.Event.GetSphereConfiguration(self.entityId)
        if config ~= nil then
            request = CreateSphereOverlapRequest(config.Radius, pose)
        end
    end

    if request == nil then
        self:Log("Failed to create overlap request")
        return
    end

    request.Collision = self.collisionGroup
    local hits = self.scene:QueryScene(request)
    if hits ~= nil then
        self:Log("Found " .. tostring(#(hits.HitArray)) .. " hits")
        for i=1,#(hits.HitArray) do
            local sceneQueryHit = hits.HitArray[i]
            if self.triggerTarget ~= nil then
                if sceneQueryHit.EntityId == self.triggerTarget then
                    self:Log(Utilities.DebugColors.Green .. "Found target entity in trigger area")
                    self:Trigger(self.triggerTarget)
                    sentTrigger = true
                    break
                end
            else
                self:Log(Utilities.DebugColors.Green .. "Found target entity in trigger area")
                self:Trigger(sceneQueryHit.EntityId)
                sentTrigger = true
            end

            --if self.Properties.Debug then
                --local name = GameEntityContextRequestBus.Broadcast.GetEntityName(sceneQueryHit.EntityId)
                --self:Log("Found entity in trigger area: " .. name)
            --end
        end
    else
        self:Log(Utilities.DebugColors.Red .."No hits Found ")
    end

    if not sentTrigger then
        self:Log(Utilities.DebugColors.Cyan .. "Didn't find target entity in trigger area")
    end
end

function EventCollider:OnTick(deltaTime, scriptTime)
    if self.scene and self.nextTriggerTime < scriptTime:GetSeconds() then
        self.nextTriggerTime = scriptTime:GetSeconds() + self.Properties.TriggerPeriod
        self:DetectEntitiesInTrigger()
    end
end

function EventCollider:Trigger(entityId)
    self:SendEvents(entityId)

    if self.Properties.TriggerAudio then
        local time = TickRequestBus.Broadcast.GetTimeAtCurrentTick()
        if self.nextAudioTriggerTime < time:GetSeconds() then
            self.nextAudioTriggerTime = time:GetSeconds() + 0.1
            AudioTriggerComponentRequestBus.Event.Play(self.entityId)
        end
    end

    self.numTriggeredTimes = self.numTriggeredTimes + 1
end

function EventCollider:OnTrigger(entityId)
    if self.numTriggeredTimes <= 0 and self.Properties.TriggerLimit > 0 then
        self:Log("Ignoring trigger, already reached limit")
        return
    end

    self.triggerTarget = entityId
    if self.Properties.TriggerPeriod > 0 and self.tickHandler == nil then
        local time = TickRequestBus.Broadcast.GetTimeAtCurrentTick()
        self.nextTriggerTime = time:GetSeconds() + self.Properties.TriggerPeriod
        self.tickHandler = TickBus.Connect(self)
    end

    self:Trigger(entityId)
end

function EventCollider:OnDeactivate()
    if self.triggerHandler ~= nil then
        self.triggerHandler:Disconnect()
    end
    if self.triggerExitHandler ~= nil then
        self.triggerExitHandler:Disconnect()
    end

    self.triggerEvent = nil
    Events:Disconnect(self)
    if self.tickHandler ~= nil then
        self.tickHandler:Disconnect()
    end
end

return EventCollider