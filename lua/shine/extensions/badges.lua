--[[
	Override the badge mod's stuff to read from Shine's user data.
]]

local type = type

local Plugin = {}
Plugin.Version = "1.0"

local function isstring( String )
	return type( String ) == "string"
end

function Plugin:Initialise()
	if self.Enabled ~= nil then 
		self.Enabled = true

		return true
	end
	
	Shine.Hook.Add( "Think", "ReplaceBadges", function( Deltatime )
		local BadgeMixin = BadgeMixin

		if not BadgeMixin then
			return
		end

		if not kBadges then
			return
		end

		if not getBadge then return end

		--Comply with the reserved settings, no cheating here.
		local ReservedBadges = {}

		local OldReserved = Shine.GetUpValue( getBadge, "kReservedBadges" )

		if OldReserved then
			for i = 1, #OldReserved do
				ReservedBadges[ OldReserved[ i ] ] = true
			end
		end

		local BadgeData = {}

		--Enum tables throw an error when trying to access an index that doesn't exist. I don't even.
		for k, v in pairs( kBadges ) do
			if isstring( k ) then
				BadgeData[ k ] = v
			end
		end

		local BadgeCache = {}
		local function GetBadge( Client )
			local SteamID = Client:GetUserId()
			local Badge = BadgeCache[ SteamID ]

			if Badge then
				return Badge
			end

			Badge = BadgeData.None

			local UserData = Shine.UserData

			if UserData then --Support defined badges in the Shine user config.
				local User = UserData.Users[ tostring( SteamID ) ]
				local GroupName = User and User.Group

				if GroupName then
					local Group = UserData.Groups[ GroupName ]

					if Group and ( Group.Badge or Group.badge ) then
						local NewBadge = BadgeData[ Group.Badge or Group.badge ]

						if NewBadge and not ReservedBadges[ NewBadge ] then 
							Badge = NewBadge
						end
					end

					if Badge == BadgeData.None then
						local NewBadge = BadgeData[ GroupName ]

						if NewBadge and not ReservedBadges[ NewBadge ] then
							Badge = NewBadge
						end
					end
				end
			end

			BadgeCache[ SteamID ] = Badge

			setBadge( Client, Badge )

			return Badge
		end
		getBadge = GetBadge

		Shine.Hook.Remove( "Think", "ReplaceBadges" )
	end )

	self.Enabled = true

	return true
end

function Plugin:Cleanup()
	self.Enabled = false
end

Shine:RegisterExtension( "badges", Plugin )
