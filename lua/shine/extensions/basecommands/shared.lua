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
	self:AddNetworkMessage( "PluginTabAuthed", {}, "Client" )

	local MessageTypes = {
		Empty = {},
		Enabled = {
			Enabled = "boolean"
		},
		Kick = {
			TargetName = self:GetNameNetworkField(),
			Reason = "string (64)"
		},
		FF = {
			Scale = "float (0 to 100 by 0.01)"
		},
		TeamChange = {
			TargetCount = "integer (0 to 127)",
			Team = "integer (0 to 3)"
		},
		RandomTeam = {
			TargetCount = "integer (0 to 127)"
		},
		TargetName = {
			TargetName = self:GetNameNetworkField()
		},
		Gagged = {
			TargetName = self:GetNameNetworkField(),
			Duration = "integer (0 to 1800)"
		},
		FloatRate = {
			Rate = "float (0 to 1000 by 0.01)"
		},
		IntegerRate = {
			Rate = "integer (0 to 1000)"
		}
	}

	self:AddNetworkMessages( "AddTranslatedMessage", {
		[ MessageTypes.Empty ] = {
			"RESET_GAME", "HIVE_TEAMS", "FORCE_START", "VOTE_STOPPED"
		},
		[ MessageTypes.Enabled ] = {
			"CHEATS_TOGGLED", "ALLTALK_TOGGLED", "ALLTALK_PREGAME_TOGGLED"
		},
		[ MessageTypes.Kick ] = {
			"ClientKicked"
		},
		[ MessageTypes.FF ] = {
			"FRIENDLY_FIRE_SCALE"
		},
		[ MessageTypes.TeamChange ] = {
			"ChangeTeam"
		},
		[ MessageTypes.RandomTeam ] = {
			"RANDOM_TEAM"
		},
		[ table.Copy( MessageTypes.TargetName ) ] = {
			"PLAYER_EJECTED", "PLAYER_UNGAGGED"
		},
		[ MessageTypes.Gagged ] = {
			"PLAYER_GAGGED"
		}
	} )

	self:AddNetworkMessages( "AddTranslatedError", {
		[ MessageTypes.TargetName ] = {
			"ERROR_NOT_COMMANDER", "ERROR_NOT_GAGGED"
		},
		[ MessageTypes.FloatRate ] = {
			"ERROR_INTERP_CONSTRAINT"
		},
		[ MessageTypes.IntegerRate ] = {
			"ERROR_TICKRATE_CONSTRAINT", "ERROR_SENDRATE_CONSTRAINT",
			"ERROR_SENDRATE_MOVE_CONSTRAINT", "ERROR_MOVERATE_CONSTRAINT",
			"ERROR_MOVERATE_SENDRATE_CONSTRAINT"
		}
	} )

	self:AddNetworkMessage( "EnableLocalAllTalk", { Enabled = "boolean" }, "Server" )
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

Plugin.HasConfig = true
Plugin.ConfigName = "BaseCommands.json"
Plugin.DefaultConfig = {
	DisableLocalAllTalk = false
}
Plugin.CheckConfig = true
Plugin.CheckConfigTypes = true

Shine.Hook.Add( "PostLoadScript", "SetupCustomVote", function( Script )
	if Script ~= "lua/Voting.lua" then return end

	Shine.Hook.Remove( "PostLoadScript", "SetupCustomVote" )

	RegisterVoteType( "ShineCustomVote", { VoteQuestion = "string (64)" } )

	AddVoteSetupCallback( function( VoteMenu )
		AddVoteStartListener( "ShineCustomVote", function( Data )
			return Data.VoteQuestion
		end )
	end )
end )

local Shine = Shine
local Hook = Shine.Hook
local SGUI = Shine.GUI

local StringFormat = string.format
local StringTimeToString = string.TimeToString
local TableEmpty = table.Empty

local NOT_STARTED = 1
local PREGAME = 2
local COUNTDOWN = 3

function Plugin:Initialise()
	if self.dt.AllTalk then
		self:UpdateAllTalk( self.dt.Gamestate )
	end

	self:SetupAdminMenuCommands()
	self:SetupClientConfig()

	self.Enabled = true

	return true
end

function Plugin:ReceiveClientKicked( Data )
	local Key = Data.Reason ~= "" and "CLIENT_KICKED_REASON" or "CLIENT_KICKED"
	self:CommandNotify( Data.AdminName, Key, Data )
end

