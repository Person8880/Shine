--[[
	Vote object tests.
]]

local UnitTest = Shine.UnitTest

UnitTest:Test( "Adding votes", function( Assert )
	local Success = false
	local Vote = Shine:CreateVote(
		function() return 2 end,
		function() Success = true end
	)

	Assert.True( "Expected new vote to be added successfully", Vote:AddVote( 1 ) )

	Assert.True( "Client 1 should have voted", Vote:GetHasClientVoted( 1 ) )
	Assert.Equals( "Expected one vote", 1, Vote:GetVotes() )
	Assert.Equals( "Expected one more vote required to pass", 1, Vote:GetVotesNeeded() )
	Assert.False( "Vote should not have passed yet", Success )

	Assert.False( "Expected vote from same client to be rejected", Vote:AddVote( 1 ) )
	Assert.False( "Vote should not have passed yet", Success )

	Assert.True( "Expected second vote to be added successfully", Vote:AddVote( 2 ) )
	Assert.True( "Expected vote to pass", Success )
	Assert.True( "Expected vote to be marked as successful due to the last vote",
		Vote:HasSucceededOnLastVote() )
	Assert.Equals( "Expected vote count to be reset", 0, Vote:GetVotes() )
	Assert.Equals( "Expected two more vote required to pass", 2, Vote:GetVotesNeeded() )
end )

UnitTest:Test( "Removing votes", function( Assert )
	local Success = false
	local Vote = Shine:CreateVote(
		function() return 2 end,
		function() Success = true end
	)

	Assert.True( "Expected new vote to be added successfully", Vote:AddVote( 1 ) )

	Assert.True( "Client 1 should have voted", Vote:GetHasClientVoted( 1 ) )
	Assert.Equals( "Expected one vote", 1, Vote:GetVotes() )
	Assert.Equals( "Expected one more vote required to pass", 1, Vote:GetVotesNeeded() )
	Assert.False( "Vote should not have passed yet", Success )

	Vote:RemoveVote( 1 )

	Assert.False( "Client 1 should not have voted", Vote:GetHasClientVoted( 1 ) )
	Assert.Equals( "Expected vote count to be reset", 0, Vote:GetVotes() )
	Assert.Equals( "Expected two more vote required to pass", 2, Vote:GetVotesNeeded() )
	Assert.False( "Vote should not have passed yet", Success )

	-- Removing the vote again should do nothing.
	Vote:RemoveVote( 1 )

	Assert.Equals( "Expected vote count to be reset", 0, Vote:GetVotes() )
	Assert.Equals( "Expected two more vote required to pass", 2, Vote:GetVotesNeeded() )
	Assert.False( "Vote should not have passed yet", Success )
end )

UnitTest:Test( "Resetting", function( Assert )
	local Success = false
	local Vote = Shine:CreateVote(
		function() return 2 end,
		function() Success = true end
	)

	Assert.True( "Expected new vote to be added successfully", Vote:AddVote( 1 ) )

	Assert.True( "Client 1 should have voted", Vote:GetHasClientVoted( 1 ) )
	Assert.Equals( "Expected one vote", 1, Vote:GetVotes() )
	Assert.Equals( "Expected one more vote required to pass", 1, Vote:GetVotesNeeded() )
	Assert.False( "Vote should not have passed yet", Success )

	Vote:Reset()

	Assert.False( "Client 1 should not have voted", Vote:GetHasClientVoted( 1 ) )
	Assert.Equals( "Expected vote count to be reset", 0, Vote:GetVotes() )
	Assert.Equals( "Expected two more vote required to pass", 2, Vote:GetVotesNeeded() )
	Assert.False( "Vote should not have passed yet", Success )
end )

UnitTest:Test( "Timeout duration", function( Assert )
	local Success = false
	local Vote = Shine:CreateVote(
		function() return 2 end,
		function() Success = true end
	)

	Vote:SetTimeoutDuration( 5 )
	Vote:AddVote( 1 )
	Vote:Think()

	Assert.Equals( "Expected one vote", 1, Vote:GetVotes() )
	Assert.False( "Vote should not have passed yet", Success )

	Vote.LastVoted = Shared.GetTime() - 6

	Vote:Think()
	Assert.Equals( "Expected vote count to be reset", 0, Vote:GetVotes() )
end )
