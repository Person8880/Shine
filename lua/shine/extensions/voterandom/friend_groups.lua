--[[
	Friend group handling.
]]

local Plugin = ...

local SharedTime = Shared.GetTime
local TableRemoveByValue = table.RemoveByValue

local function HasGameStarted()
	local Gamerules = GetGamerules()
	return Gamerules and Gamerules:GetGameStarted()
end

function Plugin:GetGroupLeaderType( Group )
	local LeaderSteamID = Group.Leader:GetUserId()
	local LeaderConfig = self.FriendGroupConfigBySteamID[ LeaderSteamID ]
	return LeaderConfig and LeaderConfig.LeaderType or self.FriendGroupLeaderType.LEADER_ADD_ONLY
end

function Plugin:CanClientInviteOthersToGroup( Client, Group )
	return Group.Leader == Client or self:GetGroupLeaderType( Group ) == self.FriendGroupLeaderType.ALLOW_ALL_TO_JOIN
end

function Plugin:GetInviteTo( Client )
	local SteamID = Client:GetUserId()
	local Invite = self.FriendGroupInvitesBySteamID[ SteamID ]
	if not Invite then return nil end

	if Invite.ExpiryTime <= SharedTime() then
		self.FriendGroupInvitesBySteamID[ SteamID ] = nil
		return nil
	end

	return Invite
end

function Plugin:GetGroupInviterID( Client )
	local Invite = self:GetInviteTo( Client )
	if not Invite then return nil end

	return Invite.InviterID
end

function Plugin:CanJoinGroup( Client, Group )
	local LeaderType = self:GetGroupLeaderType( Group )
	if LeaderType == self.FriendGroupLeaderType.ALLOW_ALL_TO_JOIN then
		return true
	end

	-- Group requires the leader to add players, so the client must be invited by the leader.
	local InviterID = self:GetGroupInviterID( Client )
	return InviterID == Group.Leader:GetUserId()
end

function Plugin:ReceiveClientFriendGroupConfig( Client, Data )
	if self.Logger:IsDebugEnabled() then
		self.Logger:Debug( "%s friend group config: %s", Shine.GetClientInfo( Client ),
			table.ToString( Data ) )
	end

	local SteamID = Client:GetUserId()
	self.FriendGroupConfigBySteamID[ SteamID ] = Data

	local Group = self.FriendGroupsBySteamID[ SteamID ]
	if Group and Group.Leader == Client then
		-- The client's a leader of a group, update all clients in the group with the new config.
		self:SendNetworkMessage( Group.Clients, "FriendGroupConfig", {
			LeaderID = SteamID,
			LeaderType = Data.LeaderType
		}, true )
	end
end

function Plugin:ReceiveJoinFriendGroup( Client, Data )
	if HasGameStarted() then return end

	local TargetSteamID = Data.SteamID
	local TargetClient = Shine.GetClientByNS2ID( TargetSteamID )
	if not TargetClient or Client == TargetClient or ( TargetClient:GetIsVirtual() and not Shared.GetDevMode() ) then
		if self.Logger:IsDebugEnabled() then
			self.Logger:Debug( "Rejecting friend group request from %s to %s as the target is invalid.",
				Shine.GetClientInfo( Client ), Shine.GetClientInfo( TargetClient ) )
		end

		return
	end

	if not Shine:HasAccess( Client, "sh_add_to_friendgroup", true ) then
		self:SendTranslatedNotification( Client, Shine.NotificationType.ERROR, "ERROR_BLOCKED_BY_SERVER" )
		return
	end

	if self.Logger:IsDebugEnabled() then
		self.Logger:Debug( "Received friend group join request from %s to %s.",
			Shine.GetClientInfo( Client ), Shine.GetClientInfo( TargetClient ) )
	end

	self:HandleFriendGroupJoinRequest( Client, TargetClient )
end

