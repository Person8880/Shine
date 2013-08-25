--[[
Shine tournament mode
]]

local Shine = Shine
local Notify = Shared.Message

local Plugin = {}
Plugin.Version = "0.3"

Plugin.HasConfig = true
Plugin.ConfigName = "Tournament.json"
Plugin.DefaultConfig =
{
    CaptainMode = false, //Use Captain Mode
    Captains = {}, // Captains ns2ids
    Warmup = false, //Warmup enabled?
    Warmuptime = 5, //Warmup time in min    
    ForceTeams = false, //force teams to stay the same
    Teams = {},
}
Plugin.CheckConfig = true

local BlacklistMods = {
        [ "5f35045" ] = "Combat",
        [ "7e64c1a" ] = "Xenoswarm",
        [ "7957667" ] = "Marine vs Marine",
        [ "6ed01f8" ] = "The Faded"
}

//saves Votes
local Voted = {}
local Votes = 0
local CaptainsOnline = 0
local Warmup = false

function Plugin:Initialise()
        
    local GetMod = Server.GetActiveModId

    for i = 1, Server.GetNumActiveMods() do
        local Mod = GetMod( i ):lower()

        local OnBlacklist = BlacklistMods[ Mod ]

        if OnBlacklist then
            return false, StringFormat( "The tournamentmode plugin does not work with %s.", OnBlacklist )
        end
    end
    
     //loads Commands
     Plugin:CreateCommands()
     self.Enabled = true
     return true
end

function Plugin:CheckGameStart( Gamerules )
    local State = Gamerules:GetGameState()
	if State ~= kGameState.Started then return end
    local playernumber = Server.GetNumPlayers()
    if self.Config.CaptainMode then playernumber = CaptainsOnline end
    if Votes >= playernumber or Warmup then Plugin:StartGame( Gamerules ) return end    
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

//value for first join
local first = true

//Player connects
function Plugin:ClientConfirmConnect(Client)

    //we have to use this way because shine is loaded to early
    if first then
    
        //start warmup
        if self.Config.Warmup == true then
            Plugin:StartWarmuptime()        
        end
        
        //turn off autobalance        
        Server.SetConfigSetting("auto_team_balance", nil)
        Server.SetConfigSetting("end_round_on_team_unbalance",nil)
        first = false
    end
    if Client:GetIsVirtual() then return end 
    local id = Client:GetUserId()  
	if not self.Config.CaptainMode then Shine:Notify( Client, "", "", "Tournamentmode is enabled!. Type !rdy into chat when you are ready")
	elseif self.Captains[id] == true then Shine:Notify( Client, "", "", "Tournamentmode is enabled!. Type !rdy into chat when you are ready.\n Chosse your teammates with !choose")
    else Shine:Notify( Client, "", "", "Tournamentmode is enabled!. Wait until a Teamcaptain picks you.") end
    if self.Config.ForceTeams then        
        if self.Config.Teams[id] then
            Gamerules:JoinTeam( Client:GetPlayer(), self.Config.Teams[id], nil, true )     
        end
    end
    if self.Config.Captains[id] == true then CaptainsOnline = CaptainsOnline + 1 end
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
	Shine:Notify( nil, "", "", "Warmup Time started. You can't use !rdy until its not over")  
    //disable ns2stats
    if Shine.Plugins.ns2stats.Enabled then
      Shine.Plugins.ns2stats.Config.Statsonline = false
    end
    //end Warmup after set min in config
    Shine.Timer.Simple(self.Config.Warmuptime*60, function()
       Plugin:EndWarmuptime()
    end)
       
end

function Plugin:EndWarmuptime()
   if Warmup == false then return end
   Warmup = false  
    Shine:Notify( nil, "", "", "Warmup Time is over. Join teams and type !rdy to start the game")
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
        if Warmup == true then return end
        if self.Config.CaptainMode then
            if not self.Config.Captains[Client:GetUserId()] then return end
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
        if self.Config.Captainmode and self.Config.Captains[Client:GetUserId()] == true then
            local Player = player:GetPlayer()
            local playerTeam = Client:GetPlayer():GetTeam():GetTeamNumber()
            if playerTeam ~= 0 then Shine:Notify( Client, "", "", "You can only choose players from the Ready Room") return end
            Gamerules:JoinTeam( Player, playerTeam, nil, true )
        end
    end,true)
    Choose:AddParam{ Type = "client"}    
    Choose:Help ("Choose Player with the given name for you team ")
    
    local Clearteams = self:BindCommand( "sh_clearteams","clearteams" ,function()
        self.Config.Teams = {}
        self:SaveConfig()        
    end)
    Clearteams:Help("Removes all players from teams in config ")
end

function Plugin:Cleanup()
    //turn on balancemode
    Server.SetConfigSetting("auto_team_balance", true)
    Server.SetConfigSetting("end_round_on_team_unbalance",true)
    self.Enabled = false
end

Shine:RegisterExtension( "tournamentmode", Plugin )
