--[[
	Shine generic voting object.

	Set it up with a function that returns the needed votes, a function to run on vote success
	and optionally, a function to check for timing out.
]]

if Client then return end

local Shine = Shine

local Max = math.max
local setmetatable = setmetatable
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
end

function VoteMeta:RemoveVote( Client )
	if self.Voted[ Client ] then
		self.Voted[ Client ] = nil
		self.Votes = Max( self.Votes - 1, 0 )
	end
end

function VoteMeta:ClientDisconnect( Client )
	return self:RemoveVote( Client )
end

function VoteMeta:AddVote( Client )
	if self.Voted[ Client ] then return false, "already voted" end

	self.Voted[ Client ] = true
	self.Votes = self.Votes + 1

	self.LastVoted = Shared.GetTime()

	if self.Votes >= self.VotesNeeded() then
		self.OnSuccess()
		self:Reset()
	end

	return true
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
