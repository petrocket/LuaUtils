local Events = require "scripts.luautils.events"
local Utilities = require "scripts.luautils.utilities"

local PlayerController = {
    Properties = {
        Debug = { default=false, description="Output debug logs when active"},
		MoveSpeed = 500.0,
		SideSpeedFactor = 0.5,
		BackSpeedFactor = 0.25,
		Camera = EntityId(),
		Mesh = EntityId(),
		Audio = EntityId(),
		PrimaryActionTarget = { default=EntityId(), description="Entity to notify for the player's primary action"},
		PrimaryActionCooldown = { default=0.3, suffix="sec", description="Optional primary action cooldown in seconds"},
		SecondaryActionTarget = { default=EntityId(), description="Entity to notify for the player's secondary action"},
		SecondaryActionCooldown = { default=0.3, suffix="sec", description="Optional secondary action cooldown in seconds"},
        Enabled = { default=true, description="Whether the player starts enabled or not."},
		Invincible=false
    },
    InputEvents = {
        MoveLeftRight = {},
        MoveForwardBack = {},
        MouseLeftClick = {},
        MouseRightClick = {},
        MouseX = {},
        MouseY = {},
        Player1Primary = {},
        Player1Secondary = {},
        LookLeftRight = {},
        LookUpDown = {},
        GamePadUsed = {},
        MouseUsed = {}
    }
}

function PlayerController:OnActivate()
    Utilities:InitLogging(self)
	Utilities:BindInputEvents(self, self.InputEvents)

	self.offset = Vector3(0,0,0) 
	self.tickHandler = TickBus.Connect(self,0)
	self.cameraSpawnTM = TransformBus.Event.GetWorldTM(self.entityId)
	self.spawnTM = nil
	self:Reset()
	self:SetEnabled(self.Properties.Enabled)

	-- wait for gamepad usage
	self.usingGamePad = false
	self.receivedInput = false

	Events:Connect(self, Events.OnStateChange)
	Events:Connect(self, Events.GetPlayer)
	Events:Connect(self, Events.OnResourceChangedHealth, self.Properties.Mesh)

    Utilities:ExecuteOnNextTick(self, function(self)
		self.spawnTM = TransformBus.Event.GetWorldTM(self.Properties.Mesh)
	end)
end

function PlayerController:GetPlayer()
	return self
end

function PlayerController:OnResourceChangedHealth(oldAmount, newAmount)
	if newAmount == 0 and not self.Properties.Invincible then
		self.alive = false
		self:SetEnabled(false)
	end	
end

function PlayerController:Reset()
	TransformBus.Event.SetWorldTM(self.entityId, self.cameraSpawnTM)
	if self.spawnTM ~= nil then
		TransformBus.Event.SetWorldTM(self.Properties.Mesh, self.spawnTM)
	end

	AudioTriggerComponentRequestBus.Event.KillAllTriggers(self.Properties.Audio)
	self.lightOn = nil
	self.alive =true 
	self.primaryAction = 0 
	self.secondaryAction = 0 
	self.nextPrimaryActionTime=0
	self.nextSecondaryActionTime=0
	self.facing = Vector2(0,0)
	self.movement = Vector2(0,0)
	self.mouse = Vector2(0,0)
	self.footStepTimeWait = 0.5
	self.nextFootStepTime = 0
end

function PlayerController:SetEnabled(enabled)
	if enabled ~= self.enabled then
		self.enabled = enabled
		self:Log("Setting enabled " ..tostring(self.enabled))
		if not self.enabled then
			self.movement = Vector2(0, 0)
		end
	end
end

function PlayerController:OnStateChange(value)
    if value == 'Reset' then
		-- we really need to disable the physics before teleporting
		SimulatedBodyComponentRequestBus.Event.DisablePhysics(self.Properties.Mesh)
        self:Reset()
		SimulatedBodyComponentRequestBus.Event.EnablePhysics(self.Properties.Mesh)
    end
	self:SetEnabled(value == 'InGame')
