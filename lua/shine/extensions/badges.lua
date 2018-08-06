--[[
	Override the badge mod's stuff to read from Shine's user data.
]]

local pairs = pairs
local pcall = pcall
local rawget = rawget
local tonumber = tonumber
local tostring = tostring
local IsType = Shine.IsType
local Notify = Shared.Message

local Plugin = {}
Plugin.Version = "2.1"

function Plugin:Initialise()
	self.AssignedGuests = {}

	self.Enabled = true

	return true
end

function Plugin:OnFirstThink()
	Shine.Hook.SetupGlobalHook( "Badges_OnClientBadgeRequest", "OnClientBadgeRequest", "ActivePre" )
	self:Setup()
end

local DefaultRow = 5
local MaxBadgeRows = 10
Plugin.DefaultRow = DefaultRow

local function AssignBadge( ID, Name, Row )
	-- Catch error from badge enum missing values.
	local Success, BadgeAssigned = pcall( GiveBadge, ID, Name, Row )
	if not Success then
		BadgeAssigned = false
	end
	return BadgeAssigned
end

function Plugin:AssignGroupBadge( ID, GroupName, Group, AssignedGroups, MasterBadgeTable )
	if not Group then return end

	AssignedGroups = AssignedGroups or {}
	if AssignedGroups[ Group ] then return end

	AssignedGroups[ Group ] = true

	-- Assign badges defined in the group's table.
	self:AssignBadgesToID( ID, Group, MasterBadgeTable, GroupName or "The default group" )

	-- Assign the badge for the group's (lowercase) name.
	if GroupName then
		local GroupBadgeName = GroupName:lower()
		local Rows = MasterBadgeTable and MasterBadgeTable:Get( GroupBadgeName ) or { DefaultRow }
		for i = 1, #Rows do
			AssignBadge( ID, GroupBadgeName, Rows[ i ] )
		end
	end

	local InheritTable = Group.InheritsFrom
	local UserData = Shine.UserData

	-- Inherit group badges.
	if GroupName and IsType( InheritTable, "table" ) then
		for i = 1, #InheritTable do
			local Name = InheritTable[ i ]
			self:AssignGroupBadge( ID, Name, UserData.Groups[ Name ],
				AssignedGroups, MasterBadgeTable )
		end
	end

	if Group.InheritFromDefault then
		local DefaultGroup = Shine:GetDefaultGroup()
		if not DefaultGroup then return end

		self:AssignGroupBadge( ID, nil, DefaultGroup, AssignedGroups, MasterBadgeTable )
	end
end

--[[
	Maps a set of badges contained in rows to their row number.
]]
function Plugin:GetMasterBadgeLookup( MasterBadgeTable )
	if not IsType( MasterBadgeTable, "table" ) then return nil end

	local Lookup = Shine.Multimap()
	-- Use a numeric loop to keep order consistent.
	for i = 1, MaxBadgeRows do
		local Badges = MasterBadgeTable[ tostring( i ) ]
		if Badges then
			for j = 1, #Badges do
				Lookup:Add( Badges[ j ], i )
			end
		end
	end

	return Lookup
end

--[[
	Takes a badge list, and produces a table of badge rows, where each badge has been
	placed in the row they're mapped to by the MasterBadgeTable, or otherwise the default row.
]]
function Plugin:MapBadgesToRows( BadgeList, MasterBadgeTable )
	local BadgeRows = Shine.Multimap()

	for i = 1, #BadgeList do
		local Badge = BadgeList[ i ]
		local Rows = MasterBadgeTable:Get( Badge ) or { DefaultRow }

		for j = 1, #Rows do
			BadgeRows:Add( Rows[ j ], Badge )
		end
	end

	return BadgeRows:AsTable()
end

