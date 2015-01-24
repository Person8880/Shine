--[[
	Base commands shared.
]]

local Plugin = {}

function Plugin:SetupDataTable()
	self:AddDTVar( "integer (1 to 10)", "Gamestate", 1 )
	self:AddDTVar( "boolean", "AllTalk", false )

	self:AddNetworkMessage( "RequestMapData", {}, "Server" )
	self:AddNetworkMessage( "MapData", { Name = "string (32)" }, "Client" )

	self:AddNetworkMessage( "RequestPluginData", {}, "Server" )
	self:AddNetworkMessage( "PluginData", { Name = "string (32)", Enabled = "boolean" }, "Client" )
end

function Plugin:NetworkUpdate( Key, Old, New )
	if Server then return end

	if Key == "Gamestate" then
		if Old == 2 and New == 1 then
			--The game state changes back to 1, then to 3 to start. This is VERY annoying...
			self:SimpleTimer( 1, function()
				if not self.Enabled then return end

				if self.dt.Gamestate == 1 then
					self:UpdateAllTalk( self.dt.Gamestate )
				end
			end )

			return
		end

		self:UpdateAllTalk( New )
	elseif Key == "AllTalk" then
		if not New then
			self:RemoveAllTalkText()
		else
			self:UpdateAllTalk( self.dt.Gamestate )
		end
	end
end

Shine:RegisterExtension( "basecommands", Plugin )

if Server then return end

local Shine = Shine
local Hook = Shine.Hook
local SGUI = Shine.GUI

local StringFormat = string.format
local TableEmpty = table.Empty

local NOT_STARTED = 1
local PREGAME = 2
local COUNTDOWN = 3

function Plugin:Initialise()
	if self.dt.AllTalk then
		self:UpdateAllTalk( self.dt.Gamestate )
	end

	self:SetupAdminMenuCommands()

	self.Enabled = true

	return true
end

