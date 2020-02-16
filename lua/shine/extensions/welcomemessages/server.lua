--[[
	Shine welcome message plugin.
]]

local ChatAPI = require "shine/core/shared/chat/chat_api"

local Shine = Shine

local GetOwner = Server.GetOwner
local IsType = Shine.IsType
local IsValid = debug.isvalid
local StringFormat = string.format
local TableEmpty = table.Empty
local tostring = tostring
local type = type

local Plugin = ...
Plugin.Version = "1.4"

Plugin.HasConfig = true
Plugin.ConfigName = "WelcomeMessages.json"
Plugin.MessageDisplayHistoryFile = "config://shine/temp/welcomemessages_history.json"

Plugin.DefaultConfig = {
	MessageDelay = 5,
	Users = {
		[ "90000001" ] = {
			Welcome = "Bob has joined the party!",
			Leave = "Bob is off to fight more important battles."
		}
	},
	ShowGeneric = false,
	ShowForBots = false
}

Plugin.CheckConfig = true
Plugin.CheckConfigTypes = true
Plugin.SilentConfigSave = true

Plugin.ConfigMigrationSteps = {
	{
		VersionTo = "1.3",
		Apply = function( Config )
			if not IsType( Config.Users, "table" ) then return end

			-- Remove any remaining "Said" entries.
			for ID, Data in pairs( Config.Users ) do
				if IsType( Data, "table" ) then
					Data.Said = nil
				end
			end
		end
	}
}

do
	local Validator = Shine.Validator()

	local function ValidateColour( Key, Validator )
		Validator:AddFieldRule( Key, Validator.IsType( "table", { 255, 255, 255 } ) )
		Validator:AddFieldRule( Key, Validator.Each( Validator.IsType( "number", 255 ) ) )
		Validator:AddFieldRule( Key, Validator.Each( Validator.Clamp( 0, 255 ) ) )
	end

	local function AddMessageRules( Key, PrintKey, Validator, Message )
		if Message.Colour then
			ValidateColour( { Key..".Colour", PrintKey..".Colour" }, Validator )
		end
		if Message.PrefixColour then
			ValidateColour( { Key..".PrefixColour", PrintKey..".PrefixColour" }, Validator )
		end

		Validator:AddFieldRule( { Key..".Prefix", PrintKey..".Prefix" }, Validator.IsAnyType( { "string", "nil" } ) )

		local MessageKey = { Key..".Message", PrintKey..".Message" }
		Validator:AddFieldRule( MessageKey, Validator.IsAnyType( { "string", "table" } ) )

		if IsType( Message.Message, "table" ) then
			Validator:AddFieldRule( MessageKey, Validator.Each( Validator.IsAnyType( { "string", "table" } ) ) )
		end
	end

	local function ValidateUserEntry( ID, Entry )
		local Key = StringFormat( "Users[ \"%s\" ]", ID )

		local EntryValidator = Shine.Validator()
		EntryValidator:AddFieldRule( { "Welcome", Key..".Welcome" },
			EntryValidator.IsAnyType( { "string", "table", "nil" } ) )
		EntryValidator:AddFieldRule( { "Leave", Key..".Leave" },
			EntryValidator.IsAnyType( { "string", "table", "nil" } ) )

		if IsType( Entry.Welcome, "table" ) then
			AddMessageRules( "Welcome", StringFormat( "%s.Welcome", Key ), EntryValidator, Entry.Welcome )
		end

		if IsType( Entry.Leave, "table" ) then
			AddMessageRules( "Leave", StringFormat( "%s.Leave", Key ), EntryValidator, Entry.Leave )
		end

		return EntryValidator:Validate( Entry )
	end

	Validator:AddRule( {
		Matches = function( self, Config )
			local Failed = false

			for ID, MessageData in pairs( Config.Users ) do
				if not IsType( MessageData, "table" ) then
					Print( "Welcome message for user %s was not a table and will be removed.", ID )
					Config.Users[ ID ] = nil

					Failed = true
				elseif ValidateUserEntry( ID, MessageData ) then
					Failed = true
				end
			end

			return Failed
		end
	} )

	Plugin.ConfigValidator = Validator
end

function Plugin:Initialise()
	self.Welcomed = {}
	self.AlreadyDisplayedMessages = Shine.LoadJSONFile( self.MessageDisplayHistoryFile ) or {}
	self.Enabled = true

	return true
end

function Plugin:SaveMessageDisplayHistory()
	Shine.SaveJSONFile( self.AlreadyDisplayedMessages, self.MessageDisplayHistoryFile )
end

function Plugin:RememberMessageDisplay( ID )
	self.AlreadyDisplayedMessages[ ID ] = true
	self:SaveMessageDisplayHistory()
end

