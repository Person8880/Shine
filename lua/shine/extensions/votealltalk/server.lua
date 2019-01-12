--[[
	All talk voting.
]]

local Plugin = ...

Plugin.DependsOnPlugins = {
	"basecommands"
}

Plugin.Version = "1.0"

Plugin.HasConfig = true
Plugin.ConfigName = "VoteAllTalk.json"
Plugin.CheckConfig = true
Plugin.CheckConfigTypes = true

Plugin.VoteCommand = {
	ConCommand = "sh_votealltalk",
	ChatCommand = "votealltalk",
	Help = "Votes to enable or disable all talk."
}

local ALLTALK_TYPE = "AllTalk"
function Plugin:Initialise()
	local Enabled, BaseCommands = Shine:IsExtensionEnabled( "basecommands" )
	assert( Enabled and BaseCommands, "basecommands plugin was not enabled!" )

	-- Extract the current all-talk state.
	self.dt.IsEnabled = BaseCommands:IsAllTalkEnabled( ALLTALK_TYPE )

	return self.BaseClass.Initialise( self )
end

function Plugin:GetVoteNotificationParams()
	return {
		VoteType = self.dt.IsEnabled and "DISABLE" or "ENABLE"
	}
end

function Plugin:OnVotePassed()
	local Enabled, BaseCommands = Shine:IsExtensionEnabled( "basecommands" )
	if not Enabled then
		return
	end

	local NewState = not BaseCommands:IsAllTalkEnabled( ALLTALK_TYPE )

	BaseCommands:SetAllTalkEnabled( ALLTALK_TYPE, NewState )
	BaseCommands:NotifyAllTalkState( ALLTALK_TYPE, NewState )
end

function Plugin:OnAllTalkStateChange( Type, Enabled )
	if Type ~= ALLTALK_TYPE then return end

	self.dt.IsEnabled = Enabled
	self.Vote:Reset()
end
