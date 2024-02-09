local Events = require "scripts.luautils.events"
local Utilities = require "scripts.luautils.utilities"

local DestroyOnEvent = {
    Properties = {
        Debug = false,
        Event = { default="Event"},
        ArgValue1 = { default="Value1"},
        ArgValue2 = { default="Value2"},
        GlobalEvent = false,
        TriggerAudio = false,
        Deactivate = false,
    }
}

function DestroyOnEvent:OnActivate()
    Utilities:InitLogging(self, "DestroyOnEvent")

    self[self.Properties.Event] = function(self, value1, value2)
        if value1 ~= nil then
            value1 = tostring(value1)
        end
        if value2 ~= nil then
            value2 = tostring(value2)
        end
        if self.Properties.ArgValue1 ~= "" and value1 ~= self.Properties.ArgValue1 then
            self:Log("Argvalue1 doesn't match " ..  tostring(value1))
            return
        end 
        if self.Properties.ArgValue2 ~= "" and value2 ~= self.Properties.ArgValue2 then
            self:Log("Argvalue2 doesn't match " ..  tostring(value2))
            return
        end 
        self:Trigger()
    end
    if self.Properties.GlobalEvent then
        Events:Connect(self, self.Properties.Event)
    else
        Events:Connect(self, self.Properties.Event, self.entityId)
    end
end

function DestroyOnEvent:Trigger()
    if self.Properties.Deactivate then
        Events:Send(Events.OnEntityDeactivated, self.entityId)
        GameEntityContextRequestBus.Broadcast.DeactivateGameEntity(self.entityId)
    else
        GameEntityContextRequestBus.Broadcast.DestroyGameEntityAndDescendants(self.entityId)
    end
end

function DestroyOnEvent:OnDeactivate()
    Events:Disconnect(self, self.Properties.Event)
end

return DestroyOnEvent