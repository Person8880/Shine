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

local Shine = Shine
local SGUI = Shine.GUI

local Ceil = math.ceil
local StringFormat = string.format
local TableCount = table.Count
local TableEmpty = table.Empty
local Vector = Vector

Plugin.ServerList = {}

local ZeroVec = Vector( 0, 0, 0 )

function Plugin:Initialise()
	local VoteMenu = Shine.VoteMenu

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

			Shine.QueryServerPopulation( Server.IP, tonumber( Server.Port ) + 1, function( Connected, Max )
				if not Connected then return end
				if not SGUI.IsValid( Button ) then return end
				if Button:GetText() ~= Server.Name then return end

				Button:SetText( StringFormat( "%s (%i/%i)", Server.Name, Connected, Max ) )
			end )
		end
	end )

	VoteMenu:EditPage( "Main", function( self )
		if next( Plugin.ServerList ) then
			self:AddBottomButton( "Switch Server", function()
				self:SetPage( "ServerSwitch" )
			end )
		end
	end )

	self.Enabled = true

	return true
end

Client.HookNetworkMessage( "Shine_SendServerList", function( Data )
	if Plugin.ServerList[ Data.ID ] then --We're refreshing the data.
		TableEmpty( Plugin.ServerList )
	end

	Plugin.ServerList[ Data.ID ] = {
		IP = Data.IP,
		Port = Data.Port,
		Name = Data.Name
	}
end )
