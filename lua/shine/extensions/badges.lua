--[[
	Override the badge mod's stuff to read from Shine's user data.
]]

local pairs = pairs
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
	self:Setup()
end

local DefaultRow = 5
local MaxBadgeRows = 10
Plugin.DefaultRow = DefaultRow

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
			GiveBadge( ID, GroupBadgeName, Rows[ i ] )
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
	local AssignBadge = GiveBadge
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
end

function Plugin:ClientConnect( Client )
	local DefaultGroup = Shine:GetDefaultGroup()
	if not DefaultGroup then return end

	local ID = Client:GetUserId()
	local UserData = Shine:GetUserData( ID )
	if UserData or self.AssignedGuests[ ID ] then return end

	self.AssignedGuests[ ID ] = true
	self:AssignGroupBadge( ID, nil, DefaultGroup, {},
		self:GetMasterBadgeLookup( Shine.UserData.Badges ) )
end

Shine:RegisterExtension( "badges", Plugin )
