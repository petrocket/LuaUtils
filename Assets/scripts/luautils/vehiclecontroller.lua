local Events = require "scripts.luautils.events"
local Utilities = require "scripts.luautils.utilities"

local VehicleController = {
	Properties = {
		Debug = false,
		MoveSpeed = 100.0,
		SideSpeedFactor = 0.5,
		BackSpeedFactor = 0.25,
		Physics = EntityId(),
		Mesh = EntityId(),
		Weapon = EntityId(),
		BulletSpawnLocation = EntityId(),
		Audio = EntityId(),
		FireCooldown = 0.2,
		RotationSpeed = 10.0
	},
    InputEvents = {
		MoveLeftRight = {},
		MoveForwardBack = {},
        MouseLeftClick = {},
        MouseX = {},
        MouseY = {}
    }
}

function VehicleController:OnActivate()
	Utilities:InitLogging(self, "Player")

	Utilities:BindInputEvents(self, self.InputEvents)
	self.offset = Vector3(0,0,0) 
	self.tickHandler = TickBus.Connect(self,0)

	self.currentRotation = 0
	self.desiredRotation = 0
	self.nextFireTime = 0
	self.isMoving = false

 	self.spawnTM = TransformBus.Event.GetWorldTM(self.entityId)

	self:Reset()
	Events:Connect(self, Events.OnStateChange)
end

function VehicleController:OnStateChange(value)
    if value == 'Reset' then
        self:Reset()
    end

	self.enabled = value == 'InGame'
	self:Log("setting enabled " ..tostring(self.enabled) .. ' state is ' ..tostring(value))
end

function VehicleController:Reset()
	TransformBus.Event.SetWorldTM(self.entityId, self.spawnTM)
	AudioTriggerComponentRequestBus.Event.KillAllTriggers(self.Properties.Audio)
	self.lightOn = nil
	self.leftMouseClicked = false
	self.nextMouseClickTime = 0
	self.movement = Vector2(0,0)
	self.mouse = Vector2(0,0)
	self.footStepTimeWait = 0.5
	self.nextFootStepTime = 0
	self.enabled = true
end

function VehicleController:OnTick(deltaTime, scriptTime)

	if not self.enabled then
		self.leftMouseClicked = false
		self.movement = Vector2(0, 0)
		return
	end

	if self.firing then
		if self.nextFireTime <= scriptTime:GetSeconds() then
			Events:Send(Events.OnFireBullet, self.Properties.BulletSpawnLocation)
			self.nextFireTime = scriptTime:GetSeconds() + self.Properties.FireCooldown
		end 
	end

	local moveDirection = Vector3(self.movement.x, self.movement.y, 0):GetNormalized()
	local moveAmount = moveDirection * self.Properties.MoveSpeed * deltaTime
	local cameraTranslation = TransformBus.Event.GetWorldTranslation(self.entityId)
	--local meshTranslation = TransformBus.Event.GetWorldTranslation(self.Properties.Mesh)
	local meshTranslation = TransformBus.Event.GetWorldTranslation(self.Properties.Physics)

	if self.offset.z == 0 then
		self.offset = cameraTranslation - meshTranslation
	end

	local mousePosition = UiCursorBus.Broadcast.GetUiCursorPosition()
	local worldPosition0 = CameraRequestBus.Broadcast.ScreenToWorld(mousePosition, 0.0)
	local worldPosition1 = CameraRequestBus.Broadcast.ScreenToWorld(mousePosition, 1.0)
	local direction = worldPosition1 - worldPosition0

	local denom = Vector3(0,0,1):Dot(-direction:GetNormalized())
	--if(denom > 0.001) then
	local distance = (worldPosition0):Dot(Vector3(0,0,1)) / denom
	local groundLocation = cameraTranslation + direction:GetNormalized() * distance
	local deltaPos = groundLocation - meshTranslation
	local rotation = Math.ArcTan2(deltaPos.y, deltaPos.x)
	TransformBus.Event.SetWorldRotation(self.Properties.Weapon, Vector3(0,0,rotation - math.pi * 0.5))
	--end

	-- move at different speeds
	if(moveAmount:GetLengthSq() > 0.1) then
		self.desiredRotation = Math.ArcTan2(moveAmount.y, moveAmount.x)

		if not self.isMoving then
			self.isMoving = true
			Events:Send(Events.OnVehicleMoving, "moving")
		end
		local dot = deltaPos:GetNormalized():Dot(Vector3(moveAmount.x,moveAmount.y,0):GetNormalized())

		if(dot < -0.1) then
			moveAmount = moveAmount * self.Properties.BackSpeedFactor
		elseif (dot < 0.2) then
			moveAmount = moveAmount * self.Properties.SideSpeedFactor
		end
		--self:PlayFootstep(moveAmount:GetLength(), scriptTime:GetSeconds())
		--RigidBodyRequestBus.Event.SetLinearVelocity(self.Properties.Physics, moveAmount)
		RigidBodyRequestBus.Event.ApplyLinearImpulse(self.Properties.Physics, moveAmount)
		--RigidBodyRequestBus.Event.ApplyAngularImpulse(self.Properties.Physics, moveAmount)
		--CharacterControllerRequestBus.Event.AddVelocityForTick(self.Properties.Mesh, moveAmount)
		--local meshTranslation = TransformBus.Event.GetWorldTranslation(self.Properties.Mesh)

		TransformBus.Event.SetWorldTranslation(self.Properties.Weapon, meshTranslation)
	--else
		--AudioTriggerComponentRequestBus.Event.KillAllTriggers(self.Properties.Audio)
	else
		if self.isMoving then
			self.isMoving = false
			Events:Send(Events.OnVehicleMoving, 0)
		end
	end

	-- ArcTan2 range is -pi to +pi
	local pi2 = math.pi * 2.0
	local pi3 = math.pi * 3.0
	local shortestAngle = ((((self.desiredRotation - self.currentRotation + pi2) % pi2) + pi3) % pi2) - math.pi --pi2 
	--Debug.Log('from ' .. tostring(self.currentRotation) .. ' to ' ..tostring(self.desiredRotation) .. ' closest angle ' .. tostring(shortestAngle))

	local sign = Math.Sign(shortestAngle)
	--Debug.Log('sign ' .. tostring(sign))
	--Debug.Log(tostring(shortestAngle))


	if Math.IsClose(shortestAngle, 0.0, 0.1) then
		self.currentRotation = self.desiredRotation	
	else
		self.currentRotation = self.currentRotation + deltaTime * sign * self.Properties.RotationSpeed 
	end
	--self.currentRotation = self.desiredRotation	

	TransformBus.Event.SetWorldRotation(self.Properties.Mesh, Vector3(0,0,self.currentRotation - math.pi * 0.5))

	local meshTranslation = TransformBus.Event.GetWorldTranslation(self.Properties.Physics)

	local cameraTranslation = meshTranslation + self.offset
	TransformBus.Event.SetWorldTranslation(self.entityId, cameraTranslation)

	-- move the car mesh to wherever the physics body is
	TransformBus.Event.SetWorldTranslation(self.Properties.Mesh, meshTranslation)
	TransformBus.Event.SetWorldTranslation(self.Properties.Weapon, meshTranslation)

