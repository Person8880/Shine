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
         local RealKiller = Attacker.GetOwner and Attacker:GetOwner() or nil
         if RealKiller and RealKiller:isa("Player") then
            Attacker = RealKiller
         else return
         end
    end
    
    local VictimClient = GetOwner( Victim )
    local VictimId = VictimClient:GetUserId() or 0
    
    --for bots
    if VictimId == 0 then VictimId = Plugin:GetIdbyName(Victim:GetName()) or 0 end
    
    if VictimId>0 then
        local VName        
        if Killstreaks[VictimId] and Killstreaks[VictimId] > 3 then  VName = Victim:GetName() end
        Killstreaks[VictimId] = nil 
        if VName then Shine:NotifyColour(nil,255,0,0,StringFormat("%s has been stopped",VName)) end
    else return end
    
    local AttackerClient = GetOwner( Attacker )
    if not AttackerClient then return end
    
    local SteamId = AttackerClient:GetUserId() or 0
    local Name = Attacker:GetName()
    if SteamId == 0 then SteamId = Plugin:GetIdbyName(Name) end
    if not SteamId or SteamId<=0 then return end
    
    if not Killstreaks[SteamId] then Killstreaks[SteamId] = 1
    else Killstreaks[SteamId] = Killstreaks[SteamId] + 1 end    

    Plugin:CheckForMultiKills(Name,Killstreaks[SteamId])      
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

local Streaks = {
    [ 3 ] = {
        Text = "%s is on a triple kill!",
        Sound = "Triplekill"
    },    
    [ 5 ] = {
        Text = "%s is on multikill!",
        Sound = "Multikill"
    },    
    [ 6 ] = {
        Text = "%s is on rampage!",
        Sound = "Rampage"
    },
    [ 7 ] = {
        Text = "%s is on a killing spree!",
        Sound = "Killingspree"
    },
    [ 9 ] = {
        Text = "%s is dominating!",
        Sound = "Dominating"
    },
    [ 11 ] = {
        Text = "%s is unstoppable!",
        Sound = "Unstoppable"
    },
    [ 13 ] = {
        Text = "%s made a mega kill!",
        Sound = "Megakill"
    },
    [ 15 ] = {
        Text = "%s made an ultra kill!",
        Sound = "Ultrakill"
    },
    [ 17 ] = {
        Text = "%s owns!",
        Sound = "Ownage"
    },
    [ 18 ] = {
        Text = "%s made a ludicrouskill!",
        Sound = "Ludicrouskill"
    },
    [ 19 ] = {
        Text = "%s is a head hunter!",
        Sound = "Headhunter"
    },
    [ 20 ] = {
        Text = "%s is whicked sick!",
        Sound = "Whickedsick"
    },
    [ 21 ] = {
        Text = "%s made a monster kill!",
        Sound = "Monsterkill"
    },
    [ 23 ] = {
        Text = "Holy Shit! %s got another one!",
        Sound = "Holyshit"
    },
    [ 25 ] = {
        Text = "%s is G o d L i k e !!!",
        Sound = "Godlike"
    }
}
Streaks[27] = Streaks[25]
Streaks[30] = Streaks[25]
Streaks[34] = Streaks[25]
Streaks[40] = Streaks[25]
Streaks[48] = Streaks[25]
Streaks[58] = Streaks[25]
Streaks[70] = Streaks[25]
Streaks[80] = Streaks[25]
Streaks[100] = Streaks[25]
        
function Plugin:CheckForMultiKills( Name, Streak )
    local StreakData = Streaks[ Streak ]

    if not StreakData then return end

    Shine:NotifyColour( nil, 255, 0, 0, StringFormat( StreakData.Text, Name ) )
    self:PlaySoundForEveryPlayer(StreakData.Sound)
end

function Plugin:PlaySoundForEveryPlayer(name)
    if self.Config.SendSounds then
        self:SendNetworkMessage(nil,"PlaySound",{Name = name } ,true)
    end
end

function Plugin:Cleanup()
    self.Enabled = false
end    
    