--[[
	Fun commands client.
]]

local Plugin = ...

local SGUI = Shine.GUI

local TableConcat = table.concat

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
	local Category = "Fun Commands"

	self:AddAdminMenuCommand( Category, self:GetPhrase( "GOTO" ), "sh_goto", false, nil,
		self:GetPhrase( "GOTO_TIP" ) )
	self:AddAdminMenuCommand( Category, self:GetPhrase( "BRING" ), "sh_bring", false, nil,
		self:GetPhrase( "BRING_TIP" ) )
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