function Plugin:ForgetMessageDisplay( ID )
	if not self.AlreadyDisplayedMessages[ ID ] then return end

	self.AlreadyDisplayedMessages[ ID ] = nil
	self:SaveMessageDisplayHistory()
end

function Plugin:ShouldShowMessage( Client )
	return Shine:IsValidClient( Client ) and ( self.Config.ShowForBots
		or not Client:GetIsVirtual() )
end

local function ToColour( ColourDef )
	if not ColourDef then
		return { 255, 255, 255 }
	end

	local R = ColourDef[ 1 ] or 255
	local G = ColourDef[ 2 ] or 255
	local B = ColourDef[ 3 ] or 255

	return R, G, B
end

function Plugin:DisplayMessage( Message )
	if IsType( Message, "string" ) then
		Shine:NotifyColour( nil, 255, 255, 255, Message )
		return
	end

	if IsType( Message.Message, "table" ) then
		self:NotifyRichText( nil, ChatAPI.ToRichTextMessage( Message.Message ) )
		return
	end

	local R, G, B = ToColour( Message.Colour )

	if Message.Prefix then
		local PR, PG, PB = ToColour( Message.PrefixColour )
		Shine:NotifyDualColour( nil, PR, PG, PB, Message.Prefix,
			R, G, B, Message.Message )
	else
		Shine:NotifyColour( nil, R, G, B, Message.Message )
	end
end

function Plugin:ClientConnect( Client )
	self:SimpleTimer( self.Config.MessageDelay, function()
		if not self:ShouldShowMessage( Client ) then return end

		local ID = tostring( Client:GetUserId() )
		local MessageTable = self.Config.Users[ ID ]

		if MessageTable and MessageTable.Welcome then
			if not self.AlreadyDisplayedMessages[ ID ] then
				self:RememberMessageDisplay( ID )
				self:DisplayMessage( MessageTable.Welcome )
			end

			self.Welcomed[ Client ] = true

			return
		end

		if not self.Config.ShowGeneric then return end

		self.Welcomed[ Client ] = true

		local Player = Client:GetControllingPlayer()
		if not Player then return end

		self:SendTranslatedNotifyColour( nil, "PLAYER_JOINED_GENERIC", {
			R = 255, G = 255, B = 255,
			TargetName = Player:GetName()
		} )
	end )
end

function Plugin:ClientDisconnect( Client )
	local ID = tostring( Client:GetUserId() )

	self:ForgetMessageDisplay( ID )

	if not self.Welcomed[ Client ] then return end

	self.Welcomed[ Client ] = nil

	local MessageTable = self.Config.Users[ ID ]
	if MessageTable and MessageTable.Leave then
		self:DisplayMessage( MessageTable.Leave )
		return
	end

	if not self.Config.ShowGeneric then return end

	local Player = Client:GetControllingPlayer()
	if not Player then return end

	local Team = Client.DisconnectTeam or 0
	if not IsType( Client.DisconnectReason, "string" ) then
		self:SendTranslatedNotifyRichText( nil, "PLAYER_LEAVE_GENERIC", {
			Team = Team,
			TargetName = Player:GetName()
		} )
	else
		self:SendTranslatedNotifyRichText( nil, "PLAYER_LEAVE_REASON", {
			Team = Team,
			TargetName = Player:GetName(),
			Reason = Client.DisconnectReason
		} )
	end
end

function Plugin:OnScriptDisconnect( Client, Reason )
	local Player = Client:GetControllingPlayer()
	if not Player then return end

	local Team = Player.GetTeamNumber and Player:GetTeamNumber()
	if not Team then return end

	Client.DisconnectTeam = Team
	Client.DisconnectReason = Client.DisconnectReason or Reason
end

function Plugin:PostJoinTeam( Gamerules, Player, OldTeam, NewTeam, Force, ShineForce )
	if NewTeam < 0 then return end
	if not Player then return end

	local Client = GetOwner( Player )
	if Client then
		Client.DisconnectTeam = NewTeam
	end
end

function Plugin:Cleanup()
	self.Welcomed = nil
	self.BaseClass.Cleanup( self )
end

Shine.Hook.SetupGlobalHook(
	"Server.DisconnectClient",
	"OnScriptDisconnect",
	function( DisconnectClient, Client, ... )
		if not IsType( Client, "userdata" ) or not IsValid( Client )
		or not ( IsType( Client.isa, "function" ) and Client:isa( "ServerClient" ) ) then
			Print(
				"Invalid ServerClient object (%s) passed to Server.DisconnectClient!\n%s",
				type( Client ),
				Shine.StackDump( 2 )
			)
		else
			Shine.Hook.Broadcast( "OnScriptDisconnect", Client, ... )
		end

		return DisconnectClient( Client, ... )
	end
)
