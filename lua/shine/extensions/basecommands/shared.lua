--[[
	Base commands shared.
]]

local Plugin = Shine.Plugin( ... )

Plugin.ToggleNotificationKeys = {
	"CHEATS_TOGGLED",
	"ALLTALK_TOGGLED",
	"ALLTALK_PREGAME_TOGGLED",
	"ALLTALK_LOCAL_TOGGLED"
}
Plugin.TargetNotificationKeys = {
	"PLAYER_EJECTED",
	"PLAYER_UNGAGGED",
	"PLAYER_GAGGED_PERMANENTLY"
}

function Plugin:SetupDataTable()
	self:AddDTVar( "integer (1 to 10)", "Gamestate", 1 )
	self:AddDTVar( "boolean", "AllTalk", false )
	self:AddDTVar( "boolean", "AllTalkPreGame", false )

	self:AddNetworkMessage( "RequestMapData", {}, "Server" )
	self:AddNetworkMessage( "MapData", { Name = "string (32)" }, "Client" )

	self:AddNetworkMessage( "RequestPluginData", {}, "Server" )
	self:AddNetworkMessage( "PluginData", { Name = "string (32)", Enabled = "boolean" }, "Client" )
	self:AddNetworkMessage( "PluginTabAuthed", {}, "Client" )

	local MessageTypes = {
		Empty = {},
		Enabled = {
			Enabled = "boolean"
		},
		Kick = {
			TargetName = self:GetNameNetworkField(),
			Reason = "string (64)"
		},
		FF = {
			Scale = "float (0 to 100 by 0.01)"
		},
		TeamChange = {
			TargetCount = "integer (0 to 127)",
			Team = "integer (0 to 3)"
		},
		RandomTeam = {
			TargetCount = "integer (0 to 127)"
		},
		TargetName = {
			TargetName = self:GetNameNetworkField()
		},
		MapName = {
			MapName = "string (64)"
		},
		Gagged = {
			TargetName = self:GetNameNetworkField(),
			Duration = "integer (0 to 1800)"
		},
		FloatRate = {
			Rate = "float (0 to 1000 by 0.01)"
		},
		IntegerRate = {
			Rate = "integer (0 to 1000)"
		}
	}

	self:AddNetworkMessages( "AddTranslatedMessage", {
		[ MessageTypes.Empty ] = {
			"RESET_GAME", "HIVE_TEAMS", "FORCE_START", "VOTE_STOPPED"
		},
		[ MessageTypes.Enabled ] = self.ToggleNotificationKeys,
		[ MessageTypes.Kick ] = {
			"ClientKicked"
		},
		[ MessageTypes.FF ] = {
			"FRIENDLY_FIRE_SCALE"
		},
		[ MessageTypes.TeamChange ] = {
			"ChangeTeam"
		},
		[ MessageTypes.RandomTeam ] = {
			"RANDOM_TEAM"
		},
		[ MessageTypes.TargetName ] = self.TargetNotificationKeys,
		[ MessageTypes.Gagged ] = {
			"PLAYER_GAGGED"
		}
	} )

	self:AddNetworkMessages( "AddTranslatedCommandError", {
		[ MessageTypes.TargetName ] = {
			"ERROR_NOT_COMMANDER", "ERROR_NOT_GAGGED"
		},
		[ MessageTypes.FloatRate ] = {
			"ERROR_INTERP_CONSTRAINT"
		},
		[ MessageTypes.IntegerRate ] = {
			"ERROR_TICKRATE_CONSTRAINT", "ERROR_SENDRATE_CONSTRAINT",
			"ERROR_SENDRATE_MOVE_CONSTRAINT", "ERROR_MOVERATE_CONSTRAINT",
			"ERROR_MOVERATE_SENDRATE_CONSTRAINT"
		},
		[ MessageTypes.MapName ] = {
			"UNKNOWN_MAP_NAME", "UNCLEAR_MAP_NAME"
		}
	} )

	self:AddNetworkMessage( "EnableLocalAllTalk", { Enabled = "boolean" }, "Server" )
end

return Plugin
