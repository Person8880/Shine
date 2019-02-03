--[[
	Friend group handling.
]]

local Plugin = ...

local TableRemoveByValue = table.RemoveByValue

function Plugin:ReceiveFriendGroupOptOut( Client, Data )
	if self.Logger:IsDebugEnabled() then
		self.Logger:Debug( "%s %s friend groups.", Shine.GetClientInfo( Client ),
			Data.OptOut and "does not want to be added to" or "wants to be added to" )
	end
	self.BlockFriendGroupRequestsForSteamIDs[ Client:GetUserId() ] = Data.OptOut or nil
end

function Plugin:ReceiveJoinFriendGroup( Client, Data )
	local TargetSteamID = Data.SteamID

	local TargetClient = Shine.GetClientByNS2ID( TargetSteamID )
	if not TargetClient then return end

	if not Shine:HasAccess( Client, "sh_add_to_friendgroup", true ) then
		self:SendTranslatedNotification( Client, Shine.NotificationType.ERROR, "ERROR_BLOCKED_BY_SERVER" )
		return
	end

	self:HandleFriendGroupJoinRequest( Client, TargetClient )
end

function Plugin:HandleFriendGroupJoinRequest( Client, TargetClient )
	local TargetSteamID = TargetClient:GetUserId()
	local CallerSteamID = Client:GetUserId()

	if self.BlockFriendGroupRequestsForSteamIDs[ TargetSteamID ] then
		self:SendTranslatedNotification( Client, Shine.NotificationType.ERROR, "ERROR_TARGET_OPTED_OUT", {
			PlayerName = TargetClient:GetControllingPlayer():GetName()
		} )
		return
	end

	local TargetGroup = self.FriendGroupsBySteamID[ TargetSteamID ]
	local CallerGroup = self.FriendGroupsBySteamID[ CallerSteamID ]

	if not TargetGroup and not CallerGroup then
		-- Neither player is in a group, so create a new group with them both in.
		local NewGroup = {
			Clients = {
				Client,
				TargetClient
			}
		}
		self.FriendGroups[ #self.FriendGroups + 1 ] = NewGroup
		self.FriendGroupsBySteamID[ TargetSteamID ] = NewGroup
		self.FriendGroupsBySteamID[ CallerSteamID ] = NewGroup

		self:SendNetworkMessage( NewGroup.Clients, "FriendGroupUpdated", {
			SteamID = TargetSteamID,
			Joined = true
		}, true )
		self:SendNetworkMessage( NewGroup.Clients, "FriendGroupUpdated", {
			SteamID = CallerSteamID,
			Joined = true
		}, true )

		if self.Logger:IsDebugEnabled() then
			self.Logger:Debug( "Created new friend group containing players: [ %s, %s ]",
				Shine.GetClientInfo( Client ), Shine.GetClientInfo( TargetClient ) )
		end

		return
	end

	if TargetGroup == CallerGroup then
		-- Both players are already in the same group, ignore the request.
		self.Logger:Debug( "Received request to join friend group when target is already in the client's group!" )
		return
	end

	if TargetGroup and CallerGroup then
		-- Both clients are already in groups, cannot move the target player.
		self:SendTranslatedNotification( Client, Shine.NotificationType.ERROR, "ERROR_TARGET_IN_FRIEND_GROUP", {
			PlayerName = TargetClient:GetControllingPlayer():GetName()
		} )
		return
	end

	if not TargetGroup then
		-- Target is not in a group, but we are.
		-- Make sure there's enough room for the new player.
		if #CallerGroup.Clients >= self.Config.TeamPreferences.MaxFriendGroupSize then
			self:SendTranslatedNotification( Client, Shine.NotificationType.ERROR, "ERROR_FRIEND_GROUP_FULL", {
				PlayerName = TargetClient:GetControllingPlayer():GetName()
			} )
			return
		end

		self:AddClientToFriendGroup( CallerGroup, TargetClient )
		self:SendTranslatedNotify( TargetClient, "ADDED_TO_FRIEND_GROUP", {
			PlayerName = Client:GetControllingPlayer():GetName()
		} )

		return
	end

	-- We're not in a group, but the target is.
	if #TargetGroup.Clients >= self.Config.TeamPreferences.MaxFriendGroupSize then
		self:SendTranslatedNotification( Client, Shine.NotificationType.ERROR, "ERROR_TARGET_FRIEND_GROUP_FULL", {
			PlayerName = TargetClient:GetControllingPlayer():GetName()
		} )
		return
	end

	self:AddClientToFriendGroup( TargetGroup, Client )
end

local function GroupToString( Group )
	return table.ToString( {
		Clients = Shine.Stream.Of( Group.Clients ):Map( Shine.GetClientInfo ):AsTable()
	} )
end

function Plugin:AddClientToFriendGroup( Group, Client )
	if self.Logger:IsDebugEnabled() then
		self.Logger:Debug( "Adding %s to group: %s", Shine.GetClientInfo( Client ), GroupToString( Group ) )
	end

	local SteamID = Client:GetUserId()

	Group.Clients[ #Group.Clients + 1 ] = Client
	self.FriendGroupsBySteamID[ SteamID ] = Group

	-- Notify all clients in the group of the new player.
	self:SendNetworkMessage( Group.Clients, "FriendGroupUpdated", {
		SteamID = SteamID,
		Joined = true
	}, true )

	-- Notify the new player of all the other members.
	for i = 1, #Group.Clients - 1 do
		self:SendNetworkMessage( Client, "FriendGroupUpdated", {
			SteamID = Group.Clients[ i ]:GetUserId(),
			Joined = true
		}, true )
	end
end

function Plugin:ReceiveLeaveFriendGroup( Client, Data )
	local Group = self.FriendGroupsBySteamID[ Client:GetUserId() ]
	if not Group then return end

	self:RemoveClientFromFriendGroup( Group, Client )
end

function Plugin:RemoveClientFromFriendGroup( Group, Client, IsDisconnecting )
	if self.Logger:IsDebugEnabled() then
		self.Logger:Debug( "Removing %s from group: %s", Shine.GetClientInfo( Client ), GroupToString( Group ) )
	end

	local SteamID = Client:GetUserId()
	TableRemoveByValue( Group.Clients, Client )
	self.FriendGroupsBySteamID[ SteamID ] = nil

	-- Tell the client they've left the group.
	if not IsDisconnecting then
		self:SendNetworkMessage( Client, "LeftFriendGroup", {}, true )
	end

	if #Group.Clients <= 1 then
		-- Clean up empty groups.
		TableRemoveByValue( self.FriendGroups, Group )

		local RemainingClient = Group.Clients[ 1 ]
		if RemainingClient then
			self.FriendGroupsBySteamID[ RemainingClient:GetUserId() ] = nil
			self:SendNetworkMessage( RemainingClient, "LeftFriendGroup", {}, true )
		end

		return
	end

	-- Tell everyone left in the group that they've left.
	self:SendNetworkMessage( Group.Clients, "FriendGroupUpdated", {
		SteamID = SteamID,
		Joined = false
	}, true )
end