function Plugin:SetupAdminMenuCommands()
	local Category = "Base Commands"

	self:AddAdminMenuCommand( Category, "Eject", "sh_eject", false, nil,
		"Ejects the player from the command station/hive." )
	self:AddAdminMenuCommand( Category, "Kick", "sh_kick", false, {
		"No Reason", "",
		"Trolling", "Trolling.",
		"Offensive language", "Offensive language.",
		"Mic spamming", "Mic spamming."
	}, "Kicks the player from the server." )
	self:AddAdminMenuCommand( Category, "Gag", "sh_gag", false, {
		"5 minutes", "300",
		"10 minutes", "600",
		"15 minutes", "900",
		"20 minutes", "1200",
		"30 minutes", "1800",
		"Until map change", ""
	}, "Stops the player from using text and voice chat." )
	self:AddAdminMenuCommand( Category, "Ungag", "sh_ungag", false, nil,
		"Allows a previously gagged player to speak again." )
	self:AddAdminMenuCommand( Category, "Force Random", "sh_forcerandom", true, nil,
		"Moves the selected player(s) onto a random team." )
	self:AddAdminMenuCommand( Category, "Ready Room", "sh_rr", true, nil,
		"Moves the selected player(s) into the ready room." )
	local Teams = {}
	for i = 0, 3 do
		local TeamName = Shine:GetTeamName( i, true )
		i = i + 1

		Teams[ i * 2 - 1 ] = TeamName
		Teams[ i * 2 ] = tostring( i - 1 )
	end
	self:AddAdminMenuCommand( Category, "Set Team", "sh_setteam", true, Teams,
		"Moves the selected player(s) onto the selected team." )

	self:AddAdminMenuTab( "Maps", {
		OnInit = function( Panel, Data )
			local List = SGUI:Create( "List", Panel )
			List:SetAnchor( GUIItem.Left, GUIItem.Top )
			List:SetPos( Vector( 16, 28, 0 ) )
			List:SetColumns( 1, "Map" )
			List:SetSpacing( 1 )
			List:SetSize( Vector( 640, 512, 0 ) )
			List.ScrollPos = Vector( 0, 32, 0 )

			self.MapList = List

			if not self.MapData then
				self:RequestMapData()
			else
				for Map in pairs( self.MapData ) do
					List:AddRow( Map )
				end
			end

			if Data and Data.SortedColumn then
				List:SortRows( Data.SortedColumn, nil, Data.Descending )
			else
				List:SortRows( 1 )
			end

			local ChangeMap = SGUI:Create( "Button", Panel )
			ChangeMap:SetAnchor( "BottomLeft" )
			ChangeMap:SetSize( Vector( 128, 32, 0 ) )
			ChangeMap:SetPos( Vector( 16, -48, 0 ) )
			ChangeMap:SetText( "Change map" )
			ChangeMap:SetFont( Fonts.kAgencyFB_Small )
			function ChangeMap.DoClick()
				local Selected = List:GetSelectedRow()
				if not Selected then return end

				local Map = Selected:GetColumnText( 1 )

				Shine.AdminMenu:RunCommand( "sh_changelevel", Map )
			end
			ChangeMap:SetTooltip( "Changes the map immediately." )

			if Shine:IsExtensionEnabled( "mapvote" ) then
				local CallVote = SGUI:Create( "Button", Panel )
				CallVote:SetAnchor( "BottomRight" )
				CallVote:SetSize( Vector( 128, 32, 0 ) )
				CallVote:SetPos( Vector( -144, -48, 0 ) )
				CallVote:SetText( "Call Map Vote" )
				CallVote:SetFont( Fonts.kAgencyFB_Small )
				function CallVote.DoClick()
					Shine.AdminMenu:RunCommand( "sh_forcemapvote" )
				end
				CallVote:SetTooltip( "Calls a map vote." )
			end
		end,

		OnCleanup = function( Panel )
			local SortColumn = self.MapList.SortedColumn
			local Descending = self.MapList.Descending

			self.MapList = nil

			return {
				SortedColumn = SortColumn,
				Descending = Descending
			}
		end
	} )

	self:AddAdminMenuTab( "Plugins", {
		OnInit = function( Panel, Data )
			local List = SGUI:Create( "List", Panel )
			List:SetAnchor( GUIItem.Left, GUIItem.Top )
			List:SetPos( Vector( 16, 28, 0 ) )
			List:SetColumns( 2, "Plugin", "State" )
			List:SetSpacing( 0.7, 0.3 )
			List:SetSize( Vector( 640, 512, 0 ) )
			List.ScrollPos = Vector( 0, 32, 0 )

			self.PluginList = List
			self.PluginRows = self.PluginRows or {}

			--We need information about the server side only plugins too.
			if not self.PluginData then
				self:RequestPluginData()
			end

			for Plugin in pairs( Shine.AllPlugins ) do
				local Enabled, PluginTable = Shine:IsExtensionEnabled( Plugin )
				local Skip
				--Server side plugin.
				if not PluginTable then
					Enabled = self.PluginData and self.PluginData[ Plugin ]
				elseif PluginTable.IsClient and not PluginTable.IsShared then
					Skip = true
				end

				if not Skip then
					local Row = List:AddRow( Plugin, Enabled and "Enabled" or "Disabled" )

					self.PluginRows[ Plugin ] = Row
				end
			end

			if Data and Data.SortedColumn then
				List:SortRows( Data.SortedColumn, nil, Data.Descending )
			else
				List:SortRows( 1 )
			end

			local ButtonSize = Vector( 128, 32, 0 )

			local function GetSelectedPlugin()
				local Selected = List:GetSelectedRow()
				if not Selected then return end

				return Selected:GetColumnText( 1 )
			end

			local UnloadPlugin = SGUI:Create( "Button", Panel )
			UnloadPlugin:SetAnchor( "BottomLeft" )
			UnloadPlugin:SetSize( ButtonSize )
			UnloadPlugin:SetPos( Vector( 16, -48, 0 ) )
			UnloadPlugin:SetText( "Unload Plugin" )
			UnloadPlugin:SetFont( Fonts.kAgencyFB_Small )
			function UnloadPlugin:DoClick()
				local Plugin = GetSelectedPlugin()
				if not Plugin then return false end

				local Menu = self:AddMenu()

				Menu:AddButton( "Now", function()
					Menu:Destroy()

					Shine.AdminMenu:RunCommand( "sh_unloadplugin", Plugin )
				end, "Temporarily unloads the plugin." )

				Menu:AddButton( "Permanently", function()
					Menu:Destroy()

					Shine.AdminMenu:RunCommand( "sh_unloadplugin", Plugin.." true" )
				end, "Saves the plugin as disabled." )
			end

			local LoadPlugin = SGUI:Create( "Button", Panel )
			LoadPlugin:SetAnchor( "BottomRight" )
			LoadPlugin:SetSize( ButtonSize )
			LoadPlugin:SetPos( Vector( -144, -48, 0 ) )
			LoadPlugin:SetText( "Load Plugin" )
			LoadPlugin:SetFont( Fonts.kAgencyFB_Small )
			local function NormalLoadDoClick( self )
				local Plugin = GetSelectedPlugin()
				if not Plugin then return false end

				local Menu = self:AddMenu()

				Menu:AddButton( "Now", function()
					Menu:Destroy()

					Shine.AdminMenu:RunCommand( "sh_loadplugin", Plugin )
				end, "Temporarily loads the plugin." )

				Menu:AddButton( "Permanently", function()
					Menu:Destroy()

					Shine.AdminMenu:RunCommand( "sh_loadplugin", Plugin.." true" )
				end, "Saves the plugin as enabled." )
			end

			local function ReloadDoClick()
				local Plugin = GetSelectedPlugin()
				if not Plugin then return false end

				Shine.AdminMenu:RunCommand( "sh_loadplugin", Plugin )
			end

			LoadPlugin.DoClick = NormalLoadDoClick

			function List:OnRowSelected( Index, Row )
				local State = Row:GetColumnText( 2 )

				if State == "Enabled" then
					LoadPlugin:SetText( "Reload Plugin" )
					LoadPlugin.DoClick = ReloadDoClick
				else
					LoadPlugin:SetText( "Load Plugin" )
					LoadPlugin.DoClick = NormalLoadDoClick
				end
			end

			Hook.Add( "OnPluginLoad", "AdminMenu_OnPluginLoad", function( Name, Plugin, Shared )
				local Row = self.PluginRows[ Name ]

				if SGUI.IsValid( Row ) then
					Row:SetColumnText( 2, "Enabled" )
					if Row == List:GetSelectedRow() then
						List:OnRowSelected( nil, Row )
					end
				end
			end )

			Hook.Add( "OnPluginUnload", "AdminMenu_OnPluginUnload", function( Name, Shared )
				local Row = self.PluginRows[ Name ]

				if SGUI.IsValid( Row ) then
					Row:SetColumnText( 2, "Disabled" )
					if Row == List:GetSelectedRow() then
						List:OnRowSelected( nil, Row )
					end
				end
			end )
		end,

		OnCleanup = function( Panel )
			local SortColumn = self.PluginList.SortedColumn
			local Descending = self.PluginList.Descending

			TableEmpty( self.PluginRows )

			self.PluginList = nil

			Hook.Remove( "OnPluginLoad", "AdminMenu_OnPluginLoad" )
			Hook.Remove( "OnPluginUnload", "AdminMenu_OnPluginUnload" )

			return {
				SortedColumn = SortColumn,
				Descending = Descending
			}
		end
	} )
