--[[
	Override the badge mod's stuff to read from Shine's user data.
]]

local pairs = pairs
local tonumber = tonumber
local IsType = Shine.IsType
local Notify = Shared.Message
local InsertUnique = table.InsertUnique

local Plugin = {}
Plugin.Version = "2.0"

function Plugin:Initialise()
	self.AssignedGuests = {}

	self.Enabled = true

	return true
end

function Plugin:OnFirstThink()
	self:Setup()
end

function Plugin:AssignGroupBadge( ID, GroupName, Group, AssignedGroups )
	local AssignBadge = GiveBadge

	if not Group then return end

	AssignedGroups = AssignedGroups or {}

	if AssignedGroups[ Group ] then return end

	AssignedGroups[ Group ] = true

	local GroupBadges = Group.Badges or Group.badges or {}
	if not IsType( GroupBadges, "table" ) then
		GroupBadges = {}
	end

	if GroupBadges[ 1 ] and IsType( GroupBadges[ 1 ], "string" ) then
		GroupBadges = {}
		GroupBadges[ 5 ] = Group.Badges or Group.badges
	end

	if IsType( Group.Badge or Group.badge, "string" ) then
		if not GroupBadges[ 5 ] then GroupBadges[ 5 ] = {} end
		InsertUnique( GroupBadges[ 5 ], Group.Badge or Group.badge )
	end

	for Row, GroupRowBadges in pairs( GroupBadges ) do
		for i = 1, #GroupRowBadges do
			local BadgeName = GroupRowBadges[ i ]

			if not AssignBadge( ID, BadgeName, Row ) then
				Print( "%s has a non-existant or reserved badge: %s",
					GroupName or "The default group", BadgeName )
			end
		end
	end

	if GroupName then
		AssignBadge( ID, GroupName:lower() )
	end

	local InheritTable = Group.InheritsFrom
	local UserData = Shine.UserData

	--Inherit group badges.
	if GroupName and IsType( InheritTable, "table" ) then
		for i = 1, #InheritTable do
			local Name = InheritTable[ i ]
			self:AssignGroupBadge( ID, Name, UserData.Groups[ Name ], AssignedGroups )
		end
	end

	if Group.InheritFromDefault then
		local DefaultGroup = Shine:GetDefaultGroup()
		if not DefaultGroup then return end

		self:AssignGroupBadge( ID, nil, DefaultGroup, AssignedGroups )
	end
end

function Plugin:Setup()
	if not GiveBadge then
		Notify( "[Shine] Unable to find the badge mod, badge plugin cannot load." )
		Shine:UnloadExtension( "badges" )
		return
	end

	local AssignBadge = GiveBadge

	local UserData = Shine.UserData
	if not UserData or not UserData.Groups or not UserData.Users then return end

	for ID, User in pairs( UserData.Users ) do
		ID = tonumber( ID )

		if ID then
			local GroupName = User.Group
			local UserBadge = User.Badge or User.badge
			local UserBadges = User.Badges or User.badges

			if IsType( UserBadge, "string" ) then
				if not AssignBadge( ID, UserBadge ) then
					Print( "%s has a non-existant or reserved badge: %s", ID, UserBadge )
				end
			end

			if IsType( UserBadges, "table" ) then
				if UserBadges[ 1 ] and IsType( UserBadges[ 1 ], "string" ) then
					UserBadges = {}
					UserBadges[ 5 ] = User.Badges or User.badges
				end

				for Row, UserRowBadges in pairs( UserBadges ) do
					for i = 1, #UserRowBadges do
						local BadgeName = UserRowBadges[ i ]

						if not AssignBadge( ID, BadgeName, Row ) then
							Print( "%s has a non-existant or reserved badge: %s", ID, BadgeName )
						end
					end
				end
			end

			self:AssignGroupBadge( ID, GroupName, UserData.Groups[ GroupName ] )
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

	if not UserData then
		if self.AssignedGuests[ ID ] then return end

		self.AssignedGuests[ ID ] = true

		self:AssignGroupBadge( ID, nil, DefaultGroup )
	end
end

Shine:RegisterExtension( "badges", Plugin )
