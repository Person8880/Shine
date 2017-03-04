--[[
	Provides a way to control who is considered in votes.
]]

local GetHumanPlayerCount = Shine.GetHumanPlayerCount
local Stream = Shine.Stream

local Module = {}

Module.DefaultConfig = {
	VoteSettings = {
		ConsiderAFKPlayersInVotes = true,
		AFKTimeInSeconds = 60
	}
}

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

	local AFKEnabled, AFKKick = Shine:IsExtensionEnabled( "afkkick" )
	if not AFKEnabled then
		return GetHumanPlayerCount()
	end

	local Clients = Shine.GameIDs:GetKeys()
	local AFKTime = self.Config.VoteSettings.AFKTimeInSeconds
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
