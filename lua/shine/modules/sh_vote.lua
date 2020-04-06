--[[
	Provides vote tracking by updating a vote menu button.
]]

local Plugin, UseStandardBehaviour = ...
local Module = {}

function Module:SetupDataTable()
	self:AddDTVar( "integer", "CurrentVotes", 0 )
	self:AddDTVar( "integer", "RequiredVotes", 0 )
	self:AddNetworkMessage( "HasVoted", { HasVoted = "boolean" }, "Client" )
end

if Server then
	function Module:ResetVoteCounters()
		self.dt.CurrentVotes = 0
		self.dt.RequiredVotes = 0
		self:NotifyVoteReset( nil )
	end

	function Module:UpdateVoteCounters( VoteObject )
		self.dt.CurrentVotes = VoteObject:GetVotes()
		self.dt.RequiredVotes = VoteObject.VotesNeeded()
	end

	function Module:NotifyVoted( Client )
		self:SendNetworkMessage( Client, "HasVoted", { HasVoted = true }, true )
	end

	function Module:NotifyVoteReset( Client )
		self:SendNetworkMessage( Client, "HasVoted", { HasVoted = false }, true )
	end

	if UseStandardBehaviour then
		local Ceil = math.ceil
		local next = next
		local SharedTime = Shared.GetTime
		local TableShallowMerge = table.ShallowMerge

		Shine.LoadPluginModule( "vote.lua", Plugin )

		local FractionKey = Plugin.FractionConfigKey or "PercentNeeded"

		Module.DefaultConfig = {
			VoteTimeoutInSeconds = 60,
			[ FractionKey ] = 0.6,
			NotifyOnVote = true
		}
		if not Plugin.UseCustomVoteTiming then
			Module.DefaultConfig.BlockUntilSecondsIntoMap = 0
		end

		function Module:Initialise()
			assert( Shine.IsCallable( self.OnVotePassed ), "Plugin has not provided OnVotePassed method" )

			local function GetVotesNeeded()
				return self:GetVotesNeeded()
			end

			local function OnVotePassed()
				self:OnVotePassed()
			end

			self.Vote = Shine:CreateVote( GetVotesNeeded, self:WrapCallback( OnVotePassed ) )
			self:SetupVoteTimeout( self.Vote, self.Config.VoteTimeoutInSeconds )
			function self.Vote.OnReset()
				self:ResetVoteCounters()
			end

			self:CreateCommands()

			return true
		end

		function Module:GetVotesNeeded()
			local PlayerCount = self:GetPlayerCountForVote()
			return Ceil( PlayerCount * self.Config[ FractionKey ] )
		end

		function Module:ClientConnect( Client )
			self:UpdateVoteCounters( self.Vote )
		end

		function Module:ClientDisconnect( Client )
			self.Vote:ClientDisconnect( Client )
			self:UpdateVoteCounters( self.Vote )
		end

		function Module:CanStartVote()
			local Time = SharedTime()
			local TimeTillVoteAllowed = self.Config.BlockUntilSecondsIntoMap - Time
			if TimeTillVoteAllowed > 0 then
				return false, "ERROR_MUST_WAIT", TableShallowMerge( {
					SecondsToWait = Ceil( TimeTillVoteAllowed )
				}, self:GetVoteNotificationParams() )
			end
			return true
		end

		function Module:AddVote( Client )
			local Success, Err, Args = self:CanClientVote( Client )
			if not Success then
				return false, Err, Args
			end

			Success, Err, Args = self:CanStartVote()
			if not Success then
				return false, Err, Args
			end

			if not self.Vote:AddVote( Client ) then
				return false, "ERROR_ALREADY_VOTED", self:GetVoteNotificationParams()
			end

			return true
		end

		function Module:GetVoteNotificationParams()
			return {}
		end

		function Module:CreateCommands()
			self:BindCommand( self.VoteCommand.ConCommand, self.VoteCommand.ChatCommand, function( Client )
				if not Client then return end

				local Player = Client:GetControllingPlayer()
				local PlayerName = Player and Player:GetName() or "NSPlayer"

				local Success, Err, Args = self:AddVote( Client )
				if not Success then
					if not Args or next( Args ) == nil then
						self:NotifyTranslatedError( Client, Err )
					else
						self:SendTranslatedError( Client, Err, Args )
					end
					return
				end

				local Succeeded = self.Vote:HasSucceededOnLastVote()
				if Succeeded and not self.ShowLastVote then return end

				local MessageParams = self:GetVoteNotificationParams()
				MessageParams.VotesNeeded = Succeeded and 0 or self.Vote:GetVotesNeeded()

				if self.Config.NotifyOnVote then
					MessageParams.PlayerName = PlayerName
					self:SendTranslatedNotify( nil, "PLAYER_VOTED", MessageParams )
				else
					self:SendTranslatedNotify( Client, "PLAYER_VOTED_PRIVATE", MessageParams )
				end

				if not Succeeded then
					self:UpdateVoteCounters( self.Vote )
					self:NotifyVoted( Client )
				end
			end, true ):Help( self.VoteCommand.Help )
		end
	end

	Plugin:AddModule( Module )

	return
end

local StringFormat = string.format

function Module:ReceiveHasVoted( Message )
	self.HasVoted = Message.HasVoted
	self:UpdateVoteButton()
end

function Module:UpdateVoteButton()
	local Button = Shine.VoteMenu:GetButtonByPlugin( self.VoteButtonName )
	if not Button then return end

	if self.dt.CurrentVotes == 0 or self.dt.RequiredVotes == 0 then
		Button:SetText( Button.DefaultText )
		Shine.VoteMenu:MarkAsSelected( Button, false )

		return
	end

	if self.VoteButtonCheckMarkXScale then
		Button.CheckMarkXScale = self.VoteButtonCheckMarkXScale
	end

	if self.HasVoted then
		Shine.VoteMenu:MarkAsSelected( Button, true )
	end

	-- Update the button with the current vote count.
	Button:SetText( StringFormat( "%s (%d/%d)", Button.DefaultText,
		self.dt.CurrentVotes,
		self.dt.RequiredVotes ) )
end

function Module:NetworkUpdate( Key, Old, New )
	if Key == "RequiredVotes" or Key == "CurrentVotes" then
		if not Shine.VoteMenu.Visible then return end

		self:UpdateVoteButton()
	end
end

function Module:OnFirstThink()
	Shine.VoteMenu:EditPage( "Main", function( VoteMenu )
		if not self.Enabled then return end

		self:UpdateVoteButton()
	end )
end

Plugin:AddModule( Module )
