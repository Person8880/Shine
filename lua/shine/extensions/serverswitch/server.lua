--[[
	Shine multi-server plugin.
]]

local Shine = Shine

local Notify = Shared.Message
local StringFormat = string.format
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

	Validator:AddFieldRule( "Servers", Validator.AllValuesSatisfy(
		Validator.ValidateField( "Name", Validator.IsAnyType( { "string", "nil" } ) ),
		Validator.ValidateField( "IP", Validator.IsType( "string" ), { DeleteIfFieldInvalid = true } ),
		Validator.ValidateField( "IP", Validator.MatchesPattern( "^%d%d?%d?%.%d%d?%d?%.%d%d?%d?%.%d%d?%d?$" ), {
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
