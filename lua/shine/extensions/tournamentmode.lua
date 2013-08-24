--[[
Shine tournament mode
]]

local Shine = Shine
local Notify = Shared.Message

local Plugin = {}
Plugin.Version = "0.2"

Plugin.HasConfig = true
Plugin.ConfigName = "Tournament.json"
Plugin.DefaultConfig =
{
    CaptainMode= false, //Use Captain Mode
    Captains = {"90000001" = true , "123456789" = true}, // Captains ns2ids
    Warmup = false, //Warmup enabled?
    Warmuptime = 5, //Warmup time in min    
    ForceTeams = false, //force teams to stay the same
    Teams = {},
}
Plugin.CheckConfig = true

//saves Votes
Voted = {}
Votes = 0
CaptainsOnline = 0
Warmup = false

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
    local playernumber = Server.GetNumPlayers()
    if self.Config.CaptainMode then playernumber = CaptainsOnline end
    if Votes >= playernumber or Warmup then return Plugin:StartGame( Gamerules ) return end    
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
	Shine:Notify( Client, "", "", "Tournamentmode is enabled!. Type !rdy into chat when you are ready")
    local id = Client:GetUserId()
    if self.Config.ForceTeams then        
        if self.Config.Teams[id] then
            Gamerules:JoinTeam( Client:GetPlayer(), self.Config.Teams[id], nil, true )     
        end
    end
    if self.Config.Captains[id] then CaptainsOnline = CaptainsOnline + 1 end
end

//Player disconnects
function Plugin:ClientDisconnect(Client)
    if Voted[Client:GetUserId()] then Voted[Client:GetUserId()]= nil Votes = Votes -1 end   
end

//Block players from joining teams in captain mode
function Plugin:JoinTeam( Gamerules, Player, NewTeam, Force, ShineForce )
    local id= Player:GetClient():GetUserId()    
    //block f4 if forceteams is true
    if self.Config.ForceTeams then
        if NewTeam == kTeamReadyRoom then return false end 
    end 
    
    //cases in which jointeam is not limited
    if not self.Config.CaptainMode or Warmup or ShineForce then
        self.Config.Teams[id] = NewTeam
        self:SaveConfig()
    return end
    //check if player is Captain
    if self.Config.CaptainMode then        
        if self.Config.Captains[id] then
            self.Config.Teams[id] = NewTeam
            self:SaveConfig()            
        return end
    end    
    return false
end

//Warmuptime functions
function Plugin:StartWarmuptime()
    if Warmup == true then return end
    Warmup = true
    Shine.Timer.Simple( self.Config.MsgDelay, function()
	    Shine:Notify( nil, "", "", "Warmup Time started. You can't use !rdy will its not over")
    end )
    //disable ns2stats
    if Shine.Plugins.ns2stats.Enabled then
      Shine.Plugins.ns2stats.Config.Statsonline = false
    end
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
    if self.Config.CaptainMode then
       local allPlayers = Shared.GetEntitiesWithClassname("Player")
        for index, fromPlayer in ientitylist(allPlayers) do
            //move all player to rr
            Gamerules:JoinTeam(fromPlayer,0,nil,true)              
        end
        self.Config.Teams = {}
    end
    //enable ns2stats
   if Shine.Plugins.ns2stats.Enabled then
      Shine.Plugins.ns2stats.Config.Statsonline = true
   end
   Gamerules:Reset()  
end

// commands
function Plugin:CreateCommands()
    local Ready = self:BindCommand( "sh_ready", {"rdy","ready"},function(Client)
        if Warmup == true return end
        if self.Config.CaptainMode then
            if string.find(self.Config.Captains, Client:GetUserId()) == nil then return end
        end
        if not Voted[Client:GetUserId()] then Voted[Client:GetUserId()]= true Votes = Votes + 1 end
    end, true)
    Ready:Help ("Make yourself ready to start the game")
    
    local StartWarmup = self:BindCommand( "sh_startwarmup","startwarmup" ,function(Client)
        Plugin:StartWarmuptime()        
    end)
    StartWarmup:Help ("Starts Warmup time")
    
    local EndWarmup = self:BindCommand( "sh_endwarmup","endwarmup" ,function(Client)
        Plugin:EndWarmuptime()       
    end)
    EndWarmup:Help ("Ends Warmup time")
    
    local Choose = self:BindCommand( "sh_choose","choose" ,function(Client, player)
        if self.Config.Captainmode and string.find(self.Config.Captains, Client:GetUserId()) ~= nil then
            local Player = player:GetPlayer()
            Gamerules:JoinTeam( Player, Client:GetPlayer():GetTeam():GetTeamNumber(), nil, true )
        end
    end,true)
    Chosse:AddParam{ Type = "client"}    
    Choose:Help ("Choose Player with the given name for you team ")
    
    local Clearteams = self:BindCommand( "sh_clearteams","clearteams" ,function()
        self.Config.Teams = {}
        self:SaveConfig()        
    end)
    Clearteams:Help("Removes all players from teams in config ")
end

function Plugin:Cleanup()
    Shine.Timer.Destroy("Warmuptimer")
    //turn on balancemode
    Server.SetConfigSetting("auto_team_balance", true)
    Server.SetConfigSetting("end_round_on_team_unbalance",true)
    self.Enabled = false
end
Shine:RegisterExtension( "tournamentmode", Plugin )