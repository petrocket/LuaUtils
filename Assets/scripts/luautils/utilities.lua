local Events = require "scripts.luautils.events"
local Utilities = {}
Utilities.__index = Utilities
Utilities.DebugColors = {
    White = "$1",
    DarkBlue = "$2",
    Green = "$3",
    Red = "$4",
    Cyan = "$5",
    Yellow = "$6",
    Purple = "$7",
    Blue = "$8",
    Grey = "$9"
}

function Utilities:BindInputEvents(component, events)
    for event, handler in pairs(events) do
        handler.Component = component
        handler.Listener = InputEventNotificationBus.Connect(handler, InputEventNotificationId(event))
    end
end

function Utilities:UnBindInputEvents(events)
    for event, handler in pairs(events) do
        if handler ~= nil and handler.Listener ~= nil then
            handler.Listener:Disconnect()
            handler.Listener = nil
        end
    end
end

-- second parameter is optional name
function Utilities:InitLogging(object, ...)
    local name = ""
    local numArgs  = select('#', ...)
    if numArgs > 0 then
        local args = {...}
        name = args[1]
    elseif object.entityId ~= nil then
        name = GameEntityContextRequestBus.Broadcast.GetEntityName(object.entityId)
    end
    if object.Log == nil then
        if object.debug ~= nil then
            object.Log = function(context, value) if context.debug then Debug.Log(name .. ": " .. tostring(value)); end end
        elseif object.Properties.Debug ~= nil then
            object.Log = function(context, value) if context.Properties.Debug then Debug.Log(name .. ": " .. tostring(value)); end end
        else 
            object.Log = function(context, value) Debug.Log(name .. ": " .. tostring(value)); end
        end
    end
end

function Utilities:ExecuteOnNextTick(component, func)
    if component._nextTickHandler == nil or component._nextTickHandler.Listener == nil then
        -- create a handler to capture OnTick events
        component._nextTickHandler = {
            -- OnTick gets called by the TickBus
            OnTick = function(self, deltaTime, scriptTime)
                -- disconnect form the tick bus
                if self.Listener ~= nil then
                    self.Listener:Disconnect()
                    self.Listener = nil
                end
                -- call the function
                func(component)                                
            end
        }
    end

    -- connect to the TickBus
    component._nextTickHandler.Listener = TickBus.Connect(component._nextTickHandler, 0)
end

-- call a function when a tag is added to any entity
-- this is useful for getting entity ids of a unique entity
function Utilities:OnTagAdded(component, tag, func)
    if component._tagHandlers == nil then
        component._tagHandlers = {}
    end

    local handler = {
        listener = nil,
        activated = false,
        OnEntityTagAdded = function(self, entityId)
            activated = true
            if self.listener ~= nil then
                self.listener:Disconnect()
            end
            func(component, entityId)
        end
    }

    handler.listener = TagGlobalNotificationBus.Connect(handler, Crc32(tag))

    -- if an entity already has that tag OnEntityTagAdded will be called
    -- immediately so we can clean up now
    if handler.activated then
        if handler.listener ~= nil then
            handler.listener:Disconnect()
        end
        handler = nil
    else
        component._tagHandlers[tag] = handler
    end
end

-- Run func when all provided entityIds have been activated
-- useful when you need to wait for multiple entities to activate
function Utilities:OnActivated(component, entityIds, func)
    component._onActivatedEntities = entityIds
    if component._onActivatedHandlers == nil then
        component._onActivatedHandlers = {}
    end

    -- reverse iterate so we can remove elements from this table without messing
    -- up the iterator
    for i=#entityIds,1,-1 do
        local entityId = entityIds[i]
        --local name = GameEntityContextRequestBus.Broadcast.GetEntityName(entityId)
        --Debug:Log("Waiting for ".. tostring(name).." to activate ("..tostring(entityId)..")")

        local handler = {
            entityActivated = false,
            OnEntityActivated = function(self, activatedEntityId)
                --local name = GameEntityContextRequestBus.Broadcast.GetEntityName(activatedEntityId)
                --Debug:Log("entity " .. tostring(name) .. " activated")

                -- if it is in our list then remove it
                for i=#component._onActivatedEntities,1,-1 do
                    if component._onActivatedEntities[i] == activatedEntityId then
                        self.entityActivated = true
                        table.remove(component._onActivatedEntities,i)
                        break
                    end
                end

                if #component._onActivatedEntities <= 0 then
                    --Debug:Log("all entities activated")
                    func(component)
                end
            end
        }

        handler.listener = EntityBus.Connect(handler, entityId)
        -- if the entity activated immediately we disconnect/remove the listener
        if handler.entityActivated then
            handler.listener:Disconnect()
            handler = nil
        end
        component._onActivatedHandlers[tostring(entityId)] = handler
    end
end

function Utilities:Shuffle(tbl)
  for i = #tbl, 2, -1 do
    local j = math.random(i)
    tbl[i], tbl[j] = tbl[j], tbl[i]
  end
end

function Utilities:GetKeyList(tbl)
  local result = {}
  -- use own index for speed improvement over table.insert on large tables of 10000+
  local i = 0
  for key, value in pairs(tbl)  do
    i=i+1
    result[i]=key
  end
  return result
end

function Utilities:Count(tbl)
    -- don't check for nil, we want those errors to cause failures so we see them
    local count = 0
    for key,value in pairs(tbl) do
        count = count + 1
    end
    return count
end

function Utilities:Split (str, sep)
    -- split a string based on separator 'sep'
    if sep == nil then
        sep = ","
    end
    local t={}
    for match in string.gmatch(str, "([^"..sep.."]+)") do
        table.insert(t, match)
    end
    return t
end

return Utilities
