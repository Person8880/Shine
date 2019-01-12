--[[
	Shine bans plugin.
]]

local Plugin = Shine.Plugin( ... )

Plugin.SortColumn = table.AsEnum( {
	"NAME", "BANNED_BY", "EXPIRY"
}, function( Index ) return Index end )

function Plugin:SetupDataTable()
	self:AddNetworkMessage( "BanData", {
		ID = "string (32)",
		Name = "string (32)",
		Duration = "integer",
		UnbanTime = "integer",
		BannedBy = "string (32)",
		BannerID = "integer",
		Reason = "string (128)",
		Issued = "integer"
	}, "Client" )
	self:AddNetworkMessage( "RequestBanPage", {
		Page = "integer",
		MaxResults = "integer",
		Filter = "string (128)",
		SortColumn = "integer (1 to 3)",
		SortAscending = "boolean"
	}, "Server" )
	self:AddNetworkMessage( "BanPage", {
		Page = "integer",
		NumPages = "integer",
		MaxResults = "integer",
		TotalNumResults = "integer"
	}, "Client" )

	self:AddTranslatedMessage( "PLAYER_BANNED", {
		TargetName = self:GetNameNetworkField(),
		Duration = "integer",
		Reason = "string (128)"
	} )

	local ErrorTypes = {
		ID = {
			ID = "string (32)"
		}
	}

	self:AddNetworkMessages( "AddTranslatedCommandError", {
		[ ErrorTypes.ID ] = {
			"PLAYER_REQUEST_IN_PROGRESS", "ERROR_NOT_BANNED"
		}
	} )
end

return Plugin
