--[[
	Provides a way to filter out player names.
]]

local JSON = require "shine/lib/json"

local Shine = Shine

local IsType = Shine.IsType
local pcall = pcall
local Random = math.random
local StringFind = string.find
local StringFormat = string.format
local StringGSub = string.gsub
local StringLower = string.lower
local TableAsSet = table.AsSet
local TableShallowCopy = table.ShallowCopy
local tostring = tostring

local Plugin = Shine.Plugin( ... )

Plugin.PrintName = "Name Filter"
Plugin.Version = "1.2"

Plugin.ConfigName = "NameFilter.json"
Plugin.HasConfig = true

Plugin.FilterActionType = table.AsEnum{
	"RENAME", "KICK", "BAN"
}

Plugin.DefaultConfig = {
	ForcedNames = JSON.Object(),
	Filters = {},
	FilterAction = Plugin.FilterActionType.RENAME,
	BanLength = 1440
}

Plugin.CheckConfig = true
Plugin.CheckConfigTypes = true

do
	local DeleteIfFieldInvalid = { DeleteIfFieldInvalid = true }

	local Validator = Shine.Validator()
	Validator:AddFieldRule( "BanLength", Validator.Min( 0 ) )
	Validator:AddFieldRule(
		"FilterAction",
		Validator.InEnum( Plugin.FilterActionType, Plugin.FilterActionType.RENAME )
	)
	Validator:AddFieldRule( "ForcedNames", Validator.AllKeyValuesSatisfy( Validator.IsType( "string" ) ) )
	Validator:AddFieldRule( "Filters", Validator.AllValuesSatisfy(
		Validator.ValidateField( "Pattern", Validator.IsType( "string" ), DeleteIfFieldInvalid ),
		Validator.ValidateField(
			"Excluded",
			Validator.IsAnyType( { "string", "number", "table", "nil" } )
		),
		Validator.ValidateField(
			"Excluded",
			Validator.IfType( "table", Validator.AllValuesSatisfy( Validator.IsAnyType( { "string", "number" } ) ) )
		)
	) )
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

function Plugin:CompileFilters()
	local Filters = self.Config.Filters
	local CompiledFilters = {}

	for i = 1, #Filters do
		local Filter = Filters[ i ]
		local CompiledFilter = TableShallowCopy( Filter )

		-- Turn the exclusions into a lookup table.
		local Excluded = CompiledFilter.Excluded
		if IsType( Excluded, "table" ) then
			if #Excluded > 0 then
				CompiledFilter.Excluded = TableAsSet( Shine.Stream.Of( Excluded ):Map( tostring ):AsTable() )
			end
		else
			CompiledFilter.Excluded = { [ tostring( Excluded ) ] = true }
		end

		CompiledFilters[ i ] = CompiledFilter
	end

	return CompiledFilters
end

function Plugin:Initialise()
	self:CreateCommands()
	self.InvalidFilters = {}
	self.Filters = self:CompileFilters()

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

		Shine:AdminPrint( nil, "%s was renamed to '%s' by %s.", true, TargetInfo, NewName, CallingInfo )
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

		Shine:AdminPrint(
			nil,
			"%s was permanently renamed to '%s' by %s",
			true,
			ID,
			NewName,
			Shine.GetClientInfo( Client )
		)
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
	[ Plugin.FilterActionType.RENAME ] = function( self, Player, FilteredName )
		local Client = Player:GetClient()
		if not Client then return "NSPlayer"..Random( 1e3, 1e5 ) end

		-- Use the client's Steam ID as it's guaranteed to be unique.
		local SteamID = Client:GetUserId()
		local UserName = "NSPlayer"..SteamID

		self:Print( "Client %s[%s] was renamed from filtered name: %s", true, UserName, SteamID, FilteredName )

		return UserName
	end,

	[ Plugin.FilterActionType.KICK ] = function( self, Player, FilteredName )
		local Client = Player:GetClient()
		if not Client then return end

		self:Print( "Client %s[%s] was kicked for filtered name.", true, FilteredName, Client:GetUserId() )

		Shine:DisconnectClient( Client, "Kicked for filtered name." )
	end,

	[ Plugin.FilterActionType.BAN ] = function( self, Player, FilteredName )
		local Client = Player:GetClient()
		if not Client then return end

		local ID = Client:GetUserId()
		local Enabled, BanPlugin = Shine:IsExtensionEnabled( "ban" )
		local BanReason

		if Enabled then
			self:Print( "Client %s[%s] was banned for filtered name.", true, FilteredName, ID )

			local Duration = self.Config.BanLength * 60
			BanPlugin:AddBan( ID, FilteredName, Duration, "NameFilter", 0, "Player used filtered name." )

			BanReason = StringFormat( "Banned %s for filtered name.", string.TimeToDuration( Duration ) )
		else
			self:Print(
				"Client %s[%s] was kicked for filtered name (unable to ban, ban plugin not loaded).",
				true,
				FilteredName,
				ID
			)

			BanReason = "Kicked for filtered name."
		end

		Shine:DisconnectClient( Client, BanReason )
	end
}

--[[
	Checks a player's name for a match with the given pattern.

	Excluded should be an NS2ID which identifies the player who owns this name pattern.
]]
function Plugin:ProcessFilter( Player, Name, Filter )
	local Client = Player:GetClient()
	if Client and Filter.Excluded and Filter.Excluded[ tostring( Client:GetUserId() ) ] then return end

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
			self:Print(
				"Pattern '%s' is invalid: %s. Set \"PlainText\": true if you do not want to use a Lua pattern match.",
				true, Pattern, StringGSub( Start, "^.+:%d+:(.+)$", "%1" )
			)
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
	if not Client then return nil end

	local ID = Client:GetUserId()
	return self.Config.ForcedNames[ tostring( ID ) ]
end

--[[
	When a player's name changes, check all set filters on their new name.
]]
function Plugin:CheckPlayerName( Player, Name, OldName )
	local Client = Player:GetClient()
	if Client and Client:GetIsVirtual() then return end

	local ForcedName = self:EnforceName( Client )
	if ForcedName then return ForcedName end

	local Filters = self.Filters
	for i = 1, #Filters do
		if not self.InvalidFilters[ Filters[ i ] ] then
			local Filtered, NewName = self:ProcessFilter( Player, Name, Filters[ i ] )
			if Filtered then
				return NewName or OldName
			end
		end
	end
end

return Plugin
