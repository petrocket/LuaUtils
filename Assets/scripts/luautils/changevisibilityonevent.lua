local Events = require "scripts.luautils.events"
local Utilities = require "scripts.luautils.utilities"

local ChangeVisibilityOnEvent = {
    Properties = {
        Debug = false,
        Event = { default="Event"},
        Values = { default={"ValueOption1"}}
    }
}

function ChangeVisibilityOnEvent:OnActivate()
    Utilities:InitLogging(self, "ChangeVisibilityOnEvent")
    self.lightIntensity = nil
    self[self.Properties.Event] = function(self, value)
        local valueFound = false
        for i = 1, #self.Properties.Values do
            local optionValue = self.Properties.Values[i]
            if type(value) == "boolean" then
                if optionValue == "false" or optionValue == "False" or optionValue == "0" then
                    optionValue = false
                else
                    self:Log("value is " .. tostring(value) .. " optionValue (pre) " ..tostring(optionValue))
                    optionValue = true
                end
            end

            if value == optionValue then
                valueFound = true
                break
            end
        end

        RenderMeshComponentRequestBus.Event.SetVisibility(self.entityId, valueFound)
        if self.lightIntensity ~= nil then
            if valueFound then
                AreaLightRequestBus.Event.SetIntensity(self.entityId, self.lightIntensity)
            else
                AreaLightRequestBus.Event.SetIntensity(self.entityId, 0)
            end
        end
    end

    Utilities:ExecuteOnNextTick(self, function()
        self.lightIntensity = AreaLightRequestBus.Event.GetIntensity(self.entityId)
    end)

    Events:Connect(self, self.Properties.Event)
end

function ChangeVisibilityOnEvent:OnDeactivate()
    Events:Disconnect(self, self.Properties.Event)
end

return ChangeVisibilityOnEvent