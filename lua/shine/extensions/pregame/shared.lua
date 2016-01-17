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
			TeamWithCommander = "integer (0 to 3)",
			TeamWithoutCommander = "integer (0 to 3)",
			TimeLeft = "integer"
		},
		Duration = {
			Duration = "integer"
		}
	}

	self:AddNetworkMessages( "AddTranslatedNotify", {
		[ MessageTypes.Empty ] = {
			"WaitingForBoth"
		},
		[ MessageTypes.Team ] = {
			"ABORT_EMPTY_TEAM", "WaitingForTeam"
		},
		[ MessageTypes.Duration ] = {
			"EXCEEDED_TIME", "GameStartsSoon", "GameStarting"
		},
		[ MessageTypes.CommanderAdd ] = {
			"TeamHasCommander"
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
	self:SetTeamMessage( self:GetInterpolatedPhrase( "WAITING_FOR_TEAM", Data ) )
end

function Plugin:ReceiveWaitingForBoth( Data )
	self:SetTeamMessage( self:GetPhrase( "WAITING_FOR_BOTH" ) )
end

function Plugin:ReceiveTeamHasCommander( Data )
	Shine.ScreenText.Add( 2, {
		X = 0.5, Y = 0.7,
		Text = self:GetInterpolatedPhrase( "TEAM_HAS_COMMANDER", Data ),
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
