-- Create a file named EventNames.lua in your scripts folder
-- This file should return an object with all the event names like so
-- return {
--     EventName1 = "EventName1,
--     EventName2 = "EventName2"
--     ...
-- }
-- Usage:
-- at the top of your Lua file add
-- local Events = require "scripts.utils.events"
-- To send an event (for example EventName1 with a value of 1) add
-- Events:Event(entityId, Events.EventName1, 1)

 local Events = require "scripts.eventnames"
 if Events == nil then
    Events = {}
end

-- add some other events for Utilities
Events.OnRequestProperty = "OnRequestProperty"
Events.OnReceiveProperty = "OnReceiveProperty"
Events.OnGameDataUpdated = "OnGameDataUpdated"
Events.DebugEvents = false;

-- used by StateMachine
Events.OnStateChange = "OnStateChange"

if rawget(_G, "LuaEvents") == nil then
    _G["LuaEvents"] = {}
end

function Events:Log(message)
    if self.DebugEvents then
        Debug.Log(message)
    end
end

-- call this on the deactivate of your main level to clean up all events
function Events:ClearAll()
    self:Log("Clearing all LuaEvents handlers")
    _G["LuaEvents"] = {}
end

function Events:Connect(listener, event, address)
    local combined = event .. "%" .. tostring(address)
    if _G["LuaEvents"][combined] == nil then
        _G["LuaEvents"][combined] = {}
    end

    table.insert(_G["LuaEvents"][combined], listener)
    self:Log("Connected to " .. tostring(combined))
end

function Events:Disconnect(listener, event, address)
    if event == nil and address == nil then
        -- disconnect the listener from every event, useful on Deactivate
        self:Log("Disconnecting listener from all events ")
        for eventaddress,listeners in pairs(_G["LuaEvents"]) do
            for k,l in ipairs(listeners) do
                if l == listener then
                    table.remove(listeners,k)
                end
            end
        end
    -- listener is disconnected from everything so early out
        return
    end

    local combined = event .. "%" .. tostring(address)
    local listeners = _G["LuaEvents"][combined]
    if listeners ~= nil then
        for k,l in ipairs(listeners) do
            if l == listener then
                table.remove(listeners,k)
                self:Log("Disconnecting listener from event " .. tostring(combined))
                return
            end
        end
    end
end

function Events:SendTo(event, address, ...)
    if event == nil then
        Debug.Log("Attempting to send nil event")
        return nil
    end
    local combined = event .. "%" .. tostring(address)
    self:Log("Looking for listeners for " .. tostring(combined))
    local listeners = _G["LuaEvents"][combined]
    local returnValue = nil
    if listeners ~= nil then
        self:Log("Found " ..tostring(#listeners) .." listeners for " .. tostring(combined))
        for k,listener in ipairs(listeners) do
            if listener[event] == nil then
            self:Log("Unable to send event " ..tostring(event) .." to listener because missing event function")
            else
                returnValue = listener[event](listener,...)
            end
        end
    end
    return returnValue
end

function Events:Send(event, ...)
    return self:SendTo(event, nil, ...)
end

return Events