function Plugin:ReceiveRemoveFromFriendGroup( Client, Data )
	local CallerSteamID = Client:GetUserId()

	local CallerGroup = self.FriendGroupsBySteamID[ CallerSteamID ]
	if not CallerGroup then return end

	local Target = Shine.GetClientByNS2ID( Data.SteamID )
	if not Target then return end
	if self.FriendGroupsBySteamID[ Data.SteamID ] ~= CallerGroup then return end

	if CallerGroup.Leader ~= Client then
		self:SendTranslatedNotification( Client, Shine.NotificationType.ERROR, "ERROR_CANNOT_REMOVE_NOT_LEADER", {
			PlayerName = Target:GetControllingPlayer():GetName()
		} )
		return
	end

	self:RemoveClientFromFriendGroup( CallerGroup, Target )

	self:SendTranslatedNotify( Target, "REMOVED_FROM_GROUP", {
		PlayerName = Client:GetControllingPlayer():GetName()
	} )
end

function Plugin:ReceiveFriendGroupInviteAnswer( Client, Data )
	local Invite = self:GetInviteTo( Client )
	if not Invite then return end

	local SteamID = Client:GetUserId()
	self:CancelFriendGroupInviteTo( SteamID )

	if HasGameStarted() then return end

	local InviterID = Invite.InviterID
	local Inviter = Shine.GetClientByNS2ID( InviterID )
	if not Inviter or Inviter == Client then return end

	if not Data.Accepted then
		if self.Logger:IsDebugEnabled() then
			self.Logger:Debug( "%s declined a friend group invite from %s.", Shine.GetClientInfo( Client ),
				Shine.GetClientInfo( Inviter ) )
		end

		self:SendTranslatedNotify( Inviter, "INVITE_REJECTED", {
			PlayerName = Client:GetControllingPlayer():GetName()
		} )
		return
	end

	if self.Logger:IsDebugEnabled() then
		self.Logger:Debug( "%s accepted a friend group invite from %s.", Shine.GetClientInfo( Client ),
			Shine.GetClientInfo( Inviter ) )
	end

	local InviteDelays = self.FriendGroupInviteDelaysBySteamID[ SteamID ]
	if InviteDelays then
		-- Reset the invite delay on accept as they can't be invited again while in the group,
		-- but if they accidentally leave it they may want to be invited back immediately.
		InviteDelays[ InviterID ] = nil
	end

	local Group = self.FriendGroupsBySteamID[ InviterID ]
	if Group then
		if #Group.Clients >= self.Config.TeamPreferences.MaxFriendGroupSize then
			-- Answered the invite too late.
			self:SendTranslatedNotification( Client, Shine.NotificationType.ERROR, "ERROR_TARGET_FRIEND_GROUP_FULL", {
				PlayerName = Inviter:GetControllingPlayer():GetName()
			} )
			return
		end

		-- Inviter is already in a group, add the client accepting the invite to it.
		self:AddClientToFriendGroup( Group, Client )
	else
		-- Inviter is not in a group, make a new group with the inviter as the leader.
		self:MakeNewFriendGroup( Inviter, { Inviter, Client }, true )
	end

	-- Tell each client that the accept was successful.
	self:SendTranslatedNotify( Inviter, "INVITE_ACCEPTED", {
		PlayerName = Client:GetControllingPlayer():GetName()
	} )
	self:SendTranslatedNotify( Client, "SELF_INVITE_ACCEPTED", {
		PlayerName = Inviter:GetControllingPlayer():GetName()
	} )
end

