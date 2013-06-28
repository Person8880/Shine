--[[
	Server switch shared part.
]]

local Plugin = {}

Shared.RegisterNetworkMessage( "Shine_SendServerList", {
	Name = "string (15)",
	IP = "string (16)",
	Port = "string (6)",
	ID = "integer (0 to 255)"
} )

Shine:RegisterExtension( "serverswitch", Plugin )

if Server then return end

local Ceil = math.ceil
local TableCount = table.Count
local TableEmpty = table.Empty
local Vector = Vector

Plugin.ServerList = {}

local ZeroVec = Vector( 0, 0, 0 )

function Plugin:Initialise()
	self.Enabled = true

	return true
end

function Plugin:OnVoteMenuOpen()
	TableEmpty( self.ServerList )
end

local function VoteButtonDoClick( self )
	if self.MainMenu then
		self:ClearOptions()
		self:PopulateMaps()
		self.VoteButton.Text:SetText( "Back" )

		return true
	else
		self:ClearOptions()
		self:Populate( Shine.ActivePlugins )
		self.VoteButton.Text:SetText( "Vote" )

		if self.SwitchServerButton then
			self.SwitchServerButton.Background:SetIsVisible( true )
		end
		
		return true
	end
end

local function PopulateServers( self )
	local Servers = Plugin.ServerList
		
	local NumServers = TableCount( Servers )
	local HalfServers = Ceil( NumServers * 0.5 )

	local MenuButtons = self.MenuButtons

	local CurCount = 1

	local function ClickServer( ID )
		if self.GetCanSendVote() then
			Shared.ConsoleCommand( "sh_switchserver "..ID )

			return true
		end

		return false
	end

	for ID, Server in pairs( Servers ) do
		if CurCount <= HalfServers then
			MenuButtons[ #MenuButtons + 1 ] = self:CreateMenuButton( self.TeamType, Server.Name, GUIItem.Left, CurCount, HalfServers,
			function() return ClickServer( ID ) end )
		else
			MenuButtons[ #MenuButtons + 1 ] = self:CreateMenuButton( self.TeamType, Server.Name, GUIItem.Right, CurCount - HalfServers, HalfServers,
			function() return ClickServer( ID ) end )
		end

		CurCount = CurCount + 1
	end
end

Client.HookNetworkMessage( "Shine_SendServerList", function( Data )
	Plugin.ServerList[ Data.ID ] = {
		IP = Data.IP,
		Port = Data.Port,
		Name = Data.Name
	}

	local VoteMenu = Shine.VoteMenu

	if not VoteMenu or VoteMenu.SwitchServerButton then return end

	if GUIShineVoteMenu.VoteButtonDoClick ~= VoteButtonDoClick then
		GUIShineVoteMenu.VoteButtonDoClick = VoteButtonDoClick
		VoteMenu.VoteButtonDoClick = VoteButtonDoClick
	end

	if not GUIShineVoteMenu.PopulateServers then
		GUIShineVoteMenu.PopulateServers = PopulateServers
		VoteMenu.PopulateServers = PopulateServers
	end

	local BackButton = VoteMenu:CreateCustomButton( "BackButton", ZeroVec, GUIItem.Middle, GUIItem.Bottom, "Back",
	function( self )
		self:ClearOptions()

		self.SwitchServerButton.Background:SetIsVisible( true )

		self.HideVoteButton = false

		if self.VoteButton then
			self.VoteButton.Background:SetIsVisible( true )
		end

		self:Populate( Shine.ActivePlugins )

		return true
	end )
	local Size = BackButton.Background:GetSize()

	BackButton.Background:SetIsVisible( false )

	local Pos = Vector( -Size.x * 0.5, -Size.y * 0.5, 0 )

	BackButton.Background:SetPosition( Pos )

	local SwitchButton = VoteMenu:CreateCustomButton( "SwitchServerButton", Pos, GUIItem.Middle, GUIItem.Bottom, "Switch Server", 
	function( self )
		self:ClearOptions()

		if self.VoteButton then
			self.VoteButton.Background:SetIsVisible( false )
		end

		self.BackButton.Background:SetIsVisible( true )

		self.HideVoteButton = true

		self:PopulateServers()

		return true
	end )
end )