function Plugin:ReceiveChangeTeam( Data )
	local TeamKeys = {
		[ 0 ] = "CHANGE_TEAM_READY_ROOM",
		"CHANGE_TEAM_MARINE",
		"CHANGE_TEAM_ALIEN",
		"CHANGE_TEAM_SPECTATOR"
	}

	self:CommandNotify( Data.AdminName, TeamKeys[ Data.Team ], Data )
end

function Plugin:SetupClientConfig()
	Shine.AddStartupMessage( "You can choose to enable/disable local all talk for yourself by entering sh_alltalklocal_cl true/false." )

	if self.Config.DisableLocalAllTalk then
		self:SendNetworkMessage( "EnableLocalAllTalk", { Enabled = false }, true )
	end

	self:BindCommand( "sh_alltalklocal_cl", function( Enable )
		self.Config.DisableLocalAllTalk = not Enable
		self:SaveConfig( true )
		self:SendNetworkMessage( "EnableLocalAllTalk", { Enabled = Enable }, true )

		Print( "Local all talk is now %s.", Enable and "enabled" or "disabled" )
	end ):AddParam{ Type = "boolean", Optional = true, Default = function() return self.Config.DisableLocalAllTalk end }

	Shine:RegisterClientSetting( {
		Type = "Boolean",
		Command = "sh_alltalklocal_cl",
		ConfigOption = function() return not self.Config.DisableLocalAllTalk end,
		Description = "ALL_TALK_LOCAL_DESCRIPTION",
		TranslationSource = self.__Name
	} )
end

