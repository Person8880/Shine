--[[
	Override the badge mod's stuff to read from Shine's user data.
]]

local Decode = json.decode

local Plugin = {}
Plugin.Version = "1.0"

function Plugin:Initialise()
	local BadgeMixin = BadgeMixin

	if not BadgeMixin then 
		return false, "Badge mixin not found."
	end

	local OldInitBadge
	local GetBadge = BadgeMixin.GetBadgeIcon

	local BadgeData = Shine.GetUpValue( GetBadge, "kBadgeData" )
	if not BadgeData then 
		return false, "Badge data not found."
	end

	local function BadgeAuthorized( Client, BadgeID )
		local UserData = Shine.UserData

		local SteamID = Client:GetUserId()

		if type( BadgeID ) == "number" then
			return Server.GetIsDlcAuthorized( Client, BadgeID )
		elseif UserData then
			if not UserData.Users then return false end
			local User = UserData.Users[ tostring( SteamID ) ]

			if User and User.Group == BadgeID then return true end
		end
		
		return false
	end

	local BadgeCache = {}
	local function CacheGet( Client )
		local SteamID = Client:GetUserId()
		local Badge = BadgeCache[ SteamID ]

		if Badge then
			return Badge
		end

		Shared.SendHTTPRequest( "http://ns2comp.herokuapp.com/t/badge/"..tostring( SteamID ), "GET", function( Response )
			local Data = Decode( Response )
			
			if Data.override or not Badge or Badge == kBadges.None or Badge == kBadges.PAX2012 then
				BadgeCache[ SteamID ] = kBadges[ Data.badge ]
			end
		end )

		Badge = kBadges.None

		for Enum, Data in pairs( BadgeData ) do
			if Data.Id and BadgeAuthorized( Client, Data.Id ) then
				Badge = Enum
				break
			end
		end

		BadgeCache[ SteamID ] = Badge

		return Badge
	end

	OldInitBadge = Shine.ReplaceClassMethod( "BadgeMixin", "InitializeBadges", function( Mixin )
		local Client = Server.GetOwner( Mixin )

		if Client then
			Mixin:SetBadge( CacheGet( Client ) )
		end
	end )

	self.Enabled = true

	return true
end

function Plugin:Cleanup()
	self.Enabled = false
end

Shine:RegisterExtension( "badges", Plugin )
