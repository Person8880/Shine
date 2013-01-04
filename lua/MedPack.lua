// ======= Copyright (c) 2003-2011, Unknown Worlds Entertainment, Inc. All rights reserved. =======
//
// lua\MedPack.lua
//
//    Created by:   Charlie Cleveland (charlie@unknownworlds.com) and
//                  Max McGuire (max@unknownworlds.com)
//
// ========= For more information, visit us at http://www.unknownworlds.com =====================

--[[
    Inserting hacks here.
    Combat mode does not let my game_setup.xml file get parsed.
    Thus, I've taken a stock NS2 Lua file that's not used by Combat or NS2 stats and added this check.
    If Shine hasn't been loaded by now, it will be and thus should work with Combat mod fine.
]]
if not Shine then
    if Server then
        Script.Load "lua/init.lua"
    elseif Client then
        Script.Load "lua/cl_init.lua"
    end
end

Script.Load("lua/DropPack.lua")
Script.Load("lua/PickupableMixin.lua")

class 'MedPack' (DropPack)

MedPack.kMapName = "medpack"

MedPack.kModelName = PrecacheAsset("models/marine/medpack/medpack.model")
MedPack.kHealthSound = PrecacheAsset("sound/NS2.fev/marine/common/health")

MedPack.kHealth = 50

function MedPack:OnInitialized()

    DropPack.OnInitialized(self)
    
    self:SetModel(MedPack.kModelName)
    
    InitMixin(self, PickupableMixin, { kRecipientType = "Marine" })
    
    if Server then
        self:_CheckForPickup()
    end
    
end

function MedPack:OnTouch(recipient)

    recipient:AddHealth(MedPack.kHealth, false, true)

    StartSoundEffectAtOrigin(MedPack.kHealthSound, self:GetOrigin())
    
    TEST_EVENT("Commander MedPack picked up")
    
end

function MedPack:GetIsValidRecipient(recipient)
    return not GetIsVortexed(recipient) and recipient:GetHealth() < recipient:GetMaxHealth()
end

function GetAttachToMarineRequiresHealth(entity)

    local valid = false
    
    if entity:isa("Marine") then
        valid = entity:GetHealth() < entity:GetMaxHealth()
    end
    
    return valid
    
end

Shared.LinkClassToMap("MedPack", MedPack.kMapName)