end

function VehicleController:PlayFootstep(speed, currentTime)
	if self.nextFootStepTime < currentTime then
		--Debug.Log("footstep " .. tostring(speed))
		if speed <= 5.0 then
			self.nextFootStepTime = currentTime + self.footStepTimeWait
			AudioTriggerComponentRequestBus.Event.Play(self.Properties.Audio)
		else
			self.nextFootStepTime = currentTime + self.footStepTimeWait * 0.75
			AudioTriggerComponentRequestBus.Event.Play(self.Properties.Audio)
		end
	end
end
function VehicleController:OnDeactivate()
	self.tickHandler:Disconnect()
	Utilities:UnBindInputEvents(self.InputEvents)
	Events:Disconnect(self, Events.OnStateChange)
end

function VehicleController.InputEvents.MoveLeftRight:OnPressed(value)
    self.Component.movement.x = value
end
function VehicleController.InputEvents.MoveLeftRight:OnHeld(value)
    self.Component.movement.x = value
end
function VehicleController.InputEvents.MoveLeftRight:OnReleased(value)
    self.Component.movement.x = 0
end
function VehicleController.InputEvents.MoveForwardBack:OnPressed(value)
    self.Component.movement.y = value
end
function VehicleController.InputEvents.MoveForwardBack:OnHeld(value)
    self.Component.movement.y = value
end
function VehicleController.InputEvents.MoveForwardBack:OnReleased(value)
    self.Component.movement.y = 0
end
function VehicleController.InputEvents.MouseX:OnPressed(value)
    self.Component.mouse.x = value
end
function VehicleController.InputEvents.MouseX:OnHeld(value)
    self.Component.mouse.x = value
end
function VehicleController.InputEvents.MouseX:OnReleased(value)
    self.Component.mouse.x = 0
end
function VehicleController.InputEvents.MouseY:OnPressed(value)
    self.Component.mouse.y = value
end
function VehicleController.InputEvents.MouseY:OnHeld(value)
    self.Component.mouse.y = value
end
function VehicleController.InputEvents.MouseY:OnReleased(value)
    self.Component.mouse.y = 0
end

function VehicleController.InputEvents.MouseLeftClick:OnPressed(value)
	self.Component.firing = true
end
function VehicleController.InputEvents.MouseLeftClick:OnHeld(value)
	self.Component.firing = true
end
function VehicleController.InputEvents.MouseLeftClick:OnReleased(value)
	self.Component.firing = false
end

return VehicleController