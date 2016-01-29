--[[
	Shine vote random plugin.
]]

local Shine = Shine

local Notify = Shared.Message

local Abs = math.abs
local assert = assert
local Ceil = math.ceil
local Clamp = math.Clamp
local Decode = json.decode
local Floor = math.floor
local GetAllPlayers = Shine.GetAllPlayers
local GetNumPlayers = Shine.GetHumanPlayerCount
local GetOwner = Server.GetOwner
local IsType = Shine.IsType
local Max = math.max
local Min = math.min
local next = next
local Random = math.random
local SharedTime = Shared.GetTime
local StringFormat = string.format
local TableConcat = table.concat
local TableEmpty = table.Empty
local TableRemove = table.remove
local TableSort = table.sort
local tostring = tostring

local Plugin = Plugin
Plugin.Version = "2.0"
Plugin.PrintName = "Shuffle"

Plugin.HasConfig = true
Plugin.ConfigName = "VoteRandom.json"

Plugin.RandomEndTimer = "VoteRandomTimer"

Plugin.MODE_RANDOM = 1
Plugin.MODE_SCORE = 2
Plugin.MODE_ELO = 3
Plugin.MODE_KDR = 4
Plugin.MODE_HIVE = 5

local ModeStrings = {
	Action = {
		"SHUFFLE_RANDOM",
		"SHUFFLE_SCORE",
		nil,
		"SHUFFLE_KDR",
		"SHUFFLE_HIVE"
	},
	Mode = {
		"RANDOM_BASED",
		"SCORE_BASED",
		nil,
		"KDR_BASED",
		"HIVE_BASED"
	},
	ModeLower = {
		"RANDOM_BASED_LOWER",
		"SCORE_BASED_LOWER",
		nil,
		"KDR_BASED_LOWER",
		"HIVE_BASED_LOWER"
	}
}
Plugin.ModeStrings = ModeStrings

Plugin.DefaultConfig = {
	MinPlayers = 10, --Minimum number of players on the server to enable voting.
	PercentNeeded = 0.75, --Percentage of the server population needing to vote for it to succeed.

	Duration = 15, --Time to force people onto teams for after a vote. Also time between successful votes.
	BlockAfterTime = 0, --Time after round start to block the vote. 0 to disable blocking.
	RandomOnNextRound = true, --If false, then random teams are forced for a duration instead.
	InstantForce = true, --Forces a shuffle of everyone instantly when the vote succeeds (for time based).
	VoteTimeout = 60, --Time after the last vote before the vote resets.

	BalanceMode = Plugin.MODE_HIVE, --How should teams be balanced?
	FallbackMode = Plugin.MODE_KDR, --Which method should be used if Elo/Hive fails?
	UseStandardDeviation = true, --Should standard deviation be accounted for when sorting?
	--[[
		How much of an increase in standard deviation should be allowed if the
		average is being improved but the standard deviation can't be?
	]]
	StandardDeviationTolerance = 40,

	BlockTeams = true, --Should team changing/joining be blocked after an instant force or in a round?
	IgnoreCommanders = true, --Should the plugin ignore commanders when switching?
	IgnoreSpectators = false, --Should the plugin ignore spectators when switching?
	AlwaysEnabled = false, --Should the plugin be always forcing each round?

	ReconnectLogTime = 0, --How long (in seconds) after a shuffle to log reconnecting players for?
	HighlightTeamSwaps = false, -- Should players swapping teams be highlighted on the scoreboard?
	DisplayStandardDeviations = false -- Should the scoreboard show each team's standard deviation of skill?
}
Plugin.CheckConfig = true
Plugin.CheckConfigTypes = true

local ModeError = [[Error in voterandom config, FallbackMode is not set as a valid option.
Make sure BalanceMode and FallbackMode are not the same, and that FallbackMode is not 3 (Elo) or 5 (Hive).
Setting FallbackMode to KDR mode (4).]]

local ModeClamp = Shine.IsNS2Combat and 4 or 5

function Plugin:OnFirstThink()
	local select = select

	local function SupplimentAdder( Adder, ExtraKey, PointsIndex )
		local OldFunc = ScoringMixin[ Adder ]

		ScoringMixin[ Adder ] = function( self, ... )
			OldFunc( self, ... )

			if not GetGamerules():GetGameStarted() then return end

			self[ ExtraKey ] = ( self[ ExtraKey ] or 0 ) + ( PointsIndex and select( PointsIndex, ... ) or 1 )
		end
	end

	SupplimentAdder( "AddScore", "totalScore", 1 )
	SupplimentAdder( "AddKill", "totalKills" )
	SupplimentAdder( "AddDeaths", "totalDeaths" )
	SupplimentAdder( "AddAssistKill", "totalAssists" )
end

