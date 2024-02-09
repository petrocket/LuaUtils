local Events = require "scripts.luautils.events"
local Utilities = require "scripts.luautils.utilities"

local EventCondition = {
    Properties = {
        Debug = false,
        Receive = {
            Event = { default="Receive"},
            Value1 = { default=""},
            Value2 = { default=""},
            From = { default=EntityId() },
            Global = false
        },
        Send = { 
            Event = {default="SendEvent"},
            Value1 = { default=""},
            Value2 = { default=""},
            To = { default=EntityId() },
            Global = false
        }
    }
}

function EventCondition:OnActivate()
    Utilities:InitLogging(self, "EventCondition")

    self[self.Properties.Receive.Event] = function(self, value1, value2)
        if value1 ~= nil then
            value1 = tostring(value1)
        end
        if value2 ~= nil then
            value2 = tostring(value2)
        end
        if self.Properties.Receive.Value1 ~= "" and value1 ~= self.Properties.Receive.Value1 then
            self:Log("Receive arg1 doesn't match " ..  tostring(value1))
            return
        end 
        if self.Properties.Receive.Value2 ~= "" and value2 ~= self.Properties.Receive.Value2 then
            self:Log("Receive arg2 doesn't match " ..  tostring(value2))
            return
        end 
        self:Send()
    end
    if self.Properties.Receive.Global then
        Events:Connect(self, self.Properties.Receive.Event)
    elseif self.Properties.Receive.Entity ~= nil then
        Events:Connect(self, self.Properties.Receive.Event, self.Properties.Receive.Entity)
    else
        Events:Connect(self, self.Properties.Receive.Event, self.entityId)
    end
end

function EventCondition:Send()
    if self.Properties.Send.Global then
        Events:Send(self.Properties.Send.Event, self.Properties.Send.Value1, self.Properties.Send.Value2)
    elseif self.Properties.Send.Entity ~= nil then
        Events:SendTo(self.Properties.Send.Event, self.Properties.Send.Entity, self.Properties.Send.Value1, self.Properties.Send.Value2)
    else
        Events:SendTo(self.Properties.Send.Event, self.entityId, self.Properties.Send.Value1, self.Properties.Send.Value2)
    end
end

function EventCondition:OnDeactivate()
    Events:Disconnect(self)
end

return EventCondition