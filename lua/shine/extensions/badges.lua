--[[
	Override the badge mod's stuff to read from Shine's user data.
]]

local pairs = pairs
local tonumber = tonumber
local IsType = Shine.IsType
local Notify = Shared.Message
local InsertUnique = table.insertunique

local Plugin = {}
Plugin.Version = "1.0"

function Plugin:Initialise()
	if self.Enabled ~= nil then 
		self.Enabled = true

		return true
	end
	
	Shine.Hook.Add( "Think", "ReplaceBadges", function( Deltatime )
		self:Setup()

		Shine.Hook.Remove( "Think", "ReplaceBadges" )
	end )

	self.Enabled = true

	return true
end

function Plugin:Setup()
	if not GiveBadge then
		Notify( "[Shine] Unable to find the badge mod, badge plugin cannot load." )
		return
	end
	
	local AssignBadge = GiveBadge

	local UserData = Shine.UserData
	if not UserData or not UserData.Groups or not UserData.Users then return end

	local function AssignGroupBadge( ID, GroupName, AssignedGroups )
		local Group = UserData.Groups[ GroupName ]

		if not Group then return end

		AssignedGroups = AssignedGroups or {}

		if AssignedGroups[ GroupName ] then return end

		AssignedGroups[ GroupName ] = true
		
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
					Print( "%s has a non-existant or reserved badge: %s", GroupName, BadgeName )
				end
			end
		end

		AssignBadge( ID, GroupName:lower() )

		local InheritTable = Group.InheritsFrom

		--Inherit group badges.
		if IsType( InheritTable, "table" ) then
			for i = 1, #InheritTable do
				AssignGroupBadge( ID, InheritTable[ i ], AssignedGroups )
			end
		end
	end

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

			AssignGroupBadge( ID, GroupName )
		end
	end
end

function Plugin:OnUserReload()
	self:Setup()
end

Shine:RegisterExtension( "badges", Plugin )
