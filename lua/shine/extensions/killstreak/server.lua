--[[
Shine Killstreak Plugin - Server
]]

local Shine = Shine
local GetOwner = Server.GetOwner
local Notify = Shared.Message

local StringFormat = string.format
local StringSub = string.UTF8Sub
local StringLen = string.len
local StringFind = string.find

local Plugin = Plugin

Plugin.Version = "1.0"

Plugin.HasConfig = true

Plugin.ConfigName = "Killstreak.json"
Plugin.DefaultConfig =
{
    SendSounds = false
}

Plugin.CheckConfig = true

local Killstreaks = {}
function Plugin:Initialise()
    self.Enabled = true
    return true
end

function Plugin:OnEntityKilled( Gamerules, Victim, Attacker, Inflictor, Point, Dir )
    if not Attacker or not Victim then return end
    if not Victim:isa("Player") then return end
    
    if not Attacker:isa("Player") then 
         local realKiller = (Attacker.GetOwner and Attacker:GetOwner()) or nil
         if realKiller and realKiller:isa("Player") then
            Attacker = realKiller
         else return
         end
    end
    
    local VictimClient = GetOwner( Victim )
    local victimId = VictimClient:GetUserId() or 0
    
    --for bots
    if victimId == 0 then victimId = Plugin:GetIdbyName(Victim:GetName()) or 0 end
    
    if victimId>0 then
        local vname        
        if Killstreaks[victimId] and Killstreaks[victimId] > 3 then  vname = Victim:GetName() end
        Killstreaks[victimId] = nil 
        if vname then Shine:NotifyColour(nil,255,0,0,StringFormat("%s has been stopped",vname)) end
    else return end
    
    local AttackerClient = GetOwner( Attacker )
    if not AttackerClient then return end
    
    local steamId = AttackerClient:GetUserId() or 0
    local name = Attacker:GetName()
    if steamId == 0 then steamId = Plugin:GetIdbyName(name) end
    if not steamId or steamId<=0 then return end
    
    if not Killstreaks[steamId] then Killstreaks[steamId] = 1
    else Killstreaks[steamId] = Killstreaks[steamId] + 1 end    

    Plugin:checkForMultiKills(name,Killstreaks[steamId])      
end

Shine.Hook.SetupGlobalHook("RemoveAllObstacles","OnGameReset","PassivePost")

--Gamereset
function Plugin:OnGameReset()
    Killstreaks = {}
end

--For Bots
function Plugin:GetIdbyName(Name)

    if not Name then return end
    
    local newId=""
    local letters = " (){}[]/.,+-=?!*1234567890aAbBcCdDeEfFgGhHiIjJkKlLmMnNoOpPqQrRsStTuUvVwWxXyYzZ"
    
    --cut the [Bot]
    local input = tostring(Name)
    input = StringSub(input,6)
    
    --to differ between e.g. name and name (2)   
    input = string.UTF8Reverse(input)
    
    for i=1, #input do
        local char = StringSub(input,i,i)
        local num = StringFind(letters,char,nil,true)
        newId = StringFormat("%s%s",newId,num)        
    end
    
    --fill up the ns2id to 12 numbers
    while StringLen(newId) < 12 do
        newId = StringFormat("%s0",newId)
    end       
    newId = StringSub(newId, 1 , 12)
    
    --make a int
    newId = tonumber(newId)
    return newId
end

