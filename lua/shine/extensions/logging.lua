--[[
	Shine logging plugin.
]]

local Floor = math.floor
local StringFormat = string.format
local StringSub = string.sub

local IsType = Shine.IsType

local Plugin = Shine.Plugin( ... )
Plugin.Version = "1.1"

Plugin.ConfigName = "Logging.json"
Plugin.HasConfig = true

Plugin.DefaultConfig = {
	LogConnections = true,
	LogChat = true,
	LogKills = true,
	LogConstruction = true,
	LogRecycling = true,
	LogNameChanges = true,
	LogRoundStartEnd = true,
	LogCommanderLogin = true,
	LogTeamJoins = true,
	LogEjectVotes = true,
	LogGameVotes = true
}

Plugin.CheckConfig = true
Plugin.CheckConfigTypes = true

function Plugin:Initialise()
	if not Shine.Config.EnableLogging then
		return false, "Shine logging must be enabled, check your BaseConfig.json file."
	end

	self.Enabled = true

	return true
end

function Plugin:GetClientInfo( Client, NoTeam )
	if not Client then return "Console" end

	local Player = Client:GetControllingPlayer()
	local PlayerName = Player and Player:GetName() or "<unknown>"
	local ID = Client.GetUserId and Client:GetUserId() or 0

	if not NoTeam then
		local Team = Player and Shine:GetTeamName( Player:GetTeamNumber(), true ) or "No team"

		return StringFormat( "%s[%s][%s]", PlayerName, ID, Team )
	end

	return StringFormat( "%s[%s - %s]<%s>", PlayerName, ID,
		Shine.NS2ToSteamID( ID ), IPAddressToString( Server.GetClientAddress( Client ) ) )
end

function Plugin:ClientConfirmConnect( Client )
	if not self.Config.LogConnections then return end

	if not Client then return end

	if Client:GetIsVirtual() then
		Shine:LogString( "Bot added." )
		return
	end

	Shine:LogString( StringFormat( "Client %s connected.", self:GetClientInfo( Client, true ) ) )
end

function Plugin:ClientDisconnect( Client )
	if not self.Config.LogConnections then return end

	if not Client then return end

	if Client:GetIsVirtual() then
		Shine:LogString( "Bot removed." )
		return
	end

	Shine:LogString( StringFormat( "Client %s disconnected.", self:GetClientInfo( Client ) ) )
end

function Plugin:PlayerNameChange( Player, Name, OldName )
	if not self.Config.LogNameChanges then return end
	if not Player or not Name then return end

	if Name == kDefaultPlayerName then return end
	if OldName == kDefaultPlayerName then return end

	local Client = Server.GetOwner( Player )
	if Client and Client:GetIsVirtual() then return end

	Shine:LogString( StringFormat( "%s changed their name from '%s' to '%s'.",
		self:GetClientInfo( Client ), OldName or "", Name ) )
end

function Plugin:PostJoinTeam( Gamerules, Player, OldTeam, NewTeam, Force )
	if not self.Config.LogTeamJoins then return end
	if not Player then return end

	local Client = Server.GetOwner( Player )
	if not Client then return end

	Shine:LogString( StringFormat( "Player %s joined team %s.",
		Shine.GetClientInfo( Client ),
		Shine:GetTeamName( NewTeam )
	) )
end

function Plugin:PlayerSay( Client, Message )
	if not self.Config.LogChat then return end

	Shine:LogString( StringFormat( "%s from %s: %s",
		Message.teamOnly and "Team Chat" or "Chat", self:GetClientInfo( Client ),
		Message.message ) )
end

function Plugin:SetGameState( Gamerules, State, OldState )
	if not self.Config.LogRoundStartEnd then return end

	if State == kGameState.Started then
		Shine:LogString( StringFormat( "Round started. Build: %s. Map: %s.",
			Shared.GetBuildNumber(), Shared.GetMapName() ) )
	end
end

