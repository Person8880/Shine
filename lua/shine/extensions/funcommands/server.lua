--[[
	Shine fun commands plugin.
]]

local StringFind = string.find
local StringLower = string.lower

local Plugin = ...
Plugin.Version = "1.1"

function Plugin:Initialise()
	self:CreateCommands()

	self.Enabled = true

	return true
end

function Plugin:MovePlayerToPosition( Player, Pos )
	local TechID = kTechId.Skulk
	if Player:GetIsAlive() then
		TechID = Player:GetTechId()
	end

	local Bounds = LookupTechData( TechID, kTechDataMaxExtents )
	if not Bounds then return false end

	-- Start the trace from the player's eye level rather than the ground to avoid small obstacles on the floor blocking
	-- the trace.
	Pos = Pos + Player:GetCoords().yAxis * Player:GetViewOffset().y

	local Height, Radius = GetTraceCapsuleFromExtents( Bounds )
	local Range = 6
	local Filter = EntityFilterAll()

	for i = 1, 10 do
		local SpawnPoint = GetRandomSpawnForCapsule( Height, Radius, Pos, 2, Range, Filter )
		if SpawnPoint then
			SpawnPlayerAtPoint( Player, SpawnPoint )
			return true
		end
	end

	return false
end

function Plugin:MovePlayerToPlayer( Player, TargetPlayer )
	return self:MovePlayerToPosition( Player, TargetPlayer:GetOrigin() )
end

function Plugin:MovePlayerToEntityAtLocation( Player, ClassName, LocationID )
	local Entities = Shared.GetEntitiesWithClassname( ClassName )
	for _, Entity in ientitylist( Entities ) do
		if Entity:GetLocationId() == LocationID and self:MovePlayerToPosition( Player, Entity:GetOrigin() ) then
			return true
		end
	end
	return false
end

function Plugin:MovePlayerToLocation( Player, TargetLocation )
	local LocationID = Shared.GetStringIndex( TargetLocation )
	return self:MovePlayerToEntityAtLocation( Player, "TechPoint", LocationID ) or
		self:MovePlayerToEntityAtLocation( Player, "ResourcePoint", LocationID ) or
		self:MovePlayerToEntityAtLocation( Player, "PowerPoint", LocationID )
end

