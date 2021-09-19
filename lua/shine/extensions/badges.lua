--[[
	Override the badge mod's stuff to read from Shine's user data.
]]

local JSON = require "shine/lib/json"

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
Plugin.Version = "2.3"
Plugin.PrintName = "Badges"
Plugin.HasConfig = true
Plugin.ConfigName = "Badges.json"
Plugin.CheckConfig = true
Plugin.CheckConfigTypes = true

Plugin.DefaultConfig = {
	-- A mapping of badge name to a human-readable name to show when hovering over the badge in the scoreboard.
	BadgeNames = JSON.Object()
}

do
	local Validator = Shine.Validator()

	Validator:AddFieldRule( "BadgeNames", Validator.AllKeyValuesSatisfy(
		Validator.IsType( "string" )
	) )

	Plugin.ConfigValidator = Validator
end

Plugin.ConfigMigrationSteps = {
	{
		VersionTo = "2.3",
		Apply = Shine.Migrator():AddField( "BadgeNames", Plugin.DefaultConfig.BadgeNames )
	}
}

function Plugin:Initialise()
	self:BroadcastModuleEvent( "Initialise" )

	self.AssignedUserIDs = {}
	self.ForcedBadges = {}
	self.BadgesByGroup = {}

	if SetFormalBadgeName then
		for BadgeName, NiceName in pairs( self.Config.BadgeNames ) do
			local BadgeID = rawget( gBadges, BadgeName )
			if BadgeID then
				self.Logger:Debug( "Setting name of badge '%s' to: %s", BadgeName, NiceName )
				if not SetFormalBadgeName( BadgeName, NiceName ) then
					self.Logger:Warn( "Failed to set badge '%s' to have name '%s'.", BadgeName, NiceName )
				end
			else
				self.Logger:Warn( "Badge '%s' configured in BadgeNames is not a valid badge.", BadgeName )
			end
		end
	end

	self.Enabled = true

	return true
end