function Plugin:Initialise()
	self.Config.BalanceMode = Clamp( Floor( self.Config.BalanceMode or 1 ), 1, ModeClamp )
	self.Config.FallbackMode = Clamp( Floor( self.Config.FallbackMode or 1 ), 1, ModeClamp )
	self.Config.ReconnectLogTime = Max( self.Config.ReconnectLogTime, 0 )

	local BalanceMode = self.Config.BalanceMode
	local FallbackMode = self.Config.FallbackMode

	if BalanceMode == self.MODE_ELO then
		BalanceMode = self.MODE_HIVE
		self.Config.BalanceMode = BalanceMode
		Notify( "NS2Stats Elo mode no longer exists. Switching to Hive skill mode..." )
	end

	if FallbackMode == self.MODE_ELO or FallbackMode == self.MODE_HIVE then
		self.Config.FallbackMode = self.MODE_KDR

		Notify( ModeError )

		self:SaveConfig()
	end

	self:CreateCommands()

	self.NextVote = 0

	self.Vote = Shine:CreateVote( function() return self:GetVotesNeeded() end,
		function() self:ApplyRandomSettings() end,
		function( Vote )
		if Vote.LastVoted and SharedTime() - Vote.LastVoted > self.Config.VoteTimeout then
			Vote:Reset()
		end
	end )

	self.ForceRandomEnd = 0 --Time based.
	self.RandomOnNextRound = false --Round based.
	self.ForceRandom = self.Config.AlwaysEnabled

	self.dt.HighlightTeamSwaps = self.Config.HighlightTeamSwaps
	self.dt.DisplayStandardDeviations = self.Config.DisplayStandardDeviations
		and BalanceMode == self.MODE_HIVE

	self.Enabled = true

	return true
end

local EvenlySpreadTeams = Shine.EvenlySpreadTeams

local function RandomiseSimilarSkill( Data, Count, Difference )
	local LastSkill = Data[ 1 ] and Data[ 1 ].Skill or 0

	--Swap those with a similar skill value randomly to make things different.
	for i = 2, Count do
		local Obj = Data[ i ]

		local CurSkill = Obj.Skill

		if LastSkill - CurSkill < Difference then
			if Random() >= 0.5 then
				local LastObj = Data[ i - 1 ]

				Data[ i ] = LastObj
				Data[ i - 1 ] = Obj

				LastSkill = LastObj.Skill
			else
				LastSkill = CurSkill
			end
		else
			LastSkill = CurSkill
		end
	end
end

