local Events = require "scripts.luautils.events"
local Utilities = require "scripts.luautils.utilities"

local UiCanvasEventLoader = {
    Properties = {
        Debug = false,
        ShowCursor = false,
        Event = { default="Event"},
        Values = { default={"Value",""}}
    }
}

function UiCanvasEventLoader:OnActivate()
    Utilities:InitLogging(self, "UiCanvasEventLoader")
    self.canvasLoaded = false

    self[self.Properties.Event] = function(self, value)
        self:Log("Received event value " .. tostring(value))
        local valueFound = false
        for i = 0, #self.Properties.Values do
            if value == self.Properties.Values[i] then
                if not self.canvasLoaded then
                    UiCanvasAssetRefBus.Event.LoadCanvas(self.entityId)
                    self.canvasLoaded = true

                    if self.Properties.ShowCursor then
                        UiCursorBus.Broadcast.IncrementVisibleCounter()
                    end
                end
                valueFound = true
                break
            end
        end
        if not valueFound and self.canvasLoaded then
            self.canvasLoaded = false 
            UiCanvasAssetRefBus.Event.UnloadCanvas(self.entityId)
        end
    end
    self:Log("Connecting to event: " .. self.Properties.Event)
    Events:Connect(self, self.Properties.Event)
end

function UiCanvasEventLoader:OnDeactivate()
    Events:Disconnect(self, self.Properties.Event)
end

return UiCanvasEventLoader