function Plugin:checkForMultiKills(name,streak)
        
    local text = ""
    
    if streak == 3 then
        text = StringFormat("%s is on triple kill!", name)
        Plugin:playSoundForEveryPlayer(ShineSoundTriplekill)
    elseif streak == 5 then
        text = StringFormat("%s is on multikill!", name)
        Plugin:playSoundForEveryPlayer(ShineSoundMultikill)
    elseif streak == 6 then
        text = StringFormat("%s is on rampage!", name)
        Plugin:playSoundForEveryPlayer(ShineSoundRampage)
    elseif streak == 7 then
        text = StringFormat("%s is on a killing spree!", name)
        Plugin:playSoundForEveryPlayer(ShineSoundKillingspree)
    elseif streak == 9 then
        text = StringFormat("%s is dominating!", name)
        Plugin:playSoundForEveryPlayer(ShineSoundDominating)
    elseif streak == 11 then
        text = StringFormat("%s is unstoppable!", name)
        Plugin:playSoundForEveryPlayer(ShineSoundUnstoppable)
    elseif streak == 13 then
        text = StringFormat("%s made a mega kill!", name)
        Plugin:playSoundForEveryPlayer(ShineSoundMegakill)
    elseif streak == 15 then
        text = StringFormat("%s made an ultra kill!", name)
        Plugin:playSoundForEveryPlayer(ShineSoundUltrakill)
    elseif streak == 17 then
        text = StringFormat("%s owns!", name)
        Plugin:playSoundForEveryPlayer(ShineSoundOwnage)
    elseif streak == 18 then
        text = StringFormat("%s made a ludicrouskill!", name)
        Plugin:playSoundForEveryPlayer(ShineSoundLudicrouskill)
    elseif streak == 19 then
        text = StringFormat("%s is a head hunter!", name)
        Plugin:playSoundForEveryPlayer(ShineSoundHeadhunter)
    elseif streak == 20 then
        text = StringFormat("%s is whicked sick!", name)
        Plugin:playSoundForEveryPlayer(ShineSoundWhickedsick)
    elseif streak == 21 then
        text = StringFormat("%s made a monster kill!", name)
        Plugin:playSoundForEveryPlayer(ShineSoundMonsterkill)
    elseif streak == 23 then
        text = StringFormat("Holy Shit! %s got another one!", name)
        Plugin:playSoundForEveryPlayer(ShineSoundHolyshit)
    elseif streak == 25 then
        text = StringFormat("%s is G o d L i k e !!!", name)
        Plugin:playSoundForEveryPlayer(ShineSoundGodlike)
    elseif streak == 27 then
        text = StringFormat("%s is G o d L i k e !!!", name)
        Plugin:playSoundForEveryPlayer(ShineSoundGodlike)
    elseif streak == 30 then
        text = StringFormat("%s is G o d L i k e !!!", name)
        Plugin:playSoundForEveryPlayer(ShineSoundGodlike)
    elseif streak == 34 then
        text = StringFormat("%s is G o d L i k e !!!", name)
        Plugin:playSoundForEveryPlayer(ShineSoundGodlike)
    elseif streak == 40 then
        text = StringFormat("%s is G o d L i k e !!!", name)
        Plugin:playSoundForEveryPlayer(ShineSoundGodlike)
    elseif streak == 48 then
        text = StringFormat("%s is G o d L i k e !!!", name)
        Plugin:playSoundForEveryPlayer(ShineSoundGodlike)
    elseif streak == 58 then
        text = StringFormat("%s is G o d L i k e !!!", name)
        Plugin:playSoundForEveryPlayer(ShineSoundGodlike)
    elseif streak == 70 then
        text = StringFormat("%s is G o d L i k e !!!", name)
        Plugin:playSoundForEveryPlayer(ShineSoundGodlike)
    elseif streak == 80 then
        text = StringFormat("%s is G o d L i k e !!!", name)
        Plugin:playSoundForEveryPlayer(ShineSoundGodlike)
    elseif streak == 100 then
        text = StringFormat("%s is G o d L i k e !!!", name)
        Plugin:playSoundForEveryPlayer(ShineSoundGodlike)
    end
    Shine:NotifyColour(nil,255,0,0,text)
end

function Plugin:playSoundForEveryPlayer(name)
    if self.Config.SendSounds then
        self:SendNetworkMessage(nil,"PlaySound",{Name = name } ,true)
    end
end

function Plugin:Cleanup()
    self.Enabled = false
end    
    