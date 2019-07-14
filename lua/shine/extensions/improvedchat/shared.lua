--[[
	Improved chat plugin.

	Provides a more feature-rich chat with arbitrary number of colours, support for embedding
	images and more.
]]

local Plugin = Shine.Plugin( ... )

function Plugin:SetupDataTable()
	-- TODO: Network messages to send multi-coloured chat messages.
	self:AddNetworkMessage( "ChatTag", {
		Image = "string (255)",
		Text = "string (255)",
		Colour = "integer",
		Index = "integer"
	}, "Client" )

	self:AddNetworkMessage( "AssignChatTag", {
		Index = "integer",
		SteamID = "integer"
	}, "Client" )

	self:AddNetworkMessage( "ResetChatTag", {
		SteamID = "integer"
	}, "Client" )
end

return Plugin
