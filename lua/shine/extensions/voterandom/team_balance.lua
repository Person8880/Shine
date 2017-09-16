--[[
	Handles team balancing related stuff.
]]

Script.Load( Shine.GetPluginFile( "voterandom", "team_optimiser.lua" ) )

local BalanceModule = {}
local Plugin = Plugin

local Abs = math.abs
local Ceil = math.ceil
local GetOwner = Server.GetOwner
local Max = math.max
local next = next
local Random = math.random
local TableMixin = table.Mixin
local TableSort = table.sort

local EvenlySpreadTeams = Shine.EvenlySpreadTeams

Shine.Hook.SetupClassHook( "BotTeamController", "UpdateBots", "UpdateBots", "ActivePre" )

local function GetAverageSkillFunc( Players, Func, TeamNumber )
	local PlayerCount = #Players
	if PlayerCount == 0 then
		return {
			Average = 0,
			Total = 0,
			Count = 0,
			Skills = {}
		}
	end

	local PlayerSkillSum = 0
	local Count = 0
	local Skills = {}

	for i = 1, PlayerCount do
		local Ply = Players[ i ]

		if Ply then
			local Skill = Func( Ply, TeamNumber )
			if Skill then
				Count = Count + 1
				PlayerSkillSum = PlayerSkillSum + Skill

				Skills[ Count ] = Skill
			end
		end
	end

	if Count == 0 then
		return {
			Average = 0,
			Total = 0,
			Count = 0,
			Skills = Skills
		}
	end

	TableSort( Skills, function( A, B )
		return A > B
	end )

	return {
		Average = PlayerSkillSum / Count,
		Total = PlayerSkillSum,
		Count = Count,
		Skills = Skills
	}
end

local DebugMode = false

-- TeamNumber parameter currently unused, but ready for Hive 2.0
BalanceModule.SkillGetters = {
	GetHiveSkill = function( Ply, TeamNumber )
		if DebugMode then
			local Client = GetOwner( Ply )
			if Client and Client:GetIsVirtual() then
				Client.Skill = Client.Skill or Random( 0, 2500 )
				return Client.Skill
			end
		end

		if Ply.GetPlayerSkill then
			return Ply:GetPlayerSkill()
		end

		return nil
	end,

	-- KA/D Ratio.
	GetKDR = function( Ply, TeamNumber )
		if DebugMode then
			local Client = GetOwner( Ply )
			if Client and Client:GetIsVirtual() then
				Client.Skill = Client.Skill or Random() * 3
				return Client.Skill
			end
		end

		do
			local KDR = Plugin:CallModuleEvent( "GetPlayerKDR", Ply, TeamNumber )
			if KDR then return KDR end
		end

		local Kills = Ply.totalKills
		local Deaths = Ply.totalDeaths
		local Assists = Ply.totalAssists or 0

		if Kills and Deaths then
			if Deaths == 0 then Deaths = 1 end

			return ( Kills + Assists * 0.1 ) / Deaths
		end

		return nil
	end,

	-- Score per minute played.
	GetScore = function( Ply, TeamNumber )
		if DebugMode then
			local Client = GetOwner( Ply )
			if Client and Client:GetIsVirtual() then
				Client.Skill = Client.Skill or Random() * 10
				return Client.Skill
			end
		end

		do
			local ScorePerMinute = Plugin:CallModuleEvent( "GetPlayerScorePerMinute", Ply, TeamNumber )
			if ScorePerMinute then return ScorePerMinute end
		end

		if not Ply.totalScore or not Ply.totalPlayTime then
			return nil
		end

		local PlayTime = Ply.totalPlayTime + ( Ply.playTime or 0 )
		if PlayTime <= 0 then
			return nil
		end

		return Ply.totalScore / ( PlayTime / 60 )
	end
}

