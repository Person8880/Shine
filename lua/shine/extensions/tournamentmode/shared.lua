--[[
	Tournament mode shared.
]]

local Plugin = Shine.Plugin( ... )

Plugin.EnabledGamemodes = {
	[ "ns2" ] = true
}

local StringFormat = string.format

--[[
	We network the team names and the scores, so spectators that join
	get their spectator HUD instantly updated without needing to set it
	manually again.
]]
function Plugin:SetupDataTable()
	self:AddDTVar( "string (25)", "MarineName", "" )
	self:AddDTVar( "string (25)", "AlienName", "" )

	self:AddDTVar( "integer (0 to 255)", "MarineScore", 0 )
	self:AddDTVar( "integer (0 to 255)", "AlienScore", 0 )

	local TeamField = "integer (1 to 2)"

	self:AddNetworkMessage( "StartNag", { WaitingTeam = "integer (0 to 2)" }, "Client" )
	self:AddNetworkMessage( "TeamReadyChange", {
		Team = TeamField,
		IsReady = "boolean"
	}, "Client" )
	self:AddNetworkMessage( "GameStartCountdown", {
		IsFinalCountdown = "boolean",
		CountdownTime = "integer"
	}, "Client" )
	self:AddNetworkMessage( "GameStartAborted", {}, "Client" )
	self:AddNetworkMessage( "TeamPlayerNotReady", {
		Team = TeamField,
		PlayerName = self:GetNameNetworkField()
	}, "Client" )
	self:AddNetworkMessage( "PlayerReadyChange", {
		PlayerName = self:GetNameNetworkField(),
		IsReady = "boolean"
	}, "Client" )
	self:AddNetworkMessage( "TeamReadyWaiting", {
		ReadyTeam = TeamField,
		WaitingTeam = TeamField
	}, "Client" )
end

return Plugin
