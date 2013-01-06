--[[
	Vote menu client side stuff.
]]

local StringFormat = string.format

Shine = Shine or {}

Shine.Maps = {}
Shine.EndTime = 0

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
	
	local Message = Shine:AddMessageToQueue( 1, 0.95, 0.05, VoteMessage, Duration, 255, 0, 0, 2 )

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
end )

local Menu

Event.Hook( "Console_sh_votemenu", function( Client )
	if Shine.EndTime < Shared.GetTime() then return end
	
	local Manager = GetGUIManager()

	if Menu then
		Manager:DestroyGUIScript( Menu )

		Menu = nil

		return
	end

	Menu = Manager:CreateGUIScript( "GUIShineVoteMenu" )
	Menu:Populate()

	Menu:SetIsVisible( true )
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

			return
		end
	end

	if CantBind then return end

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
			end
		else
			Shared.ConsoleCommand( "bind M sh_votemenu" )
			Shine.VoteButtonBound = true
		end
	end
end

Event.Hook( "LoadComplete", BindVoteKey )

