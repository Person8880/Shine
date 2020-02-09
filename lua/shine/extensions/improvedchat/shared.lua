--[[
	Improved chat plugin.

	Provides a more feature-rich chat with arbitrary number of colours, support for embedding
	images and more.
]]

local ChatAPI = require "shine/core/shared/chat/chat_api"
local DefaultProvider = require "shine/core/shared/chat/default_provider"
local StringFormat = string.format

local Plugin = Shine.Plugin( ... )

-- Any more than 6 seems to cause the server to crash instantly when sending...
Plugin.MAX_CHUNKS_PER_MESSAGE = 6

function Plugin:SetupDataTable()
	self:AddDTVar( "boolean", "DisplayChatTagsInTeamChat", false )

	self:AddNetworkMessage( "CreateChatTagDefinition", {
		Image = "string (255)",
		Text = "string (255)",
		Colour = "integer",
		Index = "integer"
	}, "Client" )
	self:AddNetworkMessage( "DeleteChatTagDefinition", {
		Index = "integer"
	}, "Client" )

	self:AddNetworkMessage( "AssignChatTag", {
		Index = "integer",
		SteamID = "integer"
	}, "Client" )

	self:AddNetworkMessage( "ResetChatTag", {
		SteamID = "integer"
	}, "Client" )

	-- Unfortunately, network messages don't support repeated values, so this awkward generation of messages
	-- is required to try to avoid needing to send loads of individual messages in one go.
	for i = 1, self.MAX_CHUNKS_PER_MESSAGE do
		local Message = {
			SourceType = StringFormat( "integer (1 to %d)", #ChatAPI.SourceType ),
			SourceID = "string (64)",
			SuppressSound = "boolean",
			MessageID = "integer",
			ChunkIndex = "integer",
			NumChunks = "integer"
		}
		for j = 1, i do
			-- If colour is negative, the value is skipped. Otherwise it's turned into 3 bytes of colour.
			Message[ "Colour"..j ] = "integer"
			-- Value is encoded with a prefix to identify its type.
			-- For example, "t:" for text, "i:" for image.
			-- If network message fields could be optional, this could be done better...
			Message[ "Value"..j ] = "string (255)"
		end
		self:AddNetworkMessage( "RichTextChatMessage"..i, Message, "Client" )
	end
end

function Plugin:SupportsRichText()
	return true
end

function Plugin:AddMessage( MessageColour, Message, Targets )
	return DefaultProvider:AddMessage( MessageColour, Message, Targets )
end

function Plugin:AddDualColourMessage( PrefixColour, Prefix, MessageColour, Message, Targets )
	return DefaultProvider:AddDualColourMessage( PrefixColour, Prefix, MessageColour, Message, Targets )
end

return Plugin
