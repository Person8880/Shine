--[[
    Shine Roundlimiter Plugin
]]
local Shine = Shine

local Plugin = {}
Plugin.Version = "1.0"

Plugin.HasConfig = true
Plugin.ConfigName = "roundlimiter.json"
Plugin.DefaultConfig =
{
    WarningTime = 5,
    WarningRepeatTimes = 5,
    MaxRoundLength = 60,
}
Plugin.CheckConfig = true

local TeamScores = {
    [ 1 ] = 0,
    [ 2 ] = 0,
}

Shine.Hook.SetupClassHook("ScoringMixin","AddScore","OnScore","PassivePost")
function Plugin:OnScore(player, points, res, wasKill)
    if not points then return end
    
    local teamnr = player.GetTeamNumber and player:GetTeamNumber()    
    if teamnr ~= 1 and teamnr ~= 2 then return end
    
    TeamScores[teamnr] =  TeamScores[teamnr] + points   
end

function Plugin:EndRound()
    local winner = 2
    if TeamScores[1] > TeamScores[2] then winner = 1 end
    
    local Gamerules = GetGamerules()
    if not Gamerules then return end
    
    Shine:NotifyDualColour(nil , 100, 255, 100, "[RoundLimiter]", 255, 255, 255,"Round ends now ...")
    Gamerules:EndGame( winner == 2 and Gamerules.team2 or Gamerules.team1 )
end

local WarningsLeft = 0

function Plugin:WarningMsg()
   local m = string.format("There are %i seconds left until this round ends.", WarningsLeft * self.Config.WarningTime * 60 / self.Config.WarningRepeatTimes)
   WarningsLeft = WarningsLeft - 1
   Shine:NotifyDualColour( nil , 100, 255, 100, "[RoundLimiter]", 255, 255, 255, m)
end

function Plugin:Warn()
   WarningsLeft = self.Config.WarningRepeatTimes
   Plugin:WarningMsg()
   self:CreateTimer("Nag", self.Config.WarningTime * 60 / self.Config.WarningRepeatTimes, self.Config.WarningRepeatTimes,function() self:WarningMsg() end)
end

--Gamestart
function Plugin:SetGameState( Gamerules, NewState, OldState )    
    if NewState == kGameState.Started then
        
        --reset team scores
        TeamScores = {
            [ 1 ] = 0,
            [ 2 ] = 0,
        }
        
        if self.Config.WarningTime > 0 then 
            self:SimpleTimer((self.Config.MaxRoundLength - self.Config.WarningTime) * 60, function() self:Warn() end)
        end    
        self:SimpleTimer(self.Config.MaxRoundLength * 60, function() self:EndRound() end)
    end
end

--Gameend
function Plugin:EndGame( Gamerules, WinningTeam )
    self:DestroyAllTimers()
end

Shine:RegisterExtension( "roundlimiter", Plugin )
