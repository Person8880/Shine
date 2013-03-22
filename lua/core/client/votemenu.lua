--[[
	Vote menu client side stuff.
]]

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
		if Data == 1 then
			ActivePlugins[ #ActivePlugins + 1 ] = Index
		end
	end

	TableSort( ActivePlugins )

	if WaitingForData then
		Shine.OpenVoteMenu()

		WaitingForData = false
	end
end )

local Menu

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
	local Manager = GetGUIManager()

	if Menu then
		local ShouldClose = Menu.Background and Menu.Background:GetIsVisible()

		Manager:DestroyGUIScript( Menu )

		Menu = nil

		if ShouldClose then
			return
		end
	end

	Menu = Manager:CreateGUIScript( "core/client/GUIShineVoteMenu" )
	Menu:Populate( ActivePlugins )

	local Time = Shared.GetTime()

	if Shine.EndTime > Time then
		Menu:CreateVoteButton()
	elseif ( Shine.NextVoteOptionRequest or 0 ) < Time then
		Shine.NextVoteOptionRequest = Time + 10

		Client.SendNetworkMessage( "Shine_RequestVoteOptions", { Cake = 0 }, true )
	end

	Menu:SetIsVisible( true )
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
	
	local Message = Shine:AddMessageToQueue( 1, 0.95, 0.2, VoteMessage, Duration, 255, 0, 0, 2 )

	function Message:Think()
		if self.Duration == Duration - 10 then
			self.Colour = Color( 1, 1, 1 )
			self.Obj:SetColor( self.Colour )

			if ButtonBound then
				self.Text = StringFormat( "%s Press %s to vote.\nTime left to vote:", 
					NextMap and "Vote for the next map in progress." or "Map vote in progress.",
					VoteButton ).." %s."
			else 
				self.Text = StringFormat( "%s\nMaps: %s\nType !vote <map> to vote.\nTime left to vote:", 
					NextMap and "Vote for the next map in progress." or "Map vote in progress.",
					Options ).." %s."
			end

			self.Obj:SetText( StringFormat( self.Text, string.TimeToString( self.Duration ) ) )

			return
		end

		if self.Duration == 10 then
			self.Colour = Color( 1, 0, 0 )
			self.Obj:SetColor( self.Colour )
		end
	end

	Shine.SentVote = false

	if Menu then
		if not Menu.VoteButton then
			Menu:CreateVoteButton()
		end
	end
end )

local function BindVoteKey()
	local Binds = BindingsUI_GetBindingsTable()

	local CantBind
	for i = 1, #Binds do
		if Binds[ i ].current == "M" then
			CantBind = true
			break
		end
	end

	local CustomBinds = io.open( "config://ConsoleBindings.json", "r" )

	if not CustomBinds then
		if not CantBind then
			Shared.ConsoleCommand( "bind M sh_votemenu" )
			Shine.VoteButtonBound = true

			Shared.Message( "Shine has bound the M key to the vote menu. If you would like to change this, type bind <key> sh_votemenu" )

			return
		end
	end

	if CantBind then 
		Shared.Message( "Shine was unable to bind a key to the vote menu. If you would like to use it, type bind <key> sh_votemenu" )
		return 
	end

	if CustomBinds then
		local Binds = json.decode( CustomBinds:read( "*all" ) ) or {}

		CustomBinds:close()

		for Button, Data in pairs( Binds ) do
			if Data.command:find( "sh_votemenu" ) then
				Shine.VoteButtonBound = true
				Shine.VoteButton = Button
				return
			end
		end

		local MButton = Binds[ "M" ]

		if MButton then
			if MButton.command:find( "sh_votemenu" ) then
				Shine.VoteButtonBound = true
			elseif MButton.command == "" then
				Shared.ConsoleCommand( "bind M sh_votemenu" )
				Shine.VoteButtonBound = true

				Shared.Message( "Shine has bound the M key to the vote menu. If you would like to change this, type bind <key> sh_votemenu" )
			end
		else
			Shared.ConsoleCommand( "bind M sh_votemenu" )
			Shine.VoteButtonBound = true

			Shared.Message( "Shine has bound the M key to the vote menu. If you would like to change this, type bind <key> sh_votemenu" )
		end
	end

	Shared.Message( "Shine was unable to bind a key to the vote menu. If you would like to use it, type bind <key> sh_votemenu" )
end

Event.Hook( "LoadComplete", BindVoteKey )