function Plugin:OnFirstThink()
	Shine.Hook.SetupGlobalHook( "Badges_OnClientBadgeRequest", "OnClientBadgeRequest", "ActivePre" )

	-- Load badges upfront at startup to avoid needing to send lots of network messages at connection time.
	self:SetupAndLoadUserBadges()
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

		local NamedBadgeLists = {}
		for Key, List in pairs( MasterBadgeTable ) do
			if IsType( List, "table" ) then
				NamedBadgeLists[ Key ] = List
			end
		end

		return Lookup, NamedBadgeLists
	end

	local function IsBadgeListReference( Badge )
		return IsType( Badge, "table" ) and IsType( Badge.BadgeList, "string" )
	end

	local function GetBadgeList( Badge, NamedBadgeLists )
		if IsBadgeListReference( Badge ) then
			return NamedBadgeLists and NamedBadgeLists[ Badge.BadgeList ]
		end
		return nil
	end

	--[[
		Takes a badge list, and produces a table of badge rows, where each badge has been
		placed in the row they're mapped to by the MasterBadgeTable, or otherwise the default row.
	]]
	function Plugin:MapBadgesToRows( BadgeList, MasterBadgeTable, NamedBadgeLists, SeenLists )
		SeenLists = SeenLists or {}

		local BadgeRows = Shine.Multimap()

		for i = 1, #BadgeList do
			local Badge = BadgeList[ i ]
			local List = GetBadgeList( Badge, NamedBadgeLists )
			if List then
				if not SeenLists[ List ] then
					SeenLists[ List ] = true
					-- Referencing a badge list, map the list recursively to resolve nested lists and copy the results.
					BadgeRows:CopyFrom( self:MapBadgesToRows( List, MasterBadgeTable, NamedBadgeLists, SeenLists ) )
				end
			elseif IsType( Badge, "string" ) then
				-- A single badge, add it to every relevant row.
				local Rows = MasterBadgeTable:Get( Badge ) or DefaultRowList
				for j = 1, #Rows do
					BadgeRows:Add( Rows[ j ], Badge )
				end
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

	local function AddBadgeListToRow( BadgesByRow, Row, BadgeList, NamedBadgeLists, SeenLists )
		SeenLists = SeenLists or {}

		for i = 1, #BadgeList do
			local Badge = BadgeList[ i ]
			local List = GetBadgeList( Badge, NamedBadgeLists )
			if List then
				if not SeenLists[ List ] then
					SeenLists[ List ] = true
					AddBadgeListToRow( BadgesByRow, Row, List, NamedBadgeLists, SeenLists )
				end
			elseif IsType( Badge, "string" ) then
				BadgesByRow:Add( Row, Badge )
			end
		end
	end

	function Plugin:CollectBadgesFromEntry( Entry )
		local MasterBadgeTable = self.MasterBadgeTable
		local NamedBadgeLists = self.NamedBadgeLists
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
			if BadgeList[ 1 ] and ( IsType( BadgeList[ 1 ], "string" ) or IsBadgeListReference( BadgeList[ 1 ] ) ) then
				-- If it's an array and we have a master badge list, map the badges.
				if MasterBadgeTable then
					BadgesByRow:CopyFrom( self:MapBadgesToRows( BadgeList, MasterBadgeTable, NamedBadgeLists ) )
				else
					-- Otherwise take the array to be the default row.
					AddBadgeListToRow( BadgesByRow, DefaultRow, BadgeList, NamedBadgeLists )
				end
			else
				-- Otherwise assume it's specifying multiple rows and add each one.
				for i = 1, MaxBadgeRows do
					local BadgesForRow = BadgeList[ i ] or BadgeList[ tostring( i ) ]
					if IsType( BadgesForRow, "table" ) then
						AddBadgeListToRow( BadgesByRow, i, BadgesForRow, NamedBadgeLists )
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
		return false
	end

	local UserData = Shine.UserData
	if not UserData or not UserData.Groups or not UserData.Users then
		self.Logger:Error( "User data is missing groups and/or users, unable to setup badges." )
		return false
	end

	self.MasterBadgeTable, self.NamedBadgeLists = self:GetMasterBadgeLookup( UserData.Badges )
	self.Logger:Debug( "Parsed master badges table successfully." )

	return true
end

function Plugin:AssignBadgesFromGroupToID( ID, GroupName )
	if not IsType( GroupName, "string" ) then return end

	local Badges = self:BuildGroupBadges( GroupName )
	self:AssignBadgesToID( ID, Badges.Assigned, Badges.Forced )
end

function Plugin:AssignBadgesForUser( ID, User )
	self.Logger:Debug( "Assigning badges from user data for: %s", ID )

	self:AssignBadgesToID( ID, self:CollectBadgesFromEntry( User ) )
	self:AssignBadgesFromGroupToID( ID, User.Group )
end

function Plugin:SetupAndLoadUserBadges()
	if not self:Setup() then return end

	for UserID, User in pairs( Shine.UserData.Users ) do
		local ID = Shine.CoerceToID( UserID ) or Shine.SteamIDToNS2( UserID )
		if ID then
			self.AssignedUserIDs[ ID ] = true
			self:AssignBadgesForUser( ID, User )
		end
	end
end

function Plugin:AssignBadgesToClient( Client )
	local ID = Client:GetUserId()
	if not self.AssignedUserIDs[ ID ] then
		self.AssignedUserIDs[ ID ] = true

		local User = Shine:GetUserData( ID )
		if User then
			self:AssignBadgesForUser( ID, User )
		else
			self:AssignGuestBadge( Client )
		end
	end

	self:AssignForcedBadges( Client )
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

function Plugin:OnUserReload( TriggerType )
	if TriggerType == Shine.UserDataReloadTriggerType.INITIAL_WEB_LOAD then
		-- Treat the first load from web data the same as startup as it's likely to occur before most players load in.
		self:SetupAndLoadUserBadges()
	else
		-- Otherwise, only reload the currently connected player's badges, leave the rest to be loaded later.
		self:Setup()

		for Client in Shine.IterateClients() do
			self:AssignBadgesToClient( Client )
		end
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
