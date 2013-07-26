--[[
	Shine voting radial menu.
]]

Shine = Shine or {}

local NWMessage = {
	Options = "string (255)",
	Duration = "integer (0 to 1800)",
	NextMap = "integer (0 to 1)",
	TimeLeft = "integer (0 to 32768)"
}

Shared.RegisterNetworkMessage( "Shine_VoteMenu", NWMessage )

Shared.RegisterNetworkMessage( "Shine_OpenedVoteMenu", {} )

Shared.RegisterNetworkMessage( "Shine_EndVote", { Bleh = "integer (0 to 1)" } )

local PluginMessage = {
	Random = "boolean",
	RTV = "boolean",
	Surrender = "boolean",
	Unstuck = "boolean",
	MOTD = "boolean"
}

Shared.RegisterNetworkMessage( "Shine_PluginData", PluginMessage )

local RequestAddonList = {
	Bleh = "integer (0 to 1)"
}

Shared.RegisterNetworkMessage( "Shine_RequestPluginData", RequestAddonList )

local RequestVoteList = {
	Cake = "integer (0 to 1)"
}

Shared.RegisterNetworkMessage( "Shine_RequestVoteOptions", RequestVoteList )

if Server then
	Server.HookNetworkMessage( "Shine_RequestVoteOptions", function( Client, Message )
		local MapVote = Shine.Plugins.mapvote

		if MapVote and MapVote.Enabled then
			MapVote:SendVoteData( Client )
		end
	end )
end
