--[[
	Shine pregame plugin shared.
]]

local Plugin = {}

Plugin.NS2Only = true

function Plugin:SetupDataTable()
	self:AddNetworkMessage( "StartDelay", { StartTime = "integer" }, "Client" )
	self:AddNetworkMessage( "StartNag", { Message = "string (64)" }, "Client" )
end

Shine:RegisterExtension( "pregame", Plugin )

if Server then return end

function Plugin:ReceiveStartNag( Data )
	local Player = Client.GetLocalPlayer()

	if not Player or not HasMixin( Player, "TeamMessage" ) then return end

	Player:SetTeamMessage( Data.Message:upper() )
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
			Text = "Game start waiting for players to load.",
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
