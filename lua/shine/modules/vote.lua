--[[
	Provides a way to control who is considered in votes.
]]

local Plugin = ... or _G.Plugin

local GetHumanPlayerCount = Shine.GetHumanPlayerCount
local GetNumSpectators = Server.GetNumSpectators
local Stream = Shine.Stream

local Module = {}

if not Plugin.HandlesVoteConfig then
	Module.DefaultConfig = {
		VoteSettings = {
			ConsiderAFKPlayersInVotes = true,
			ConsiderSpectatorsInVotes = true,
			AFKTimeInSeconds = 60
		}
	}

	local Validator = Shine.Validator()

	Validator:CheckTypesAgainstDefault( "VoteSettings", Module.DefaultConfig.VoteSettings )
	Validator:AddFieldRule( "VoteSettings.AFKTimeInSeconds", Validator.Min( 0 ) )

	Module.ConfigValidator = Validator
end

function Module:SetupVoteTimeout( Vote, TimeoutInSeconds, TimerName )
	Vote:SetTimeoutDuration( TimeoutInSeconds )
	self:CreateTimer( TimerName or "VoteTimeout", 1, -1, function()
		Vote:Think()
	end )
end

local function GetPlayerCount( SkipSpectators )
	local PlayerCount = GetHumanPlayerCount()
	if SkipSpectators then
		PlayerCount = PlayerCount - GetNumSpectators()
	end
	return PlayerCount
end

--[[
	Returns the number of humans players, minus any that are AFK for the configured time.
]]
function Module:GetPlayerCountForVote()
	if self.Config.VoteSettings.ConsiderAFKPlayersInVotes then
		return GetPlayerCount( not self.Config.VoteSettings.ConsiderSpectatorsInVotes )
	end

	return self:GetNumNonAFKHumans(
		self.Config.VoteSettings.AFKTimeInSeconds,
		not self.Config.VoteSettings.ConsiderSpectatorsInVotes
	)
end

function Module:GetNumNonAFKHumans( AFKTime, SkipSpectators )
	local AFKEnabled, AFKKick = Shine:IsExtensionEnabled( "afkkick" )
	if not AFKEnabled then
		return GetPlayerCount( SkipSpectators )
	end

	local Clients = Shine.GameIDs:GetKeys()
	return Stream.Of( Clients ):Filter( function( Client )
		return ( not SkipSpectators or not Client:GetIsSpectator() )
			and not Client:GetIsVirtual()
			and not AFKKick:IsAFKFor( Client, AFKTime )
	end ):GetCount()
end

function Module:CanClientVote( Client )
	if Client:GetIsVirtual() then
		return false, "ERROR_BOT_CANNOT_VOTE"
	end

	if Client:GetIsSpectator() and not self.Config.VoteSettings.ConsiderSpectatorsInVotes then
		return false, "ERROR_CANNOT_VOTE_IN_SPECTATE"
	end

	return true
end

--[[
	Returns whether the given client is valid to be counted in a vote.
]]
function Module:IsValidVoter( Client )
	if not self:CanClientVote( Client ) then return false end

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
