--[[
	Provides vote tracking by updating a vote menu button.
]]

local Plugin = ...
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
		self:SendNetworkMessage( nil, "HasVoted", { HasVoted = false }, true )
	end

	function Module:UpdateVoteCounters( VoteObject )
		self.dt.CurrentVotes = VoteObject:GetVotes()
		self.dt.RequiredVotes = VoteObject.VotesNeeded()
	end

	function Module:NotifyVoted( Client )
		self:SendNetworkMessage( Client, "HasVoted", { HasVoted = true }, true )
	end

	Plugin:AddModule( Module )

	return
end

local SGUI = Shine.GUI
local TickTexture = PrecacheAsset( "ui/checkmark.dds" )

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

		if SGUI.IsValid( Button.CheckMark ) then
			Button.CheckMark:Destroy()
			Button.CheckMark = nil
		end

		return
	end

	if self.HasVoted and not SGUI.IsValid( Button.CheckMark ) then
		local CheckMark = SGUI:Create( "Image", Button )
		local Height = Button:GetSize().y * 0.75
		CheckMark:SetAnchor( "CentreRight" )
		CheckMark:SetSize( Vector2( Height, Height ) )
		CheckMark:SetPos( Vector2( -Height, -Height * 0.5 ) )
		CheckMark:SetTexture( TickTexture )
		Button.CheckMark = CheckMark
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
