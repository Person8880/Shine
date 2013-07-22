--[[
	Vote menu client side stuff.
]]

Script.Load( "lua/shine/core/client/votemenu_gui.lua" )

local StringFormat = string.format
local TableSort = table.sort

Shine = Shine or {}

Shine.Maps = {}
Shine.EndTime = 0

local ActivePlugins = {}
Shine.ActivePlugins = ActivePlugins

local WaitingForData = false

Client.HookNetworkMessage( "Shine_PluginData", function( Message ) 
	if #ActivePlugins > 0 then
		for i = 1, #ActivePlugins do
			ActivePlugins[ i ] = nil
		end
	end

	for Index, Data in pairs( Message ) do
		if Data then
			ActivePlugins[ #ActivePlugins + 1 ] = Index
		end
	end

	TableSort( ActivePlugins )

	if WaitingForData then
		Shine.OpenVoteMenu()

		WaitingForData = false
	end
end )

Client.HookNetworkMessage( "Shine_EndVote", function()
	Shine.EndTime = 0
end )

--[[
	Updates the binding data in case they changed it whilst connected.
]]
local function CheckForBind()
	local CustomBinds = io.open( "config://ConsoleBindings.json", "r" )

	if not CustomBinds then 
		Shine.VoteButtonBound = nil
		Shine.VoteButton = nil

		return 
	end

	local Binds = json.decode( CustomBinds:read( "*all" ) ) or {}

	CustomBinds:close()

	for Button, Data in pairs( Binds ) do
		if Data.command:find( "sh_votemenu" ) then
			Shine.VoteButtonBound = true
			Shine.VoteButton = Button
			return
		end
	end

	Shine.VoteButtonBound = nil
	Shine.VoteButton = nil
end

function Shine.OpenVoteMenu()
	local VoteMenu = Shine.VoteMenu

	if VoteMenu.Visible then
		VoteMenu:SetIsVisible( false )

		return
	end

	VoteMenu:SetIsVisible( true )

	local Time = Shared.GetTime()

	if ( Shine.NextVoteOptionRequest or 0 ) < Time and Shine.EndTime < Time then
		Shine.NextVoteOptionRequest = Time + 10

		Client.SendNetworkMessage( "Shine_RequestVoteOptions", { Cake = 0 }, true )
	end

	Client.SendNetworkMessage( "Shine_OpenedVoteMenu", {}, true )
	Shine.Hook.Call( "OnVoteMenuOpen" )
end

Event.Hook( "Console_sh_votemenu", function()
	if #ActivePlugins == 0 then --Request addon list if our table is empty.
		Client.SendNetworkMessage( "Shine_RequestPluginData", { Bleh = 0 }, true )

		WaitingForData = true

		return 
	end
	
	Shine.OpenVoteMenu()
end )

Client.HookNetworkMessage( "Shine_VoteMenu", function( Message )
	CheckForBind()

	local Duration = Message.Duration
	local NextMap = Message.NextMap == 1
	local TimeLeft = Message.TimeLeft

	local Options = Message.Options

	Shine.Maps = string.Explode( Options, ", " )
	Shine.EndTime = Shared.GetTime() + Duration

	local ButtonBound = Shine.VoteButtonBound
	local VoteButton = Shine.VoteButton or "M"

	local VoteMessage

	if ButtonBound then
		VoteMessage = StringFormat( "%s Press %s to vote.\nTime left to vote:", 
			NextMap and "Voting for the next map has begun." or "Map vote has begun.",
			VoteButton ).." %s." 
	else 
		VoteMessage = StringFormat( "%s\nMaps: %s\nType !vote <map> to vote.\nTime left to vote:", 
			NextMap and "Voting for the next map has begun." or "Map vote has begun.",
			Options ).." %s."
	end

	if NextMap and TimeLeft > 0 then
		VoteMessage = VoteMessage.."\nTime left on the current map: %s."
	end

	if NextMap then
		local ScreenText = Shine:AddMessageToQueue( 1, 0.95, 0.2, VoteMessage, Duration, 255, 0, 0, 2, nil, nil, true )

		ScreenText.TimeLeft = TimeLeft

		ScreenText.Obj:SetText( StringFormat( ScreenText.Text, string.TimeToString( ScreenText.Duration ), string.TimeToString( ScreenText.TimeLeft ) ) )

		function ScreenText:UpdateText()
			self.Obj:SetText( StringFormat( self.Text, string.TimeToString( self.Duration ), string.TimeToString( self.TimeLeft ) ) )
		end

		function ScreenText:Think()
			self.TimeLeft = self.TimeLeft - 1

			if self.Duration == Duration - 10 then
				self.Colour = Color( 1, 1, 1 )
				self.Obj:SetColor( self.Colour )

				if ButtonBound then
					self.Text = StringFormat( "Vote for the next map in progress. Press %s to vote.\nTime left to vote:", VoteButton ).." %s."
				else 
					self.Text = StringFormat( "Vote for the next map in progress.\nMaps: %s\nType !vote <map> to vote.\nTime left to vote:", Options ).." %s."
				end

				if self.TimeLeft > 0 then
					self.Text = self.Text.."\nTime left on the current map: %s."
				end

				self.Obj:SetText( StringFormat( self.Text, string.TimeToString( self.Duration ), string.TimeToString( self.TimeLeft ) ) )

				return
			end

			if self.Duration == 10 then
				self.Colour = Color( 1, 0, 0 )
				self.Obj:SetColor( self.Colour )
			end
		end
	else
		local ScreenText = Shine:AddMessageToQueue( 1, 0.95, 0.2, VoteMessage, Duration, 255, 0, 0, 2 )

		ScreenText.Obj:SetText( StringFormat( ScreenText.Text, string.TimeToString( ScreenText.Duration ) ) )

		function ScreenText:Think()
			if self.Duration == Duration - 10 then
				self.Colour = Color( 1, 1, 1 )
				self.Obj:SetColor( self.Colour )

				if ButtonBound then
					self.Text = StringFormat( "Map vote in progress. Press %s to vote.\nTime left to vote:", VoteButton ).." %s."
				else 
					self.Text = StringFormat( "Map vote in progress.\nMaps: %s\nType !vote <map> to vote.\nTime left to vote:", Options ).." %s."
				end

				self.Obj:SetText( StringFormat( self.Text, string.TimeToString( self.Duration ) ) )

				return
			end

			if self.Duration == 10 then
				self.Colour = Color( 1, 0, 0 )
				self.Obj:SetColor( self.Colour )
			end
		end
	end

	Shine.SentVote = false
end )

local function CanBind( MenuBinds, Binds, Button )
	for i = 1, #MenuBinds do --Main menu binds.
		if MenuBinds[ i ].current == Button then
			return false
		end
	end

	if not Binds then return true end --No custom binds file.

	if not Binds[ Button ] then return true end

	if Binds[ Button ].command == "" then return true end

	return false
end

local function BindVoteKey()
	local MenuBinds = BindingsUI_GetBindingsTable()

	local CustomBinds = io.open( "config://ConsoleBindings.json", "r" )

	local Binds

	if CustomBinds then
		Binds = json.decode( CustomBinds:read( "*all" ) ) or {}

		CustomBinds:close()

		for Button, Data in pairs( Binds ) do
			if Data.command and Data.command:find( "sh_votemenu" ) then
				Shine.VoteButtonBound = true
				Shine.VoteButton = Button
				return
			end
		end
	end

	if CanBind( MenuBinds, Binds, "M" ) then --This is now the default map button...
		Shared.ConsoleCommand( "bind M sh_votemenu" )
		Shine.VoteButtonBound = true

		Shared.Message( "Shine has bound the M key to the vote menu. If you would like to change this, type bind <key> sh_votemenu" )

		return
	elseif CanBind( MenuBinds, Binds, "N" ) then
		Shared.ConsoleCommand( "bind N sh_votemenu" )
		
		Shine.VoteButton = "N"
		Shine.VoteButtonBound = true

		Shared.Message( "Shine has bound the N key to the vote menu. If you would like to change this, type bind <key> sh_votemenu" )

		return
	elseif CanBind( MenuBinds, Binds, "C" ) then --Try the old default map button!
		Shared.ConsoleCommand( "bind C sh_votemenu" )
		
		Shine.VoteButton = "C"
		Shine.VoteButtonBound = true

		Shared.Message( "Shine has bound the C key to the vote menu. If you would like to change this, type bind <key> sh_votemenu" )

		return
	end

	Shared.Message( "Shine was unable to bind a key to the vote menu. If you would like to use it, type bind <key> sh_votemenu" )
end
Event.Hook( "LoadComplete", BindVoteKey )

local function OverrideNS2StatsText()
	if not RBPS then return end
	--Taken straight from the NS2stats code, just modified the starting height.
	function RBPS:clientShowNextAward( id )
		local addY = id * 22
		local col = Color( 230/255, 230/255, 0/255 )             
		
		Cout:addClientTextMessage(Client.GetScreenWidth() * 6/8,(Client.GetScreenHeight() * 1/3) + addY
			,RBPSclientAwards[id],30-id, col, "awardmsg" .. id)                    
	end
end
Event.Hook( "LoadComplete", OverrideNS2StatsText ) 