function Plugin:SetupAdminMenuCommands()
	local Category = self:GetPhrase( "CATEGORY" )

	self:AddAdminMenuCommand( Category, self:GetPhrase( "EJECT" ), "sh_eject", false, nil,
		self:GetPhrase( "EJECT_TIP" ) )
	self:AddAdminMenuCommand( Category, self:GetPhrase( "KICK" ), "sh_kick", false, {
		self:GetPhrase( "KICK_NO_REASON" ), "",
		self:GetPhrase( "KICK_TROLLING" ), "Trolling.",
		self:GetPhrase( "KICK_LANGUAGE" ), "Offensive language.",
		self:GetPhrase( "KICK_MIC_SPAM" ), "Mic spamming."
	}, self:GetPhrase( "KICK_TIP" ) )

	local GagTimes = {
		5 * 60, 10 * 60, 15 * 60, 20 * 60, 30 * 60
	}
	local GagLabels = {}
	for i = 1, #GagTimes do
		local Time = GagTimes[ i ]
		local TimeString = StringTimeToString( Time )

		GagLabels[ i * 2 - 1 ] = TimeString
		GagLabels[ i * 2 ] = tostring( Time )
	end

	GagLabels[ #GagLabels + 1 ] = self:GetPhrase( "GAG_UNTIL_MAP_CHANGE" )
	GagLabels[ #GagLabels + 1 ] = ""

	self:AddAdminMenuCommand( Category, self:GetPhrase( "GAG" ), "sh_gag", false, GagLabels,
		self:GetPhrase( "GAG_TIP" ) )
	self:AddAdminMenuCommand( Category, self:GetPhrase( "UNGAG" ), "sh_ungag", false, nil,
		self:GetPhrase( "UNGAG_TIP" ) )
	self:AddAdminMenuCommand( Category, self:GetPhrase( "FORCE_RANDOM" ), "sh_forcerandom", true, nil,
		self:GetPhrase( "FORCE_RANDOM_TIP" ) )
	self:AddAdminMenuCommand( Category, self:GetPhrase( "READY_ROOM" ), "sh_rr", true, nil,
		self:GetPhrase( "READY_ROOM_TIP" ) )
	local Teams = {}
	for i = 0, 3 do
		local TeamName = Shine:GetTeamName( i, true )
		i = i + 1

		Teams[ i * 2 - 1 ] = TeamName
		Teams[ i * 2 ] = tostring( i - 1 )
	end
	self:AddAdminMenuCommand( Category, self:GetPhrase( "SET_TEAM" ), "sh_setteam", true, Teams,
		self:GetPhrase( "SET_TEAM_TIP" ) )

	self:AddAdminMenuTab( self:GetPhrase( "MAPS" ), {
		OnInit = function( Panel, Data )
			local List = SGUI:Create( "List", Panel )
			List:SetAnchor( GUIItem.Left, GUIItem.Top )
			List:SetPos( Vector( 16, 28, 0 ) )
			List:SetColumns( self:GetPhrase( "MAP" ) )
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

			if not Shine.AdminMenu.RestoreListState( List, Data ) then
				List:SortRows( 1 )
			end

			local ChangeMap = SGUI:Create( "Button", Panel )
			ChangeMap:SetAnchor( "BottomLeft" )
			ChangeMap:SetSize( Vector( 128, 32, 0 ) )
			ChangeMap:SetPos( Vector( 16, -48, 0 ) )
			ChangeMap:SetText( self:GetPhrase( "CHANGE_MAP" ) )
			ChangeMap:SetFont( Fonts.kAgencyFB_Small )
			function ChangeMap.DoClick()
				local Selected = List:GetSelectedRow()
				if not Selected then return end

				local Map = Selected:GetColumnText( 1 )

				Shine.AdminMenu:RunCommand( "sh_changelevel", Map )
			end
			ChangeMap:SetTooltip( self:GetPhrase( "CHANGE_MAP_TIP" ) )

			if Shine:IsExtensionEnabled( "mapvote" ) then
				local CallVote = SGUI:Create( "Button", Panel )
				CallVote:SetAnchor( "BottomRight" )
				CallVote:SetSize( Vector( 128, 32, 0 ) )
				CallVote:SetPos( Vector( -144, -48, 0 ) )
				CallVote:SetText( self:GetPhrase( "CALL_VOTE" ) )
				CallVote:SetFont( Fonts.kAgencyFB_Small )
				function CallVote.DoClick()
					Shine.AdminMenu:RunCommand( "sh_forcemapvote" )
				end
				CallVote:SetTooltip( self:GetPhrase( "CALL_VOTE_TIP" ) )
			end
		end,

		OnCleanup = function( Panel )
			local MapList = self.MapList
			self.MapList = nil

			return Shine.AdminMenu.GetListState( MapList )
		end
	} )

	self:AddAdminMenuTab( self:GetPhrase( "PLUGINS" ), {
		OnInit = function( Panel, Data )
			local List = SGUI:Create( "List", Panel )
			List:SetAnchor( GUIItem.Left, GUIItem.Top )
			List:SetPos( Vector( 16, 28, 0 ) )
			List:SetColumns( self:GetPhrase( "PLUGIN" ), self:GetPhrase( "STATE" ) )
			List:SetSpacing( 0.7, 0.3 )
			List:SetSize( Vector( 640, 512, 0 ) )
			List.ScrollPos = Vector( 0, 32, 0 )
			List:SetSecondarySortColumn( 2, 1 )

			self.PluginList = List
			self.PluginRows = self.PluginRows or {}

			--We need information about the server side only plugins too.
			if not self.PluginData then
				self:RequestPluginData()
				self.PluginData = {}
			end

			if self.PluginAuthed then
				self:PopulatePluginList()
			end

			if not Shine.AdminMenu.RestoreListState( List, Data ) then
				List:SortRows( 2, nil, true )
			end

			local ButtonSize = Vector( 128, 32, 0 )

			local function GetSelectedPlugin()
				local Selected = List:GetSelectedRow()
				if not Selected then return end

				return Selected:GetColumnText( 1 ), Selected.PluginEnabled
			end

			local UnloadPlugin = SGUI:Create( "Button", Panel )
			UnloadPlugin:SetAnchor( "BottomLeft" )
			UnloadPlugin:SetSize( ButtonSize )
			UnloadPlugin:SetPos( Vector( 16, -48, 0 ) )
			UnloadPlugin:SetText( self:GetPhrase( "UNLOAD_PLUGIN" ) )
			UnloadPlugin:SetFont( Fonts.kAgencyFB_Small )
			function UnloadPlugin.DoClick( Button )
				local Plugin, Enabled = GetSelectedPlugin()
				if not Plugin then return false end
				if not Enabled then return false end

				local Menu = Button:AddMenu()

				Menu:AddButton( self:GetPhrase( "NOW" ), function()
					Menu:Destroy()

					Shine.AdminMenu:RunCommand( "sh_unloadplugin", Plugin )
				end, self:GetPhrase( "UNLOAD_PLUGIN_TIP" ) )

				Menu:AddButton( self:GetPhrase( "PERMANENTLY" ), function()
					Menu:Destroy()

					Shine.AdminMenu:RunCommand( "sh_unloadplugin", Plugin.." true" )
				end, self:GetPhrase( "UNLOAD_PLUGIN_SAVE_TIP" ) )
			end

			local LoadPlugin = SGUI:Create( "Button", Panel )
			LoadPlugin:SetAnchor( "BottomRight" )
			LoadPlugin:SetSize( ButtonSize )
			LoadPlugin:SetPos( Vector( -144, -48, 0 ) )
			LoadPlugin:SetText( self:GetPhrase( "LOAD_PLUGIN" ) )
			LoadPlugin:SetFont( Fonts.kAgencyFB_Small )
			local function NormalLoadDoClick( Button )
				local Plugin = GetSelectedPlugin()
				if not Plugin then return false end

				local Menu = Button:AddMenu()

				Menu:AddButton( self:GetPhrase( "NOW" ), function()
					Menu:Destroy()

					Shine.AdminMenu:RunCommand( "sh_loadplugin", Plugin )
				end, self:GetPhrase( "LOAD_PLUGIN_TIP" ) )

				Menu:AddButton( self:GetPhrase( "PERMANENTLY" ), function()
					Menu:Destroy()

					Shine.AdminMenu:RunCommand( "sh_loadplugin", Plugin.." true" )
				end, self:GetPhrase( "LOAD_PLUGIN_SAVE_TIP" ) )
			end

			local function ReloadDoClick()
				local Plugin = GetSelectedPlugin()
				if not Plugin then return false end

				Shine.AdminMenu:RunCommand( "sh_loadplugin", Plugin )
			end

			LoadPlugin.DoClick = NormalLoadDoClick

			function List.OnRowSelected( List, Index, Row )
				local State = Row.PluginEnabled

				if State then
					LoadPlugin:SetText( self:GetPhrase( "RELOAD_PLUGIN" ) )
					LoadPlugin.DoClick = ReloadDoClick
				else
					LoadPlugin:SetText( self:GetPhrase( "LOAD_PLUGIN" ) )
					LoadPlugin.DoClick = NormalLoadDoClick
				end
			end

			local function UpdateRow( Name, State )
				local Row = self.PluginRows[ Name ]

				if SGUI.IsValid( Row ) then
					Row:SetColumnText( 2, State and self:GetPhrase( "ENABLED" ) or self:GetPhrase( "DISABLED" ) )
					Row.PluginEnabled = State
					if Row == List:GetSelectedRow() then
						List:OnRowSelected( nil, Row )
					end
				end
			end

			Hook.Add( "OnPluginLoad", "AdminMenu_OnPluginLoad", function( Name, Plugin, Shared )
				UpdateRow( Name, true )
			end )

			Hook.Add( "OnPluginUnload", "AdminMenu_OnPluginUnload", function( Name, Plugin, Shared )
				UpdateRow( Name, false )
			end )
		end,

		OnCleanup = function( Panel )
			TableEmpty( self.PluginRows )

			local PluginList = self.PluginList
			self.PluginList = nil

			Hook.Remove( "OnPluginLoad", "AdminMenu_OnPluginLoad" )
			Hook.Remove( "OnPluginUnload", "AdminMenu_OnPluginUnload" )

			return Shine.AdminMenu.GetListState( PluginList )
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

function Plugin:ReceivePluginTabAuthed()
	self.PluginAuthed = true
	self:PopulatePluginList()
end

function Plugin:PopulatePluginList()
	local List = self.PluginList
	if not SGUI.IsValid( List ) then return end

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
			local Row = List:AddRow( Plugin, Enabled and self:GetPhrase( "ENABLED" ) or self:GetPhrase( "DISABLED" ) )
			Row.PluginEnabled = Enabled

			self.PluginRows[ Plugin ] = Row
		end
	end
end

function Plugin:ReceivePluginData( Data )
	self.PluginData = self.PluginData or {}
	self.PluginData[ Data.Name ] = Data.Enabled

	local Row = self.PluginRows[ Data.Name ]

	if Row then
		Row:SetColumnText( 2, Data.Enabled and self:GetPhrase( "ENABLED" ) or self:GetPhrase( "DISABLED" ) )
		Row.PluginEnabled = Data.Enabled

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

	local Phrase = State > NOT_STARTED and self:GetPhrase( "ALLTALK_DISABLED" ) or self:GetPhrase( "ALLTALK_ENABLED" )

	if not self.TextObj then
		local GB = State > NOT_STARTED and 0 or 255

		self.TextObj = Shine.ScreenText.Add( "AllTalkState", {
			X = 0.5, Y = 0.95,
			Text = Phrase,
			R = 255, G = GB, B = GB,
			Alignment = 1,
			Size = 2,
			FadeIn = 1,
			IgnoreFormat = true
		} )

		return
	end

	self.TextObj.Text = Phrase

	local Col = State > NOT_STARTED and Color( 255, 0, 0 ) or Color( 255, 255, 255 )

	self.TextObj:SetColour( Col )
end

function Plugin:RemoveAllTalkText()
	if not self.TextObj then return end

	self.TextObj:End()
	self.TextObj = nil
end

function Plugin:Cleanup()
	self:RemoveAllTalkText()

	self.BaseClass.Cleanup( self )
end