end

function PlayerController:OnTick(deltaTime, scriptTime)
	if not self.enabled then
		return
	end

	-- processes actions
	if self.primaryAction ~= 0 then
		if self.nextPrimaryActionTime < scriptTime:GetSeconds() then
			self.nextPrimaryActionTime = scriptTime:GetSeconds() + self.Properties.PrimaryActionCooldown
			self:Log("PrimaryAction")
			Events:SendTo(Events.OnAction, self.Properties.PrimaryActionTarget)
		end
        self.primaryAction = 0
	end

	if self.secondaryAction ~= 0 then
		if self.nextSecondaryActionTime < scriptTime:GetSeconds() then
			self.nextSecondaryActionTime = scriptTime:GetSeconds() + self.Properties.SecondaryActionCooldown
			self:Log("SecondaryAction")
			Events:SendTo(Events.OnAction, self.Properties.SecondaryActionTarget)
		end
		self.secondaryAction = 0
	end

    -- this logic only works if the player mesh is not a child
    -- of the player camera or player controller
    -- the camera can be on the same entity as the player controller or a 
    -- different entity
	local moveDirection = Vector3(self.movement.x, self.movement.y, 0):GetNormalized()
	local moveAmount = moveDirection * self.Properties.MoveSpeed * deltaTime
	local cameraTranslation = TransformBus.Event.GetWorldTranslation(self.Properties.Camera)
	local meshTranslation = TransformBus.Event.GetWorldTranslation(self.Properties.Mesh)

	if self.offset.z == 0 then
		self.offset = cameraTranslation - meshTranslation
	end

	local deltaPos = Vector3()
	if self.usingGamePad then
		deltaPos = Vector3(self.facing.x, self.facing.y, 0.0)
	else
		local mousePosition = UiCursorBus.Broadcast.GetUiCursorPosition()
		local worldPosition0 = CameraRequestBus.Broadcast.ScreenToWorld(mousePosition, 0.0)
		local worldPosition1 = CameraRequestBus.Broadcast.ScreenToWorld(mousePosition, 1.0)
		local direction = worldPosition1 - worldPosition0
		local denom = Vector3(0,0,1):Dot(-direction:GetNormalized())
		local distance = (worldPosition0):Dot(Vector3(0,0,1)) / denom
		local groundLocation = cameraTranslation + direction:GetNormalized() * distance
		deltaPos = groundLocation - meshTranslation
	end

	local rotation = Math.ArcTan2(deltaPos.y, deltaPos.x)
	local worldRotation = Vector3(0,0,rotation - math.pi * 0.5)
	TransformBus.Event.SetWorldRotation(self.Properties.Mesh, worldRotation)

	-- move at different speeds
	if(moveAmount:GetLengthSq() > 0.1) then
		local dot = deltaPos:GetNormalized():Dot(Vector3(moveAmount.x,moveAmount.y,0):GetNormalized())

		if(dot < -0.1) then
			moveAmount = moveAmount * self.Properties.BackSpeedFactor
		elseif (dot < 0.2) then
			moveAmount = moveAmount * self.Properties.SideSpeedFactor
		end
		self:PlayFootstep(moveAmount:GetLength(), scriptTime:GetSeconds())
		CharacterControllerRequestBus.Event.AddVelocityForTick(self.Properties.Mesh, moveAmount)
		local meshTranslation = TransformBus.Event.GetWorldTranslation(self.Properties.Mesh)
		local cameraTranslation = meshTranslation + self.offset
		TransformBus.Event.SetWorldTranslation(self.Properties.Camera, cameraTranslation)
	end
end

function PlayerController:PlayFootstep(speed, currentTime)
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

