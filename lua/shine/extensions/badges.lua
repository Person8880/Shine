--[[
	Override the badge mod's stuff to read from Shine's user data.
]]

local TableContains = table.contains
local TableEmpty = table.Empty
local type = type

local Plugin = {}
Plugin.Version = "1.0"

local function isstring( String )
	return type( String ) == "string"
end

local function istable( Table )
	return type( Table ) == "table"
end

function Plugin:Initialise()
	if self.Enabled ~= nil then 
		self.Enabled = true

		return true
	end
	
	Shine.Hook.Add( "Think", "ReplaceBadges", function( Deltatime )
		if not BadgeMixin then
			Shared.Message( "[Shine] BadgeMixin doesn't exist!" )

			Shine.Hook.Remove( "Think", "ReplaceBadges" )

			return
		end

		if not kBadges then
			Shared.Message( "[Shine] Badge enum doesn't exist!" )

			Shine.Hook.Remove( "Think", "ReplaceBadges" )

			return
		end

		if not GiveBadge then
			Shared.Message( "[Shine] GiveBadge function doesn't exist!" )

			Shine.Hook.Remove( "Think", "ReplaceBadges" )

			return
		end

		self:Setup()

		Shine.Hook.Remove( "Think", "ReplaceBadges" )
	end )

	self.Enabled = true

	return true
end

function Plugin:Setup()
	if not BadgeMixin then return end
	if not kBadges then return end
	if not GiveBadge then return end

	--We need three upvalues from the GiveBadge function.
	local ServerBadges = Shine.GetUpValue( GiveBadge, "sServerBadges" )

	if not ServerBadges then
		Shared.Message( "[Shine] Unable to find ServerBadges table, badge plugin cannot load." )
		return
	end

	--These two aren't crucial, but it saves redefining them.
	local BadgeExists = Shine.GetUpValue( GiveBadge, "sBadgeExists" )
	local BadgeReserved = Shine.GetUpValue( GiveBadge, "sBadgeReserved" )

	if not BadgeExists then
		BadgeExists = function( Badge )
			return TableContains( kBadges, Badge )
		end
	end

	if not BadgeReserved then
		BadgeReserved = function( Badge )
			return false
		end
	end

	local UserData = Shine.UserData
	if not UserData or not UserData.Groups or not UserData.Users then return end

	TableEmpty( ServerBadges )

	local InsertUnique = table.insertunique

	local function AssignBadge( ID, BadgeName )
		local ClientBadges = ServerBadges[ ID ]

		if not ClientBadges then
			ClientBadges = {}
			ServerBadges[ ID ] = ClientBadges
		end

		if BadgeExists( BadgeName ) and not BadgeReserved( BadgeName ) then
			InsertUnique( ClientBadges, BadgeName )

			return true
		end

		return false
	end

	local function AssignGroupBadge( ID, GroupName )
		local Group = UserData.Groups[ GroupName ]

		if not Group then return end
		
		local GroupBadges = Group.Badges or Group.badges or {}

		if Group.Badge or Group.badge then
			InsertUnique( GroupBadges, Group.Badge or Group.badge )
		end

		for i = 1, #GroupBadges do
			local BadgeName = GroupBadges[ i ]:lower()

			if not AssignBadge( ID, BadgeName ) then
				Print( "%s has a non-existant or reserved badge: %s", GroupName, BadgeName )
			end
		end

		AssignBadge( ID, GroupName:lower() )
	end

	for ID, User in pairs( UserData.Users ) do
		ID = tonumber( ID )
		local GroupName = User.Group

		if not istable( GroupName ) then
			AssignGroupBadge( ID, GroupName )
		else
			for i = 1, #GroupName do
				local Group = GroupName[ i ]

				AssignGroupBadge( ID, Group )
			end
		end
	end
end

function Plugin:OnUserReload()
	self:Setup()
end

function Plugin:Cleanup()
	self.Enabled = false
end

Shine:RegisterExtension( "badges", Plugin )
