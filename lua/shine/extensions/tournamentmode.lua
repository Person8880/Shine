--[[
Shine tournament mode
]]

local Shine = Shine
local Notify = Shared.Message

local Plugin = {}
local tostring = tostring
Plugin.Version = "0.1"

Plugin.HasConfig = true
Plugin.ConfigName = "Tournament.json"
Plugin.DefaultConfig =
{
    Warmup = false, //Warmup enabled?
    Warmuptime = 5 //Warmup time in min
    MsgDelay = 5 // Delay in secounds before plugin shows infomessage after connect
}
Plugin.CheckConfig = true

//saves Votes
Plugin.Votes = {}
Warmup = false
local Gamerules = GetGamerules()

function Plugin:Initialise()
     self.Enabled = true 
     
     //turn off autobalance
     Server.SetConfigSetting("auto_team_balance", nil)
     Server.SetConfigSetting("end_round_on_team_unbalance",nil)
     
     if self.Config.Warmup == true then
        Plugin:StartWarmuptime()        
     end
     //loads Commands
     Plugin:CreateCommands()
     return true
end

function Plugin:CheckGameStart( Gamerules )
    //todo: addcommandermode   
    if #Plugin.Votes >= #Shared.GetEntitiesWithClassname("Player") or Warmup == true then return Gamerules:SetGameState(kGameState.NotStarted) end    
    return false
end

//Startgame
function Plugin:StartGame( Gamerules )
    Gamerules:ResetGame()
    Gamerules:SetGameState( kGameState.Countdown )
    Gamerules.countdownTime = kCountDownLength
    Gamerules.lastCountdownPlayed = nil

    for _, Player in ientitylist( Shared.GetEntitiesWithClassname( "Player" ) ) do
        if Player.ResetScores then
            Player:ResetScores()
        end
    end
end

//Player connects
function Plugin:ClientConfirmConnect(Client)
    if Client:GetIsVirtual() then return end
    Shine.Timer.Simple( self.Config.MsgDelay, function()
	    Shine:Notify( Client, "", "", "Tournamentmode is enabled!. Type !rdy into chat when you are ready")
    end )
end

//Player disconnects
function Plugin:ClientDisconnect(Client)
    local steamId = Client:GetUserId()
    local find = Plugin:TableFind(Plugin.Votes,steamid)
    if find == nil then return end
    table.remove(Plugin.Votes, find)    
end

function Plugin:TableFind(table ,find)
    for i=1, #table do
        if table[i] == find then return i end
    end
    return nil
end
//Warmuptime functions
function Plugin:StartWarmuptime()
    if Warmup == true then return end
    Warmup = true
    Shine.Timer.Simple( self.Config.MsgDelay, function()
	    Shine:Notify( nil, "", "", "Warmup Time started. You can't use !rdy will its not over")
    end )
    //disable ns2stats todo find better way
    Shared.ConsoleCommand("sh_unloadplugin ns2stats") 
    //end Warmup after set min in config
    Shine.Timer.Create( "Warmuptimer", self.Config.Warmuptime*60, self.Config.Warmuptime*60+1, function()
       Plugin:EndWarmuptime()
    end)
       
end

function Plugin:EndWarmuptime
   if Warmup == false then return end
   Warmup = false
    Shine.Timer.Simple( self.Config.MsgDelay, function()
	    Shine:Notify( nil, "", "", "Warmup Time is over. Join teams and type !rdy to start the game")
    end )
   //enable NS2stats
   Shared.ConsoleCommand("sh_loadplugin ns2stats") 
end

// commands
function Plugin:CreateCommands()
    local Ready = self:BindCommand( "sh_ready", {"rdy","ready"},function(Client)
        if Warmup == true return end
        if Plugin:TableFind(Plugin.Votes, Client:GetUserId()) ~= nil then return end
        table.insert(Plugin.Votes, Client:GetUserId()
    end)
    Ready:Help ("Make yourself ready to start the game")
    
    local Ready = self:BindCommand( "sh_startwarmup","startwarmup" ,function(Client)
        if Shine:HasAccess( Client , "sh_warmup") then
            Plugin:StartWarmuptime()
        end
    end)
    Ready:Help ("Starts Warmup time")
    
    local Ready = self:BindCommand( "sh_startwarmup","startwarmup" ,function(Client)
        if Shine:HasAccess( Client , "sh_warmup") then
            Plugin:EndWarmuptime()
        end
    end)
    Ready:Help ("Ends Warmup time")
end

function Plugin:Cleanup()
    Shine.Timer.Destroy("Warmuptimer")
    //turn on balancemode
    Server.SetConfigSetting("auto_team_balance", true)
    Server.SetConfigSetting("end_round_on_team_unbalance",true)
    self.Enabled = false
end
Shine:RegisterExtension( "tournamentmode", Plugin )