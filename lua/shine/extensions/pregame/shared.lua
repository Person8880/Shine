--[[
	Shine pregame plugin shared.
]]

local Plugin = {}

function Plugin:SetupDataTable()
	self:AddNetworkMessage( "StartDelay", { StartTime = "integer" }, "Client" )
end

Shine:RegisterExtension( "pregame", Plugin )

if Server then return end

local DigitalTime = string.DigitalTime
local Round = math.Round
local SharedTime = Shared.GetTime

function Plugin:RemoveText()
	if self.TextObj then
		Shine:RemoveMessage( self.TextObj.Index )
		self.TextObj = nil
	end

	if self.TimeObj then
		Shine:RemoveMessage( self.TimeObj.Index )
		self.TimeObj = nil
	end
end

function Plugin:ReceiveStartDelay( Data )
	local StartTime = Data.StartTime
	local Time = SharedTime()

	if Time < StartTime then
		local Duration = Round( StartTime - Time )
		local TextObj = Shine:AddMessageToQueue( "PreGameStartDelay1", 0.5, 0.1,
			"Game start waiting for players to load.", Duration, 255, 255, 255,
			1, 1, 1, true )
		local TimeObj = Shine:AddMessageToQueue( "PreGameStartDelay2", 0.5, 0.126,
			"%s", Duration, 255, 255, 255, 1, 1, 1 )

		self.TextObj = TextObj
		self.TimeObj = TimeObj

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
