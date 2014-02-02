--[[
	Server switch shared part.
]]

local Plugin = {}

local ServerListMessage = {
	Name = "string (15)",
	IP = "string (16)",
	Port = "string (6)",
	ID = "integer (0 to 255)"
}

Shine:RegisterExtension( "serverswitch", Plugin )

function Plugin:SetupDataTable()
	self:AddNetworkMessage( "ServerList", ServerListMessage, "Client" )
end

if Server then return end

local Shine = Shine
local SGUI = Shine.GUI
local VoteMenu = Shine.VoteMenu

local Ceil = math.ceil
local StringExplode = string.Explode
local StringFormat = string.format
local TableCount = table.Count
local TableEmpty = table.Empty
local Vector = Vector

Plugin.ServerList = {}

local ZeroVec = Vector( 0, 0, 0 )

function Plugin:Initialise()
	self.Enabled = true

	return true
end

VoteMenu:AddPage( "ServerSwitch", function( self )
	self:AddBottomButton( "Back", function()
		self:SetPage( "Main" )
	end )

	local Servers = Plugin.ServerList

	local function ClickServer( ID )
		if self.GetCanSendVote() then
			Shared.ConsoleCommand( "sh_switchserver "..ID )

			return true
		end

		return false
	end

	for ID, Server in pairs( Servers ) do
		local Button = self:AddSideButton( Server.Name, function() ClickServer( ID ) end )

		Shine.QueryServer( Server.IP, tonumber( Server.Port ) + 1, function( Data )
			if not Data then return end
			if not SGUI.IsValid( Button ) then return end
			if Button:GetText() ~= Server.Name then return end

			local Connected = Data.numberOfPlayers
			local Max = Data.maxPlayers
			local Tags = Data.serverTags

			local TagTable = StringExplode( Tags, "|" )

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
		self:AddBottomButton( "Switch Server", function()
			self:SetPage( "ServerSwitch" )
		end )
	end
end )

function Plugin:ReceiveServerList( Data )
	if self.ServerList[ Data.ID ] then --We're refreshing the data.
		TableEmpty( self.ServerList )
	end

	self.ServerList[ Data.ID ] = {
		IP = Data.IP,
		Port = Data.Port,
		Name = Data.Name
	}
end