local function GetAverageSkillFunc( Players, Func )
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
			local Skill = Func( Ply )
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
Plugin.SkillGetters = {
	GetHiveSkill = function( Ply )
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
	GetKDR = function( Ply )
		if DebugMode then
			local Client = GetOwner( Ply )
			if Client and Client:GetIsVirtual() then
				Client.Skill = Client.Skill or Random() * 3
				return Client.Skill
			end
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
	GetScore = function( Ply )
		if DebugMode then
			local Client = GetOwner( Ply )
			if Client and Client:GetIsVirtual() then
				Client.Skill = Client.Skill or Random() * 10
				return Client.Skill
			end
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

--Gets the average skill ranking of a table of players.
local function GetAverageSkill( Players )
	return GetAverageSkillFunc( Players, Plugin.SkillGetters.GetHiveSkill )
end

local Sqrt = math.sqrt

local function GetStandardDeviation( Players, Count, Average, RankFunc, Ply, Target )
	local Sum = 0
	local RealCount = 0

	for i = 1, Count do
		local Player = Players[ i ]
		if Player and Player ~= Ply then
			local Skill = RankFunc( Player )

			if Skill then
				RealCount = RealCount + 1
				Sum = Sum + ( Skill - Average ) ^ 2
			end
		end
	end

	if Target then
		local Skill = RankFunc( Target )

		if Skill then
			RealCount = RealCount + 1
			Sum = Sum + ( Skill - Average ) ^ 2
		end
	end

	if RealCount == 0 then
		return 0
	end

	return Sqrt( Sum / RealCount )
end

function Plugin:AssignPlayers( TeamMembers, SortTable, Count, NumTargets, TeamSkills )
	local Add = Random() >= 0.5 and 1 or 0
	local Team = 1 + Add
	local MaxForTeam = Ceil( ( NumTargets + #TeamMembers[ 1 ] + #TeamMembers[ 2 ] ) * 0.5 )

	local function GetAverages( Team, JoiningSkill )
		local Skills = TeamSkills[ Team ]
		return Skills.Average, ( Skills.Total + JoiningSkill ) / ( Skills.Count + 1 )
	end

	local Sorted = {}

	--First pass, place unassigned players onto the team with the lesser average skill rating.
	for i = 1, Count do
		if SortTable[ i ] then
			local Player = SortTable[ i ].Player
			local Skill = SortTable[ i ].Skill
			local TeamToJoin = Team
			local OtherTeam = ( Team % 2 ) + 1

			if #TeamMembers[ Team ] < MaxForTeam then
				if #TeamMembers[ OtherTeam ] < MaxForTeam then
					local OtherAverage, TheirNewAverage = GetAverages( OtherTeam, Skill )
					local OurAverage, NewAverage = GetAverages( Team, Skill )

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

			local SkillSum = TeamSkills[ TeamToJoin ].Total + Skill
			local PlayerCount = TeamSkills[ TeamToJoin ].Count + 1
			local AverageSkill = SkillSum / PlayerCount

			TeamSkills[ TeamToJoin ].Average = AverageSkill
			TeamSkills[ TeamToJoin ].Total = SkillSum
			TeamSkills[ TeamToJoin ].Count = PlayerCount
		end
	end

	return Sorted
end

local Huge = math.huge

function Plugin:PerformSwap( TeamMembers, TeamSkills, SwapData, LargerTeam, LesserTeam )
	--We've found a match that lowers the difference in averages the most.
	if SwapData.BestDiff >= Huge then return nil, LargerTeam, LesserTeam end

	for i = 1, 2 do
		local SwapPly = SwapData.BestPlayers[ i ]
		--If we're moving a player from one side to the other, drop them properly.
		if not SwapPly then
			TableRemove( TeamMembers[ i ], SwapData.Indices[ i ] )
			--Update player counts for the teams.
			TeamSkills[ LargerTeam ].Count = TeamSkills[ LargerTeam ].Count - 1
			TeamSkills[ LesserTeam ].Count = TeamSkills[ LesserTeam ].Count + 1
			--Cycle the larger/lesser teams.
			LargerTeam = ( LargerTeam % 2 ) + 1
			LesserTeam = ( LesserTeam % 2 ) + 1
		else
			TeamMembers[ i ][ SwapData.Indices[ i ] ] = SwapPly
		end
		TeamSkills[ i ].Total = SwapData.Totals[ i ]
		TeamSkills[ i ].Average = TeamSkills[ i ].Total / TeamSkills[ i ].Count
	end

	return true, LargerTeam, LesserTeam
end

function Plugin:OptimiseTeams( TeamMembers, RankFunc, TeamSkills )
	-- Sanity check, make sure both team tables have even counts.
	Shine.EqualiseTeamCounts( TeamMembers )

	--Second pass, optimise the teams by swapping players that will reduce the average skill difference.
	local NumTeam1 = #TeamMembers[ 1 ]
	local NumTeam2 = #TeamMembers[ 2 ]

	local LargerTeam
	if NumTeam1 > NumTeam2 then
		LargerTeam = 1
	elseif NumTeam2 > NumTeam1 then
		LargerTeam = 2
	end
	local LesserTeam = LargerTeam and ( ( LargerTeam % 2 ) + 1 ) or 2

	local IgnoreCommanders = self.Config.IgnoreCommanders
	local UseStandardDeviation = self.Config.UseStandardDeviation
	local StandardDeviationTolerance = self.Config.StandardDeviationTolerance

	local function CheckSwap( Ply, Skill, Target, TargetSkill, LargerIndex, LesserIndex, SwapData )
		local SwapResult = { {}, {} }

		for i = 1, 2 do
			local Total = TeamSkills[ i ].Total
			local Count = TeamSkills[ i ].Count

			local PreAverage = Total / Count
			SwapResult[ i ].PreAverage = PreAverage
			if UseStandardDeviation then
				SwapResult[ i ].PreStdDev = SwapData.StdDevs[ i ]
					or GetStandardDeviation( TeamMembers[ i ], Count, PreAverage, RankFunc )
				SwapData.StdDevs[ i ] = SwapResult[ i ].PreStdDev
			end

			local IsLesserTeam = i == LesserTeam
			SwapResult[ i ].Losing = IsLesserTeam and Target or Ply
			SwapResult[ i ].Gaining = IsLesserTeam and Ply or Target
			SwapResult[ i ].Index = IsLesserTeam and LesserIndex or LargerIndex

			local NewTotal = Total - ( IsLesserTeam and TargetSkill or Skill )
				+ ( IsLesserTeam and Skill or TargetSkill )
			if not Target then
				Count = Count + ( IsLesserTeam and 1 or -1 )
			end

			local NewAverage = NewTotal / Count
			SwapResult[ i ].PostAverage = NewAverage
			if UseStandardDeviation then
				SwapResult[ i ].PostStdDev = GetStandardDeviation( TeamMembers[ i ],
					Count, NewAverage, RankFunc,
					SwapResult[ i ].Losing, SwapResult[ i ].Gaining )
			end

			SwapResult[ i ].NewTotal = NewTotal
		end

		local PreDiff = Abs( SwapResult[ 1 ].PreAverage - SwapResult[ 2 ].PreAverage )
		local NewDiff = Abs( SwapResult[ 1 ].PostAverage - SwapResult[ 2 ].PostAverage )
		local AverageIsBetter = NewDiff < PreDiff and NewDiff < SwapData.BestDiff

		local StdDevIsBetter
		local NewStdDiff
		if not UseStandardDeviation then
			StdDevIsBetter = true
		else
			local PreStdDiff = Abs( SwapResult[ 1 ].PreStdDev - SwapResult[ 2 ].PreStdDev )
			NewStdDiff = Abs( SwapResult[ 1 ].PostStdDev - SwapResult[ 2 ].PostStdDev )

			-- Allow a slight increase in standard deviation difference if we're improving the averages.
			StdDevIsBetter = ( NewStdDiff <= PreStdDiff and NewStdDiff <= SwapData.BestStdDiff )
				or ( SwapData.BestStdDiff == Huge and ( NewStdDiff - PreStdDiff ) < StandardDeviationTolerance )
		end

		if AverageIsBetter and StdDevIsBetter then
			SwapData.BestDiff = NewDiff
			SwapData.BestStdDiff = NewStdDiff
			for i = 1, 2 do
				SwapData.BestPlayers[ i ] = SwapResult[ i ].Gaining
				SwapData.Indices[ i ] = SwapResult[ i ].Index
				SwapData.Totals[ i ] = SwapResult[ i ].NewTotal
			end
		end
	end

	TeamMembers.TeamPreferences = TeamMembers.TeamPreferences or {}
	-- If there's at least one player with a preferred team, then perform 2 passes.
	local NumPasses = next( TeamMembers.TeamPreferences ) and 2 or 1

	for Pass = 1, NumPasses do
		--Just in case, though it ought to not infinitely loop even without this.
		local Iterations = 0

		while Iterations < 30 do
			local Changed

			local SwapData = {
				BestDiff = Huge,
				BestPlayers = {},
				Indices = {},
				Totals = {}
			}
			if UseStandardDeviation then
				SwapData.BestStdDiff = Huge
				SwapData.StdDevs = {}
			end

			for i = 1, #TeamMembers[ LargerTeam or 1 ] do
				local Ply = TeamMembers[ LargerTeam or 1 ][ i ]

				if Ply and ( Pass == 2 or not TeamMembers.TeamPreferences[ Ply ] ) then
					local Skill = RankFunc( Ply )
					local ShouldIgnorePly = IgnoreCommanders and Ply:isa( "Commander" )

					if Skill and not ShouldIgnorePly then
						for j = 1, #TeamMembers[ LesserTeam ] do
							local Target = TeamMembers[ LesserTeam ][ j ]

							if Pass == 2 or not TeamMembers.TeamPreferences[ Target ] then
								local TargetSkill = RankFunc( Target )
								local ShouldIgnoreTarget = IgnoreCommanders
									and Target:isa( "Commander" )

								if TargetSkill and not ShouldIgnoreTarget then
									CheckSwap( Ply, Skill, Target, TargetSkill, i, j, SwapData )
								end
							end
						end

						if LargerTeam then
							local Team2Count = TeamSkills[ LesserTeam ].Count + 1

							CheckSwap( Ply, Skill, nil, 0, i, Team2Count, SwapData )
						end
					end
				end
			end

			Changed, LargerTeam, LesserTeam = self:PerformSwap( TeamMembers, TeamSkills, SwapData, LargerTeam, LesserTeam )

			if not Changed then break end

			Iterations = Iterations + 1
		end
	end
end

function Plugin:SortPlayersByRank( TeamMembers, SortTable, Count, NumTargets, RankFunc, NoSecondPass )
	local TeamSkills = {
		GetAverageSkillFunc( TeamMembers[ 1 ], RankFunc ),
		GetAverageSkillFunc( TeamMembers[ 2 ], RankFunc )
	}

	local Sorted = self:AssignPlayers( TeamMembers, SortTable, Count, NumTargets, TeamSkills )

	if NoSecondPass then
		return Sorted
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

function Plugin:AddPlayersRandomly( Targets, NumPlayers, TeamMembers )
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

Plugin.NormalisedScoreFactor = 2000

function Plugin:NormaliseSkills( ScoreTable, Max )
	-- Normalise KDR/Score amount to be similar values to Hive skill.
	-- This allows the optimise method to not have to worry about different scales.
	for i = 1, #ScoreTable do
		local Data = ScoreTable[ i ]
		local Skill = Data.Skill
		Data.Skill = Skill / Max * self.NormalisedScoreFactor
		ScoreTable[ Data.Player ] = Data.Skill
	end
end

function Plugin:SortByScore( Gamerules, Targets, TeamMembers, Silent, RankFunc )
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
		TableSort( ScoreTable, function( A, B ) return A.Skill > B.Skill end )

		--Make sure we ignore the second pass if we're a fallback for skill sorting.
		self:SortPlayersByRank( TeamMembers, ScoreTable, ScoreSortCount, #Targets, function( Player )
			return ScoreTable[ Player ]
		end, Silent )
	end

	local RandomTableCount = #RandomTable

	if RandomTableCount > 0 then
		self:AddPlayersRandomly( RandomTable, RandomTableCount, TeamMembers )
	end

	EvenlySpreadTeams( Gamerules, TeamMembers )

	if not Silent then
		Shine:LogString( "[Shuffle] Teams were sorted based on score." )
	end
end

Plugin.ShufflingModes = {
	--Random only.
	function( self, Gamerules, Targets, TeamMembers, Silent )
		self:AddPlayersRandomly( Targets, #Targets, TeamMembers )
		EvenlySpreadTeams( Gamerules, TeamMembers )

		if not Silent then
			Shine:LogString( "[Shuffle] Teams were sorted randomly." )
		end
	end,
	--Score based if available, random if not.
	function( self, Gamerules, Targets, TeamMembers, Silent )
		self:SortByScore( Gamerules, Targets, TeamMembers, Silent, self.SkillGetters.GetScore )
	end,

	function( self, Gamerules, Targets, TeamMembers )
		-- Was NS2Stats Elo, now does nothing.
	end,

	--KDR based works identically to score, the score data is what is different.
	function( self, Gamerules, Targets, TeamMembers, Silent )
		self:SortByScore( Gamerules, Targets, TeamMembers, Silent, self.SkillGetters.GetKDR )
	end,

	--Hive data based. Relies on UWE's ranking data to be correct for it to work.
	function( self, Gamerules, Targets, TeamMembers )
		local SortTable = {}
		local Count = 0
		local Sorted = {}

		local TargetCount = #Targets

		for i = 1, TargetCount do
			local Ply = Targets[ i ]

			local Skill = self.SkillGetters.GetHiveSkill( Ply )
			if Skill and Skill > 0 then
				Count = Count + 1
				SortTable[ Count ] = { Player = Ply, Skill = Skill }
			end
		end

		TableSort( SortTable, function( A, B )
			return A.Skill > B.Skill
		end )

		RandomiseSimilarSkill( SortTable, Count, 10 )

		local Sorted = self:SortPlayersByRank( TeamMembers, SortTable, Count, TargetCount, self.SkillGetters.GetHiveSkill )

		Shine:LogString( "[Skill Vote] Teams were sorted based on Hive skill ranking." )

		--If some players have rank 0 or no rank data, sort them with the fallback instead.
		local FallbackTargets = GetFallbackTargets( Targets, Sorted )

		if #FallbackTargets > 0 then
			self.ShufflingModes[ self.Config.FallbackMode ]( self, Gamerules,
				FallbackTargets, TeamMembers, true )

			return
		end

		EvenlySpreadTeams( Gamerules, TeamMembers )
	end
}

function Plugin:GetTeamStats()
	local Marines = GetEntitiesForTeam( "Player", 1 )
	local Aliens = GetEntitiesForTeam( "Player", 2 )

	local MarineSkill = GetAverageSkill( Marines )
	MarineSkill.StandardDeviation = GetStandardDeviation( Marines, #Marines, MarineSkill.Average, self.SkillGetters.GetHiveSkill )

	local AlienSkill = GetAverageSkill( Aliens )
	AlienSkill.StandardDeviation = GetStandardDeviation( Aliens, #Aliens, AlienSkill.Average, self.SkillGetters.GetHiveSkill )

	return {
		MarineSkill, AlienSkill
	}
end

--[[
	Gets all valid targets for sorting.
]]
function Plugin:GetTargetsForSorting( ResetScores )
	local Players, Count = GetAllPlayers()

	local Gamerules = GetGamerules()
	if not Gamerules then return end

	local Targets = {}
	local TeamMembers = {
		{},
		{},
		TeamPreferences = {}
	}

	local AFKEnabled, AFKKick = Shine:IsExtensionEnabled( "afkkick" )
	local IsRookieMode = Gamerules.gameInfo and Gamerules.gameInfo:GetRookieMode()

	local Time = SharedTime()

	local function SortPlayer( Player, Client, Commander, Pass )
		local Team = Player:GetTeamNumber()
		if Team == 3 and self.Config.IgnoreSpectators then
			return
		end

		-- Don't move non-rookies on rookie servers.
		if IsRookieMode and not Player:GetIsRookie() then
			return
		end

		local IsImmune = Shine:HasAccess( Client, "sh_randomimmune" ) or Commander

		--Pass 1, put all immune players into team slots.
		--This ensures they're picked last if there's a team imbalance at the end of sorting.
		--It does not stop them from being swapped if it helps overall balance though.
		if Pass == 1 then
			if IsImmune then
				local TeamTable = TeamMembers[ Team ]

				if TeamTable then
					TeamTable[ #TeamTable + 1 ] = Player
				end

				TeamMembers.TeamPreferences[ Player ] = true
			end

			return
		end

		--Pass 2, put all non-immune players into team slots/target list.
		if IsImmune then return end

		local BalanceMode = self.Config.BalanceMode
		local BiasTeams = BalanceMode == self.MODE_ELO or BalanceMode == self.MODE_HIVE
		--If they're on a playing team, bias towards letting them keep it.
		if ( Team == 1 or Team == 2 ) and BiasTeams then
			local TeamTable = TeamMembers[ Team ]

			TeamTable[ #TeamTable + 1 ] = Player
			TeamMembers.TeamPreferences[ Player ] = true
		else
			Targets[ #Targets + 1 ] = Player
		end
	end

	for j = 1, 2 do
		for i = 1, Count do
			local Player = Players[ i ]

			if Player then
				if Player.ResetScores and ResetScores then
					Player:ResetScores()
				end

				local Commander = Player:isa( "Commander" ) and self.Config.IgnoreCommanders

				local Client = Player:GetClient()

				if Client then
					if AFKEnabled then --Ignore AFK players in sorting.
						if not AFKKick:IsAFKFor( Client, 60 ) then
							SortPlayer( Player, Client, Commander, j )
						elseif j == 1 then --Chuck AFK players into the ready room.
							local Team = Player:GetTeamNumber()

							--Only move players on playing teams...
							if Team == 1 or Team == 2 then
								Gamerules:JoinTeam( Player, 0, nil, true )
							end
						end
					else
						SortPlayer( Player, Client, Commander, j )
					end
				end
			end
		end
	end

	return Targets, TeamMembers
end

--[[
	Shuffles everyone on the server into random teams.
]]
function Plugin:ShuffleTeams( ResetScores, ForceMode )
	local Gamerules = GetGamerules()

	if not Gamerules then return end

	local Targets, TeamMembers = self:GetTargetsForSorting( ResetScores )

	self.LastShuffleMode = ForceMode or self.Config.BalanceMode
	self.ReconnectLogTimeout = SharedTime() + self.Config.ReconnectLogTime
	self.ReconnectingClients = {}

	local ModeFunc = self.ShufflingModes[ ForceMode or self.Config.BalanceMode ]

	return ModeFunc( self, Gamerules, Targets, TeamMembers )
end

--[[
	Moves a single player onto a random team.
]]
function Plugin:JoinRandomTeam( Player )
	local Gamerules = GetGamerules()
	if not Gamerules then return end

	local Team1 = Gamerules:GetTeam( kTeam1Index ):GetNumPlayers()
	local Team2 = Gamerules:GetTeam( kTeam2Index ):GetNumPlayers()

	if Team1 < Team2 then
		Gamerules:JoinTeam( Player, 1 )
	elseif Team2 < Team1 then
		Gamerules:JoinTeam( Player, 2 )
	else
		if self.LastShuffleMode == self.MODE_HIVE then
			local Team1Players = Gamerules.team1:GetPlayers()
			local Team2Players = Gamerules.team2:GetPlayers()

			local Team1Skill = GetAverageSkill( Team1Players )
			local Team2Skill = GetAverageSkill( Team2Players )

			--If team skill is identical, then we should just pick a random team.
			if Team1Skill.Average ~= Team2Skill.Average then
				local BetterTeam = Team1Skill.Average > Team2Skill.Average and 1 or 2

				local PlayerSkill = Player.GetPlayerSkill and Player:GetPlayerSkill() or 0
				local TeamToJoin = BetterTeam == 1 and 2 or 1

				local NewTeam1Average = ( Team1Skill.Total + PlayerSkill ) / ( Team1Skill.Count + 1 )
				local NewTeam2Average = ( Team2Skill.Total + PlayerSkill ) / ( Team2Skill.Count + 1 )

				--If we're going to make the lower team even worse, then put them on the "better" team.
				if BetterTeam == 1 and NewTeam2Average < Team2Skill.Average then
					TeamToJoin = 1
				elseif BetterTeam == 2 and NewTeam1Average < Team1Skill.Average then
					TeamToJoin = 2
				end

				Gamerules:JoinTeam( Player, TeamToJoin )

				return
			end
		end

		if Random() < 0.5 then
			Gamerules:JoinTeam( Player, 1 )
		else
			Gamerules:JoinTeam( Player, 2 )
		end
	end
end

function Plugin:SetGameState( Gamerules, NewState, OldState )
	-- Reset the block time when the round stops.
	if NewState == kGameState.NotStarted then
		self.VoteBlockTime = nil
	end

	if NewState ~= kGameState.Countdown then return end

	--Block the vote after the set time.
	if self.Config.BlockAfterTime > 0 then
		self.VoteBlockTime = SharedTime() + self.Config.BlockAfterTime * 60
	end

	if not self.Config.AlwaysEnabled then return end
	if GetNumPlayers() < self.Config.MinPlayers then
		return
	end

	if self.DoneStartShuffle then return end

	self.DoneStartShuffle = true

	local OldValue = self.Config.IgnoreCommanders

	--Force ignoring commanders.
	self.Config.IgnoreCommanders = true

	self:SendTranslatedNotify( nil, "AUTO_SHUFFLE", {
		ShuffleType = ModeStrings.Action[ self.Config.BalanceMode ]
	} )
	self:ShuffleTeams()

	self.Config.IgnoreCommanders = OldValue
end

function Plugin:EndGame( Gamerules, WinningTeam )
	self.DoneStartShuffle = false
	self.VoteBlockTime = nil

	local Players, Count = GetAllPlayers()
	--Reset the randomised state of all players.
	for i = 1, Count do
		local Player = Players[ i ]

		if Player then
			Player.ShineRandomised = nil
		end
	end

	--If we're always enabled, we'll shuffle on round start.
	if self.Config.AlwaysEnabled then
		return
	end

	if self.RandomOnNextRound then
		self.RandomOnNextRound = false

		self:SimpleTimer( 15, function()
			local Enabled, MapVote = Shine:IsExtensionEnabled( "mapvote" )

			if Enabled and MapVote:IsEndVote() then
				self.ForceRandom = true

				return
			end

			self:SendTranslatedNotify( nil, "PREVIOUS_VOTE_SHUFFLE", {
				ShuffleType = ModeStrings.Action[ self.Config.BalanceMode ]
			} )

			self:ShuffleTeams()

			self.ForceRandom = true
		end )

		return
	end

	self.ForceRandom = false
	if not self:TimerExists( self.RandomEndTimer ) then return end

	self:SimpleTimer( 15, function()
		local Enabled, MapVote = Shine:IsExtensionEnabled( "mapvote" )

		if not ( Enabled and MapVote:IsEndVote() ) then
			self:SendTranslatedNotify( nil, "PREVIOUS_VOTE_SHUFFLE", {
				ShuffleType = ModeStrings.Action[ self.Config.BalanceMode ]
			} )

			self:ShuffleTeams()
		end

		if self:TimerExists( self.RandomEndTimer ) then
			self.ForceRandom = true
		end
	end )
end

function Plugin:JoinTeam( Gamerules, Player, NewTeam, Force, ShineForce )
	if ShineForce then return end
	if not self.ForceRandom then return end

	local Gamestate = Gamerules:GetGameState()

	--We'll do a mass balance, don't worry about them yet.
	if self.Config.AlwaysEnabled and Gamestate == kGameState.NotStarted then return end

	--Don't block them from going back to the ready room at the end of the round.
	if Gamestate == kGameState.Team1Won or Gamestate == kGameState.Team2Won
	or GameState == kGameState.Draw then return end

	local Client = GetOwner( Player )
	if not Client then return false end

	local Immune = Shine:HasAccess( Client, "sh_randomimmune" )
	if Immune then return end

	local Team = Player:GetTeamNumber()
	local OnPlayingTeam = Shine.IsPlayingTeam( Team )

	local NumTeam1 = Gamerules.team1:GetNumPlayers()
	local NumTeam2 = Gamerules.team2:GetNumPlayers()

	local ImbalancedTeams = Abs( NumTeam1 - NumTeam2 ) >= 2

	--Do not allow cheating the system.
	if OnPlayingTeam and self.Config.BlockTeams then
		--Allow players to switch if teams are imbalanced.
		if ImbalancedTeams then
			local MorePlayersTeam = NumTeam1 > NumTeam2 and 1 or 2
			if Team == MorePlayersTeam then
				return
			end
		end
		--Spamming F4 shouldn't spam messages...
		if Shine:CanNotify( Client ) then
			self:SendTranslatedNotify( Player, "TEAM_SWITCH_DENIED", {
				ShuffleType = ModeStrings.Mode[ self.Config.BalanceMode ]
			} )
		end

		return false
	end

	if not Player.ShineRandomised then
		if Team == 0 or Team == 3 then --They're going from the ready room/spectate to a team.
			Player.ShineRandomised = true --Prevent an infinite loop!

			self:NotifyTranslated( Player, self.LastShuffleMode == self.MODE_HIVE and "PLACED_ON_HIVE_TEAM"
				or "PLACED_ON_RANDOM_TEAM" )

			self:JoinRandomTeam( Player )

			return false
		end
	else
		--They came from ready room or spectate, i.e, we just randomised them.
		if Team == 0 or Team == 3 then
			Player.ShineRandomised = nil

			return
		end
	end
end

function Plugin:ClientDisconnect( Client )
	self.Vote:ClientDisconnect( Client )

	if not self.ReconnectLogTimeout then return end
	if SharedTime() > self.ReconnectLogTimeout then return end

	self.ReconnectingClients[ Client:GetUserId() ] = true
end

function Plugin:ClientConnect( Client )
	if not self.ReconnectingClients or not self.ReconnectLogTimeout then return end

	if SharedTime() > self.ReconnectLogTimeout then
		self.ReconnectingClients = nil

		return
	end

	if not self.ReconnectingClients[ Client:GetUserId() ] then return end

	self:Print( "Client %s reconnected after a shuffle vote.", true,
		Shine.GetClientInfo( Client ) )
end

function Plugin:GetVotesNeeded()
	local PlayerCount = GetNumPlayers()

	return Ceil( PlayerCount * self.Config.PercentNeeded )
end

function Plugin:GetStartFailureMessage()
	return "ERROR_CANNOT_START", { ShuffleType = ModeStrings.ModeLower[ self.Config.BalanceMode ] }
end

function Plugin:CanStartVote()
	local PlayerCount = GetNumPlayers()

	if PlayerCount < self.Config.MinPlayers then
		return false, "ERROR_NOT_ENOUGH_PLAYERS"
	end

	if self.NextVote >= SharedTime() then
		return false, self:GetStartFailureMessage()
	end

	if self.RandomOnNextRound then
		return false, "ERROR_ALREADY_ENABLED", { ShuffleType = ModeStrings.Mode[ self.Config.BalanceMode ] }
	end

	return true
end

--[[
	Adds a player's vote to the counter.
]]
function Plugin:AddVote( Client )
	if self.Config.AlwaysEnabled then
		return false, "ERROR_TEAMS_FORCED", { ShuffleType = ModeStrings.Mode[ self.Config.BalanceMode ] }
	end

	if self.VoteBlockTime and self.VoteBlockTime < SharedTime() then
		return false, "ERROR_ROUND_TOO_FAR"
	end

	if not Client then Client = "Console" end

	do
		local Allow, Error, TranslationKey, Args = Shine.Hook.Call( "OnVoteStart", "random" )
		if Allow == false then
			return false, TranslationKey, Args
		end
	end

	do
		local Success, Err, Args = self:CanStartVote()
		if not Success then
			return false, Err, Args
		end
	end

	if not self.Vote:AddVote( Client ) then
		return false, "ERROR_ALREADY_VOTED", { ShuffleType = ModeStrings.ModeLower[ self.Config.BalanceMode ] }
	end

	return true
end

--[[
	Timeout the vote.
]]
function Plugin:Think()
	self.Vote:Think()
end

--[[
	Applies the configured randomise settings.
	If set to random teams on next round, it queues a force of random teams for the next round.
	If set to a time duration, it enables random teams and queues the disabling of them.
]]
function Plugin:ApplyRandomSettings()
	self.RandomApplied = true
	self:SimpleTimer( 0, function()
		self.RandomApplied = false
	end )

	--Set up teams for the next round.
	if self.Config.RandomOnNextRound then
		local Gamerules = GetGamerules()

		--Game hasn't started, apply the settings now, as the next round is the one that's going to start...
		if not Gamerules:GetGameStarted() then
			self:SendTranslatedNotify( nil, "NEXT_ROUND_SHUFFLE", {
				ShuffleType = ModeStrings.Action[ self.Config.BalanceMode ]
			} )

			self:ShuffleTeams()

			self.ForceRandom = true

			return
		end

		self:SendTranslatedNotify( nil, "TEAMS_FORCED_NEXT_ROUND", {
			ShuffleType = ModeStrings.ModeLower[ self.Config.BalanceMode ]
		} )

		self.RandomOnNextRound = true

		return
	end

	--Set up teams now and make them last for the given time in the config.
	local Duration = self.Config.Duration * 60

	if Duration > 5 then
		self.ForceRandom = true
		self.NextVote = SharedTime() + Duration

		self:SendTranslatedNotify( nil, "TEAMS_SHUFFLED_FOR_DURATION", {
			ShuffleType = ModeStrings.Mode[ self.Config.BalanceMode ],
			Duration = Floor( Duration )
		} )

		self:CreateTimer( self.RandomEndTimer, Duration, 1, function()
			self:SendTranslatedNotify( nil, "TEAM_ENFORCING_TIMELIMIT", {
				ShuffleType = ModeStrings.Mode[ self.LastShuffleMode or self.Config.BalanceMode ]
			} )
			self.ForceRandom = false
		end )
	end

	if self.Config.InstantForce then
		local Gamerules = GetGamerules()

		local Started = Gamerules:GetGameStarted()

		if Started then
			self:SendTranslatedNotify( nil, "SHUFFLE_AND_RESTART", {
				ShuffleType = ModeStrings.Action[ self.Config.BalanceMode ]
			} )

			self:ShuffleTeams( true )
		else
			self:SendTranslatedNotify( nil, "SHUFFLING_TEAMS", {
				ShuffleType = ModeStrings.Action[ self.Config.BalanceMode ]
			} )

			self:ShuffleTeams()
		end

		if Started then
			Gamerules:ResetGame()
		end
	end
end

function Plugin:CreateCommands()
	local function VoteRandom( Client )
		if not Client then return end

		local Player = Client:GetControllingPlayer()
		local PlayerName = Player and Player:GetName() or "NSPlayer"

		local Success, Err, Args = self:AddVote( Client )

		if Success then
			local VotesNeeded = self.Vote:GetVotesNeeded()

			if not self.RandomApplied then
				self:SendTranslatedNotify( nil, "PLAYER_VOTED", {
					ShuffleType = ModeStrings.ModeLower[ self.Config.BalanceMode ],
					VotesNeeded = VotesNeeded,
					PlayerName = PlayerName
				} )
			end

			--Somehow it didn't apply random settings??
			if VotesNeeded == 0 and not self.RandomApplied then
				self:ApplyRandomSettings()
			end

			return
		end

		if not Args then
			self:NotifyTranslatedError( Player, Err )
		else
			self:SendTranslatedError( Player, Err, Args )
		end
	end
	local VoteRandomCommand = self:BindCommand( "sh_voterandom",
		{ "random", "voterandom", "randomvote", "shuffle", "voteshuffle", "shufflevote" },
		VoteRandom, true )
	VoteRandomCommand:Help( "Votes to force shuffled teams." )

	local function ForceRandomTeams( Client, Enable )
		if Enable then
			self.Vote:Reset()
			self:ApplyRandomSettings()

			self:SendTranslatedMessage( Client, "ENABLED_TEAMS", {
				ShuffleType = ModeStrings.ModeLower[ self.Config.BalanceMode ]
			} )
		else
			self:DestroyTimer( self.RandomEndTimer )
			self.Vote:Reset()

			self.RandomOnNextRound = false
			self.ForceRandom = false

			self.Config.AlwaysEnabled = false

			self:SendTranslatedNotify( nil, "DISABLED_TEAMS", {
				ShuffleType = ModeStrings.Mode[ self.Config.BalanceMode ]
			} )
		end
	end
	local ForceRandomCommand = self:BindCommand( "sh_enablerandom",
		{ "enablerandom", "enableshuffle" }, ForceRandomTeams )
	ForceRandomCommand:AddParam{ Type = "boolean", Optional = true,
		Default = function() return not self.ForceRandom end }
	ForceRandomCommand:Help( "Enables (and applies) or disables forcing shuffled teams." )

	local function ViewTeamStats( Client )
		if self.Config.BalanceMode ~= self.MODE_HIVE then
			if not Client then
				Notify( "Hive balancing is not currently enabled." )
				return
			end

			self:NotifyTranslatedCommandError( Client, "ERROR_NOT_HIVE_BASED" )

			return
		end

		local TeamStats = self:GetTeamStats()
		local Message = {}

		Message[ 1 ] = "Team stats:"

		for i = 1, 2 do
			Message[ #Message + 1 ] = "========="
			Message[ #Message + 1 ] = Shine:GetTeamName( i, true )
			Message[ #Message + 1 ] = "========="

			local Stats = TeamStats[ i ]
			local Skills = Stats.Skills
			for j = 1, #Skills do
				Message[ #Message + 1 ] = tostring( Skills[ j ] )
			end

			Message[ #Message + 1 ] = StringFormat( "Average: %.1f. Standard Deviation: %.1f",
				Stats.Average, Stats.StandardDeviation )
		end

		if not Client then
			Notify( TableConcat( Message, "\n" ) )
		else
			for i = 1, #Message do
				ServerAdminPrint( Client, Message[ i ] )
			end
		end
	end
	local StatsCommand = self:BindCommand( "sh_teamstats", nil, ViewTeamStats, true )
	StatsCommand:Help( "View Hive skill based team statistics." )
end
