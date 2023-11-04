--[[
	Improved chat plugin.

	Provides a more feature-rich chat with arbitrary number of colours, support for embedding
	images and more.
]]

local ChatAPI = require "shine/core/shared/chat/chat_api"
local DefaultProvider = require "shine/core/shared/chat/default_provider"

local BitBAnd = bit.band
local BitBOr = bit.bor
local BitLShift = bit.lshift
local BitRShift = bit.rshift
local Min = math.min
local StringFormat = string.format

local Plugin = Shine.Plugin( ... )

-- Any more than 6 seems to cause the server to crash instantly when sending...
Plugin.MAX_CHUNKS_PER_MESSAGE = 6

-- 16 * 32 bit integers = 512 values per message (taking up 64 bytes).
Plugin.MAX_BITSET_VALUES_PER_MESSAGE = 16

local IntegerKeys = {}
for i = 1, Plugin.MAX_BITSET_VALUES_PER_MESSAGE do
	IntegerKeys[ i ] = "Int"..i
end

function Plugin:EncodeBitsetToMessage( ChunkIndex, NumChunks, BitSet )
	local StartIndex = ( ChunkIndex - 1 ) * self.MAX_BITSET_VALUES_PER_MESSAGE
	local EndIndex = StartIndex + self.MAX_BITSET_VALUES_PER_MESSAGE - 1

	local Message = {
		-- Pack the chunk index and number of chunks into a single integer, top half is the chunk index, bottom half is
		-- the number of chunks.
		ChunkInfo = BitBOr( BitLShift( BitBAnd( ChunkIndex, 0xFFFF ), 16 ), BitBAnd( NumChunks, 0xFFFF ) )
	}

	local Count = 0
	for i = StartIndex, EndIndex do
		Count = Count + 1
		-- Have to populate the entire message here, if the bitset doesn't have a value it'll return 0 from its array.
		Message[ IntegerKeys[ Count ] ] = BitSet.Values[ i ]
	end

	return Message
end

function Plugin.DecodeMessageChunkData( Message )
	local ChunkIndex = BitRShift( Message.ChunkInfo, 16 )
	local NumChunks = BitBAnd( Message.ChunkInfo, 0xFFFF )
	return ChunkIndex, NumChunks
end

function Plugin:DecodeBitSetFromChunks( MessageChunks )
	local Values = {}
	local Count = 0
	for i = 1, #MessageChunks do
		local Chunk = MessageChunks[ i ]
		for j = 1, self.MAX_BITSET_VALUES_PER_MESSAGE do
			Count = Count + 1
			Values[ Count ] = Chunk[ IntegerKeys[ j ] ]
		end
	end

	-- Trim trailing empty values.
	for i = Count, 1, -1 do
		if Values[ i ] ~= 0 then break end
		Values[ i ] = nil
	end

	return Shine.BitSet.FromData( Values )
end

function Plugin:SetupDataTable()
	self:AddDTVar( "boolean", "DisplayChatTagsInTeamChat", false )
	self:AddDTVar( "boolean", "ParseEmojiInChat", true )

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

	local EmojiRestrictionsMessage = {
		ChunkInfo = "integer"
	}
	for i = 1, self.MAX_BITSET_VALUES_PER_MESSAGE do
		EmojiRestrictionsMessage[ IntegerKeys[ i ] ] = "integer"
	end
	self:AddNetworkMessage( "SetEmojiRestrictions", EmojiRestrictionsMessage, "Client" )
	self:AddNetworkMessage( "ResetEmojiRestrictions", {}, "Client" )

	-- Unfortunately, network messages don't support repeated values, so this awkward generation of messages
	-- is required to try to avoid needing to send loads of individual messages in one go.
	for i = 1, self.MAX_CHUNKS_PER_MESSAGE do
		local Message = {
			SourceType = StringFormat( "integer (1 to %d)", #ChatAPI.SourceType ),
			SourceID = "string (64)",
			SuppressSound = "boolean",
			MessageID = "integer",
			ChunkIndex = "integer",
			NumChunks = "integer",
			ParseEmoji = "boolean"
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
