--[[
	Server switch client.
]]

local Plugin = ...

local Shine = Shine
local SGUI = Shine.GUI
local VoteMenu = Shine.VoteMenu

local Ceil = math.ceil
local StringExplode = string.Explode
local StringFormat = string.format
local TableCount = table.Count
local TableEmpty = table.Empty
local Vector = Vector

local ZeroVec = Vector( 0, 0, 0 )

function Plugin:Initialise()
	self.Enabled = true
	self.ServerList = {}

	return true
end

VoteMenu:AddPage( "ServerSwitch", function( self )
	local Servers = Plugin.ServerList
	if not Plugin.Enabled or not Servers then
		self:SetPage( "Main" )
		return
	end

	self:AddBottomButton( Plugin:GetPhrase( "BACK" ), function()
		self:SetPage( "Main" )
	end )

	local function ClickServer( ID )
		if self.GetCanSendVote() then
			Shared.ConsoleCommand( "sh_switchserver "..ID )

			return true
		end

		return false
	end

	for ID, Server in pairs( Servers ) do
		local Button = self:AddSideButton( Server.Name, function()
			return ClickServer( ID )
		end )

		Shine.QueryServer( Server.IP, tonumber( Server.Port ) + 1, function( Data )
			if not Data then return end
			if not SGUI.IsValid( Button ) then return end
			if Button:GetText() ~= Server.Name then return end

			local Connected = Data.numberOfPlayers
			local Max = Data.maxPlayers
			local Tags = Data.serverTags

			local TagTable = StringExplode( Tags, "|", true )

			for i = 1, #TagTable do
				local Tag = TagTable[ i ]

				local Match = Tag:match( "R_S(%d+)" )

				if Match then
					Max = Max - tonumber( Match )
					break
				end
			end

			Button:SetText( StringFormat( "%s (%i/%i)", Server.Name, Connected, Max ) )
		end )
	end
end )

VoteMenu:EditPage( "Main", function( self )
	if Plugin.Enabled and next( Plugin.ServerList ) then
		self:AddBottomButton( Plugin:GetPhrase( "VOTEMENU_BUTTON" ), function()
			self:SetPage( "ServerSwitch" )
		end )
	end
end )

function Plugin:ReceiveServerList( Data )
	if self.ServerList[ Data.ID ] then -- We're refreshing the data.
		TableEmpty( self.ServerList )
	end

	self.ServerList[ Data.ID ] = {
		IP = Data.IP,
		Port = Data.Port,
		Name = Data.Name
	}
end

function Plugin:Cleanup()
	self.ServerList = nil
	return self.BaseClass.Cleanup( self )
end
