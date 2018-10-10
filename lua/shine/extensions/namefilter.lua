--[[
	Provides a way to filter out player names.
]]

local Shine = Shine

local Clamp = math.Clamp
local Floor = math.floor
local Max = math.max
local pcall = pcall
local Random = math.random
local StringChar = string.char
local StringFind = string.find
local StringFormat = string.format
local StringGSub = string.gsub
local StringLower = string.lower
local TableConcat = table.concat
local tostring = tostring

local Plugin = {}

Plugin.PrintName = "Name Filter"
Plugin.Version = "1.2"

Plugin.ConfigName = "NameFilter.json"
Plugin.HasConfig = true

Plugin.FilterActionType = table.AsEnum{
	"RENAME", "KICK", "BAN"
}

Plugin.DefaultConfig = {
	ForcedNames = {},
	Filters = {},
	FilterAction = Plugin.FilterActionType.RENAME,
	BanLength = 1440
}

Plugin.CheckConfig = true
Plugin.CheckConfigTypes = true

do
	local Validator = Shine.Validator()
	Validator:AddFieldRule( "BanLength", Validator.Min( 0 ) )
	Validator:AddFieldRule(	"FilterAction",
		Validator.InEnum( Plugin.FilterActionType, Plugin.FilterActionType.RENAME ) )
	Plugin.ConfigValidator = Validator
end

Plugin.ConfigMigrationSteps = {
	{
		VersionTo = "1.2",
		Apply = function( Config )
			local ExistingAction = Plugin.FilterActionType[ Config.FilterAction ]
			Config.FilterAction = ExistingAction or Plugin.FilterActionType.RENAME
		end
	}
}

function Plugin:Initialise()
	self:CreateCommands()
	self.InvalidFilters = {}

	self.Enabled = true

	return true
end

function Plugin:CreateCommands()
	self:BindCommand( "sh_rename", "rename", function( Client, Target, NewName )
		local TargetPlayer = Target:GetControllingPlayer()
		if not TargetPlayer then return end

		local CallingInfo = Shine.GetClientInfo( Client )
		local TargetInfo = Shine.GetClientInfo( Target )

		TargetPlayer:SetName( NewName )

		Shine:AdminPrint( nil, "%s was renamed to '%s' by %s.", true,
			TargetInfo, NewName, CallingInfo )
	end )
	:AddParam{ Type = "client" }
	:AddParam{ Type = "string", TakeRestOfLine = true, Help = "new name" }
	:Help( "Renames the given player." )

	self:BindCommand( "sh_renameid", "renameid", function( Client, ID, NewName )
		self.Config.ForcedNames[ tostring( ID ) ] = NewName
		self:SaveConfig()

		local Client = Shine.GetClientByNS2ID( ID )
		if Client then
			local Player = Client:GetControllingPlayer()
			if Player then
				Player:SetName( NewName )
			end
		end

		Shine:AdminPrint( nil, "%s was permanently renamed to '%s' by %s", true,
			ID, NewName, Shine.GetClientInfo( Client ) )
	end )
	:AddParam{ Type = "steamid" }
	:AddParam{ Type = "string", TakeRestOfLine = true, Help = "new name" }
	:Help( "Forces the player with the given Steam ID to always be named the given name." )

	self:BindCommand( "sh_unrenameid", "unrenameid", function( Client, ID )
		local IDAsString = tostring( ID )
		if not self.Config.ForcedNames[ IDAsString ] then
			Shine:NotifyCommandError( Client, "Player with Steam ID %s has not been renamed.", true, ID )
			return
		end

		self.Config.ForcedNames[ IDAsString ] = nil
		self:SaveConfig()

		Shine:AdminPrint( nil, "%s reset the name of %s.", true, Shine.GetClientInfo( Client ), ID )
	end )
	:AddParam{ Type = "steamid" }
	:Help( "Resets any forced name for the given Steam ID." )
end

Plugin.FilterActions = {
	[ Plugin.FilterActionType.RENAME ] = function( self, Player, OldName )
		local UserName = "NSPlayer"..Random( 1e3, 1e5 )
		local Client = Player:GetClient()
		if not Client then return UserName end

		self:Print( "Client %s[%s] was renamed from filtered name: %s", true,
			UserName, Client:GetUserId(), OldName )

		return UserName
	end,

	[ Plugin.FilterActionType.KICK ] = function( self, Player, OldName )
		local Client = Player:GetClient()
		if not Client then return end

		self:Print( "Client %s[%s] was kicked for filtered name.", true,
			OldName, Client:GetUserId() )

		Server.DisconnectClient( Client, "Kicked for filtered name." )
	end,

	[ Plugin.FilterActionType.BAN ] = function( self, Player, OldName )
		local Client = Player:GetClient()
		if not Client then return end

		local ID = Client:GetUserId()
		local Enabled, BanPlugin = Shine:IsExtensionEnabled( "ban" )
		local BanReason

		if Enabled then
			self:Print( "Client %s[%s] was banned for filtered name.", true,
				OldName, ID )

			local Duration = self.Config.BanLength * 60
			BanPlugin:AddBan( ID, OldName, Duration, "NameFilter", 0,
				"Player used filtered name." )

			BanReason = StringFormat( "Banned %s for filtered name.", string.TimeToDuration( Duration ) )
		else
			self:Print( "Client %s[%s] was kicked for filtered name (unable to ban, ban plugin not loaded).",
				true, OldName, ID )

			BanReason = "Kicked for filtered name."
		end

		Server.DisconnectClient( Client, BanReason )
	end
}

--[[
	Checks a player's name for a match with the given pattern.

	Excluded should be an NS2ID which identifies the player who owns this name pattern.
]]
function Plugin:ProcessFilter( Player, Name, Filter )
	if not Filter.Pattern then return end

	local Client = Player:GetClient()
	if Client and tostring( Client:GetUserId() ) == tostring( Filter.Excluded ) then return end

	local LoweredName = StringLower( Name )
	local Pattern = StringLower( Filter.Pattern )

	local Start
	if Filter.PlainText then
		Start = StringFind( LoweredName, Pattern, 1, true )
	else
		local Success
		Success, Start = pcall( StringFind, LoweredName, Pattern )

		if not Success then
			self.InvalidFilters[ Filter ] = true
			self:Print( "Pattern '%s' is invalid: %s. Set \"PlainText\": true if you do not want to use a Lua pattern match.",
				true, Pattern, StringGSub( Start, "^.+:%d+:(.+)$", "%1" ) )
			return
		end
	end

	if Start then
		local NewName = self.FilterActions[ self.Config.FilterAction ]( self, Player, Name )

		return true, NewName
	end
end

--[[
	Check for a forced name, and if the player has one, apply it.
]]
function Plugin:EnforceName( Client )
	local ID = Client and Client:GetUserId()
	return self.Config.ForcedNames[ tostring( ID ) ]
end


--[[
	When a player's name changes, we check all set filters on their new name.
]]
function Plugin:CheckPlayerName( Player, Name, OldName )
	local ForcedName = self:EnforceName( Player:GetClient() )
	if ForcedName then return ForcedName end

	local Filters = self.Config.Filters
	for i = 1, #Filters do
		if not self.InvalidFilters[ Filters[ i ] ] then
			local Filtered, NewName = self:ProcessFilter( Player, Name, Filters[ i ] )
			if Filtered then
				return NewName or OldName
			end
		end
	end
end

Shine:RegisterExtension( "namefilter", Plugin )
