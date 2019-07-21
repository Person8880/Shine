--[[
	Improved chat server side.
]]

local ChatAPI = require "shine/core/shared/chat/chat_api"
local Map = Shine.Map

local BitBAnd = bit.band
local BitLShift = bit.lshift
local IsType = Shine.IsType
local StringFind = string.find
local StringFormat = string.format
local TableConcat = table.concat
local TableEmpty = table.Empty
local tonumber = tonumber

local Plugin = ...
Plugin.PrintName = "Improved Chat"
Plugin.HasConfig = true
Plugin.ConfigName = "ImprovedChat.json"
Plugin.CheckConfig = true
Plugin.CheckConfigTypes = true

Plugin.Version = "1.0"

Plugin.DefaultState = true

local DEFAULT_GROUP_KEY = setmetatable( {}, {
	__tostring = function() return "the default group" end
} )
local MAX_MESSAGE_ID = 2 ^ 31 - 1

function Plugin:Initialise()
	self:BroadcastModuleEvent( "Initialise" )

	self.ChatTagDefinitions = Map()
	self.ClientsWithTags = Map()

	-- Wait a tick to allow the enabled state to be sent to clients.
	self:SimpleTimer( 0, function()
		self:OnUserReload()
	end )

	self.ChatTagIndex = 0
	self.NextMessageID = 0

	ChatAPI:SetProvider( self )

	return true
end

local function ToInt( R, G, B )
	return BitLShift( BitBAnd( tonumber( R ) or 255, 0xFF ), 16 )
		+ BitLShift( BitBAnd( tonumber( G ) or 255, 0xFF ), 8 )
		+ BitBAnd( tonumber( B ) or 255, 0xFF )
end

