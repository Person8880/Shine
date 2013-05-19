--[[
	Override the badge mod's stuff to read from Shine's user data.
]]

local Decode = json.decode

local Plugin = {}
Plugin.Version = "1.0"

function Plugin:Initialise()
	Shine.Hook.Add( "Think", "ReplaceBadges", function( Deltatime )
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

		local function FindBadge( ID )
			if not ID then return nil end
			
			for Enum, Data in pairs( BadgeData ) do
				if Data.Id == ID then
					return Enum
				end
			end

			return nil
		end

		local PAX2012ProductId = 4931

		local BadgeCache = {}
		local function CacheGet( Client )
			local SteamID = Client:GetUserId()
			local Badge = BadgeCache[ SteamID ]

			if Badge then
				return Badge
			end

			Shared.SendHTTPRequest( "http://ns2comp.herokuapp.com/t/badge/"..tostring( SteamID ), "GET", function( Response )
				local Data = Decode( Response )
				if not Data then return end
				
				if Data.override or not Badge or Badge == kBadges.None or Badge == kBadges.PAX2012 then
					BadgeCache[ SteamID ] = kBadges[ Data.badge ]
				end
			end )

			Badge = kBadges.None

			if Server.GetIsDlcAuthorized( Client, PAX2012ProductId ) then
				Badge = kBadges.PAX2012
			end

			local UserData = Shine.UserData

			if UserData then --Support defined badges in the Shine user config.
				local User = UserData.Users[ tostring( SteamID ) ]
				local GroupName = User and User.Group

				if GroupName then
					local Group = UserData.Groups[ GroupName ]

					if Group then
						local NewBadge = FindBadge( Group.Badge or Group.badge )

						if NewBadge then 
							BadgeCache[ SteamID ] = NewBadge

							return NewBadge
						end
					end

					local NewBadge = FindBadge( GroupName )

					if NewBadge then
						BadgeCache[ SteamID ] = NewBadge

						return NewBadge
					end
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

		Shine.Hook.Remove( "Think", "ReplaceBadges" )
	end )

	self.Enabled = true

	return true
end

function Plugin:Cleanup()
	self.Enabled = false
end

Shine:RegisterExtension( "badges", Plugin )
