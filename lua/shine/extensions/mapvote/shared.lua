--[[
	Shared stuff.
]]

local Plugin = {}

local VoteOptionsMessage = {
	Options = "string (255)",
	Duration = "integer (0 to 1800)",
	NextMap = "boolean",
	ShowTime = "boolean",
	TimeLeft = "integer (0 to 32768)"
}

local MapVotesMessage = {
	Map = "string (255)",
	Votes = "integer (0 to 255)"
}

Shine:RegisterExtension( "mapvote", Plugin )

function Plugin:SetupDataTable()
	self:AddNetworkMessage( "VoteOptions", VoteOptionsMessage, "Client" )
	self:AddNetworkMessage( "EndVote", {}, "Client" )
	self:AddNetworkMessage( "VoteProgress", MapVotesMessage, "Client" )

	self:AddNetworkMessage( "RequestVoteOptions", {}, "Server" )
end

if Server then
	function Plugin:ReceiveRequestVoteOptions( Client, Message )
		self:SendVoteData( Client )
	end

	return
end

local Shine = Shine
local SGUI = Shine.GUI

local StringExplode = string.Explode
local StringFormat = string.format
local TableEmpty = table.Empty

Plugin.Maps = {}
Plugin.MapButtons = {}
Plugin.MapVoteCounts = {}
Plugin.EndTime = 0

function Plugin:Initialise()
	self.Enabled = true

	return true
end

function Plugin:OnVoteMenuOpen()
	local Time = Shared.GetTime()

	if ( self.NextVoteOptionRequest or 0 ) < Time and self.EndTime < Time then
		self.NextVoteOptionRequest = Time + 10

		self:SendNetworkMessage( "RequestVoteOptions", {}, true )
	end
end

Shine.VoteMenu:EditPage( "Main", function( self )
	local Time = Shared.GetTime()

	if ( Plugin.EndTime or 0 ) > Time then
		self:AddTopButton( "Vote", function()
			self:SetPage( "MapVote" )
		end )
	end
end, function( self )
	local TopButton = self.Buttons.Top

	local Time = Shared.GetTime()

	if Plugin.EndTime > Time then
		if not SGUI.IsValid( TopButton ) or not TopButton:GetIsVisible() then
			self:AddTopButton( "Vote", function()
				self:SetPage( "MapVote" )
			end )
		end
	elseif Plugin.EndTime < Time then
		if SGUI.IsValid( TopButton ) and TopButton:GetIsVisible() then
			TopButton:SetIsVisible( false )
		end
	end
end )

local function SendMapVote( MapName )
	if Shine.VoteMenu.GetCanSendVote() then
		if not Plugin.SentVote then
			Shared.ConsoleCommand( "sh_vote "..MapName )
			Plugin.SentVote = true
		else
			Shared.ConsoleCommand( "sh_revote "..MapName )
		end

		return true
	end

	return false
end

Shine.VoteMenu:AddPage( "MapVote", function( self )
	local Maps = Plugin.Maps
	if not Maps then
		return
	end

	local NumMaps = #Maps

	for i = 1, NumMaps do
		local Map = Maps[ i ]
		local Votes = Plugin.MapVoteCounts[ Map ]

		local Text = StringFormat( "%s (%i)", Map, Votes )

		Plugin.MapButtons[ Map ] = self:AddSideButton( Text, function()
			if SendMapVote( Map ) then
				self:SetIsVisible( false )
			else
				return false
			end
		end )
	end

	self:AddTopButton( "Back", function()
		self:SetPage( "Main" )
	end )
end, function( self )
	local Time = Shared.GetTime()

	if Plugin.EndTime < Time then
		self:SetPage( "Main" )
	end
end )

function Plugin:ReceiveVoteProgress( Data )
	local MapName = Data.Map
	local Votes = Data.Votes

	self.MapVoteCounts[ MapName ] = Votes

	local MapButton = self.MapButtons[ MapName ]

	if SGUI.IsValid( MapButton ) and MapButton:GetText():find( MapName, 1, true ) then
		MapButton:SetText( StringFormat( "%s (%i)", MapName, Votes ) )
	end
end