function Plugin:EndGame( Gamerules, WinningTeam )
	if not self.Config.LogRoundStartEnd then return end
	if not Gamerules.gameStartTime then return end

	local Build = Shared.GetBuildNumber()
	local Map = Shared.GetMapName()

	local RoundLength = string.TimeToString( Shared.GetTime() - Gamerules.gameStartTime )

	local StartLoc1 = Gamerules.startingLocationNameTeam1
	local StartLoc2 = Gamerules.startingLocationNameTeam2

	local Team1Name = Shine:GetTeamName( 1, true )
	local Team2Name = Shine:GetTeamName( 2, true )

	if not WinningTeam or WinningTeam == kNeutralTeamType then
		Shine:LogString( StringFormat( "Rounded ended in a draw. Build: %s. Map: %s. Round length: %s. %s start: %s. %s start: %s.",
			Build, Map, RoundLength, Team1Name, StartLoc1, Team2Name, StartLoc2 ) )

		return
	end

	local WinnerNum = IsType( WinningTeam, "number" ) and WinningTeam
		or ( WinningTeam.GetTeamType and WinningTeam:GetTeamType() )

	if not WinnerNum then return end

	local TeamString = Shine:GetTeamName( WinnerNum )

	Shine:LogString( StringFormat( "Round ended with %s winning. Build: %s. Map: %s. Round length: %s. %s start: %s. %s start: %s.",
		TeamString, Build, Map, RoundLength, Team1Name, StartLoc1, Team2Name, StartLoc2
	) )
end

local function FormatPosition( Pos )
	local X, Y, Z = Pos.x, Pos.y, Pos.z

	return StringFormat( "(%.3f, %.3f, %.3f)", X, Y, Z )
end

function Plugin:OnEntityKilled( Gamerules, Victim, Attacker, Inflictor, Point, Dir )
	if not self.Config.LogKills then return end
	if not Attacker or not Inflictor or not Victim then return end

	local AttackerPos = Attacker:GetOrigin()
	local VictimPos = Victim:GetOrigin()

	local AttackerClient = Server.GetOwner( Attacker )
	local VictimClient = Server.GetOwner( Victim )

	Shine:LogString( StringFormat( "%s killed %s with %s. Attacker location: %s. Victim location: %s.",
		AttackerClient and self:GetClientInfo( AttackerClient ) or Attacker:GetClassName(),
		VictimClient and self:GetClientInfo( VictimClient ) or Victim:GetClassName(),
		Inflictor:GetClassName(),
		FormatPosition( AttackerPos ),
		FormatPosition( VictimPos )
	) )
end

function Plugin:CastVoteByPlayer( Gamerules, VoteTechID, Player )
	if not self.Config.LogEjectVotes then return end
	if VoteTechID ~= kTechId.VoteDownCommander1 and VoteTechID ~= kTechId.VoteDownCommander2 and VoteTechID ~= kTechId.VoteDownCommander3 then return end

	local Commanders = GetEntitiesForTeam( "Commander", Player:GetTeamNumber() )
	local Comm = VoteTechID - kTechId.VoteDownCommander1 + 1
	local CommPlayer = Commanders[ Comm ]

	if not CommPlayer then return end

	local Target = Server.GetOwner( CommPlayer )
	local Client = Server.GetOwner( Player )

	if Target and Client then
		Shine:LogString( StringFormat( "%s voted to eject %s.",
			self:GetClientInfo( Client ), self:GetClientInfo( Target ) ) )
	end
end

function Plugin:CommLoginPlayer( Chair, Player )
	if not self.Config.LogCommanderLogin then return end
	if not Player then return end

	Shine:LogString( StringFormat( "%s became the commander of the %s.",
		self:GetClientInfo( Server.GetOwner( Player ) ),
		Shine:GetTeamName( Player:GetTeamNumber(), nil, true )
	) )
end

function Plugin:CommLogout( Chair )
	if not self.Config.LogCommanderLogin then return end

	local Commander = Chair:GetCommander()
	if not Commander then return end

	Shine:LogString( StringFormat( "%s stopped commanding the %s.",
		self:GetClientInfo( Server.GetOwner( Commander ) ),
		Shine:GetTeamName( Commander:GetTeamNumber(), nil, true )
	) )
end

