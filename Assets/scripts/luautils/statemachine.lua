local Events = require "scripts.luautils.events"
Events.OnStateChange = "OnStateChange"
local StateMachine =
{
    sequencePlaying = false,
}
StateMachine.__index = StateMachine;

function StateMachine:Start(name, entityId, userData, statesTable, stateChangeEvents, initialStateName, isDebuggingEnabled)
    self.Name = name;
    self.EntityId = entityId;
    self.UserData = userData;
    self.States = statesTable;
    self.StateChangeEvents = stateChangeEvents;
    self:CreateSortedTransitionKeys(statesTable);
    self.IsDebuggingEnabled = isDebuggingEnabled;
    
    -- State machine needs to tick to evaluate transitions.
    self.tickBusHandler = TickBus.Connect(self);
    
    -- Jump to initial state if specified.
    if (initialStateName ~= nil) then
        self:GotoState(initialStateName);
    end
end
-- Store a sorted list of transition keys in each state so we can control the order transition functions are called. 
-- This allows us to remove redundant code in evaluate functions
function StateMachine:CreateSortedTransitionKeys(states)
    for stateKey, stateTable in pairs(states) do
        local priorityKeys = {};
        local miscKeys = {};
        for transKey, transTable in pairs(stateTable.Transitions) do
            if (transTable.Priority ~= nil) then
                if (priorityKeys[transTable.Priority] == nil) then
                    table.insert(priorityKeys, transTable.Priority, transKey);
                else
                    Debug.Warning("[StateMachine " .. tostring(self.Name) .. "] Has two states with the same priority: " .. tostring(priorityKeys[transTable.Priority]) .. " and " .. tostring(transKey));
                end
            else
                table.insert(miscKeys, transKey);
            end
        end
        table.sort(miscKeys);
        
        local sortedKeys = {};
        for transKey, transTable in pairs(priorityKeys) do
            if (transTable ~= nil) then
                table.insert(sortedKeys, transTable);
            end
        end
        for transKey, transTable in pairs(miscKeys) do
            table.insert(sortedKeys, transTable);
        end
        stateTable.Transitions.SortedKeys = sortedKeys;
    end
end
function StateMachine:Stop()
    if(self.tickBusHandler ~= nil) then
        self.tickBusHandler:Disconnect();
        self.tickBusHandler = nil;
    end
end

function StateMachine:Update(deltaTime, scriptTime)
    if (self.CurrentState == nil) then
        return
    end
    -- Check conditions for the current state's outgoing transitions.
    if (self.CurrentState.Transitions ~= nil) then
        for i, transKey in ipairs(self.CurrentState.Transitions.SortedKeys) do
            local transTable = self.CurrentState.Transitions[transKey];
            if (transTable) then
                local result = transTable.Evaluate(self, self.CurrentState)
                if (result == true) then
                    self:GotoState(transKey);
                    return;
                end
            end
        end
    end
    
    -- Call current state's update if bound.
    if (self.CurrentState.OnUpdate ~= nil) then
        self.CurrentState.OnUpdate(self, deltaTime, scriptTime);
    end
   
end

function StateMachine:GotoState(targetStateName)
    
    if (self.States == nil) then
        return
    end
    
    for stateKey, stateTable in pairs(self.States) do
        if (tostring(stateKey) == targetStateName) then
            if (self.CurrentState ~= nil) then
                -- Unbind any input events we were monitoring from the previous state.
                if (self.CurrentState.InputListeners ~= nil) then
                    for inputKey, inputTable in pairs(self.CurrentState.InputListeners) do
                        if (eventTable.EventHandler ~= nil) then
                            eventTable.EventHandler:Disconnect();
                        end
                    end
                end
                self.CurrentState.InputListeners = nil;
            
                -- Invoke previous state's OnExit handler.
                if (self.CurrentState.OnExit ~= nil) then
                    self.CurrentState.OnExit(self);
                end
            end
            
            -- Send an event signifying the state change.
            if (self.StateChangeEvents) then
                Events:SendTo(Events.OnStateChange, self.EntityId,targetStateName)
                Events:Send(Events.OnStateChange,targetStateName)
            end
            
            self.CurrentState = stateTable;
            self.CurrentStateName = stateKey;
            
            -- Invoke new state's OnEnter handler.
            if (stateTable.OnEnter ~= nil) then
                stateTable.OnEnter(self);
            end
            
            -- Identify any input conditions in the new state's transitions and register event handlers.
            if (stateTable.Transitions ~= nil) then
                for transKey, transTable in pairs(stateTable.Transitions) do
                    transTable.InputListeners = {};
                end
                for transKey, transTable in pairs(stateTable.Transitions) do
                    if (transTable.InputEvent ~= nil) then
                        local listenerCount = #transTable.InputListeners;
                        transTable.InputListeners[listenerCount+1] = {};
                        local sm = self;
                        transTable.InputListeners[listenerCount+1].OnEventBegin = function(value)
                        sm:GotoState(tostring(transKey));
                    end
                    transTable.InputListeners[listenerCount+1].EventHandler =
                        GameplayNotificationBus.Connect(transTable.InputListeners[listenerCount+1], GameplayNotificationId(self.EntityId, transTable.InputEvent), "float");
                    end
                end
            end
            
            if (self.IsDebuggingEnabled) then
                Debug.Log("[StateMachine " .. tostring(self.Name) .. "] Successfully transitioned: " .. targetStateName);
            end
            return
        end

    end
    self:Log("Failed to find state: " .. targetStateName)
end

function StateMachine:OnStop(sequenceTime)
    self:Log("Sequence finished")
    self.sequencePlaying = false
    if self.sequenceListener ~= nil then
        self.sequenceListener:Disconnect()
        self.sequenceListener = nil
    end
end

function StateMachine:CurrentSequenceIsFinished()
    return not self.sequencePlaying
end

function StateMachine:PlaySequence(sequenceEntity)
    self:Log("Playing sequence " .. tostring(sequenceEntity))
    
    self.sequencePlaying = true
    self.sequenceListener = SequenceComponentNotificationBus.Connect(self, sequenceEntity)
    SequenceComponentRequestBus.Event.JumpToBeginning(sequenceEntity)
    SequenceComponentRequestBus.Event.Play(sequenceEntity)
end

function StateMachine:OnTick(deltaTime, scriptTime)
    self:Update(deltaTime, scriptTime);
end

function StateMachine:Resume()
    self.tickBusHandler = TickBus.Connect(self);
end

function StateMachine:Log(value)
    if self.IsDebuggingEnabled then
        Debug.Log("StateMachine " .. tostring(self.Name) .. " " .. tostring(value))
    end
end


return StateMachine
