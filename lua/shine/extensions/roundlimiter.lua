--[[
	Shine Roundlimiter Plugin
]]

local Shine = Shine

local StringFormat = string.format
local TimeToString = string.TimeToString

local Plugin = {}
Plugin.Version = "1.0"

Plugin.WIN_SCORE = 1
Plugin.WIN_RTS = 2
Plugin.WIN_COLLECTEDRES = 3

Plugin.HasConfig = true
Plugin.ConfigName = "RoundLimiter.json"

Plugin.DefaultConfig = {
	WarningTime = 5,
	WarningRepeatTimes = 5,
	MaxRoundLength = 60,
	WinCondition = 1
}

Plugin.CheckConfig = true

local TeamScores = {
	[ 1 ] = 0,
	[ 2 ] = 0,
}

Shine.Hook.SetupClassHook( "ScoringMixin", "AddScore", "OnScore", "PassivePost" )

--[[
	Keep track of the playing team scores.
]]
function Plugin:OnScore( Player, Points, Res, WasKill )
	if self.Config.WinCondition ~= self.WIN_SCORE then return end
	if not Points then return end
	
	local Team = Player.GetTeamNumber and Player:GetTeamNumber()    
	if not TeamScores[ Team ] then return end
	
	TeamScores[ Team ] = TeamScores[ Team ] + Points   
end

--[[
	Ends the round, making the team with the highest tracked score win.
]]
function Plugin:EndRound()
	local Winner = 2

	local Gamerules = GetGamerules()
	if not Gamerules then return end

	local WinCondition = self.Config.WinCondition

	--Team with the most points scored over the game.
	if WinCondition == self.WIN_SCORE then
		if TeamScores[ 1 ] > TeamScores[ 2 ] then Winner = 1 end
	--Team with the most RTs at the time of ending.
	elseif WinCondition == self.WIN_RTS then
		local Extractors = Shared.GetEntitiesWithClassname( "Extractor" ):GetSize()
		local Harvesters = Shared.GetEntitiesWithClassname( "Harvester" ):GetSize()

		if Extractors > Harvesters then Winner = 1 end
	--Team that collected the most team resources (i.e resources over the whole game).
	elseif WinCondition == self.WIN_COLLECTEDRES then
		local Marines = Gamerules.team1
		local Aliens = Gamerules.team2

		local MarineRes = Marines:GetTotalTeamResources()
		local AlienRes = Aliens:GetTotalTeamResources()

		if MarineRes > AlienRes then Winner = 1 end
	end
	
	Shine:NotifyDualColour( nil, 100, 255, 100, "[RoundLimiter]", 255, 255, 255,
		"Ending round due to time limit..." )
	
	Gamerules:EndGame( Winner == 2 and Gamerules.team2 or Gamerules.team1 )
end

local WarningsLeft = 0

function Plugin:DisplayWarning()
	local TimeLeft = WarningsLeft * self.Config.WarningTime * 60 / self.Config.WarningRepeatTimes
	local Message = StringFormat( "%s left until this round ends.", 
		TimeToString( TimeLeft ) )

	WarningsLeft = WarningsLeft - 1

	Shine:NotifyDualColour( nil , 100, 255, 100, "[RoundLimiter]", 255, 255, 255, Message )
end

function Plugin:StartWarning()
	WarningsLeft = self.Config.WarningRepeatTimes

	self:DisplayWarning()

	if WarningsLeft > 0 then
		local TimeInterval = self.Config.WarningTime * 60 / self.Config.WarningRepeatTimes

		self:CreateTimer( "Nag", TimeInterval, WarningsLeft, function()
			self:DisplayWarning()
		end )
	end
end

function Plugin:SetGameState( Gamerules, NewState, OldState )    
	if NewState ~= kGameState.Started then 
		self:DestroyAllTimers()

		return
	end

	--Reset team scores.
	TeamScores[ 1 ] = 0
	TeamScores[ 2 ] = 0

	--Queue the warnings.
	if self.Config.WarningTime > 0 then
		local WarnTime = ( self.Config.MaxRoundLength - self.Config.WarningTime ) * 60
		
		self:SimpleTimer( WarnTime, function()
			self:StartWarning()
		end )
	end

	--Queue the round end.
	self:SimpleTimer( self.Config.MaxRoundLength * 60, function()
		self:EndRound()
	end )
end

Shine:RegisterExtension( "roundlimiter", Plugin )
