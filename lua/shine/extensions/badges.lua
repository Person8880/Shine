--[[
	Override the badge mod's stuff to read from Shine's user data.
]]

local Shine = Shine

local pairs = pairs
local pcall = pcall
local rawget = rawget
local tonumber = tonumber
local tostring = tostring
local IsType = Shine.IsType
local Notify = Shared.Message
local TableEmpty = table.Empty

local Plugin = Shine.Plugin( ... )
Plugin.PrintName = "Badges"
Plugin.HasConfig = true
Plugin.ConfigName = "Badges.json"
Plugin.CheckConfig = true
Plugin.CheckConfigTypes = true

Plugin.Version = "2.2"

function Plugin:Initialise()
	self:BroadcastModuleEvent( "Initialise" )

	self.AssignedUserIDs = {}
	self.ForcedBadges = {}
	self.BadgesByGroup = {}

	self.Enabled = true

	return true
end

function Plugin:OnFirstThink()
	Shine.Hook.SetupGlobalHook( "Badges_OnClientBadgeRequest", "OnClientBadgeRequest", "ActivePre" )
	self:Setup()
end

local DefaultGroupKey = -1

do
	local DefaultRow = 5
	local DefaultRowList = { DefaultRow }
	local MaxBadgeRows = 10
	Plugin.DefaultRow = DefaultRow

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
			local Rows = MasterBadgeTable:Get( Badge ) or DefaultRowList

			for j = 1, #Rows do
				BadgeRows:Add( Rows[ j ], Badge )
			end
		end

		return BadgeRows
	end


	local EMPTY_BADGES = Shine.Multimap()
	local function MergeBadges( Badges, ParentBadges )
		-- Merge all parent badges into the current badge assignment lookup.
		Badges.Assigned:CopyFrom( ParentBadges.Assigned )

		if ParentBadges.Forced then
			Badges.Forced = Badges.Forced or Shine.Map()

			-- Only force badges from the parent that have not already been forced.
			for Row, Badge in ParentBadges.Forced:Iterate() do
				if not Badges.Forced:Get( Row ) then
					Badges.Forced:Add( Row, Badge )
				end
			end
		end
	end

	function Plugin:CollectBadgesFromEntry( Entry )
		local MasterBadgeTable = self.MasterBadgeTable
		local BadgesByRow = Shine.Multimap()
		local ForcedBadgesByRow

		local SingleBadge = Entry.Badge or Entry.badge
		local BadgeList = Entry.Badges or Entry.badges

		if IsType( SingleBadge, "string" ) then
			local Rows = MasterBadgeTable and MasterBadgeTable:Get( SingleBadge ) or DefaultRowList
			for i = 1, #Rows do
				BadgesByRow:Add( Rows[ i ], SingleBadge )
			end
		end

		if IsType( BadgeList, "table" ) then
			if BadgeList[ 1 ] and IsType( BadgeList[ 1 ], "string" ) then
				-- If it's an array and we have a master badge list, map the badges.
				if MasterBadgeTable then
					BadgesByRow:CopyFrom( self:MapBadgesToRows( BadgeList, MasterBadgeTable ) )
				else
					-- Otherwise take the array to be the default row.
					BadgesByRow:AddAll( DefaultRow, BadgeList )
				end
			else
				for i = 1, MaxBadgeRows do
					local BadgesForRow = BadgeList[ i ] or BadgeList[ tostring( i ) ]
					if IsType( BadgesForRow, "table" ) then
						BadgesByRow:AddAll( i, BadgesForRow )
					end
				end
			end
		end

		local ForcedBadges = Entry.ForcedBadges
		if IsType( ForcedBadges, "table" ) then
			ForcedBadgesByRow = Shine.Map()

			for i = 1, MaxBadgeRows do
				local Badge = ForcedBadges[ i ] or ForcedBadges[ tostring( i ) ]
				if IsType( Badge, "string" ) then
					ForcedBadgesByRow:Add( i, Badge )
				end
			end
		end

		return BadgesByRow, ForcedBadgesByRow
	end

	function Plugin:GetGroupData( GroupName )
		local Group

		if IsType( GroupName, "string" ) then
			Group = Shine:GetGroupData( GroupName )
		else
			Group = Shine:GetDefaultGroup()
		end

		return Group
	end

	function Plugin:BuildGroupBadges( GroupName )
		local Badges = self.BadgesByGroup[ GroupName ]
		if Badges then return Badges end

		Badges = {
			Assigned = EMPTY_BADGES
		}
		self.BadgesByGroup[ GroupName ] = Badges

		local Group = self:GetGroupData( GroupName )
		if not Group then return Badges end

		local BadgesByRow, ForcedBadgesByRow = self:CollectBadgesFromEntry( Group )
		Badges.Assigned = BadgesByRow
		Badges.Forced = ForcedBadgesByRow

		local ParentGroupNames = Group.InheritsFrom
		if IsType( GroupName, "string" ) and IsType( ParentGroupNames, "table" ) then
			for i = 1, #ParentGroupNames do
				local ParentBadges = self:BuildGroupBadges( ParentGroupNames[ i ] )
				MergeBadges( Badges, ParentBadges )
			end
		end

		if Group.InheritFromDefault then
			local ParentBadges = self:BuildGroupBadges( DefaultGroupKey )
			MergeBadges( Badges, ParentBadges )
		end

		return Badges
	end
