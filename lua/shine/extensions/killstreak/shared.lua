--[[
Shine Killstreak Plugin - Shared
]]

local Plugin = {}

Plugin.Version = "1.0"

--Sounds 
Plugin.Sounds = {       
    ["Triplekill"] = PrecacheAsset("sound/killstreaks.fev/killstreaks/triplekill"),
    ["Multikill"] = PrecacheAsset("sound/killstreaks.fev/killstreaks/multikill"),
    ["Rampage"] = PrecacheAsset("sound/killstreaks.fev/killstreaks/rampage"),
    ["Killingspree"] = PrecacheAsset("sound/killstreaks.fev/killstreaks/killingspree"),
    ["Dominating"] = PrecacheAsset("sound/killstreaks.fev/killstreaks/dominating"),
    ["Unstoppable"] = PrecacheAsset("sound/killstreaks.fev/killstreaks/unstoppable"),
    ["Megakill"] = PrecacheAsset("sound/killstreaks.fev/killstreaks/megakill"),
    ["Ultrakill"] = PrecacheAsset("sound/killstreaks.fev/killstreaks/ultrakill"),
    ["Ownage"] = PrecacheAsset("sound/killstreaks.fev/killstreaks/ownage"),
    ["Ludicrouskill"] = PrecacheAsset("sound/killstreaks.fev/killstreaks/ludicrouskill"),
    ["Headhunter"] = PrecacheAsset("sound/killstreaks.fev/killstreaks/headhunter"),
    ["Whickedsick"] = PrecacheAsset("sound/killstreaks.fev/killstreaks/whickedsick"),
    ["Monsterkill"] = PrecacheAsset("sound/killstreaks.fev/killstreaks/monsterkill"),
    ["Holyshit"] = PrecacheAsset("sound/killstreaks.fev/killstreaks/holyshit"),
    ["Godlike"] = PrecacheAsset("sound/killstreaks.fev/killstreaks/godlike")
}
  
function Plugin:SetupDataTable()
    local Sound = {
        Name = "string(255)",
    }
    self:AddNetworkMessage("PlaySound", Sound, "Client" )
end
    
Shine:RegisterExtension( "killstreak", Plugin )