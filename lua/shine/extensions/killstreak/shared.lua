--[[
Shine Killstreak Plugin - Shared
]]

local Plugin = {}

--precache ShineSounds        
ShineSoundTriplekill = PrecacheAsset("sound/killstreaks.fev/killstreaks/triplekill")
ShineSoundMultikill = PrecacheAsset("sound/killstreaks.fev/killstreaks/multikill")
ShineSoundRampage = PrecacheAsset("sound/killstreaks.fev/killstreaks/rampage")
ShineSoundKillingspree = PrecacheAsset("sound/killstreaks.fev/killstreaks/killingspree")
ShineSoundDominating = PrecacheAsset("sound/killstreaks.fev/killstreaks/dominating")
ShineSoundUnstoppable = PrecacheAsset("sound/killstreaks.fev/killstreaks/unstoppable")
ShineSoundMegakill = PrecacheAsset("sound/killstreaks.fev/killstreaks/megakill")
ShineSoundUltrakill = PrecacheAsset("sound/killstreaks.fev/killstreaks/ultrakill")
ShineSoundOwnage = PrecacheAsset("sound/killstreaks.fev/killstreaks/ownage")
ShineSoundLudicrouskill = PrecacheAsset("sound/killstreaks.fev/killstreaks/ludicrouskill")
ShineSoundHeadhunter = PrecacheAsset("sound/killstreaks.fev/killstreaks/headhunter")
ShineSoundWhickedsick = PrecacheAsset("sound/killstreaks.fev/killstreaks/whickedsick")
ShineSoundMonsterkill = PrecacheAsset("sound/killstreaks.fev/killstreaks/monsterkill")
ShineSoundHolyshit = PrecacheAsset("sound/killstreaks.fev/killstreaks/holyshit")
ShineSoundGodlike = PrecacheAsset("sound/killstreaks.fev/killstreaks/godlike")
  
function Plugin:SetupDataTable()
    local Sound = {
        Name = "string(255)",
    }
    self:AddNetworkMessage("PlaySound", Sound, "Client" )
end
    
Shine:RegisterExtension( "killstreak", Plugin )