function Plugin:CreateCommands()
	local function Slay( Client, Targets )
		for i = 1, #Targets do
			local Player = Targets[ i ]:GetControllingPlayer()
			if Player then
				Player:Kill( nil, nil, Player:GetOrigin() )
			end
		end
		self:SendTranslatedMessage( Client, "SLAYED", {
			TargetCount = #Targets
		} )
	end
	local SlayCommand = self:BindCommand( "sh_slay", "slay", Slay )
	SlayCommand:AddParam{ Type = "clients" }
	SlayCommand:Help( "Slays the given player(s)." )

	local function GoTo( Client, Target )
		if not Client then return end

		local TargetPlayer = Target:GetControllingPlayer()
		local Player = Client:GetControllingPlayer()
		if not Player or not TargetPlayer then return end

		if not self:MovePlayerToPlayer( Player, TargetPlayer ) then
			self:NotifyTranslatedCommandError( Client, "ERROR_CANT_GOTO" )
		else
			self:SendTranslatedMessage( Client, "TELEPORTED_GOTO", {
				TargetName = TargetPlayer:GetName() or "<unknown>"
			} )
		end
	end
	local GoToCommand = self:BindCommand( "sh_goto", "goto", GoTo )
	GoToCommand:AddParam{ Type = "client", NotSelf = true, IgnoreCanTarget = true }
	GoToCommand:Help( "Moves you to the given player." )

	local LocationNames
	local function GetLocationNames()
		if not LocationNames then
			LocationNames = Shine.Map()

			local Locations = GetLocations()
			for i = 1, #Locations do
				local Name = Locations[ i ]:GetName()
				LocationNames:Add( StringLower( Name ), Name )
			end
		end
		return LocationNames
	end

	local function FindLocationWithName( LocationName )
		local Locations = GetLocationNames()
		local BestMatch = Locations:Get( LocationName )
		if not BestMatch then
			local BestMatchIndex = math.huge
			for LowerCaseName, Name in Locations:Iterate() do
				local StartIndex = StringFind( LowerCaseName, LocationName, 1, true )
				if StartIndex and StartIndex < BestMatchIndex then
					BestMatchIndex = StartIndex
					BestMatch = Name
				end
			end
		end
		return BestMatch
	end

	local function SuggestLocations()
		local NamesMap = GetLocationNames()
		local Names = {}
		local Count = 0
		for LowerCaseName, Name in NamesMap:Iterate() do
			Count = Count + 1
			Names[ Count ] = Name
		end
		return Names
	end

	local function GoToLocation( Client, LocationName )
		if not Client then return end

		local Player = Client:GetControllingPlayer()
		if not Player then return end

		local ActualLocationName = FindLocationWithName( StringLower( LocationName ) )
		if ActualLocationName and self:MovePlayerToLocation( Player, ActualLocationName ) then
			self:SendTranslatedMessage( Client, "TELEPORTED_GOTO_LOCATION", {
				LocationID = Shared.GetStringIndex( ActualLocationName )
			} )
		else
			self:NotifyTranslatedCommandError( Client, "ERROR_CANT_GOTO_LOCATION" )
		end
	end
	local GoToLocationCommand = self:BindCommand( "sh_goto_location", "gotoloc", GoToLocation )
	GoToLocationCommand:AddParam{
		Type = "string",
		TakeRestOfLine = true,
		AutoCompletions = SuggestLocations
	}
	GoToLocationCommand:Help( "Moves you to the given location name." )

	local function SendTo( Client, Source, Target )
		if Source == Target then
			if Client then
				self:NotifyTranslatedCommandError( Client, "ERROR_CANT_SEND_TO_SELF" )
			else
				Print( "You cannot send a player to themselves." )
			end
			return
		end

		local SourcePlayer = Source:GetControllingPlayer()
		local TargetPlayer = Target:GetControllingPlayer()
		if not SourcePlayer or not TargetPlayer then return end

		if not self:MovePlayerToPlayer( SourcePlayer, TargetPlayer ) then
			if Client then
				self:NotifyTranslatedCommandError( Client, "ERROR_CANT_GOTO" )
			else
				Print( "Failed to find a valid location near the specified player." )
			end
		else
			self:SendTranslatedMessage( Client, "TELEPORTED_SENT_TO", {
				SourceName = SourcePlayer:GetName() or "<unknown>",
				TargetName = TargetPlayer:GetName() or "<unknown>"
			} )
		end
	end
	local SendToCommand = self:BindCommand( "sh_sendto", "sendto", SendTo )
	SendToCommand:AddParam{ Type = "client" }
	SendToCommand:AddParam{ Type = "client", IgnoreCanTarget = true }
	SendToCommand:Help( "Moves the given player to the given target player." )

	local function SendToLocation( Client, Target, LocationName )
		local TargetPlayer = Target:GetControllingPlayer()
		if not TargetPlayer then return end

		local ActualLocationName = FindLocationWithName( StringLower( LocationName ) )
		if ActualLocationName and self:MovePlayerToLocation( TargetPlayer, ActualLocationName ) then
			self:SendTranslatedMessage( Client, "TELEPORTED_SENT_TO_LOCATION", {
				LocationID = Shared.GetStringIndex( ActualLocationName ),
				TargetName = TargetPlayer:GetName() or "<unknown>"
			} )
		else
			if Client then
				self:NotifyTranslatedCommandError( Client, "ERROR_CANT_GOTO_LOCATION" )
			else
				Print( "Failed to find a valid position at the specified location." )
			end
		end
	end
	local SendToLocationCommand = self:BindCommand( "sh_sendto_location", "sendtoloc", SendToLocation )
	SendToLocationCommand:AddParam{ Type = "client" }
	SendToLocationCommand:AddParam{
		Type = "string",
		TakeRestOfLine = true,
		AutoCompletions = SuggestLocations
	}
	SendToLocationCommand:Help( "Moves the given player to the given location name." )

	local function Bring( Client, Target )
		if not Client then return end

		local TargetPlayer = Target:GetControllingPlayer()
		local Player = Client:GetControllingPlayer()

		if not Player or not TargetPlayer then return end

		if not self:MovePlayerToPlayer( TargetPlayer, Player ) then
			self:NotifyTranslatedCommandError( Client, "ERROR_CANT_BRING" )
		else
			self:SendTranslatedMessage( Client, "TELEPORTED_BRING", {
				TargetName = TargetPlayer:GetName() or "<unknown>"
			} )
		end
	end
	local BringCommand = self:BindCommand( "sh_bring", "bring", Bring )
	BringCommand:AddParam{ Type = "client", NotSelf = true }
	BringCommand:Help( "Moves the given player to your location." )

	local function DarwinMode( Client, Targets, Enable )
		local TargetCount = 0
		local OriginalTargetCount = #Targets

		for i = 1, OriginalTargetCount do
			local Player = Targets[ i ]:GetControllingPlayer()
			if Player and Player.SetDarwinMode then
				TargetCount = TargetCount + 1
				Player:SetDarwinMode( Enable )
			end
		end

		if TargetCount > 0 then
			self:SendTranslatedMessage( Client, Enable and "GRANTED_DARWIN_MODE" or "REVOKED_DARWIN_MODE", {
				TargetCount = TargetCount
			} )

			if not Client then
				Print(
					"%s darwin mode on %d player%s.",
					Enable and "Enabled" or "Disabled",
					TargetCount,
					TargetCount == 1 and "" or "s"
				)
			end
		else
			if Client then
				self:NotifyTranslatedCommandError( Client, "ERROR_CANT_SET_DARWIN_MODE" )
			else
				Print(
					"Failed to set darwin mode on the specified player%s.",
					OriginalTargetCount == 1 and "" or "s"
				)
			end
		end
	end
	local DarwinModeCommand = self:BindCommand( "sh_darwin", { "god", "darwin" }, DarwinMode )
	DarwinModeCommand:AddParam{ Type = "clients" }
	DarwinModeCommand:AddParam{ Type = "boolean", Optional = true, Default = true }
	DarwinModeCommand:Help( "Enables or disables Darwin mode on the given players (unlimited health and ammo)." )
end