function Plugin:OnBuildingRecycled( Building, ResearchID )
	if not self.Config.LogRecycling then return end

	local ID = Building:GetId()
	local Name = Building:GetClassName()

	Shine:LogString( StringFormat( "%s[%s] was recycled.", Name, ID ) )
end

function Plugin:OnRecycle( Building, ResearchID )
	if not self.Config.LogRecycling then return end

	local ID = Building:GetId()
	local Name = Building:GetClassName()
	local Team = Building:GetTeam()

	if not Team then return end

	local Commander = Team:GetCommander()
	if not Commander then return end

	if ResearchID ~= kTechId.Recycle then return end

	local Client = Server.GetOwner( Commander )

	Shine:LogString( StringFormat( "%s began recycling %s[%s].",
		self:GetClientInfo( Client ), Name, ID ) )
end

function Plugin:OnConstructInit( Building )
	if not self.Config.LogConstruction then return end

	local ID = Building:GetId()
	local Name = Building:GetClassName()
	local Team = Building:GetTeam()

	-- We really don't need to know about cysts...
	if Name:lower() == "cyst" then return end

	if not Team or not Team.GetCommander then return end

	local Owner = Building:GetOwner()
	Owner = Owner or Team:GetCommander()

	if not Owner then return end

	local Client = Server.GetOwner( Owner )
	Shine:LogString( StringFormat( "%s began construction of %s[%s].",
		self:GetClientInfo( Client ), Name, ID ) )
end

Plugin.VoteStartingMessageBuilders = {
	[ "ShineCustomVote" ] = function( Client, Data )
		return StringFormat( "%s started a custom vote with question: %s", Plugin:GetClientInfo( Client ), Data.VoteQuestion )
	end,
	[ "VoteAddCommanderBots" ] = function( Client, Data )
		return StringFormat( "%s started a vote to add commander bots.", Plugin:GetClientInfo( Client ) )
	end,
	[ "VotingForceEvenTeams" ] = function( Client, Data )
		return StringFormat( "%s started a \"force even teams\" vote.", Plugin:GetClientInfo( Client ) )
	end,
	[ "VoteChangeMap" ] = function( Client, Data )
		local MapName
		if Data.map_index <= Server.GetNumMaps() then
			MapName = Server.GetMapName( Data.map_index )
		else
			-- This is a bit brittle...
			local Prefixes = { "infest", "infect" }
			local Index = Server.GetNumMaps() + 1

			for i = 1, #Prefixes do
				for j = 1, Server.GetNumMaps() do
					local Map = Server.GetMapName( j )
					if MapCycle_GetMapIsInCycle( Map ) then
						if Index == Data.map_index then
							MapName = StringFormat(
								"%s_%s",
								Prefixes[ i ],
								StringSub( Map, 5 )
							)
							break
						end
						Index = Index + 1
					end
				end

				if MapName then break end
			end
		end

		return StringFormat( "%s started a vote to change map to %s.", Plugin:GetClientInfo( Client ),
			MapName or "an unknown map" )
	end,
	[ "VoteKickPlayer" ] = function( Client, Data )
		local Target = Server.GetClientById( Data.kick_client )
		return StringFormat(
			"%s started a vote to kick %s.",
			Plugin:GetClientInfo( Client ),
			Target and Plugin:GetClientInfo( Target ) or "<unknown>"
		)
	end,
	[ "VoteRandomizeRR" ] = function( Client, Data )
		return StringFormat( "%s started a vote to randomise the ready room.", Plugin:GetClientInfo( Client ) )
	end,
	[ "VoteResetGame" ] = function( Client, Data )
		return StringFormat( "%s started a vote to reset the game.", Plugin:GetClientInfo( Client ) )
	end
}
function Plugin:OnNS2VoteStarting( VoteName, Client, Data )
	if not self.Config.LogGameVotes then return end

	local MessageBuilder = self.VoteStartingMessageBuilders[ VoteName ]
	local Message
	if MessageBuilder then
		Message = MessageBuilder( Client, Data )
	else
		Message = StringFormat( "%s started vote: %s", self:GetClientInfo( Client ), VoteName )
	end

	Shine:LogString( Message )
end

return Plugin