function Plugin:HandleFriendGroupJoinRequest( Client, TargetClient )
	local TargetSteamID = TargetClient:GetUserId()
	local CallerSteamID = Client:GetUserId()

	local TargetConfig = self.FriendGroupConfigBySteamID[ TargetSteamID ]
	if TargetSteamID == 0 and not TargetConfig then
		-- For testing purposes, the dev mode check above prevents this from happening normally.
		TargetConfig = {
			JoinType = self.FriendGroupJoinType.REQUIRE_INVITE,
			LeaderType = self.FriendGroupLeaderType.ALLOW_ALL_TO_JOIN
		}
	end

	if not TargetConfig then return end

	if TargetConfig.JoinType == self.FriendGroupJoinType.BLOCK then
		-- Target player is blocking all requests to join friend groups, so cannot be added or invited.
		self:SendTranslatedNotification( Client, Shine.NotificationType.ERROR, "ERROR_TARGET_OPTED_OUT", {
			PlayerName = TargetClient:GetControllingPlayer():GetName()
		} )
		return
	end

	local CallerGroup = self.FriendGroupsBySteamID[ CallerSteamID ]
	if CallerGroup and not self:CanClientInviteOthersToGroup( Client, CallerGroup ) then
		-- Client attempting to add a player is not the group leader, and the group is set to leader-only invites.
		self:SendTranslatedNotification( Client, Shine.NotificationType.ERROR, "ERROR_CANNOT_INVITE_NOT_LEADER" )
		return
	end

	local TargetGroup = self.FriendGroupsBySteamID[ TargetSteamID ]
	if not TargetGroup and TargetConfig.JoinType == self.FriendGroupJoinType.REQUIRE_INVITE then
		-- Target player needs to accept an invitation to join the group.
		self:SendInviteToFriendGroup( Client, TargetClient )
		return
	end

	if not TargetGroup and not CallerGroup then
		-- Neither player is in a group, and the target player doesn't need inviting,
		-- so create a new group with them both in.
		self:MakeNewFriendGroup( Client, { Client, TargetClient } )
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

		-- The invitation case is already covered above, so by this point the target is allowing all requests
		-- and the caller is either the group leader or the group is allowing anyone to join.
		self:AddClientToFriendGroup( CallerGroup, TargetClient )
		self:SendTranslatedNotify( TargetClient, "ADDED_TO_FRIEND_GROUP", {
			PlayerName = Client:GetControllingPlayer():GetName()
		} )

		return
	end

	-- We're not in a group, but the target is.
	-- Check if we need to be invited to the group.
	if not self:CanJoinGroup( Client, TargetGroup ) then
		self:SendTranslatedNotification( Client, Shine.NotificationType.ERROR, "ERROR_MUST_BE_INVITED_TO_GROUP", {
			PlayerName = TargetClient:GetControllingPlayer():GetName()
		} )
		return
	end

	-- Also make sure the group isn't full.
	if #TargetGroup.Clients >= self.Config.TeamPreferences.MaxFriendGroupSize then
		self:SendTranslatedNotification( Client, Shine.NotificationType.ERROR, "ERROR_TARGET_FRIEND_GROUP_FULL", {
			PlayerName = TargetClient:GetControllingPlayer():GetName()
		} )
		return
	end

	-- Don't need an invite (or already have one), and group is not full, so add us to the target's group.
	self:AddClientToFriendGroup( TargetGroup, Client )
end

function Plugin:SendInviteToFriendGroup( Inviter, TargetClient )
	local TargetSteamID = TargetClient:GetUserId()
	local CallerSteamID = Inviter:GetUserId()

	-- If the target's already been invited by someone, deny the invite.
	if self:GetGroupInviterID( TargetClient ) then
		self:SendTranslatedNotification( Inviter, Shine.NotificationType.ERROR, "ERROR_TARGET_ALREADY_INVITED", {
			PlayerName = TargetClient:GetControllingPlayer():GetName()
		} )
		return
	end

	local CallerGroup = self.FriendGroupsBySteamID[ CallerSteamID ]

	-- Make sure there's enough room for the new player if the caller's already in a group.
	if CallerGroup and #CallerGroup.Clients >= self.Config.TeamPreferences.MaxFriendGroupSize then
		self:SendTranslatedNotification( Inviter, Shine.NotificationType.ERROR, "ERROR_FRIEND_GROUP_FULL", {
			PlayerName = TargetClient:GetControllingPlayer():GetName()
		} )
		return
	end

	local Now = SharedTime()
	local InviteDelaysForTarget = self.FriendGroupInviteDelaysBySteamID[ TargetSteamID ]
	if InviteDelaysForTarget then
		local NextInviteTime = InviteDelaysForTarget[ CallerSteamID ] or 0
		if NextInviteTime > Now then
			self:SendTranslatedNotification( Inviter, Shine.NotificationType.ERROR, "ERROR_INVITE_ON_COOLDOWN", {
				PlayerName = TargetClient:GetControllingPlayer():GetName()
			} )
			return
		end
	end

	-- Send the target an invitation to join the calling player.
	local ExpiryTime = Now + self.Config.TeamPreferences.FriendGroupInviteDurationInSeconds
	self.FriendGroupInvitesBySteamID[ TargetSteamID ] = {
		ExpiryTime = ExpiryTime,
		InviterID = CallerSteamID
	}

	-- Add a delay before another invite is allowed to avoid a player spamming invites to someone.
	InviteDelaysForTarget = InviteDelaysForTarget or {}
	InviteDelaysForTarget[ CallerSteamID ] = ExpiryTime + self.Config.TeamPreferences.FriendGroupInviteCooldownInSeconds
	self.FriendGroupInviteDelaysBySteamID[ TargetSteamID ] = InviteDelaysForTarget

	self:SendTranslatedNotification( Inviter, Shine.NotificationType.INFO, "SENT_INVITE_TO_FRIEND_GROUP", {
		PlayerName = TargetClient:GetControllingPlayer():GetName()
	} )

	-- Tell the target they've been invited.
	self:SendNetworkMessage( TargetClient, "FriendGroupInvite", {
		PlayerName = Inviter:GetControllingPlayer():GetName(),
		InviterID = CallerSteamID,
		ExpiryTime = ExpiryTime
	}, true )
