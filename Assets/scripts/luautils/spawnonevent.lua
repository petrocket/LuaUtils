local Events = require "scripts.luautils.events"
local Utilities = require "scripts.luautils.utilities"

local SpawnOnEvent = {
    Properties = {
        Debug=false,
        SpawnEvent = {
            Name = { default=""},
            Value1 = { default=""},
            Value2 = { default=""},
            From = { default=EntityId() },
            Global = false
        },
        DeSpawnEvent = {
            Name = { default=""},
            Value1 = { default=""},
            Value2 = { default=""},
            From = { default=EntityId() },
            Global = false
        },
        ParentEntity= { default=EntityId() },
        Prefab = {default=SpawnableScriptAssetRef(), description="Prefab to spawn"},
    },
    SpawnEventHandler = {},
    DeSpawnEventHandler = {}
}

function SpawnOnEvent:SpawnEvent(value1, value2)
    local c = self.Component
    c:Log("SpawnEvent "..tostring(value1))
    if value1 ~= nil then
        if type(value1) ~= "string" then
            value1 = tostring(value1)
        end
    end
    if value2 ~= nil then
        if type(value2) ~= "string" then
            value2 = tostring(value2)
        end
    end
    if c.Properties.SpawnEvent.Value1 ~= "" and value1 ~= c.Properties.SpawnEvent.Value1 then
        --c:Log("SpawnEvent arg1 " ..  value1 .. " doesn't match " .. c.Properties.SpawnEvent.Value1)
        return
    end 
    if c.Properties.SpawnEvent.Value2 ~= "" and value2 ~= c.Properties.SpawnEvent.Value2 then
        --c:Log("SpawnEvent arg2 doesn't match " ..  tostring(value2))
        return
    end 
    c:Spawn()
end

function SpawnOnEvent:DeSpawnEvent(value1, value2)
    local c = self.Component
    c:Log("DeSpawnEvent "..tostring(value1))
    if value1 ~= nil then
        value1 = tostring(value1)
    end
    if value2 ~= nil then
        value2 = tostring(value2)
    end
    if c.Properties.DeSpawnEvent.Value1 ~= "" and value1 ~= c.Properties.DeSpawnEvent.Value1 then
        --c:Log("Despawn arg1 doesn't match " ..  tostring(value1))
        return
    end 
    if c.Properties.DeSpawnEvent.Value2 ~= "" and value2 ~= c.Properties.DeSpawnEvent.Value2 then
        --c:Log("Despawn arg2 doesn't match " ..  tostring(value2))
        return
    end
    c:DeSpawn()
end

function SpawnOnEvent:OnActivate()
    Utilities:InitLogging(self)

    self.spawnableMediator = SpawnableScriptMediator()
    self.spawnTicket = self.spawnableMediator:CreateSpawnTicket(self.Properties.Prefab)
    --self.spawnListerer = SpawnableScriptNotificationsBus.Connect(self, self.spawnTicket)

    self:Log("Value1 is " .. self.Properties.SpawnEvent.Value1)
    self.parentEntity = self.Properties.ParentEntity
    if self.parentEntity == nil then
        self.parentEntity = self.entityId
    elseif not self.parentEntity:IsValid() then
        self.parentEntity = self.entityId
    end

    self.SpawnEventHandler.Component = self
    self.SpawnEventHandler[self.Properties.SpawnEvent.Name] = self.SpawnEvent
    if self.Properties.SpawnEvent.Global then
        Events:Connect(self.SpawnEventHandler, self.Properties.SpawnEvent.Name)
    elseif self.Properties.SpawnEvent.From ~= nil then
        Events:Connect(self.SpawnEventHandler, self.Properties.SpawnEvent.Name, self.Properties.SpawnEvent.From)
    else
        Events:Connect(self.SpawnEventHandler, self.Properties.SpawnEvent.Name, self.entityId)
    end


    self.DeSpawnEventHandler.Component = self
    self.DeSpawnEventHandler[self.Properties.DeSpawnEvent.Name] = self.DeSpawnEvent
    if self.Properties.DeSpawnEvent.Global then
        Events:Connect(self.DeSpawnEventHandler, self.Properties.DeSpawnEvent.Name)
    elseif self.Properties.DeSpawnEvent.From ~= nil then
        Events:Connect(self.DeSpawnEventHandler, self.Properties.DeSpawnEvent.Name, self.Properties.DeSpawnEvent.From)
    else
        Events:Connect(self.DeSpawnEventHandler, self.Properties.DeSpawnEvent.Name, self.entityId)
    end
end

function SpawnOnEvent:DeSpawn()
    self:Log("DeSpawning")
    self.spawnableMediator:Despawn(self.spawnTicket)
end

function SpawnOnEvent:Spawn()
    local tm = TransformBus.Event.GetWorldTM(self.entityId)
    self:Log("Spawning at " .. tostring(tm:GetTranslation()))
    self.spawnableMediator:SpawnAndParentAndTransform(
        self.spawnTicket,
        self.parentEntity,
        --tm:GetTranslation(),
        Vector3(0,0,0), -- local to parent
        Vector3(0,0,180), -- local to parent
        1.0 -- scale
        )
end

--function SpawnOnEvent:OnSpawn(entityList)
    --for i=1,#entityList do
    --end 
--end

function SpawnOnEvent:OnDeactivate()
    self.spawnableMediator:Despawn(self.spawnTicket)
    Events:Disconnect(self)
    Events:Disconnect(self.SpawnEventHandler)
    Events:Disconnect(self.DeSpawnEventHandler)
end

return SpawnOnEvent