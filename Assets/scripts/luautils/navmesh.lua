local Utilities = require "scripts.luautils.utilities"
local NavMesh = {
    Properties = {
        Debug = false
    }
}

function NavMesh:OnActivate()
    Utilities:InitLogging(self, "NavMesh")
    self:Log("Updating navmesh")
    self.navMeshListener = RecastNavigationMeshNotificationBus.Connect(self, self.entityId)
    self.tickListener = TickBus.Connect(self)
end
function NavMesh:OnTick(deltaTime, scriptTime)
    RecastNavigationMeshRequestBus.Event.UpdateNavigationMeshAsync(self.entityId)
    self.tickListener:Disconnect()
end

function NavMesh:OnNavigationMeshUpdated(entityId)
    self:Log("Navmesh updated")
    RecastNavigationMeshRequestBus.Event.UpdateNavigationMeshAsync(self.entityId)
end
function NavMesh:OnDeactivate()
    self.navMeshListener:Disconnect()
    self.tickListener:Disconnect()
end
return NavMesh