end

function Plugin:RequestMapData()
	self:SendNetworkMessage( "RequestMapData", {}, true )
end

function Plugin:ReceiveMapData( Data )
	self.MapData = self.MapData or {}

	if self.MapData[ Data.Name ] then return end

	self.MapData[ Data.Name ] = true

	if SGUI.IsValid( self.MapList ) then
		self.MapList:AddRow( Data.Name )
	end
end

function Plugin:RequestPluginData()
	self:SendNetworkMessage( "RequestPluginData", {}, true )
end

function Plugin:ReceivePluginData( Data )
	self.PluginData = self.PluginData or {}

	self.PluginData[ Data.Name ] = Data.Enabled

	local Row = self.PluginRows[ Data.Name ]

	if Row then
		Row:SetColumnText( 2, Data.Enabled and "Enabled" or "Disabled" )
		if Row == self.PluginList:GetSelectedRow() then
			self.PluginList:OnRowSelected( nil, Row )
		end
	end
end

function Plugin:UpdateAllTalk( State )
	if not self.dt.AllTalk then return end

	if State >= COUNTDOWN then
		if not self.TextObj then return end

		self:RemoveAllTalkText()

		return
	end

	local Enabled = State > NOT_STARTED and "disabled." or "enabled."

	if not self.TextObj then
		local GB = State > NOT_STARTED and 0 or 255

		--A bit of a hack, but the whole screen text stuff is in dire need of a replacement...
		self.TextObj = Shine:AddMessageToQueue( -1, 0.5, 0.95,
			StringFormat( "All talk is %s", Enabled ), -2, 255, GB, GB, 1, 2, 1, true )

		return
	end

	self.TextObj.Text = StringFormat( "All talk is %s", Enabled )

	local Col = State > NOT_STARTED and Color( 255, 0, 0 ) or Color( 255, 255, 255 )

	self.TextObj.Colour = Col
	self.TextObj.Obj:SetColor( Col )
end

function Plugin:RemoveAllTalkText()
	if not self.TextObj then return end

	self.TextObj.LastUpdate = Shared.GetTime() - 1
	self.TextObj.Duration = 1

	self.TextObj = nil
end

function Plugin:Cleanup()
	self:RemoveAllTalkText()

	self.BaseClass.Cleanup( self )
end
