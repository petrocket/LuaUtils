local Events = require "scripts.events"

local UiTextEventUpdator = {
    Properties = {
        Event = { default="Event"},
    }
}

function UiTextEventUpdator:OnActivate()
    self[self.Properties.Event] = function(self, text)
        UiTextBus.Event.SetText(self.entityId, text)
    end
    Events:Connect(self, self.Properties.Event)
end

function UiTextEventUpdator:OnDeactivate()
    Events:Disconnect(self, self.Properties.Event)
end

return UiTextEventUpdator