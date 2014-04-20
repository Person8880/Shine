--[[
	Override the badge mod's stuff to read from Shine's user data.
]]

local pairs = pairs
local tonumber = tonumber
local type = type

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
		Shared.Message( "[Shine] Unable to find the badge mod, badge plugin cannot load." )
		return
	end

	local UserData = Shine.UserData
	if not UserData or not UserData.Groups or not UserData.Users then return end

	local InsertUnique = table.insertunique

	local AssignBadge = GiveBadge

	local function AssignGroupBadge( ID, GroupName, AssignedGroups )
		local Group = UserData.Groups[ GroupName ]

		if not Group then return end

		AssignedGroups = AssignedGroups or {}

		if AssignedGroups[ GroupName ] then return end

		AssignedGroups[ GroupName ] = true
		
		local GroupBadges = Group.Badges or Group.badges or {}
		
		if GroupBadges[ 1 ] and type( GroupBadges[ 1 ] ) == "string" then
			GroupBadges = {}
			GroupBadges[ 3 ] = Group.Badges or Group.badges
		end
		
		if Group.Badge or Group.badge then
			if not GroupBadges[ 3 ] then GroupBadges[ 3 ] = {} end
			InsertUnique( GroupBadges[ 3 ], Group.Badge or Group.badge )
		end
		
		for Row, GroupRowBadges in pairs( GroupBadges ) do
			if GroupRowBadges then
				for i = 1, #GroupRowBadges do
					local BadgeName = GroupRowBadges[ i ]

					if not AssignBadge( ID, BadgeName, Row ) then
						Print( "%s has a non-existant or reserved badge: %s", GroupName, BadgeName )
					end
				end
			end
		end

		AssignBadge( ID, GroupName:lower() )

		local InheritTable = Group.InheritsFrom

		--Inherit group badges.
		if InheritTable then
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

			if UserBadge then
				if not AssignBadge( ID, UserBadge ) then
					Print( "%s has a non-existant or reserved badge: %s", ID, UserBadge )
				end
			end
			
			if UserBadges then
				if UserBadges[ 1 ] and type( UserBadges[ 1 ] ) == "string" then
					UserBadges = {}
					UserBadges[ 3 ] = User.Badges or User.badges
				end
				
				for Row, UserRowBadges in pairs( UserBadges ) do
					if UserRowBadges then
						for i = 1, #UserRowBadges do
							local BadgeName = UserRowBadges[ i ]

							if not AssignBadge( ID, BadgeName, Row ) then
								Print( "%s has a non-existant or reserved badge: %s", ID, BadgeName )
							end
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

function Plugin:Cleanup()
	self.Enabled = false
end

Shine:RegisterExtension( "badges", Plugin )
