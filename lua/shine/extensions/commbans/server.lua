--[[
	Shine commander bans plugin.
]]

local Plugin = Plugin

local Shine = Shine

local Encode = json.encode
local Decode = json.decode
local GetOwner = Server.GetOwner
local Max = math.max
local Time = os.time

Plugin.Version = "1.0"
Plugin.HasConfig = true
Plugin.ConfigName = "CommBans.json"

Plugin.DefaultConfig = {
	Banned = {},
	BansSubmitURL = "",
	BansSubmitArguments = {},
	MaxSubmitRetries = 3,
	SubmitTimeout = 5,
	DefaultBanTime = 60
}

Plugin.CheckConfig = true
Plugin.ListPermission = "sh_uncommban"

function Plugin:Initialise()
	self:GenerateNetworkData()

	self.Config.MaxSubmitRetries = Max( self.Config.MaxSubmitRetries, 0 )
	self.Config.SubmitTimeout = Max( self.Config.SubmitTimeout, 0 )
	self.Config.DefaultBanTime = Max( self.Config.DefaultBanTime, 0 )

	self.Retries = {}
	self.NextNotify = setmetatable( {}, { __mode = "k" } )

	self:CreateCommands()
	self:CheckBans()

	self.Enabled = true

	return true
end

function Plugin:Notify( Player, String, Format, ... )
	Shine:NotifyDualColour( Player, 255, 50, 0, "[CommBan]", 255, 255, 255, String, Format, ... )
end

--[[
	Deny commanding if they're banned.
]]
function Plugin:CheckCommLogin( CommandStation, Player )
	local Client = GetOwner( Player )
	if not Client then return end

	local ID = tostring( Client:GetUserId() )
	local BanData = self.Config.Banned[ ID ]

	if not BanData then return end
	
	local CurTime = Time()

	if BanData.UnbanTime == 0 or BanData.UnbanTime > CurTime then
		if Player.TriggerInvalidSound then
			Player:TriggerInvalidSound()
		end

		if ( self.NextNotify[ Client ] or 0 ) <= CurTime then
			self.NextNotify[ Client ] = CurTime + 10

			local Duration = BanData.UnbanTime == 0 and "permanently"
				or "for "..string.TimeToString( BanData.UnbanTime - CurTime )

			self:Notify( Client, "You are banned from commanding %s.", true, Duration )
		end

		return false
	end

	self:RemoveBan( ID, 0 )
end

