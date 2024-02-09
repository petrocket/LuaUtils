--  Note: Listener callbacks should implement OnEasingStart, OnEasingUpdate, OnEasingEnd

local Easing = {
	jobs = {},
	active = false
}

-- Get a job kid.
local function GetAJob(jobs)
	-- look for an available job
	for id,job in pairs(jobs) do
		if job.active == false then
			return jobs[id] , id
		end
	end
	
	-- didn't find an available job so make a new one
	local id = #jobs + 1
	jobs[id] = { active = false, id = id }
	return jobs[id], id
end

-- special case for transforms
function Easing:EaseTM(method, duration, value, endValue, listener, selfReference)
	local startPosition = value:GetTranslation()
	local endPosition = endValue:GetTranslation()
	local startRotation = value:GetRotation()
	local endRotation = endValue:GetRotation(endValue)
	
	-- TODO scale maybe
	
	local tmListener = {
		OnEasingBegin = function(self, jobId, normalizedValue)
			if listener and listener.OnEasingBegin then
				listener.OnEasingBegin(selfReference, jobId, value)
			end
		end,
		OnEasingUpdate = function(self, jobId, normalizedValue)
			--Debug.Log("OnEasingUpdate normalizedValue: " .. tostring(normalizedValue))
			if listener and listener.OnEasingUpdate then
				-- lerp the position
				local position = startPosition:Lerp(endPosition, normalizedValue)
				
				-- slerp rotation
				local rotation = startRotation:Slerp(endRotation, normalizedValue)
				
				listener.OnEasingUpdate(selfReference, jobId, Transform.CreateFromQuaternionAndTranslation(rotation, position))
			end		
		end,
		OnEasingEnd = function(self, jobId, normalizedValue)
			if listener and listener.OnEasingEnd then
				listener.OnEasingEnd(selfReference, jobId, endValue)
			end		
		end,		
	}
	
	return self:Ease(method, duration, 0.0, 1.0, tmListener)
end

-- automatically ease a value from start to end
-- @method The method to use (Linear, InQuad, etc)
-- @duration The total time the easing should take
-- @value The value to update (also the starting value).  This must be an AZ type (Vector2,Vector3 etc)
-- @end_value The end value
-- @listener Optional listener to receive callbacks OnEasingStart, OnEasingUpdate, OnEasingEnd
-- returning false from OnEasingUpdate to stop easing
function Easing:Ease(method, duration, value, endValue, listener)
	local job, id = GetAJob(self.jobs)
	
	job.active = true
	job.method = method
	local scriptTime = TickRequestBus.Broadcast.GetTimeAtCurrentTick()
	job.startTime = scriptTime:GetMilliseconds()
	job.duration = duration
	job.endTime = job.startTime + duration
	job.value = value
	if type(value) == 'userdata' then
		job.startValue = value:Clone()
		job.endValue = endValue:Clone()
	else
		job.startValue = value
		job.endValue = endValue
	end
	job.valueDelta = endValue - value
	job.listener = listener
	
	if listener and listener.OnEasingBegin then
		listener:OnEasingBegin(job.id, job.startValue)
	end
	
	-- should we call update here also? not sure..
	
	-- connect to the tick bus so we can update every easing job
	if self.active == false then
		self.active = true
		self.tickListener = TickBus.Connect(self,0)
	end
	
	return id
end

function Easing:StopAll()

	for id, job in pairs(self.jobs) do
		if job.active then
			job.active = nil
		end
	end
	
	-- should we call OnEasingEnd?
	
	-- destroy all jobs
	self.jobs = nil
	self.jobs = {}
	self.active = false

	if self.tickListener ~= nil then
		self.tickListener:Disconnect()
		self.tickListener = nil
	end	
end

function Easing:IsActive(jobId)
	local job = self.jobs[jobId]
	--Debug.Log("IsActive " .. tostring(jobId) .. " " .. tostring(job.active))
	return job and job.active or false
end

function Easing:Stop(jobId)
	if self:IsActive(jobId) then
		local job = self.jobs[jobId]
		job.active = false
		if job.listener then
			if job.listener.OnEasingEnd then
				job.listener:OnEasingEnd(job.id, job.value)
			end					
		end
	end
