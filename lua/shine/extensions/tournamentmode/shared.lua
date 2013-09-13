--[[
	Tournament mode shared.
]]

local Plugin = {}

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
end

--[[
	Set the insight values when we receive them.
]]
function Plugin:NetworkUpdate( Key, Old, New )
	if Server then return end
	
	--Using team1 or team2 resets the other team's name...
	if Key == "MarineName" and New ~= "" then
		Shared.ConsoleCommand( StringFormat( "teams %s %s", New, self.dt.AlienName ) )
	elseif Key == "AlienName" and New ~= "" then
		Shared.ConsoleCommand( StringFormat( "teams %s %s", self.dt.MarineName, New ) )
	elseif Key == "MarineScore" then
		Shared.ConsoleCommand( StringFormat( "score1 %i", New ) )
	elseif Key == "AlienScore" then
		Shared.ConsoleCommand( StringFormat( "score2 %i", New ) )
	end
end

Shine:RegisterExtension( "tournamentmode", Plugin )

if Server then return end