end

do
	local function AssignBadge( ID, Name, Row )
		-- Catch error from badge enum missing values.
		local Success, BadgeAssigned = pcall( GiveBadge, ID, Name, Row )
		if not Success then
			BadgeAssigned = false
		end
		return BadgeAssigned
	end

	--[[
		Assigns badges to the given NS2ID from the given pre-computed badge lookups.
	]]
	function Plugin:AssignBadgesToID( ID, BadgesByRow, ForcedBadgesByRow )
		for Row, BadgeNames in BadgesByRow:Iterate() do
			for i = 1, #BadgeNames do
				if not AssignBadge( ID, BadgeNames[ i ], Row ) then
					self.Logger:Warn( "%s has a non-existent or reserved badge: %s", ID, BadgeNames[ i ] )
				end
			end
		end

		if ForcedBadgesByRow then
			for Row, ForcedBadge in ForcedBadgesByRow:Iterate() do
				self:ForceBadgeForIDIfNotAlready( ID, ForcedBadge, Row )
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
		if not AssignBadge( ID, Badge, Column ) then
			self.Logger:Warn( "%s cannot be forced to use badge '%s' as it is reserved or does not exist.", ID, Badge )
			return
		end

		local ForcedBadges = self.ForcedBadges[ ID ] or {}
		ForcedBadges[ Column ] = Badge
		self.ForcedBadges[ ID ] = ForcedBadges
	end
end

function Plugin:ResetState()
	TableEmpty( self.AssignedUserIDs )
	TableEmpty( self.ForcedBadges )
	TableEmpty( self.BadgesByGroup )
end

function Plugin:Setup()
	self:ResetState()

	if not GiveBadge then
		self.Logger:Error( "Badge system unavailable, cannot load badges." )
		Shine:UnloadExtension( self:GetName() )
		return
	end

	local UserData = Shine.UserData
	if not UserData or not UserData.Groups or not UserData.Users then
		self.Logger:Error( "User data is missing groups and/or users, unable to setup badges." )
		return
	end

	self.MasterBadgeTable = self:GetMasterBadgeLookup( UserData.Badges )
	self.Logger:Debug( "Parsed master badges table successfully." )
end

function Plugin:AssignBadgesFromGroupToID( ID, GroupName )
	if not IsType( GroupName, "string" ) then return end

	local Badges = self:BuildGroupBadges( GroupName )
	self:AssignBadgesToID( ID, Badges.Assigned, Badges.Forced )
end

function Plugin:AssignBadgesToClient( Client )
	local ID = Client:GetUserId()
	if self.AssignedUserIDs[ ID ] then return end

	self.AssignedUserIDs[ ID ] = true

	local User = Shine:GetUserData( ID )
	if User then
		self:AssignBadgesToID( ID, self:CollectBadgesFromEntry( User ) )
		self:AssignBadgesFromGroupToID( ID, User.Group )
		self:AssignForcedBadges( Client )
	else
		self:AssignGuestBadge( Client )
	end
end

function Plugin:AssignGuestBadge( Client )
	local ID = Client:GetUserId()
	self.Logger:Debug( "Assigning guest badges for: %s", ID )

	local Badges = self:BuildGroupBadges( DefaultGroupKey )
	self:AssignBadgesToID( ID, Badges.Assigned, Badges.Forced )
end

function Plugin:AssignForcedBadges( Client )
	local ID = Client:GetUserId()
	local ForcedBadges = self.ForcedBadges[ ID ]
	if not ForcedBadges then return end

	for Column, BadgeName in pairs( ForcedBadges ) do
		local BadgeID = rawget( gBadges, BadgeName )
		if BadgeID then
			self.Logger:Debug( "Forcing badge '%s' on column %s for user %s", BadgeName, Column, ID )
			if not Badges_SetBadge( Client:GetId(), BadgeID, Column ) then
				self.Logger:Warn( "Unable to set forced badge '%s' on column %s for user %s", BadgeName, Column, ID )
			end
		end
	end
end

function Plugin:OnUserReload()
	self:Setup()

	-- Re-assign connected player's badges.
	for Client in Shine.GameIDs:Iterate() do
		self:AssignBadgesToClient( Client )
	end
end

function Plugin:ClientConnect( Client )
	self:AssignBadgesToClient( Client )
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

function Plugin:Cleanup()
	self:ResetState()
	return self.BaseClass.Cleanup( self )
end

Shine.LoadPluginModule( "logger.lua", Plugin )

return Plugin
