
local Events = require "scripts.luautils.events"
local Utilities = require "scripts.luautils.utilities"

local ResourceComponent = {
	Properties = {
		Debug = false,
		ResourceType = "",
		Amount = 0,
		Minimum = 0,
		Maximum = 10,
		Events = {
			Changed="OnResourceChanged",
		}
	}
}

function ResourceComponent:OnActivate()
	Utilities:InitLogging(self, "ResourceComponent - " .. tostring(self.Properties.ResourceType))
	self:Log("OnActivate")

	self.Events = self
	self.amount = self.Properties.Amount

	self:ConnectEvent(Events.SetResourceAmount)
	self:ConnectEvent(Events.GetResourceAmount)
	self:ConnectEvent(Events.AddResourceAmount)

	Events:Connect(self, Events.OnStateChange)

	Utilities:ExecuteOnNextTick(self, function()
		Events:SendTo(self.Properties.Events.Changed, self.entityId, self.amount, self.amount)
		Events:Send(self.Properties.Events.Changed, self.entityId, self.amount, self.amount)
	end)
end

function ResourceComponent:ConnectEvent(functionName)
	local event = functionName .. self.Properties.ResourceType
	self[event] = self[functionName]
	Events:Connect(self, event, self.entityId)
end

function ResourceComponent:OnStateChange(value)
	self:Log("OnStateChange " .. value)
	if value == 'InGame' then
		self.amount = self.Properties.Amount
		Utilities:ExecuteOnNextTick(self, function()
			Events:SendTo(self.Properties.Events.Changed, self.entityId, self.amount, self.amount)
			Events:Send(self.Properties.Events.Changed, self.entityId, self.amount, self.amount)
		end)
	end
end

function ResourceComponent:SetResourceAmount(amount)
	self:Log("SetResourceAmount received " .. tostring(amount))
	local oldAmount = self.amount
	self.amount = amount
	Events:SendTo(self.Properties.Events.Changed, self.entityId, oldAmount, amount)
	Events:Send(self.Properties.Events.Changed, self.entityId, oldAmount, amount)
end

function ResourceComponent:GetResourceAmount()
	self:Log("GetResourceAmount received")
	return self.amount
end

function ResourceComponent:AddResourceAmount(amount)
	self:Log("AddResourceAmount received " .. tostring(amount))
	local oldAmount = self.amount
	self.amount = self.amount + amount
	if self.amount < self.Properties.Minimum then
		self.amount = self.Properties.Minimum
	elseif self.amount > self.Properties.Maximum then
		self.amount = self.Properties.Maximum
	end

	self:Log("Sending changed event: " .. tostring(self.Properties.Events.Changed))
	Events:SendTo(self.Properties.Events.Changed, self.entityId, oldAmount, self.amount)
	Events:Send(self.Properties.Events.Changed, self.entityId, oldAmount, self.amount)
end

function ResourceComponent:OnDeactivate()
	Events:Disconnect(self)
end

return ResourceComponent