function Plugin:ReceiveEndVote( Data )
	self.EndTime = 0

	TableEmpty( self.MapVoteCounts )
	TableEmpty( self.MapButtons )
end

local ButtonBoundMessage =
[[%s. Press %s to vote.
Time left to vote: %%s.]]

local ButtonUnboundMessage =
[[%s.
Maps: %s.
Type !vote <map> to vote.
Time left to vote: %%s.
Bind a key to sh_votemenu to make voting easier.]]

function Plugin:ReceiveVoteOptions( Message )
	Shine.CheckVoteMenuBind()

	local Duration = Message.Duration
	local NextMap = Message.NextMap
	local TimeLeft = Message.TimeLeft
	local ShowTimeLeft = Message.ShowTime

	local Options = Message.Options

	local Maps = StringExplode( Options, ", " )

	self.Maps = Maps
	self.EndTime = Shared.GetTime() + Duration

	for i = 1, #Maps do
		local Map = Maps[ i ]

		if not self.MapVoteCounts[ Map ] then
			self.MapVoteCounts[ Map ] = 0
		end
	end

	local ButtonBound = Shine.VoteButtonBound
	local VoteButton = Shine.VoteButton or "M"

	local VoteMessage

	if ButtonBound then
		VoteMessage = StringFormat( ButtonBoundMessage,
			NextMap and "Voting for the next map has begun" or "Map vote has begun",
			VoteButton )
	else
		VoteMessage = StringFormat( ButtonUnboundMessage,
			NextMap and "Voting for the next map has begun." or "Map vote has begun.",
			Options )
	end

	if NextMap and TimeLeft > 0 and ShowTimeLeft then
		VoteMessage = VoteMessage.."\nTime left on the current map: %s."
	end

	if NextMap and ShowTimeLeft then
		local ScreenText = Shine:AddMessageToQueue( 1, 0.95, 0.2,
			VoteMessage, Duration, 255, 0, 0, 2, nil, nil, true )

		ScreenText.TimeLeft = TimeLeft

		ScreenText.Obj:SetText( StringFormat( ScreenText.Text,
			string.TimeToString( ScreenText.Duration ),
			string.TimeToString( ScreenText.TimeLeft ) ) )

		function ScreenText:UpdateText()
			self.Obj:SetText( StringFormat( self.Text,
				string.TimeToString( self.Duration ),
				string.TimeToString( self.TimeLeft ) ) )
		end

		function ScreenText:Think()
			self.TimeLeft = self.TimeLeft - 1

			if self.Duration == Duration - 10 then
				self.Colour = Color( 1, 1, 1 )
				self.Obj:SetColor( self.Colour )

				local FirstLine = "Vote for the next map in progress"

				if ButtonBound then
					self.Text = StringFormat( ButtonBoundMessage, FirstLine, VoteButton )
				else
					self.Text = StringFormat( ButtonUnboundMessage, FirstLine, Options )
				end

				if self.TimeLeft > 0 then
					self.Text = self.Text.."\nTime left on the current map: %s."
				end

				self.Obj:SetText( StringFormat( self.Text, string.TimeToString( self.Duration ),
					string.TimeToString( self.TimeLeft ) ) )

				return
			end

			if self.Duration == 10 then
				self.Colour = Color( 1, 0, 0 )
				self.Obj:SetColor( self.Colour )
			end
		end
	else
		local ScreenText = Shine:AddMessageToQueue( 1, 0.95, 0.2,
			VoteMessage, Duration, 255, 0, 0, 2 )

		ScreenText.Obj:SetText( StringFormat( ScreenText.Text,
			string.TimeToString( ScreenText.Duration ) ) )

		function ScreenText:Think()
			if self.Duration == Duration - 10 then
				self.Colour = Color( 1, 1, 1 )
				self.Obj:SetColor( self.Colour )

				local FirstLine = NextMap and "Vote for the next map in progress"
					or "Map vote in progress"

				if ButtonBound then
					self.Text = StringFormat( ButtonBoundMessage, FirstLine, VoteButton )
				else
					self.Text = StringFormat( ButtonUnboundMessage, FirstLine, Options )
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

	self.SentVote = false
end