function BalanceModule:AssignPlayers( TeamMembers, SortTable, Count, NumTargets, TeamSkills, RankFunc )
	local Add = Random() >= 0.5 and 1 or 0
	local Team = 1 + Add
	local MaxForTeam = Ceil( ( NumTargets + #TeamMembers[ 1 ] + #TeamMembers[ 2 ] ) * 0.5 )

	local function GetAverages( Team, JoiningSkill )
		local Skills = TeamSkills[ Team ]
		return Skills.Average, ( Skills.Total + JoiningSkill ) / ( Skills.Count + 1 )
	end

	local Sorted = {}

	-- First pass, place unassigned players onto the team with the lesser average skill rating.
	for i = 1, Count do
		if SortTable[ i ] then
			local Player = SortTable[ i ]
			local TeamToJoin = Team
			local OtherTeam = ( Team % 2 ) + 1

			if #TeamMembers[ Team ] < MaxForTeam then
				if #TeamMembers[ OtherTeam ] < MaxForTeam then
					local OtherAverage, TheirNewAverage = GetAverages( OtherTeam, RankFunc( Player, OtherTeam ) )
					local OurAverage, NewAverage = GetAverages( Team, RankFunc( Player, Team ) )

					if OurAverage > OtherAverage then
						if TheirNewAverage > OtherAverage then
							TeamToJoin = OtherTeam
							Team = OtherTeam
						end
					end
				end
			else
				TeamToJoin = OtherTeam
			end

			local TeamTable = TeamMembers[ TeamToJoin ]

			TeamTable[ #TeamTable + 1 ] = Player
			Sorted[ Player ] = true

			local SkillSum = TeamSkills[ TeamToJoin ].Total + RankFunc( Player, TeamToJoin )
			local PlayerCount = TeamSkills[ TeamToJoin ].Count + 1
			local AverageSkill = SkillSum / PlayerCount

			TeamSkills[ TeamToJoin ].Average = AverageSkill
			TeamSkills[ TeamToJoin ].Total = SkillSum
			TeamSkills[ TeamToJoin ].Count = PlayerCount
		end
	end

	return Sorted
end

function BalanceModule:UpdateBots()
	if self.OptimisingTeams then return false end
	if self.HasShuffledThisRound and not self.Config.ApplyToBots then return false end
end

local function DebugLogTeamMembers( Logger, self, TeamMembers )
	local TeamMemberOutput = {
		self:AsLogOutput( TeamMembers[ 1 ] ),
		self:AsLogOutput( TeamMembers[ 2 ] )
	}

	Logger:Debug( "Assigned team members:\n%s", table.ToString( TeamMemberOutput ) )
end

function BalanceModule:OptimiseTeams( TeamMembers, RankFunc, TeamSkills )
	-- Sanity check, make sure both team tables have even counts.
	Shine.EqualiseTeamCounts( TeamMembers )

	local Optimiser = self.TeamOptimiser( TeamMembers, TeamSkills, RankFunc )
	function Optimiser:GetNumPasses()
		return next( TeamMembers.TeamPreferences ) and 2 or 1
	end

	local IgnoreCommanders = self.Config.IgnoreCommanders
	function Optimiser:IsValidForSwap( Player, Pass )
		return ( Pass == 2 or not TeamMembers.TeamPreferences[ Player ] )
			and not ( IgnoreCommanders and Player:isa( "Commander" ) )
	end

	TableMixin( self.Config, Optimiser, {
		"StandardDeviationTolerance",
		"AverageValueTolerance"
	} )

	Optimiser:Optimise()

	self.Logger:Debug( "After optimisation:" )
	self.Logger:IfDebugEnabled( DebugLogTeamMembers, self, TeamMembers )
end

function BalanceModule:SortPlayersByRank( TeamMembers, SortTable, Count, NumTargets, RankFunc, NoSecondPass )
	local TeamSkills = {
		GetAverageSkillFunc( TeamMembers[ 1 ], RankFunc ),
		GetAverageSkillFunc( TeamMembers[ 2 ], RankFunc )
	}

	local Sorted = self:AssignPlayers( TeamMembers, SortTable, Count, NumTargets, TeamSkills, RankFunc )

	-- If you want/need to control number of players on teams, this is the best point to do it.
	Shine.Hook.Call( "PreShuffleOptimiseTeams", TeamMembers )

	if NoSecondPass then
		return Sorted
	end

	-- Update the team skill values in case the team members table was modified by the event.
	for i = 1, 2 do
		TeamSkills[ i ] = GetAverageSkillFunc( TeamMembers[ i ], RankFunc )
	end

	self:OptimiseTeams( TeamMembers, RankFunc, TeamSkills )

	return Sorted
end

local function GetFallbackTargets( Targets, Sorted )
	local FallbackTargets = {}

	for i = 1, #Targets do
		local Player = Targets[ i ]

		if Player and not Sorted[ Player ] then
			FallbackTargets[ #FallbackTargets + 1 ] = Player
			Sorted[ Player ] = true
		end
	end

	return FallbackTargets
end

function BalanceModule:AddPlayersRandomly( Targets, NumPlayers, TeamMembers )
	while NumPlayers > 0 and #TeamMembers[ 1 ] ~= #TeamMembers[ 2 ] do
		NumPlayers = NumPlayers - 1

		local Team = #TeamMembers[ 1 ] < #TeamMembers[ 2 ] and 1 or 2
		local TeamTable = TeamMembers[ Team ]
		local Player = Targets[ #Targets ]

		TeamTable[ #TeamTable + 1 ] = Player
		Targets[ #Targets ] = nil
	end

	if NumPlayers == 0 then return end

	local TeamSequence = math.GenerateSequence( NumPlayers, { 1, 2 } )

	for i = 1, NumPlayers do
		local Player = Targets[ i ]
		if Player then
			local TeamTable = TeamMembers[ TeamSequence[ i ] ]

			TeamTable[ #TeamTable + 1 ] = Player
		end
	end
end

BalanceModule.NormalisedScoreFactor = 2000

function BalanceModule:NormaliseSkills( ScoreTable, Max )
	-- Normalise KDR/Score amount to be similar values to Hive skill.
	-- This allows the optimise method to not have to worry about different scales.
	for i = 1, #ScoreTable do
		local Data = ScoreTable[ i ]
		local Skill = Data.Skill
		Data.Skill = Skill / Max * self.NormalisedScoreFactor
		ScoreTable[ Data.Player ] = Data.Skill
		ScoreTable[ i ] = Data.Player
	end
end

function BalanceModule:SortByScore( Gamerules, Targets, TeamMembers, Silent, RankFunc )
	local ScoreTable = {}
	local RandomTable = {}

	local Max = 0
	for i = 1, #Targets do
		local Player = Targets[ i ]

		if Player then
			local Score = RankFunc( Player )
			if Score then
				ScoreTable[ #ScoreTable + 1 ] = { Player = Player, Skill = Score }
				if Score > Max then
					Max = Score
				end
			else
				RandomTable[ #RandomTable + 1 ] = Player
			end
		end
	end

	self:NormaliseSkills( ScoreTable, Max )

	local ScoreSortCount = #ScoreTable
	if ScoreSortCount > 0 then
		--Make sure we ignore the second pass if we're a fallback for skill sorting.
		self:SortPlayersByRank( TeamMembers, ScoreTable, ScoreSortCount, #Targets, function( Player, TeamNumber )
			return ScoreTable[ Player ]
		end, Silent )
	end

	local RandomTableCount = #RandomTable

	if RandomTableCount > 0 then
		self:AddPlayersRandomly( RandomTable, RandomTableCount, TeamMembers )
	end

	self.Logger:Debug( "After SortByScore:" )
	self.Logger:IfDebugEnabled( DebugLogTeamMembers, self, TeamMembers )

	EvenlySpreadTeams( Gamerules, TeamMembers )
end

BalanceModule.ShufflingModes = {
	--Random only.
	function( self, Gamerules, Targets, TeamMembers, Silent )
		self:AddPlayersRandomly( Targets, #Targets, TeamMembers )

		self.Logger:Debug( "After AddPlayersRandomly:" )
		self.Logger:IfDebugEnabled( DebugLogTeamMembers, self, TeamMembers )

		EvenlySpreadTeams( Gamerules, TeamMembers )

		if not Silent then
			self:Print( "Teams were sorted randomly." )
		end
	end,
	--Score based if available, random if not.
	function( self, Gamerules, Targets, TeamMembers, Silent )
		self:SortByScore( Gamerules, Targets, TeamMembers, Silent, self.SkillGetters.GetScore )

		if not Silent then
			self:Print( "Teams were sorted based on score per minute." )
		end
	end,

	function( self, Gamerules, Targets, TeamMembers )
		-- Was NS2Stats Elo, now does nothing.
	end,

	--KDR based works identically to score, the score data is what is different.
	function( self, Gamerules, Targets, TeamMembers, Silent )
		self:SortByScore( Gamerules, Targets, TeamMembers, Silent, self.SkillGetters.GetKDR )

		if not Silent then
			self:Print( "Teams were sorted based on KDR." )
		end
	end,

	--Hive data based. Relies on UWE's ranking data to be correct for it to work.
	function( self, Gamerules, Targets, TeamMembers )
		local SortTable = {}
		local Count = 0
		local Sorted = {}

		local RankFunc = self.SkillGetters.GetHiveSkill
		local TargetCount = #Targets

		for i = 1, TargetCount do
			local Player = Targets[ i ]
			local Skill = Max( RankFunc( Player, 1 ) or 0, RankFunc( Player, 2 ) or 0 )
			if Skill > 0 then
				Count = Count + 1
				SortTable[ Count ] = Player
			end
		end

		local Sorted = self:SortPlayersByRank( TeamMembers, SortTable, Count,
			TargetCount, self.SkillGetters.GetHiveSkill )

		self:Print( "Teams were sorted based on Hive skill ranking." )

		-- If some players have rank 0 or no rank data, sort them with the fallback instead.
		local FallbackTargets = GetFallbackTargets( Targets, Sorted )
		if #FallbackTargets > 0 then
			self.ShufflingModes[ self.Config.FallbackMode ]( self, Gamerules,
				FallbackTargets, TeamMembers, true )

			return
		end

		EvenlySpreadTeams( Gamerules, TeamMembers )
	end
}

do
	local Sqrt = math.sqrt

	local function GetStandardDeviation( Players, Average, RankFunc, TeamNumber )
		local Sum = 0
		local RealCount = 0

		for i = 1, #Players do
			local Player = Players[ i ]
			if Player then
				local Skill = RankFunc( Player, TeamNumber )

				if Skill then
					RealCount = RealCount + 1
					Sum = Sum + ( Skill - Average ) ^ 2
				end
			end
		end

		if RealCount == 0 then
			return 0
		end

		return Sqrt( Sum / RealCount )
	end

	function BalanceModule:GetAverageSkill( Players, TeamNumber )
		return GetAverageSkillFunc( Players, self.SkillGetters.GetHiveSkill, TeamNumber )
	end

	function BalanceModule:GetTeamStats()
		local Marines = GetEntitiesForTeam( "Player", 1 )
		local Aliens = GetEntitiesForTeam( "Player", 2 )

		local MarineSkill = self:GetAverageSkill( Marines, 1 )
		MarineSkill.StandardDeviation = GetStandardDeviation( Marines, MarineSkill.Average,
			self.SkillGetters.GetHiveSkill, 1 )

		local AlienSkill = self:GetAverageSkill( Aliens, 2 )
		AlienSkill.StandardDeviation = GetStandardDeviation( Aliens, AlienSkill.Average,
			self.SkillGetters.GetHiveSkill, 2 )

		if self.LastShuffleTeamLookup then
			local NumMatchingTeams = 0
			local NumTotal = 0
			local Counted = {}
			local function CountMatching( Player )
				if not Player.GetClient or not Player:GetClient() or not Player.GetTeamNumber then return end

				local Client = Player:GetClient()
				local SteamID = Client:GetUserId()
				if Counted[ SteamID ] then return end

				Counted[ SteamID ] = true

				local OldTeam = self.LastShuffleTeamLookup[ SteamID ]
				NumTotal = NumTotal + 1

				if Player:GetTeamNumber() == OldTeam then
					NumMatchingTeams = NumMatchingTeams + 1
				end
			end

			Shine.Stream( Shine.GetAllPlayers() ):ForEach( CountMatching )

			return {
				MarineSkill, AlienSkill,
				TotalPlayers = NumTotal,
				NumMatchingTeams = NumMatchingTeams
			}
		end

		return {
			MarineSkill, AlienSkill
		}
	end
end

Plugin:AddModule( BalanceModule )