end

local function GroupToString( Group )
	return table.ToString( {
		Clients = Shine.Stream.Of( Group.Clients ):Map( Shine.GetClientInfo ):AsTable()
	} )
end

function Plugin:MakeNewFriendGroup( Leader, Members, Silent )
	local NewGroup = {
		Clients = Members,
		Leader = Leader
	}
	self.FriendGroups[ #self.FriendGroups + 1 ] = NewGroup

	local LeaderName = Leader:GetControllingPlayer():GetName()
	for i = 1, #Members do
		local Member = Members[ i ]
		local MemberSteamID = Member:GetUserId()

		self.FriendGroupsBySteamID[ MemberSteamID ] = NewGroup
		self:SendNetworkMessage( NewGroup.Clients, "FriendGroupUpdated", {
			SteamID = MemberSteamID,
			Joined = true
		}, true )

		self:CancelFriendGroupInviteTo( MemberSteamID )

		if not Silent and Member ~= Leader then
			-- Tell everyone except the leader that they were added.
			self:SendTranslatedNotify( Member, "ADDED_TO_FRIEND_GROUP", {
				PlayerName = LeaderName
			} )
		end
	end

	self:SendNetworkMessage( NewGroup.Clients, "FriendGroupConfig", {
		LeaderID = Leader:GetUserId(),
		LeaderType = self:GetGroupLeaderType( NewGroup )
	}, true )

	self:UpdateFriendGroupTeamPreference( Leader )

	if self.Logger:IsDebugEnabled() then
		self.Logger:Debug( "Created new friend group: %s", GroupToString( NewGroup ) )
	end

	return NewGroup
end

function Plugin:AddClientToFriendGroup( Group, Client )
	if self.Logger:IsDebugEnabled() then
		self.Logger:Debug( "Adding %s to group: %s", Shine.GetClientInfo( Client ), GroupToString( Group ) )
	end

	local SteamID = Client:GetUserId()

	Group.Clients[ #Group.Clients + 1 ] = Client
	self.FriendGroupsBySteamID[ SteamID ] = Group
	-- Cancel any invite the client may have had.
	self:CancelFriendGroupInviteTo( SteamID )

	local LeaderType = self:GetGroupLeaderType( Group )
	if LeaderType ~= self.FriendGroupLeaderType.ALLOW_ALL_TO_JOIN then
		-- Group does not allow non-leaders to add players, cancel any pending
		-- invites from the joining client.
		self:CancelFriendGroupInvitesFrom( Client )
	end

	-- Notify all clients in the group of the new client.
	self:SendNetworkMessage( Group.Clients, "FriendGroupUpdated", {
		SteamID = SteamID,
		Joined = true
	}, true )

	-- Notify the new client of all the other members.
	for i = 1, #Group.Clients - 1 do
		self:SendNetworkMessage( Client, "FriendGroupUpdated", {
			SteamID = Group.Clients[ i ]:GetUserId(),
			Joined = true
		}, true )
	end

	-- Also send down the group's configuration to the new client.
	self:SendNetworkMessage( Client, "FriendGroupConfig", {
		LeaderID = Group.Leader:GetUserId(),
		LeaderType = LeaderType
	}, true )

	self:UpdateFriendGroupTeamPreference( Client )
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

	if not IsDisconnecting then
		-- Tell the client they've left the group.
		self:SendNetworkMessage( Client, "LeftFriendGroup", {}, true )
		-- Cancel any invites they sent while in the group.
		self:CancelFriendGroupInvitesFrom( Client )
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

	-- Tell everyone remaining in the group that they've left.
	self:SendNetworkMessage( Group.Clients, "FriendGroupUpdated", {
		SteamID = SteamID,
		Joined = false
	}, true )

	if Client == Group.Leader then
		-- Pick the next client in the list to be the new leader.
		Group.Leader = Group.Clients[ 1 ]

		self:SendNetworkMessage( Group.Clients, "FriendGroupConfig", {
			LeaderID = Group.Leader:GetUserId(),
			LeaderType = self:GetGroupLeaderType( Group )
		}, true )
	end

	self:UpdateFriendGroupTeamPreference( Group.Clients[ 1 ] )
end

function Plugin:CancelFriendGroupInviteTo( InvitedID )
	if not self.FriendGroupInvitesBySteamID[ InvitedID ] then return end

	local Client = Shine.GetClientByNS2ID( InvitedID )
	if Client then
		self:SendNetworkMessage( Client, "FriendGroupInviteCancelled", {}, true )
	end

	self.FriendGroupInvitesBySteamID[ InvitedID ] = nil

	self.Logger:Debug( "Removed friend group invite to %s", InvitedID )
end

function Plugin:CancelFriendGroupInvitesFrom( Client )
	local SteamID = Client:GetUserId()
	for InvitedID, Invite in pairs( self.FriendGroupInvitesBySteamID ) do
		if Invite.InviterID == SteamID then
			self:CancelFriendGroupInviteTo( InvitedID )
		end
	end
end

function Plugin:CancelAllFriendGroupInvites()
	for InvitedID in pairs( self.FriendGroupInvitesBySteamID ) do
		self:CancelFriendGroupInviteTo( InvitedID )
	end
end

function Plugin:HandleFriendGroupSetGameState( Gamerules, NewState, OldState )
	if NewState >= kGameState.Countdown then
		self:CancelAllFriendGroupInvites()
	end
end

function Plugin:HandleFriendGroupClientDisconnect( Client )
	local SteamID = Client:GetUserId()
	local Group = self.FriendGroupsBySteamID[ SteamID ]
	if Group then
		self:RemoveClientFromFriendGroup( Group, Client, true )
	end
	self.FriendGroupConfigBySteamID[ SteamID ] = nil
	self.FriendGroupInvitesBySteamID[ SteamID ] = nil
	self.FriendGroupInviteDelaysBySteamID[ SteamID ] = nil

	-- For every player the disconnecting client invited, cancel the invite.
	self:CancelFriendGroupInvitesFrom( Client )
end

function Plugin:GetFriendGroupTeamPreference( Group )
	local Preferences = { 0, 0 }
	for i = 1, #Group.Clients do
		local GroupMember = Group.Clients[ i ]
		local Preference = self:GetTeamPreference( GroupMember )
		if Preference then
			Preferences[ Preference ] = Preferences[ Preference ] + 1
		end
	end

	if Preferences[ 1 ] == Preferences[ 2 ] then
		return 0
	end

	return Preferences[ 1 ] > Preferences[ 2 ] and 1 or 2
end

local function UpdateGroupPreference( self, Group, SilentChange )
	local GroupPreference = self:GetFriendGroupTeamPreference( Group )
	self:SendNetworkMessage( Group.Clients, "GroupTeamPreference", {
		PreferredTeam = GroupPreference,
		Silent = SilentChange
	}, true )
end

function Plugin:UpdateFriendGroupTeamPreference( Client, SilentChange )
	local Group = self.FriendGroupsBySteamID[ Client:GetUserId() ]
	if not Group then return end

	if SilentChange == nil then
		SilentChange = not self:IsVoteAllowed()
	end

	UpdateGroupPreference( self, Group, SilentChange )
end

function Plugin:UpdateAllFriendGroupTeamPreferences()
	for i = 1, #self.FriendGroups do
		UpdateGroupPreference( self, self.FriendGroups[ i ], true )
	end
end
