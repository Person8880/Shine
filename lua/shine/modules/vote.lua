--[[
	Provides a way to control who is considered in votes.
]]

local Plugin = ... or _G.Plugin

local GetHumanPlayerCount = Shine.GetHumanPlayerCount
local Stream = Shine.Stream

local Module = {}

if not Plugin.HandlesVoteConfig then
	Module.DefaultConfig = {
		VoteSettings = {
			ConsiderAFKPlayersInVotes = true,
			AFKTimeInSeconds = 60
		}
	}
end

function Module:SetupVoteTimeout( Vote, TimeoutInSeconds, TimerName )
	Vote:SetTimeoutDuration( TimeoutInSeconds )
	self:CreateTimer( TimerName or "VoteTimeout", 1, -1, function()
		Vote:Think()
	end )
end

local function IsNotBot( Client )
	return Client.GetIsVirtual and not Client:GetIsVirtual()
end

--[[
	Returns the number of humans players, minus any that are AFK for the configured time.
]]
function Module:GetPlayerCountForVote()
	if self.Config.VoteSettings.ConsiderAFKPlayersInVotes then
		return GetHumanPlayerCount()
	end

	return self:GetNumNonAFKHumans( self.Config.VoteSettings.AFKTimeInSeconds )
end

function Module:GetNumNonAFKHumans( AFKTime )
	local AFKEnabled, AFKKick = Shine:IsExtensionEnabled( "afkkick" )
	if not AFKEnabled then
		return GetHumanPlayerCount()
	end

	local Clients = Shine.GameIDs:GetKeys()
	return Stream.Of( Clients ):Filter( IsNotBot ):Filter( function( Client )
		return not AFKKick:IsAFKFor( Client, AFKTime )
	end ):GetCount()
end

--[[
	Returns whether the given client is valid to be counted in a vote.
]]
function Module:IsValidVoter( Client )
	if Client:GetIsVirtual() then return false end

	if self.Config.VoteSettings.ConsiderAFKPlayersInVotes then
		return true
	end

	local AFKEnabled, AFKKick = Shine:IsExtensionEnabled( "afkkick" )
	if not AFKEnabled then
		return true
	end

	return not AFKKick:IsAFKFor( Client, self.Config.VoteSettings.AFKTimeInSeconds )
end

Plugin:AddModule( Module )
