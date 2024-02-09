local Events = require "scripts.luautils.events"

Events.OnFireBullet = "OnFireBullet"

local BulletSpawner = {
    Properties = {
        Audio = {
            Fire = "",
            Hit = ""
        },
        Prefab = {default=SpawnableScriptAssetRef(), description="Prefab to spawn"},
    }
}

function BulletSpawner:OnActivate()
    self.spawnableMediator = SpawnableScriptMediator()
    self.spawnTicket = self.spawnableMediator:CreateSpawnTicket(self.Properties.Prefab)
    --self.spawnListerer = SpawnableScriptNotificationsBus.Connect(self, self.spawnTicket)

    -- looks like DestroyEntity will call DespawnEntity if it has a spawn ticket
    Events:Connect(self, Events.OnFireBullet)
    --Events:Connect(self, Events.OnDespawnBullet)
end

function BulletSpawner:OnFireBullet(originEntity)
    local tm = TransformBus.Event.GetWorldTM(originEntity)

    --Debug.Log(tostring(tm:GetTranslation()))
    self.spawnableMediator:SpawnAndParentAndTransform(
        self.spawnTicket,
        originEntity,
        Vector3(0,0,0),
        Vector3(0,0,180),
        1.0
        )
end

--function BulletSpawner:OnSpawn(entityList)
    --for i=1,#entityList do
    --end 
--end

function BulletSpawner:OnDeactivate()
    self.spawnableMediator:Despawn(self.spawnTicket)

    Events:Disconnect(self, Events.OnFireBullet)
    --Events:Disconnect(self, Events.OnDespawnBullet)
end

return BulletSpawner