--[[
	Shine generic voting object.

	Set it up with a function that returns the needed votes, a function to run on vote success
	and optionally, a function to check for timing out.
]]

if Client then return end

local Shine = Shine

local Max = math.max
local setmetatable = setmetatable
local SharedTime = Shared.GetTime
local TableEmpty = table.Empty

local VoteMeta = {}
VoteMeta.__index = VoteMeta

function VoteMeta:Initialise()
	self.Voted = {}
	self.Votes = 0
end

function VoteMeta:SetVotesNeeded( Func )
	self.VotesNeeded = Func
end

function VoteMeta:SetOnSuccess( Func )
	self.OnSuccess = Func
end

function VoteMeta:SetTimeout( Func )
	self.Timeout = Func
end

function VoteMeta:Think()
	if self.Timeout then
		self:Timeout()
	end
end

function VoteMeta:Reset()
	TableEmpty( self.Voted )
	self.Votes = 0
	self.LastVoted = nil

	if self.OnReset then
		self:OnReset()
	end
end

function VoteMeta:RemoveVote( Client )
	if self.Voted[ Client ] then
		self.Voted[ Client ] = nil
		self.Votes = Max( self.Votes - 1, 0 )
	end
end

function VoteMeta:ClientDisconnect( Client )
	self:RemoveVote( Client )

	-- Wait a tick, as some vote results may attempt to act on the disconnecting
	-- player.
	Shine.Timer.Simple( 0, function()
		-- The total required votes may have decreased without
		-- removing any votes, thus the vote could pass now.
		self:CheckForSuccess()
	end )
end

function VoteMeta:AddVote( Client )
	if self.Voted[ Client ] then return false, "already voted" end

	self.Voted[ Client ] = true
	self.Votes = self.Votes + 1

	self.LastVoted = SharedTime()

	self:CheckForSuccess()

	return true
end

function VoteMeta:CheckForSuccess()
	if self.Votes >= self.VotesNeeded() then
		self.LastSuccessTime = SharedTime()
		self.OnSuccess()
		self:Reset()
	end
end

function VoteMeta:HasSucceededOnLastVote()
	return self.LastSuccessTime == SharedTime()
end

function VoteMeta:GetHasClientVoted( Client )
	return self.Voted[ Client ] ~= nil
end

function VoteMeta:GetVotesNeeded()
	return Max( self.VotesNeeded() - self.Votes, 0 )
end

function VoteMeta:GetVotes()
	return self.Votes
end

function Shine:CreateVote( VotesNeeded, OnSuccess, Timeout )
	local Vote = setmetatable( {}, VoteMeta )
	Vote:SetVotesNeeded( VotesNeeded )
	Vote:SetOnSuccess( OnSuccess )

	if Timeout then
		Vote:SetTimeout( Timeout )
	end

	Vote:Initialise()

	return Vote
end
