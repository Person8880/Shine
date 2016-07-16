--[[
	Shine pregame plugin shared.
]]

local Plugin = {}
Plugin.NotifyPrefixColour = {
	100, 100, 255
}

Plugin.NS2Only = true

function Plugin:SetupDataTable()
	self:AddNetworkMessage( "StartDelay", { StartTime = "integer" }, "Client" )

	local MessageTypes = {
		Empty = {},
		Team = {
			Team = "integer (0 to 3)"
		},
		CommanderAdd = {
			Team = "integer (0 to 3)",
			TimeLeft = "integer"
		},
		Duration = {
			Duration = "integer"
		},
		MinPlayers = {
			MinPlayers = "integer"
		}
	}

	self:AddNetworkMessages( "AddTranslatedNotify", {
		[ MessageTypes.Empty ] = {
			"WaitingForBoth"
		},
		[ MessageTypes.Team ] = {
			"EmptyTeamAbort", "WaitingForTeam"
		},
		[ MessageTypes.Duration ] = {
			"EXCEEDED_TIME", "GameStartsSoon", "GameStarting"
		},
		[ MessageTypes.CommanderAdd ] = {
			"TeamHasCommander"
		},
		[ MessageTypes.MinPlayers ] = {
			"WaitingForMinPlayers"
		}
	} )
end

Shine:RegisterExtension( "pregame", Plugin )

if Server then return end

function Plugin:SetTeamMessage( Message )
	local Player = Client.GetLocalPlayer()
	if not Player or not HasMixin( Player, "TeamMessage" ) then return end

	Player:SetTeamMessage( Message:UTF8Upper() )
end

function Plugin:ReceiveWaitingForTeam( Data )
	local TeamKeys = {
		"WAITING_FOR_MARINES",
		"WAITING_FOR_ALIENS"
	}
	self:SetTeamMessage( self:GetPhrase( TeamKeys[ Data.Team ] ) )
end

function Plugin:ReceiveWaitingForMinPlayers( Data )
	self:SetTeamMessage( self:GetInterpolatedPhrase( "WAITING_FOR_PLAYER_COUNT", Data ) )
end

function Plugin:ReceiveEmptyTeamAbort( Data )
	local TeamKeys = {
		"ABORT_MARINES_EMPTY",
		"ABORT_ALIENS_EMPTY"
	}
	self:Notify( self:GetPhrase( TeamKeys[ Data.Team ] ) )
end

function Plugin:ReceiveWaitingForBoth( Data )
	self:SetTeamMessage( self:GetPhrase( "WAITING_FOR_BOTH" ) )
end

function Plugin:ReceiveTeamHasCommander( Data )
	local TeamKeys = {
		"MARINES_HAVE_COMMANDER",
		"ALIENS_HAVE_COMMANDER"
	}
	Shine.ScreenText.Add( 2, {
		X = 0.5, Y = 0.7,
		Text = self:GetInterpolatedPhrase( TeamKeys[ Data.Team ], Data ),
		Duration = 5,
		R = 255, G = 255, B = 255,
		Alignment = 1,
		Size = 3,
		FadeIn = 1
	} )
end

function Plugin:ReceiveGameStartsSoon( Data )
	Shine.ScreenText.Add( 2, {
		X = 0.5, Y = 0.7,
		Text = self:GetInterpolatedPhrase( "GAME_START_SOON", Data ),
		Duration = 5,
		R = 255, G = 255, B = 255,
		Alignment = 1,
		Size = 3,
		FadeIn = 1
	} )
end

function Plugin:ReceiveGameStarting( Data )
	Shine.ScreenText.Add( 2, {
		X = 0.5, Y = 0.7,
		Text = self:GetPhrase( "GAME_START" ),
		Duration = Data.Duration,
		R = 255, G = 0, B = 0,
		Alignment = 1,
		Size = 3,
		FadeIn = 0
	} )
end

local DigitalTime = string.DigitalTime
local Round = math.Round
local SharedTime = Shared.GetTime

function Plugin:RemoveText()
	if self.TextObj then
		self.TextObj:Remove()
		self.TextObj = nil
	end

	if self.TimeObj then
		self.TimeObj:Remove()
		self.TimeObj = nil
	end
end

function Plugin:ReceiveStartDelay( Data )
	local StartTime = Data.StartTime
	local Time = SharedTime()

	if Time < StartTime then
		local Duration = Round( StartTime - Time )

		self.TextObj = Shine.ScreenText.Add( "PreGameStartDelay1", {
			X = 0.5, Y = 0.1,
			Text = self:GetPhrase( "WAITING_FOR_PLAYERS" ),
			Duration = Duration,
			R = 255, G = 255, B = 255,
			Alignment = 1,
			Size = 1,
			FadeIn = 1,
			IgnoreFormat = true
		} )
		self.TimeObj = Shine.ScreenText.Add( "PreGameStartDelay2", {
			X = 0.5, Y = 0.126,
			Text = "%s",
			Duration = Duration,
			R = 255, G = 255, B = 255,
			Alignment = 1,
			Size = 1,
			FadeIn = 1
		} )

		self.TimeObj.Digital = true
		self.TimeObj.Obj:SetText( DigitalTime( Duration ) )
	else
		self:RemoveText()
	end
end

function Plugin:Cleanup()
	self.BaseClass.Cleanup( self )

	self:RemoveText()
end
