--[[
	Override the badge mod's stuff to read from Shine's user data.
]]

local pairs = pairs
local tonumber = tonumber
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
		local Row = MasterBadgeTable and MasterBadgeTable[ GroupBadgeName ]
		GiveBadge( ID, GroupBadgeName, Row )
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

	local Lookup = {}
	for Row, Badges in pairs( MasterBadgeTable ) do
		for i = 1, #Badges do
			Lookup[ Badges[ i ] ] = tonumber( Row )
		end
	end

	return Lookup
end

--[[
	Takes a badge list, and produces a table of badge rows, where each badge has been
	placed in the row they're mapped to by the MasterBadgeTable, or otherwise the default row.
]]
function Plugin:MapBadgesToRows( BadgeList, MasterBadgeTable )
	local BadgeRows = {}

	for i = 1, #BadgeList do
		local Badge = BadgeList[ i ]
		local Row = MasterBadgeTable[ Badge ] or DefaultRow
		local BadgeRow = BadgeRows[ Row ]
		if not BadgeRow then
			BadgeRow = {}
			BadgeRows[ Row ] = BadgeRow
		end

		BadgeRow[ #BadgeRow + 1 ] = Badge
	end

	return BadgeRows
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
		local Row = MasterBadgeTable and MasterBadgeTable[ SingleBadge ]
		if not AssignBadge( ID, SingleBadge, Row ) then
			Print( "%s has a non-existant or reserved badge: %s",
				OwnerName or ID, SingleBadge )
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

		for Row, Badges in pairs( BadgeList ) do
			for i = 1, #Badges do
				local BadgeName = Badges[ i ]

				if not AssignBadge( ID, BadgeName, tonumber( Row ) ) then
					Print( "%s has a non-existant or reserved badge: %s",
						OwnerName or ID, BadgeName )
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
			self:AssignGroupBadge( ID, GroupName, UserData.Groups[ GroupName ],
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
	self:AssignGroupBadge( ID, nil, DefaultGroup,
		self:GetMasterBadgeLookup( Shine.UserData.Badges ) )
end

Shine:RegisterExtension( "badges", Plugin )
