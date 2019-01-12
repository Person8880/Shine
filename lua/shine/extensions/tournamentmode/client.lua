--[[
	Tournament mode client.
]]

local Plugin = ...

--[[
	Set the insight values when we receive them.
]]
function Plugin:NetworkUpdate( Key, Old, New )
	-- Using team1 or team2 resets the other team's name...
	if Key == "MarineName" and New ~= "" then
		self:SetTeamNames( New, self.dt.AlienName )
	elseif Key == "AlienName" and New ~= "" then
		self:SetTeamNames( self.dt.MarineName, New )
	elseif Key == "MarineScore" then
		self:SetMarineScore( New )
	elseif Key == "AlienScore" then
		self:SetAlienScore( New )
	end
end

function Plugin:SetTeamNames( MarineName, AlienName )
	if MarineName == "" and AlienName == "" then return end

	Shared.ConsoleCommand( StringFormat( "teams \"%s\" \"%s\"", MarineName, AlienName ) )
end

function Plugin:SetMarineScore( Score )
	Shared.ConsoleCommand( StringFormat( "score1 %d", Score ) )
end

function Plugin:SetAlienScore( Score )
	Shared.ConsoleCommand( StringFormat( "score2 %d", Score ) )
end

function Plugin:Initialise()
	self:SetTeamNames( self.dt.MarineName, self.dt.AlienName )
	self:SetMarineScore( self.dt.MarineScore )
	self:SetAlienScore( self.dt.AlienScore )

	self.Enabled = true

	return true
end

function Plugin:GetTeamName( Team )
	if Team == 1 then
		return self.dt.MarineName ~= "" and self.dt.MarineName or self:GetPhrase( "MARINES" )
	end

	return self.dt.AlienName ~= "" and self.dt.AlienName or self:GetPhrase( "ALIENS" )
end

function Plugin:ReceiveStartNag( Data )
	local Player = Client.GetLocalPlayer()
	if not Player or not HasMixin( Player, "TeamMessage" ) then return end

	if Data.WaitingTeam == 0 then
		Player:SetTeamMessage( self:GetPhrase( "WAITING_FOR_BOTH_TEAMS" ) )
		return
	end

	Player:SetTeamMessage( self:GetInterpolatedPhrase( "WAITING_FOR_TEAM", {
		TeamName = self:GetTeamName( Data.WaitingTeam )
	} ) )
end

function Plugin:Notify( Positive, Message )
	self:AddChatLine( Positive and 0 or 255, Positive and 255 or 0, 0,
		self:GetPhrase( "NOTIFY_PREFIX" ), 255, 255, 255, Message )
end

function Plugin:ReceiveTeamReadyChange( Data )
	local TranslationKey = Data.IsReady and "TEAM_READY" or "TEAM_NOT_READY"

	self:Notify( Data.IsReady, self:GetInterpolatedPhrase( TranslationKey, {
		TeamName = self:GetTeamName( Data.Team )
	} ) )
end

function Plugin:ReceiveTeamReadyWaiting( Data )
	self:Notify( true, self:GetInterpolatedPhrase( "TEAM_READY_WAITING", {
		TeamName = self:GetTeamName( Data.ReadyTeam ),
		OtherTeamName = self:GetTeamName( Data.WaitingTeam )
	} ) )
end

function Plugin:ReceiveGameStartCountdown( Data )
	local TimeTillStart = Data.CountdownTime
	local ShouldCountdown = Data.IsFinalCountdown

	local Text = self:GetPhrase( "GAME_START_COUNTDOWN" )

	Shine.ScreenText.Add( "TournamentModeCountdown", {
		X = 0.5, Y = 0.7,
		Text = ShouldCountdown and Text or StringFormat( Text, string.TimeToString( TimeTillStart ) ),
		Duration = 5,
		R = 255, G = ShouldCountdown and 0 or 255, B = ShouldCountdown and 0 or 255,
		Alignment = 1,
		Size = 3,
		FadeIn = ShouldCountdown and 0 or 1
	} )
end

function Plugin:ReceiveGameStartAborted( Data )
	Shine.ScreenText.Remove( "TournamentModeCountdown" )
	self:Notify( false, self:GetPhrase( "GAME_START_ABORTED" ) )
end

function Plugin:ReceiveTeamPlayerNotReady( Data )
	self:Notify( false, self:GetInterpolatedPhrase( "TEAM_NOT_READY_PLAYER", {
		TeamName = self:GetTeamName( Data.Team ),
		PlayerName = Data.PlayerName
	} ) )
end

function Plugin:ReceivePlayerReadyChange( Data )
	local TranslationKey = Data.IsReady and "PLAYER_READY" or "PLAYER_NOT_READY"
	self:Notify( Data.IsReady, self:GetInterpolatedPhrase( TranslationKey, {
		PlayerName = Data.PlayerName
	} ) )
end
