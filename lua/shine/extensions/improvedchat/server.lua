--[[
	Improved chat server side.
]]

local Map = Shine.Map

local BitBAnd = bit.band
local BitLShift = bit.lshift
local IsType = Shine.IsType
local StringFind = string.find
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

function Plugin:Initialise()
	self:BroadcastModuleEvent( "Initialise" )

	self.ChatTagDefinitions = Map()
	self.ClientsWithTags = Map()

	-- Wait a tick to allow the enabled state to be sent to clients.
	self:SimpleTimer( 0, function()
		self:OnUserReload()
	end )

	self.ChatTagIndex = 0

	return true
end

local function ToInt( Colour )
	return BitLShift( BitBAnd( tonumber( Colour[ 1 ] ) or 255, 0xFF ), 16 )
		+ BitLShift( BitBAnd( tonumber( Colour[ 2 ] ) or 255, 0xFF ), 8 )
		+ BitBAnd( tonumber( Colour[ 3 ] ) or 255, 0xFF )
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
	self.ChatTagDefinitions = nil
	self.ClientsWithTags = nil

	return self.BaseClass.Cleanup( self )
end

Shine.LoadPluginModule( "logger.lua", Plugin )
