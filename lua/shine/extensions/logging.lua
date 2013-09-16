--[[
	Shine logging plugin.
]]

local StringFormat = string.format

local Plugin = {}
Plugin.Version = "1.0.3"

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
	LogEjectVotes = true
}

Plugin.CheckConfig = true

function Plugin:Initialise()
	if not Shine.Config.EnableLogging then
		return false, "Shine logging must be enabled, check your BaseConfig.json file."
	end
	
	self.Enabled = true

	return true
end

function Plugin:GetClientInfo( Client )
	if not Client then return "Console" end
	
	local Player = Client:GetControllingPlayer()
	local PlayerName = Player and Player:GetName() or "<unknown>"
	local Team = Player and Shine:GetTeamName( Player:GetTeamNumber(), true ) or "No team"

	local ID = Client.GetUserId and Client:GetUserId() or 0

	return StringFormat( "%s[%s][%s]", PlayerName, ID, Team )
end

function Plugin:ClientConfirmConnect( Client )
	if not self.Config.LogConnections then return end
	
	if not Client then return end

	if Client:GetIsVirtual() then
		Shine:LogString( "Bot added." )
		return
	end

	Shine:LogString( StringFormat( "Client %s connected.", self:GetClientInfo( Client ) ) )
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
	
	Shine:LogString( StringFormat( "%s changed their name from '%s' to '%s'.", self:GetClientInfo( Client ), OldName or "", Name ) )
end

function Plugin:PostJoinTeam( Gamerules, Player, OldTeam, NewTeam, Force )
	if not self.Config.LogTeamJoins then return end
	if not Player then return end

	local Client = Server.GetOwner( Player )
	
	local UserID = Client.GetUserId and Client:GetUserId() or 0

	Shine:LogString( StringFormat( "Player %s[%s] joined team %s.", 
		Player:GetName(),
		UserID, 
		Shine:GetTeamName( NewTeam )
	) )
end

function Plugin:PlayerSay( Client, Message )
	if not self.Config.LogChat then return end
	
	Shine:LogString( StringFormat( "%s from %s: %s", Message.teamOnly and "Team Chat" or "Chat", self:GetClientInfo( Client ), Message.message ) )
end

function Plugin:SetGameState( Gamerules, State, OldState )
	if not self.Config.LogRoundStartEnd then return end
	
	if State == kGameState.Started then
		Shine:LogString( StringFormat( "Round started. Build: %s. Map: %s.", Shared.GetBuildNumber(), Shared.GetMapName() ) )
	end
end

function Plugin:EndGame( Gamerules, WinningTeam )
	if not self.Config.LogRoundStartEnd then return end

	local Build = Shared.GetBuildNumber()
	local Map = Shared.GetMapName()

	local RoundLength = string.TimeToString( Shared.GetTime() - Gamerules.gameStartTime )
	
	local StartLoc1 = Gamerules.startingLocationNameTeam1
	local StartLoc2 = Gamerules.startingLocationNameTeam2

	local TeamString = Shine:GetTeamName( WinningTeam:GetTeamType() )

	Shine:LogString( StringFormat( "Round ended with %s winning. Build: %s. Map: %s. Round length: %s. Marine start: %s. Alien start: %s.",
		TeamString, Build, Map, RoundLength, StartLoc1, StartLoc2
	) )
end

function Plugin:FormatPosition( Pos )
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
		self:FormatPosition( AttackerPos ),
		self:FormatPosition( VictimPos )
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
		Shine:LogString( StringFormat( "%s voted to eject %s.", self:GetClientInfo( Client ), self:GetClientInfo( Target ) ) )
	end
end

function Plugin:CommLoginPlayer( Chair, Player )
	if not self.Config.LogCommanderLogin then return end
	
	Shine:LogString( StringFormat( "%s became the commander of the %s team.", 
		self:GetClientInfo( Server.GetOwner( Player ) ), 
		Shine:GetTeamName( Player:GetTeamNumber() )
	) )
end

function Plugin:CommLogout( Chair )
	if not self.Config.LogCommanderLogin then return end

	local Commander = Chair:GetCommander()
	if not Commander then return end

	Shine:LogString( StringFormat( "%s stopped commanding the %s team.",
		self:GetClientInfo( Server.GetOwner( Commander ) ),
		Shine:GetTeamName( Commander:GetTeamNumber() )
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
	
	Shine:LogString( StringFormat( "%s began recycling %s[%s].", self:GetClientInfo( Client ), Name, ID ) )
end

function Plugin:OnConstructInit( Building )
	if not self.Config.LogConstruction then return end
	
	local ID = Building:GetId()
	local Name = Building:GetClassName()
	local Team = Building:GetTeam()

	--We really don't need to know about cysts...
	if Name:lower() == "cyst" then return end

	if not Team or not Team.GetCommander then return end

	local Owner = Building:GetOwner()
	Owner = Owner or Team:GetCommander()

	if not Owner then return end
	
	local Client = Server.GetOwner( Owner )
	Shine:LogString( StringFormat( "%s began construction of %s[%s].", self:GetClientInfo( Client ), Name, ID ) )
end

function Plugin:Cleanup()
	self.Enabled = false
end

Shine:RegisterExtension( "logging", Plugin )
