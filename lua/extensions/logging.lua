--[[
	Shine logging plugin.
]]

local StringFormat = string.format

local Plugin = {}
Plugin.Version = "1.0"

function Plugin:Initialise()
	self.Enabled = true

	return true
end

function Plugin:GetTeamName( Team, Capitals )
	if Team == 1 then
		return Capitals and "Marines" or "marines"
	elseif Team == 2 then
		return Capitals and "Aliens" or "aliens"
	else
		return Capitals and "Spectate" or "spectate"
	end
end

function Plugin:GetClientInfo( Client )
	if not Client then return "Console" end
	
	local Player = Client:GetControllingPlayer()
	local PlayerName = Player and Player:GetName() or "<unknown>"
	local Team = Player and self:GetTeamName( Player:GetTeamNumber(), true ) or "No team"

	local ID = Client:GetUserId()

	return StringFormat( "%s[%s][%s]", PlayerName, ID, Team )
end

function Plugin:ClientConnect( Client )
	if not Client then return end

	if Client:GetIsVirtual() then
		Shine:LogString( "Bot added." )
		return
	end

	Shine.Timer.Simple( 2, function()
		Shine:LogString( StringFormat( "Client %s connected.", self:GetClientInfo( Client ) ) )
	end )
end

function Plugin:ClientDisconnect( Client )
	if not Client then return end
	
	if Client:GetIsVirtual() then
		Shine:LogString( "Bot removed." )
		return
	end

	Shine:LogString( StringFormat( "Client %s disconnected.", self:GetClientInfo( Client ) ) )
end

function Plugin:PlayerNameChange( Player, Name, OldName )
	if not Player or not Name then return end

	if Name == kDefaultPlayerName then return end
	if OldName == kDefaultPlayerName then return end

	local Client = Server.GetOwner( Player )
	if Client and Client:GetIsVirtual() then return end
	
	Shine:LogString( StringFormat( "%s changed their name from '%s' to '%s'.", self:GetClientInfo( Client ), OldName or "", Name ) )
end

function Plugin:JoinTeam( Gamerules, Player, NewTeam, Force )
	if not Player then return end
	
	Shine:LogString( StringFormat( "Player %s[%s] joined team %s.", 
		Player:GetName(), 
		Server.GetOwner( Player ):GetUserId(), 
		self:GetTeamName( NewTeam )
	) )
end

function Plugin:PlayerSay( Client, Message )
	Shine:LogString( StringFormat( "%s from %s: %s", Message.teamOnly and "Team Chat" or "Chat", self:GetClientInfo( Client ), Message.message ) )
end

function Plugin:SetGameState( Gamerules, State, OldState )
	if State == kGameState.Started then
		Shine:LogString( StringFormat( "Round started. Build: %s. Map: %s.", Shared.GetBuildNumber(), Shared.GetMapName() ) )
	end
end

function Plugin:EndGame( Gamerules, WinningTeam )
	local Build = Shared.GetBuildNumber()
	local Map = Shared.GetMapName()

	local RoundLength = string.TimeToString( Shared.GetTime() - Gamerules.gameStartTime )
	
	local StartLoc1 = Gamerules.startingLocationNameTeam1
	local StartLoc2 = Gamerules.startingLocationNameTeam2

	local TeamString = self:GetTeamName( WinningTeam:GetTeamType() )

	Shine:LogString( StringFormat( "Round ended with %s winning. Build: %s. Map: %s. Round length: %s. Marine start: %s. Alien start: %s.",
		TeamString, Build, Map, RoundLength, StartLoc1, StartLoc2
	) )
end

function Plugin:FormatPosition( Pos )
	local X, Y, Z = Pos.x, Pos.y, Pos.z

	return StringFormat( "(%.3f, %.3f, %.3f)", X, Y, Z )
end

function Plugin:OnEntityKilled( Gamerules, Victim, Attacker, Inflictor, Point, Dir )
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
	Shine:LogString( StringFormat( "%s became the commander of the %s team.", 
		self:GetClientInfo( Server.GetOwner( Player ) ), 
		self:GetTeamName( Player:GetTeamNumber() )
	) )
end

function Plugin:CommLogout( Chair )
	local Commander = Chair:GetCommander()
	if not Commander then return end

	Shine:LogString( StringFormat( "%s stopped commanding the %s team.",
		self:GetClientInfo( Server.GetOwner( Commander ) ),
		self:GetTeamName( Commander:GetTeamNumber() )
	) )
end

function Plugin:OnBuildingRecycled( Building, ResearchID )
	local ID = Building:GetId()
	local Name = Building:GetClassName()

	Shine:LogString( StringFormat( "%s[%s] was recycled.", Name, ID ) )
end

function Plugin:OnRecycle( Building, ResearchID )
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
	local ID = Building:GetId()
	local Name = Building:GetClassName()
	local Team = Building:GetTeam()

	if not Team then return end

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
