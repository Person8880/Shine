--[[
	Base commands shared.
]]

local Plugin = {}

function Plugin:SetupDataTable()
	self:AddDTVar( "integer (1 to 10)", "Gamestate", 1 )
	self:AddDTVar( "boolean", "AllTalk", false )

	self:AddNetworkMessage( "RequestMapData", {}, "Server" )
	self:AddNetworkMessage( "MapData", { Name = "string (32)" }, "Client" )
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

local SGUI = Shine.GUI

local StringFormat = string.format

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

	self:AddAdminMenuCommand( Category, "Eject", "sh_eject", false )
	self:AddAdminMenuCommand( Category, "Kick", "sh_kick", false, {
		"No Reason", "",
		"Trolling", "Trolling.",
		"Offensive language", "Offensive language",
		"Mic spamming", "Mic spamming."
	} )
	self:AddAdminMenuCommand( Category, "Gag", "sh_gag", false, {
		"5 minutes", "300",
		"10 minutes", "600",
		"15 minutes", "900",
		"20 minutes", "1200",
		"30 minutes", "1800",
		"Until map change", ""
	} )
	self:AddAdminMenuCommand( Category, "Ungag", "sh_ungag", false )
	self:AddAdminMenuCommand( Category, "Force Random", "sh_forcerandom", true )
	self:AddAdminMenuCommand( Category, "Ready Room", "sh_rr", true )
	local Teams = {}
	for i = 0, 3 do
		local TeamName = Shine:GetTeamName( i, true )
		i = i + 1

		Teams[ i * 2 - 1 ] = TeamName
		Teams[ i * 2 ] = tostring( i - 1 )
	end
	self:AddAdminMenuCommand( Category, "Set Team", "sh_setteam", true, Teams )

	self:AddAdminMenuTab( "Maps", {
		OnInit = function( Panel, Data )
			local List = SGUI:Create( "List", Panel )
			List:SetAnchor( GUIItem.Left, GUIItem.Top )
			List:SetPos( Vector( 16, 24, 0 ) )
			List:SetColumns( 1, "Map" )
			List:SetSpacing( 1 )
			List:SetSize( Vector( 640, 512, 0 ) )
			List.ScrollPos = Vector( 0, 32, 0 )
			
			self.MapList = List

			if not self.MapData then
				self:RequestMapData()
			else
				for Map, ID in pairs( self.MapData ) do
					List:AddRow( Map, ID )
				end
			end

			if Data and Data.SortedColumn then
				List:SortRows( Data.SortedColumn, nil, Data.Descending )
			end

			local ChangeMap = SGUI:Create( "Button", Panel )
			ChangeMap:SetAnchor( "BottomLeft" )
			ChangeMap:SetSize( Vector( 128, 32, 0 ) )
			ChangeMap:SetPos( Vector( 16, -48, 0 ) )
			ChangeMap:SetText( "Change map" )
			ChangeMap:SetFont( "fonts/AgencyFB_small.fnt" )
			function ChangeMap.DoClick()
				local Selected = List:GetSelectedRow()
				if not Selected then return end
				
				local Map = Selected:GetColumnText( 1 )

				Shared.ConsoleCommand( "sh_changelevel "..Map )
			end
			
			if Shine:IsExtensionEnabled( "mapvote" ) then
				local CallVote = SGUI:Create( "Button", Panel )
				CallVote:SetAnchor( "BottomRight" )
				CallVote:SetSize( Vector( 128, 32, 0 ) )
				CallVote:SetPos( Vector( -144, -48, 0 ) )
				CallVote:SetText( "Call Map Vote" )
				CallVote:SetFont( "fonts/AgencyFB_small.fnt" )
				function CallVote.DoClick()
					Shared.ConsoleCommand( "sh_forcemapvote" )
				end
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