--[[
	Assigns badges to the given NS2ID from the given table.

	The table will either be a user entry, or a group entry, both of which may
	have a single value under "Badge" or a an array under "Badges".
]]
function Plugin:AssignBadgesToID( ID, Entry, MasterBadgeTable, OwnerName )
	local SingleBadge = Entry.Badge or Entry.badge
	local BadgeList = Entry.Badges or Entry.badges

	if IsType( SingleBadge, "string" ) then
		local Rows = MasterBadgeTable and MasterBadgeTable:Get( SingleBadge ) or { DefaultRow }
		for i = 1, #Rows do
			if not AssignBadge( ID, SingleBadge, Rows[ i ] ) then
				Print( "%s has a non-existant or reserved badge: %s",
					OwnerName or ID, SingleBadge )
			end
		end
	end

	if IsType( BadgeList, "table" ) then
		if BadgeList[ 1 ] and IsType( BadgeList[ 1 ], "string" ) then
			-- If it's an array and we have a master badge list, map the badges.
			if MasterBadgeTable then
				BadgeList = self:MapBadgesToRows( BadgeList, MasterBadgeTable )
			else
				-- Otherwise take the array to be the default row.
				BadgeList = {}
				BadgeList[ DefaultRow ] = Entry.Badges or Entry.badges
			end
		end

		for i = 1, MaxBadgeRows do
			local Badges = BadgeList[ i ] or BadgeList[ tostring( i ) ]

			if Badges then
				for j = 1, #Badges do
					local BadgeName = Badges[ j ]

					if not AssignBadge( ID, BadgeName, i ) then
						Print( "%s has a non-existant or reserved badge: %s",
							OwnerName or ID, BadgeName )
					end
				end
			end
		end
	end

	local ForcedBadges = Entry.ForcedBadges
	if IsType( ForcedBadges, "table" ) then
		for i = 1, MaxBadgeRows do
			local Badge = ForcedBadges[ i ] or ForcedBadges[ tostring( i ) ]
			if IsType( Badge, "string" ) then
				self:ForceBadgeForIDIfNotAlready( ID, Badge, i )
			end
		end
	end
end

--[[
	Forces the given player to have the given badge on the given column,
	regardless of the badge they have chosen.

	If there is already a forced badge for the given column, it will be left
	unchanged.
]]
function Plugin:ForceBadgeForIDIfNotAlready( ID, Badge, Column )
	local ForcedBadges = self.ForcedBadges[ ID ]
	if ForcedBadges and ForcedBadges[ Column ] then return end

	self:ForceBadgeForID( ID, Badge, Column )
end

--[[
	Forces the given player to have the given badge on the given column,
	regardless of the badge they have chosen.
]]
function Plugin:ForceBadgeForID( ID, Badge, Column )
	if not AssignBadge( ID, Badge, Column ) then return end

	local ForcedBadges = self.ForcedBadges[ ID ] or {}
	ForcedBadges[ Column ] = Badge
	self.ForcedBadges[ ID ] = ForcedBadges
end

function Plugin:Setup()
	if not GiveBadge then
		Notify( "[Shine] Unable to find the badge mod, badge plugin cannot load." )
		Shine:UnloadExtension( "badges" )
		return
	end

	local UserData = Shine.UserData
	if not UserData or not UserData.Groups or not UserData.Users then return end

	local MasterBadgeTable = self:GetMasterBadgeLookup( UserData.Badges )

	-- Remember badges that are forced per NS2ID.
	self.ForcedBadges = {}

	for ID, User in pairs( UserData.Users ) do
		ID = tonumber( ID )

		if ID then
			local GroupName = User.Group

			self:AssignBadgesToID( ID, User, MasterBadgeTable )
			self:AssignGroupBadge( ID, GroupName, UserData.Groups[ GroupName ], {},
				MasterBadgeTable )
		end
	end
end

function Plugin:OnUserReload()
	self.AssignedGuests = {}
	self:Setup()

	-- Re-assign default group badges.
	local DefaultGroup = Shine:GetDefaultGroup()
	if not DefaultGroup then return end

	for Client in Shine.GameIDs:Iterate() do
		self:AssignGuestBadge( Client, DefaultGroup )
	end
end

function Plugin:AssignGuestBadge( Client, DefaultGroup )
	if not DefaultGroup then return end

	local ID = Client:GetUserId()
	local UserData = Shine:GetUserData( ID )
	if UserData or self.AssignedGuests[ ID ] then return end

	self.AssignedGuests[ ID ] = true
	self:AssignGroupBadge( ID, nil, DefaultGroup, {},
		self:GetMasterBadgeLookup( Shine.UserData.Badges ) )
end

function Plugin:AssignForcedBadges( Client )
	local ForcedBadges = self.ForcedBadges[ Client:GetUserId() ]
	if not ForcedBadges then return end

	for Column, BadgeName in pairs( ForcedBadges ) do
		local BadgeID = rawget( gBadges, BadgeName )
		if BadgeID then
			Badges_SetBadge( Client:GetId(), BadgeID, Column )
		end
	end
end

function Plugin:ClientConnect( Client )
	self:AssignGuestBadge( Client, Shine:GetDefaultGroup() )
	self:AssignForcedBadges( Client )
end

function Plugin:OnClientBadgeRequest( ClientID, Message )
	local Client = ClientID and Server.GetClientById( ClientID )
	if not Client then return end

	local ForcedBadges = self.ForcedBadges[ Client:GetUserId() ]
	if not ForcedBadges then return end

	-- Prevent the user changing their badge if it's been forced
	-- for the given column.
	if ForcedBadges[ Message.column ] then return false end
end

Shine:RegisterExtension( "badges", Plugin )
