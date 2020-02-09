--[[
	Commbans client.
]]

local Plugin = ...

Plugin.AdminTab = "Comm Bans"

Plugin.BanCommand = "sh_commbanid"
Plugin.UnbanCommand = "sh_uncommban"

Plugin.AdminMenuIcon = Shine.GUI.Icons.Ionicons.Thumbsdown

do
	local RichTextFormat = require "shine/lib/gui/richtext/format"

	local function GetColourForName( Values )
		return RichTextFormat.GetColourForPlayer( Values.TargetName )
	end

	Plugin.RichTextMessageOptions = {
		PLAYER_BANNED = {
			Colours = {
				TargetName = GetColourForName,
				Duration = RichTextFormat.Colours.LightBlue,
				Reason = RichTextFormat.Colours.LightRed
			}
		},
		PLAYER_UNBANNED = {
			Colours = {
				TargetName = GetColourForName
			}
		}
	}
end

function Plugin:Initialise()
	self:SetupAdminMenu()

	self.Enabled = true

	return true
end
