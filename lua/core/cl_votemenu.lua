--[[
	Vote menu client side stuff.
]]

local StringFormat = string.format

Shine = Shine or {}

Shine.Maps = {}
Shine.EndTime = 0

local ActivePlugins = {}
Shine.ActivePlugins = ActivePlugins

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
end )

local Menu

Event.Hook( "Console_sh_votemenu", function( Client )
	if #ActivePlugins == 0 then return end
	
	local Manager = GetGUIManager()

	if Menu then
		local ShouldClose = Menu.Background and Menu.Background:GetIsVisible()

		Manager:DestroyGUIScript( Menu )

		Menu = nil

		if ShouldClose then
			return
		end
	end

	Menu = Manager:CreateGUIScript( "GUIShineVoteMenu" )
	Menu:Populate( ActivePlugins )
	if Shine.EndTime > Shared.GetTime() then
		Menu:CreateVoteButton()
	end

	Menu:SetIsVisible( true )
end )

Client.HookNetworkMessage( "Shine_VoteMenu", function( Message )
	local Duration = Message.Duration
	local NextMap = Message.NextMap == 1

	local Options = Message.Options

	Shine.Maps = string.Explode( Options, ", " )
	Shine.EndTime = Shared.GetTime() + Duration

	local ButtonBound = Shine.VoteButtonBound
	local VoteButton = Shine.VoteButton or "M"

	local VoteMessage

	if ButtonBound then
		VoteMessage = ButtonBound and StringFormat( "%s Press "..VoteButton.." to vote.\nTime left to vote:", NextMap and "Voting for the next map has begun." or "Map vote has begun." ).." %s." 
	else 
		VoteMessage = StringFormat( "%s\nMaps: "..Options.."\nType !vote <map> to vote.\nTime left to vote:", NextMap and "Voting for the next map has begun." or "Map vote has begun." ).." %s."
	end
	
	local Message = Shine:AddMessageToQueue( 1, 0.95, 0.2, VoteMessage, Duration, 255, 0, 0, 2 )

	function Message:Think()
		if self.Duration == Duration - 10 then
			self.Colour = Color( 1, 1, 1 )
			self.Obj:SetColor( self.Colour )

			if ButtonBound then
				self.Text = StringFormat( "%s Press "..VoteButton.." to vote.\nTime left to vote:", NextMap and "Vote for the next map in progress." or "Map vote in progress." ).." %s."
			else 
				self.Text = StringFormat( "%s\nMaps: "..Options.."\nType !vote <map> to vote.\nTime left to vote:", NextMap and "Vote for the next map in progress." or "Map vote in progress." ).." %s."
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