function PlayerController:SetUsingGamePad(used)
	if used ~= self.usingGamePad or not self.receivedInput then
		self:Log("SetUsingGamePad " .. tostring(used))
		self.usingGamePad = used
		self.receivedInput = true
		if self.enabled then
			if self.usingGamePad then
				self:Log("Hiding cursor")
				-- hide the cursor
				while UiCursorBus.Broadcast.IsUiCursorVisible() == true do
					UiCursorBus.Broadcast.DecrementVisibleCounter()
				end
			else
				self:Log("Showing cursor")
				-- show the cursor
				while UiCursorBus.Broadcast.IsUiCursorVisible() == false do
					UiCursorBus.Broadcast.IncrementVisibleCounter()
				end
			end
		end
	end
end

function PlayerController.InputEvents.MoveLeftRight:OnPressed(value)
    self.Component.movement.x = value
end
function PlayerController.InputEvents.MoveLeftRight:OnHeld(value)
    self.Component.movement.x = value
end
function PlayerController.InputEvents.MoveLeftRight:OnReleased(value)
    self.Component.movement.x = 0
end
function PlayerController.InputEvents.MoveForwardBack:OnPressed(value)
    self.Component.movement.y = value
end
function PlayerController.InputEvents.MoveForwardBack:OnHeld(value)
    self.Component.movement.y = value
end
function PlayerController.InputEvents.MoveForwardBack:OnReleased(value)
    self.Component.movement.y = 0
end
function PlayerController.InputEvents.LookLeftRight:OnPressed(value)
    self.Component.facing.x = value
end
function PlayerController.InputEvents.LookLeftRight:OnHeld(value)
    self.Component.facing.x = value
end
function PlayerController.InputEvents.LookLeftRight:OnReleased(value)
    --self.Component.facing.x = 0
end
function PlayerController.InputEvents.LookUpDown:OnPressed(value)
    self.Component.facing.y = value
end
function PlayerController.InputEvents.LookUpDown:OnHeld(value)
    self.Component.facing.y = value
end
function PlayerController.InputEvents.LookUpDown:OnReleased(value)
    --self.Component.facing.y = 0
end
function PlayerController.InputEvents.MouseX:OnPressed(value)
	self.Component:SetUsingGamePad(false)
    self.Component.mouse.x = value
end
function PlayerController.InputEvents.MouseX:OnHeld(value)
	self.Component:SetUsingGamePad(false)
    self.Component.mouse.x = value
end
function PlayerController.InputEvents.MouseX:OnReleased(value)
    self.Component.mouse.x = 0
end
function PlayerController.InputEvents.MouseY:OnPressed(value)
	self.Component:SetUsingGamePad(false)
    self.Component.mouse.y = value
end
function PlayerController.InputEvents.MouseY:OnHeld(value)
	self.Component:SetUsingGamePad(false)
    self.Component.mouse.y = value
end
function PlayerController.InputEvents.MouseY:OnReleased(value)
    self.Component.mouse.y = 0
end

function PlayerController:OnPrimaryAction(value)
   	self.primaryAction = value
end

function PlayerController:OnSecondaryAction(value)
   	self.secondaryAction = value
end

function PlayerController.InputEvents.MouseLeftClick:OnPressed(value)
	self.Component:OnPrimaryAction(value)
end

function PlayerController.InputEvents.Player1Primary:OnPressed(value)
	self.Component:OnPrimaryAction(value)
end

function PlayerController.InputEvents.MouseRightClick:OnPressed(value)
	self.Component:OnSecondaryAction(value)
end

function PlayerController.InputEvents.Player1Secondary:OnPressed(value)
	self.Component:OnSecondaryAction(value)
end

function PlayerController.InputEvents.GamePadUsed:OnPressed(value)
	self.Component:SetUsingGamePad(true)
end

function PlayerController.InputEvents.MouseUsed:OnPressed(value)
	self.Component:SetUsingGamePad(false)
end

function PlayerController:OnDeactivate()
	self.tickHandler:Disconnect()
	Utilities:UnBindInputEvents(self.InputEvents)
	Events:Disconnect(self)
end

return PlayerController