end

-- update each easing job and notify listeners of changes
function Easing:OnTick(deltaTime, scriptTime)
	local activeJobFound = false
	
	local currentMS = scriptTime:GetMilliseconds()
	
	for id, job in pairs(self.jobs) do
		if job.active then		
			-- is the job complete?
			if currentMS >= job.endTime then
				job.value = job.endValue
				job.active = false

				-- notify the listener
				if job.listener then
					-- not sure if we should call update here or just end...
					if job.listener.OnEasingUpdate then
						job.listener:OnEasingUpdate(job.id, job.value)
					end
					
					if job.listener.OnEasingEnd then
						local loop = job.listener:OnEasingEnd(job.id, job.value)
						if loop then
							self.activeJobFound = true
							job.active = true							
							job.endValue = job.startValue
							job.startValue = job.value
							job.valueDelta = job.endValue - job.startValue							
							job.startTime = currentMS
							job.endTime = job.startTime + job.duration
						end
					end					
				end
			else
				activeJobFound = true

				local t = currentMS - job.startTime
				local b = job.startValue
				local c = job.valueDelta
				local d = job.duration
				
				job.value = job.method(self, t, b, c, d)
				
				if job.listener and job.listener.OnEasingUpdate then
					job.listener:OnEasingUpdate(job.id, job.value)
				end				
			end
		end
	end
	
	-- need to make one more check in case a job was reclaimed during the loop
	for id, job in pairs(self.jobs) do
		if job.active then
			activeJobFound = true
		end
	end
	
	if activeJobFound == false then
		self.tickListener:Disconnect()
		self.tickListener = nil
		self.active = false
	end
end


-- t is the current time of the tween.  It can be seconds, ms, whatever so long as you are consistent in what you use with the total time (duration)
-- b is the beginning value of the property.
-- c is the change between the beginning and destination value of the property.
-- d is the total time of the tween (duration), must use the same units as t

function Easing:Linear(t, b, c, d)
	return c*t/d + b
end

function Easing:InQuad(t, b, c, d)
  t = t / d
  return c * (t ^ 2) + b
end

function Easing:OutQuad(t, b, c, d)
  t = t / d
  return -c * t * (t - 2) + b
end

function Easing:InOutQuad(t, b, c, d)
  t = t / d * 2
  if t < 1 then
    return c / 2 * (t ^ 2) + b
  else
    return -c / 2 * ((t - 1) * (t - 3) - 1) + b
  end
end

function Easing:OutInQuad(t, b, c, d)
  if t < d / 2 then
    return self:OutQuad(t * 2, b, c / 2, d)
  else
    return self:InQuad((t * 2) - d, b + c / 2, c / 2, d)
  end
end

function Easing:InCubic(t, b, c, d)
	t = t / d
	return c * (t ^ 3) + b
end

function Easing:OutCubic(t, b, c, d)
	t = t / d - 1
	return c * ((t ^ 3) + 1) + b
end

function Easing:InOutCubic(t, b, c, d)
	t = t / d * 2
	if t < 1 then
		return c / 2 * t * t * t + b
	else
		t = t - 2
		return c / 2 * (t * t * t + 2) + b
	end
end

function Easing:OutInCubic(t, b, c, d)
	if t < d / 2 then
		return self:OutCubic(t * 2, b, c / 2, d)
	else
		return self:InCubic((t * 2) - d, b + c / 2, c / 2, d)
	end
end

function Easing:InSine(t, b, c, d)
  return -c * math.cos(t / d * (math.pi / 2)) + c + b
end

function Easing:OutSine(t, b, c, d)
  return c * math.sin(t / d * (math.pi / 2)) + b
end

function Easing:InOutSine(t, b, c, d)
  return -c / 2 * (math.cos(math.pi * t / d) - 1) + b
end

function Easing:OutInSine(t, b, c, d)
  if t < d / 2 then
    return self:OutSine(t * 2, b, c / 2, d)
  else
    return self:InSine((t * 2) -d, b + c / 2, c / 2, d)
  end
end

return Easing
