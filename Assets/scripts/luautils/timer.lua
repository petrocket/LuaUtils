local Events = require "scripts.luautils.events"

-- Timer Events
Events.OnUpdateTimeRemaining = "OnUpdateTimeRemaining"
Events.OnUpdateTimeRemainingString = "OnUpdateTimeRemainingString"
Events.OnTimerFinished = "OnTimerFinished"

local Timer = {
    timeLeft = 0,
    duration = 0,
    endTime = 0
}
Timer.__index = Timer
setmetatable(Timer, {
  __call = function (cls, ...)
    return cls.new(...)
  end,
})
function Timer.new (duration)
	local self = setmetatable({}, Timer)
	self.duration = math.ceil(duration)
    self.timeLeft = duration
    self.tickBusHandler = nil
	return self
end

function Timer:Start()
    if self.tickBusHandler ~= nil then
        self.tickBusHandler:Disconnect()
        self.tickBusHandler = nil
    end
    self.timeLeft = self.duration
    self:Resume()
end

function Timer:GetFormattedTimeLeft()
    -- don't go below zero in case timeLeft is less
    local timeLeft = math.max(0,self.timeLeft)
    local minutes = math.floor(timeLeft / 60)
    local seconds = timeLeft % 60
    local minutesString = tostring(minutes)
    if minutes < 10 then
        minutesString = "0"..minutesString
    end
    local secondsString = seconds
    if seconds < 10 then
        secondsString = "0"..secondsString
    end
    return minutesString..":"..secondsString
end

function Timer:OnTick(deltaTime, scriptTime)
    local timeLeft = math.ceil(self.endTime - scriptTime:GetSeconds())
    if timeLeft ~= self.timeLeft and timeLeft >= 0 then
        self.timeLeft = timeLeft
        Events:Send(Events.OnUpdateTimeRemaining, tostring(timeLeft))
        Events:Send(Events.OnUpdateTimeRemainingString, self:GetFormattedTimeLeft() )

    elseif timeLeft < 0 then
        Events:Send(Events.OnTimerFinished)
        self:Stop()
    end
end

function Timer:Stop()
    self:Pause()
    self.timeLeft = -1
end

function Timer:Pause()
    if self.tickBusHandler ~= nil then
        self.tickBusHandler:Disconnect()
        self.tickBusHandler = nil
    end
end

function Timer:Resume()
    if self.tickBusHandler == nil then
        self.tickBusHandler = TickBus.Connect(self)
        local time = TickRequestBus.Broadcast.GetTimeAtCurrentTick()
        self.endTime = time:GetSeconds() + self.timeLeft 
        Events:Send(Events.OnUpdateTimeRemaining, tostring(self.timeLeft))
    end
end

return Timer