--[[
	Shine multi-server plugin.
]]

local Shine = Shine

local Notify = Shared.Message
local StringFormat = string.format
local StringMatch = string.match
local tonumber = tonumber

local Plugin = ...
Plugin.Version = "1.0"

Plugin.HasConfig = true
Plugin.ConfigName = "ServerSwitch.json"

Plugin.DefaultConfig = {
	Servers = {
		{ Name = "My awesome server", IP = "127.0.0.1", Port = "27015", Password = "" }
	}
}

Plugin.CheckConfigTypes = true

do
	local Validator = Shine.Validator()

	local BitLShift = bit.lshift
	local select = select

	local function IPToInt( ... )
		if not ... then return nil end

		for i = 1, 4 do
			if tonumber( select( i, ... ), 10 ) > 255 then
				return -1
			end
		end

		local Byte1, Byte2, Byte3, Byte4 = ...

		-- Not using lshift for the first byte to avoid getting a signed int back.
		return tonumber( Byte1, 10 ) * 16777216 +
			BitLShift( tonumber( Byte2, 10 ), 16 ) +
			BitLShift( tonumber( Byte3, 10 ), 8 ) +
			tonumber( Byte4, 10 )
	end

	local function IsValidIPAddress( IP )
		if IP <= 0 then
			return false
		end

		-- 255.255.255.255 or higher.
		if IP >= 0xFFFFFFFF then
			return false
		end

		-- 127.x.x.x
		if IP >= 0x7F000000 and IP <= 0x7FFFFFFF then
			return false
		end

		-- 10.x.x.x
		if IP >= 0x0A000000 and IP <= 0x0AFFFFFF then
			return false
		end

		-- 172.16.0.0 - 172.31.255.255
		if IP >= 0xAC100000 and IP <= 0xAC1FFFFF then
			return false
		end

		-- 192.168.x.x
		if IP >= 0xC0A80000 and IP <= 0xC0A8FFFF then
			return false
		end

		return true
	end

	Validator:AddFieldRule( "Servers", Validator.AllValuesSatisfy(
		Validator.ValidateField( "Name", Validator.IsAnyType( { "string", "nil" } ) ),
		Validator.ValidateField( "IP", Validator.IsType( "string" ), { DeleteIfFieldInvalid = true } ),
		Validator.ValidateField( "IP", {
			Check = function( Address )
				local IP = IPToInt( StringMatch( Address, "^(%d%d?%d?)%.(%d%d?%d?)%.(%d%d?%d?)%.(%d%d?%d?)$" ) )
				if IP then
					return not IsValidIPAddress( IP )
				end

				-- Hostname must contain at least 2 segments.
				if StringMatch( Address, "%." ) then
					return false
				end

				return true
			end,
			Fix = function() return nil end,
			Message = function()
				return "%s must have a valid IP address or hostname"
			end
		}, {
			DeleteIfFieldInvalid = true
		} ),
		Validator.ValidateField( "Port", Validator.IsAnyType( { "string", "number" } ), {
			DeleteIfFieldInvalid = true
		} ),
		Validator.ValidateField( "Port", Validator.IfType( "string", Validator.MatchesPattern( "^%d+$" ) ), {
			DeleteIfFieldInvalid = true
		} ),
		Validator.ValidateField( "Password", Validator.IsAnyType( { "string", "nil" } ) )
	) )

	Plugin.ConfigValidator = Validator
end

function Plugin:Initialise()
	self:CreateCommands()
	self.Enabled = true

	return true
end

function Plugin:OnNetworkingReady()
	for Client in Shine.IterateClients() do
		self:ProcessClient( Client )
	end
end

function Plugin:SendServerData( Client, ID, Data )
	self:SendNetworkMessage( Client, "ServerList", {
		Name = Data.Name and Data.Name:sub( 1, 15 ) or "No Name",
		IP = Data.IP,
		Port = tonumber( Data.Port ) or 27015,
		ID = ID
	}, true )
end

function Plugin:ProcessClient( Client )
	local Servers = self.Config.Servers
	local IsUser = Shine:GetUserData( Client )

	for i = 1, #Servers do
		local Data = Servers[ i ]

		if Data.UsersOnly then
			if IsUser then
				self:SendServerData( Client, i, Data )
			end
		else
			self:SendServerData( Client, i, Data )
		end
	end
end

function Plugin:ClientConnect( Client )
	self:ProcessClient( Client )
end

function Plugin:OnUserReload()
	for Client in Shine.IterateClients() do
		self:ProcessClient( Client )
	end
end

function Plugin:CreateCommands()
	local function SwitchServer( Client, Num )
		if not Client then return end
		local Player = Client:GetControllingPlayer()

		if not Player then return end

		local ServerData = self.Config.Servers[ Num ]

		if not ServerData then
			Shine:NotifyError( Client, "Invalid server number." )
			return
		end

		if ServerData.UsersOnly then
			local UserTable = Shine:GetUserData( Client )

			if not UserTable then
				Shine:NotifyError( Client, "You are not allowed to switch to that server." )

				return
			end
		end

		local Password = ServerData.Password

		if not Password then
			Password = ""
		elseif Password ~= "" then
			Password = " "..Password
		end

		Shine.SendNetworkMessage( Client, "Shine_Command", {
			Command = StringFormat( "connect %s:%s%s", ServerData.IP, ServerData.Port, Password )
		}, true )
	end
	local SwitchServerCommand = self:BindCommand( "sh_switchserver", "server", SwitchServer, true )
	SwitchServerCommand:AddParam{ Type = "number", Min = 1, Round = true,
		Error = "Please specify a server number to switch to." }
	SwitchServerCommand:Help( "Connects you to the given registered server." )

	local function ListServers( Client )
		local ServerData = self.Config.Servers

		if #ServerData == 0 then
			if Client then
				ServerAdminPrint( Client, "There are no registered servers." )
			else
				Notify( "There are no registered servers." )
			end

			return
		end

		for i = 1, #ServerData do
			local Data = ServerData[ i ]

			local String = StringFormat( "%i) - %s | %s:%s", i, Data.Name or "No name",
				Data.IP, Data.Port )

			if Client then
				ServerAdminPrint( Client, String )
			else
				Notify( String )
			end
		end
	end
	local ListServersCommand = self:BindCommand( "sh_listservers", nil, ListServers, true )
	ListServersCommand:Help( "Lists all registered servers that you can connect to." )
end
