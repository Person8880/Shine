--[[
	Fun commands client.
]]

local Plugin = ...

local SGUI = Shine.GUI

local IsType = Shine.IsType
local StringFormat = string.format
local TableConcat = table.concat
local tostring = tostring

do
	local RichTextFormat = require "shine/lib/gui/richtext/format"

	local function GetColourForName( Values )
		return RichTextFormat.GetColourForPlayer( Values.TargetName )
	end

	local TargetMessageOptions = {
		Colours = {
			TargetName = GetColourForName
		}
	}

	local RichTextMessageOptions = {}

	for i = 1, #Plugin.TeleportMessageKeys do
		RichTextMessageOptions[ Plugin.TeleportMessageKeys[ i ] ] = TargetMessageOptions
	end

	RichTextMessageOptions[ "TELEPORTED_GOTO_LOCATION" ] = {
		Colours = {
			LocationID = RichTextFormat.Colours.LightBlue
		}
	}
	RichTextMessageOptions[ "TELEPORTED_SENT_TO" ] = {
		Colours = {
			SourceName = function( Values ) return RichTextFormat.GetColourForPlayer( Values.SourceName ) end,
			TargetName = GetColourForName
		}
	}
	RichTextMessageOptions[ "TELEPORTED_SENT_TO_LOCATION" ] = {
		Colours = {
			TargetName = GetColourForName,
			LocationID = RichTextFormat.Colours.LightBlue
		}
	}

	local ActionMessageOptions = {
		Colours = {
			TargetCount = RichTextFormat.Colours.LightBlue
		}
	}

	for i = 1, #Plugin.ActionMessageKeys do
		RichTextMessageOptions[ Plugin.ActionMessageKeys[ i ] ] = ActionMessageOptions
	end

	Plugin.RichTextMessageOptions = RichTextMessageOptions
end

function Plugin:Initialise()
	self:SetupAdminMenuCommands()

	self.Enabled = true

	return true
end

function Plugin:SetupAdminMenuCommands()
	local Category = self:GetPhrase( "CATEGORY" )

	local LocationNames
	local function FindLocations()
		return Shine.Stream( EntityListToTable( Shared.GetEntitiesWithClassname( "Location" ) ) )
			:Map( function( Location ) return Location:GetName() end )
			:Distinct()
			:Sort()
			:AsTable()
	end

	local function GetLocations()
		if not LocationNames then
			LocationNames = FindLocations()
		end
		return LocationNames
	end

	self:AddAdminMenuCommand( Category, self:GetPhrase( "GOTO" ), "sh_goto", false, nil,
		self:GetPhrase( "GOTO_TIP" ) )
	self:AddAdminMenuCommand( Category, self:GetPhrase( "BRING" ), "sh_bring", false, nil,
		self:GetPhrase( "BRING_TIP" ) )
	self:AddAdminMenuCommand( Category, self:GetPhrase( "SEND_TO" ), "sh_sendto", false, {
		BuildMenuOptions = function( SelectedPlayerRows, MappingFunctions )
			local SelectedPlayer = SelectedPlayerRows[ 1 ]
			local SelectedName = SelectedPlayer:GetColumnText( 1 )
			local SelectedSteamID = SelectedPlayer:GetColumnText( 2 )

			local Players = EntityListToTable( Shared.GetEntitiesWithClassname( "PlayerInfoEntity" ) )
			local Options = {}
			local Count = 0

			for i = 1, #Players do
				local SteamID = tostring( Players[ i ].steamId )
				local Name = Players[ i ].playerName

				if SteamID ~= SelectedSteamID or ( SteamID == "0" and SelectedName ~= Name ) then
					Count = Count + 1
					Options[ Count ] = Name
					Count = Count + 1
					Options[ Count ] = StringFormat( "\"%s\"", MappingFunctions.GetArgFromPlayer( SteamID, Name ) )
				end
			end

			return Options
		end,
		MaxVisibleButtons = 8
	}, self:GetPhrase( "SEND_TO_TIP" ) )
	self:AddAdminMenuCommand( Category, self:GetPhrase( "SEND_TO_LOCATION" ), "sh_sendto_location", false, {
		BuildMenuOptions = function()
			local LocationNames = GetLocations()
			local Options = {}
			local Count = 0
			for i = 1, #LocationNames do
				Count = Count + 1
				Options[ Count ] = LocationNames[ i ]
				Count = Count + 1
				Options[ Count ] = StringFormat( "%q", LocationNames[ i ] )
			end
			return Options
		end,
		MaxVisibleButtons = 8
	}, self:GetPhrase( "SEND_TO_LOCATION_TIP" ) )
	self:AddAdminMenuCommand( Category, self:GetPhrase( "SLAY" ), "sh_slay", true, nil,
		self:GetPhrase( "SLAY_TIP" ) )
	self:AddAdminMenuCommand( Category, self:GetPhrase( "DARWIN_MODE" ), "sh_darwin", true, {
		self:GetPhrase( "ENABLE" ), "true",
		self:GetPhrase( "DISABLE" ), "false"
	}, self:GetPhrase( "DARWIN_MODE_TIP" ) )
end

function Plugin:PreProcessTranslatedMessage( Name, Data )
	if Data.LocationID then
		Data.LocationID = Shared.GetString( Data.LocationID )
	end
	return Data
end
