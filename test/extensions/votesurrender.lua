--[[
	Vote surrender plugin unit tests.
]]

local UnitTest = Shine.UnitTest

local VoteSurrender = UnitTest:LoadExtension( "votesurrender" )
if not VoteSurrender then return end

local OldConfig = VoteSurrender.Config
VoteSurrender.Config = table.Copy( OldConfig )

UnitTest:Test( "GetVotesNeeded in early game uses FractionOfPlayersNeededInEarlyGame", function( Assert )
	VoteSurrender.NextVote = Shared.GetTime() + 1
	VoteSurrender.Config.FractionOfPlayersNeededInEarlyGame = 0.9
	VoteSurrender.GetTeamPlayerCount = function() return 10 end

	-- Next vote is in the future, so should use FractionOfPlayersNeededInEarlyGame
	Assert:Equals( 9, VoteSurrender:GetVotesNeeded( 1 ) )
end )

UnitTest:Test( "GetVotesNeeded in later game uses FractionOfPlayersNeeded", function( Assert )
	VoteSurrender.NextVote = Shared.GetTime() - 1
	VoteSurrender.Config.FractionOfPlayersNeeded = 0.5
	VoteSurrender.GetTeamPlayerCount = function() return 10 end

	-- Next vote is in the past, so should use FractionOfPlayersNeeded.
	Assert:Equals( 5, VoteSurrender:GetVotesNeeded( 1 ) )
end )

UnitTest:Test( "HasTooManyTechPoints denies with too many tech points", function( Assert )
	VoteSurrender.Config.AllowVoteWithMultipleBases = true

	local Gamerules = {
		GetTeam = function( self, Team )
			return {
				GetNumCapturedTechPoints = function() return Team == 1 and 2 or 1 end
			}
		end
	}

	-- Both permitted, config allows multiple bases.
	Assert:False( VoteSurrender:HasTooManyTechPoints( Gamerules, 1 ) )
	Assert:False( VoteSurrender:HasTooManyTechPoints( Gamerules, 2 ) )

	VoteSurrender.Config.AllowVoteWithMultipleBases = false
	-- Team 1 has 2 tech points so should be denied, team 2 has only 1 so should be allowed.
	Assert:True( VoteSurrender:HasTooManyTechPoints( Gamerules, 1 ) )
	Assert:False( VoteSurrender:HasTooManyTechPoints( Gamerules, 2 ) )
end )

local OldGetEntitiesForTeam = GetEntitiesForTeam
function GetEntitiesForTeam( Type, Team )
	return { { GetHealthFraction = function() return Team == 1 and 0.5 or 1 end } }
end

UnitTest:Test( "HasCommandStructureAtTooLowHP denies when HP too low", function( Assert )
	VoteSurrender.Config.LastCommandStructureMinHealthFraction = 0.75

	-- Team 1 has 1 command structure at too low health
	Assert:True( VoteSurrender:HasCommandStructureAtTooLowHP( 1 ) )
	-- Team 2 has 1 command stucture at higher health.
	Assert:False( VoteSurrender:HasCommandStructureAtTooLowHP( 2 ) )
end )

GetEntitiesForTeam = OldGetEntitiesForTeam

VoteSurrender.Config = OldConfig