local function EncodeContents( Contents )
	local Messages = {}
	local EncodedValues = { Count = 0 }
	local CurrentText = {}
	local Index = 0
	local LastColour

	local function AddToMessage( Colour, Value )
		Index = Index + 1

		if Index > Plugin.MAX_CHUNKS_PER_MESSAGE then
			Messages[ #Messages + 1 ] = EncodedValues
			EncodedValues = { Count = 0 }
			Index = 1
		end

		EncodedValues[ "Colour"..Index ] = Colour and ToInt(
			Colour.r * 255,
			Colour.g * 255,
			Colour.b * 255
		) or -1
		EncodedValues[ "Value"..Index ] = Value
		EncodedValues.Count = Index

		LastColour = nil
		TableEmpty( CurrentText )
	end

	local function AddPendingText()
		if #CurrentText > 0 then
			AddToMessage( LastColour, StringFormat( "t:%s", TableConcat( CurrentText ) ) )
		end
	end

	for i = 1, #Contents do
		local Value = Contents[ i ]
		local Type = type( Value )

		if Type == "table" then
			local TypeName = Value.Type
			if TypeName == "Colour" then
				Type = "cdata"
				Value = Value.Value
			elseif TypeName == "Text" then
				Type = "string"
				Value = Value.Value
			elseif TypeName == "Image" then
				Type = nil
				AddPendingText()
				-- For now, this assumes the image should match the font size and be a square.
				AddToMessage( nil, StringFormat( "i:%s", Value.Texture ) )
			end
		end

		if Type == "cdata" then
			AddPendingText()
			LastColour = Value
		elseif Type == "string" then
			CurrentText[ #CurrentText + 1 ] = Value
		end
	end

	AddPendingText()

	if EncodedValues.Count > 0 then
		Messages[ #Messages + 1 ] = EncodedValues
	end

	return Messages
end

local DEFAULT_SOURCE = {
	Type = ChatAPI.SourceTypeName.SYSTEM,
	ID = ""
}

function Plugin:AddRichTextMessage( MessageData )
	local Messages = EncodeContents( MessageData.Message )
	local NumChunks = #Messages
	local MessageID = self.NextMessageID
	local Source = MessageData.Source or DEFAULT_SOURCE

	for i = 1, NumChunks do
		local Chunk = Messages[ i ]
		local NumParts = Chunk.Count
		Chunk.Count = nil

		if i == 1 then
			Chunk.SourceType = ChatAPI.SourceType[ Source.Type ] or ChatAPI.SourceType.SYSTEM
			Chunk.SourceID = Source.ID or ""
			Chunk.SuppressSound = not not MessageData.SuppressSound
		else
			-- Avoid repeating data to avoid some overhead.
			Chunk.SourceType = 1
			Chunk.SourceID = ""
			Chunk.SuppressSound = false
		end

		Chunk.MessageID = MessageID
		Chunk.ChunkIndex = i
		Chunk.NumChunks = NumChunks

		self:SendNetworkMessage( MessageData.Targets, "RichTextChatMessage"..NumParts, Chunk, true )
	end

	self.NextMessageID = ( MessageID + 1 ) % MAX_MESSAGE_ID
end

local function RevokeChatTag( self, Client )
	local _, Assignment = self.ClientsWithTags:Remove( Client )
	if not Assignment then
		if self.Logger:IsDebugEnabled() then
			self.Logger:Debug( "No chat tag to revoke for %s.", Shine.GetClientInfo( Client ) )
		end
		return
	end

	if self.Logger:IsDebugEnabled() then
		self.Logger:Debug( "Revoked chat tag from %s.", Shine.GetClientInfo( Client ) )
	end

	local Definition = self.ChatTagDefinitions:Get( Assignment.Key )
	if Definition then
		-- Make sure there's still at least one client using this definition, if not, then it should
		-- be forgotten so it's no longer networked to new clients.
		Definition.ReferenceCount = Definition.ReferenceCount - 1
		if Definition.ReferenceCount <= 0 then
			self.ChatTagDefinitions:Remove( Assignment.Key )
		end

		self.Logger:Debug( "Definition %s now has reference count %s.", Definition.Index, Definition.ReferenceCount )
	end

	self:SendNetworkMessage( nil, "ResetChatTag", {
		SteamID = Client:GetUserId()
	}, true )
end

function Plugin:SetChatTag( Client, ChatTagConfig, Key )
	local SteamID = Client:GetUserId()
	if not ChatTagConfig then
		RevokeChatTag( self, Client )
		return
	end

	local ChatTag = self.ChatTagDefinitions:Get( Key )
	if ChatTag then
		ChatTag.ReferenceCount = ChatTag.ReferenceCount + 1

		if self.Logger:IsDebugEnabled() then
			self.Logger:Debug(
				"Already seen chat tag with key %s, incrementing reference count to %s and assigning to %s.",
				Key, ChatTag.ReferenceCount, Shine.GetClientInfo( Client )
			)
		end

		-- Already seen this chat tag (so clients must have received it already), just assign it.
		local Assignment = {
			SteamID = SteamID,
			Index = ChatTag.Index,
			Key = Key
		}
		self.ClientsWithTags:Add( Client, Assignment )
		self:SendNetworkMessage( nil, "AssignChatTag", Assignment, true )

		return
	end

	-- Never seen this chat tag before, need to create it.
	local ChatTag = {}

	if IsType( ChatTagConfig.Text, "string" ) then
		ChatTag.Text = ChatTagConfig.Text

		if IsType( ChatTagConfig.Colour, "table" ) then
			ChatTag.Colour = ToInt( ChatTagConfig.Colour )
		elseif IsType( ChatTagConfig.Colour, "number" ) then
			ChatTag.Colour = ChatTagConfig.Colour
		else
			ChatTag.Colour = 0xFFFFFF
		end
	end

	if IsType( ChatTagConfig.Image, "string" ) and StringFind( ChatTagConfig.Image, "[^%s]" ) then
		ChatTag.Image = ChatTagConfig.Image
	end

	if not ChatTag.Text and not ChatTag.Image then
		self.Logger:Warn( "Chat tag assigned to %s has no text or image set and will be ignored.", Key )
		self:SetChatTag( Client, nil )
		return
	end

	ChatTag.Text = ChatTag.Text or ""
	ChatTag.Image = ChatTag.Image or ""
	ChatTag.Colour = ChatTag.Colour or 0xFFFFFF
	ChatTag.Index = self.ChatTagIndex
	ChatTag.ReferenceCount = 1

	if self.Logger:IsDebugEnabled() then
		self.Logger:Debug(
			"Chat tag for key %s created with index %s (due to %s)", Key, ChatTag.Index, Shine.GetClientInfo( Client )
		)
	end

	self.ChatTagIndex = self.ChatTagIndex + 1

	-- Remember the definition and broadcast it.
	self.ChatTagDefinitions:Add( Key, ChatTag )
	self:SendNetworkMessage( nil, "ChatTag", ChatTag, true )

	-- Remember the tag for this player and tell everyone about it.
	local Assignment = {
		SteamID = SteamID,
		Index = ChatTag.Index,
		Key = Key
	}
	self.ClientsWithTags:Add( Client, Assignment )
	self:SendNetworkMessage( nil, "AssignChatTag", Assignment, true )
end

local function SetTagFromGroup( Group, Name, Client )
	local ChatTagConfig = Group.ChatTag
	if IsType( ChatTagConfig, "table" ) then
		Plugin:SetChatTag( Client, ChatTagConfig, Name or DEFAULT_GROUP_KEY )
		return true
	end
end

function Plugin:AssignChatTag( Client )
	local SteamID = Client:GetUserId()
	local UserData = Shine:GetUserData( Client )
	if UserData then
		local ChatTagConfig = UserData.ChatTag
		if IsType( ChatTagConfig, "table" ) then
			self:SetChatTag( Client, ChatTagConfig, SteamID )
		-- For each group, find the first with a chat tag configured and use it.
		elseif not Shine:IterateGroupTree( UserData.Group, SetTagFromGroup, Client ) then
			self:SetChatTag( Client, nil )
		end
	else
		self:SetChatTag( Client, nil )
	end
end

function Plugin:ClientConfirmConnect( Client )
	-- First send the client all known chat tag definitions (this ensures we send a chat tag only once
	-- per group).
	for Key, Definition in self.ChatTagDefinitions:Iterate() do
		self:SendNetworkMessage( Client, "ChatTag", Definition, true )
	end

	-- Now assign their chat tag, if they have one.
	self:AssignChatTag( Client )

	-- Finally, notify the client of every player that has a chat tag that's currently connected.
	for ClientWithTag, ChatTag in self.ClientsWithTags:Iterate() do
		if ClientWithTag ~= Client then
			self:SendNetworkMessage( Client, "AssignChatTag", ChatTag, true )
		end
	end
end

function Plugin:ClientDisconnect( Client )
	RevokeChatTag( self, Client )
end

function Plugin:OnUserReload()
	-- Re-assign chat tags for all connected players when the user data is reloaded.
	for Client in Shine.GameIDs:Iterate() do
		self:AssignChatTag( Client )
	end
end

function Plugin:Cleanup()
	ChatAPI:ResetProvider( self )

	self.ChatTagDefinitions = nil
	self.ClientsWithTags = nil

	return self.BaseClass.Cleanup( self )
end

Shine.LoadPluginModule( "logger.lua", Plugin )