--[[
	Creates the plugins console/chat commands.
]]
function Plugin:CreateCommands()
	local function Ban( Client, Target, Duration, Reason )
		Duration = Duration * 60
		local ID = tostring( Target:GetUserId() )

		--We're currently waiting for a response on this ban.
		if self.Retries[ ID ] then
			Shine:NotifyError( Client, "Please wait for the current ban request on %s to finish.", true, ID )
			Shine:AdminPrint( Client, "Please wait for the current ban request on %s to finish.", true, ID )

			return
		end

		local BanningName = Client and Client:GetControllingPlayer():GetName() or "Console"
		local BanningID = Client and Client:GetUserId() or 0
		local Player = Target:GetControllingPlayer()
		local TargetName = Player:GetName()

		self:AddBan( ID, TargetName, Duration, BanningName, BanningID, Reason )

		if Player:isa( "Commander" ) then
			Player:Eject()
		end

		local DurationString = Duration ~= 0 and "for "..string.TimeToString( Duration ) or "permanently"

		Shine:CommandNotify( Client, "banned %s from commanding %s.", true, TargetName, DurationString )
		Shine:AdminPrint( nil, "%s banned %s[%s] from commanding %s.", true, BanningName, TargetName, ID, DurationString )
	end
	local BanCommand = self:BindCommand( "sh_commban", "commban", Ban )
	BanCommand:AddParam{ Type = "client", NotSelf = true }
	BanCommand:AddParam{ Type = "number", Min = 0, Round = true, Optional = true, Default = self.Config.DefaultBanTime }
	BanCommand:AddParam{ Type = "string", Optional = true, TakeRestOfLine = true, Default = "No reason given." }
	BanCommand:Help( "<player> <duration in minutes> <reason> Bans the given player from commanding for the given time in minutes. 0 is a permanent ban." )

	local function Unban( Client, ID )
		if self.Config.Banned[ ID ] then
			--We're currently waiting for a response on this ban.
			if self.Retries[ ID ] then
				Shine:NotifyError( Client, "Please wait for the current ban request on %s to finish.", true, ID )
				Shine:AdminPrint( Client, "Please wait for the current ban request on %s to finish.", true, ID )

				return
			end

			local Unbanner = ( Client and Client.GetUserId and Client:GetUserId() ) or 0

			self:RemoveBan( ID, nil, Unbanner )
			Shine:AdminPrint( nil, "%s unbanned %s from commanding.", true, Client and Client:GetControllingPlayer():GetName() or "Console", ID )

			return
		end

		local ErrorText = StringFormat( "%s is not banned from commanding.", ID )

		Shine:AdminPrint( Client, ErrorText )
		Shine:NotifyError( Client, ErrorText )
	end
	local UnbanCommand = self:BindCommand( "sh_uncommban", "uncommban", Unban )
	UnbanCommand:AddParam{ Type = "string", Error = "Please specify a Steam ID to unban." }
	UnbanCommand:Help( "<steamid> Unbans the given Steam ID from commanding." )

	local function BanID( Client, ID, Duration, Reason )
		Duration = Duration * 60

		--We want the NS2ID, not Steam ID.
		if ID:find( "STEAM" ) then
			ID = Shine.SteamIDToNS2( ID )

			if not ID then
				Shine:NotifyError( Client, "Invalid Steam ID for banning." )
				Shine:AdminPrint( Client, "Invalid Steam ID for banning." )

				return
			end
		end

		if not Shine:CanTarget( Client, tonumber( ID ) ) then
			Shine:NotifyError( Client, "You cannot ban %s from commanding.", true, ID )
			Shine:AdminPrint( Client, "You cannot ban %s from commanding.", true, ID )

			return
		end

		--We're currently waiting for a response on this ban.
		if self.Retries[ ID ] then
			Shine:NotifyError( Client, "Please wait for the current ban request on %s to finish.", true, ID )
			Shine:AdminPrint( Client, "Please wait for the current ban request on %s to finish.", true, ID )

			return
		end

		local BanningName = Client and Client:GetControllingPlayer():GetName() or "Console"
		local BanningID = Client and Client:GetUserId() or 0
		local Target = Shine.GetClientByNS2ID( tonumber( ID ) )
		local TargetName = "<unknown>"
		
		if Target then
			TargetName = Target:GetControllingPlayer():GetName()
		end
		
		if self:AddBan( ID, TargetName, Duration, BanningName, BanningID, Reason ) then
			local DurationString = Duration ~= 0 and "for "..string.TimeToString( Duration ) or "permanently"

			Shine:AdminPrint( nil, "%s banned %s[%s] from commanding %s.", true, BanningName, TargetName, ID, DurationString )
			
			if Target then
				local TargetPlayer = Target:GetControllingPlayer()
				if TargetPlayer and TargetPlayer:isa( "Commander" ) then
					TargetPlayer:Eject()
				end

				Shine:CommandNotify( Client, "banned %s from commanding %s.", true, TargetName, DurationString )
			end

			return
		end

		Shine:NotifyError( Client, "Invalid Steam ID for banning." )
		Shine:AdminPrint( Client, "Invalid Steam ID for banning." )
	end
	local BanIDCommand = self:BindCommand( "sh_commbanid", "banid", BanID )
	BanIDCommand:AddParam{ Type = "string", Error = "Please specify a Steam ID to ban." }
	BanIDCommand:AddParam{ Type = "number", Min = 0, Round = true, Optional = true, Default = self.Config.DefaultBanTime }
	BanIDCommand:AddParam{ Type = "string", Optional = true, TakeRestOfLine = true, Default = "No reason given." }
	BanIDCommand:Help( "<steamid> <duration in minutes> <reason> Bans the given Steam ID from commanding for the given time in minutes. 0 is a permanent ban." )
end
