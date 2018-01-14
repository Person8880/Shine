--[[
	Shine adverts system.
]]

local Shine = Shine

local IsType = Shine.IsType
local TableQuickCopy = table.QuickCopy
local TableQuickShuffle = table.QuickShuffle
local TableRemove = table.remove
local tonumber = tonumber

local Plugin = {}
Plugin.Version = "1.2"
Plugin.PrintName = "Adverts"

Plugin.HasConfig = true
Plugin.CheckConfigTypes = true
Plugin.ConfigName = "Adverts.json"
Plugin.DefaultConfig = {
	Adverts = {
		{
			Message = "Welcome to Natural Selection 2.",
			Type = "chat",
			Colour = { 255, 255, 255 }
		},
		{
			Message = "This server is running the Shine administration mod.",
			Type = "chat",
			Colour = { 255, 255, 255 }
		}
	},
	Interval = 60,
	RandomiseOrder = false
}

Plugin.ConfigMigrationSteps = {
	{
		VersionTo = "1.2",
		Apply = function( Config )
			local Adverts = Config.Adverts
			if not IsType( Adverts, "table" ) then return end

			for i = 1, #Adverts do
				local Advert = Adverts[ i ]
				if IsType( Advert, "table" ) then
					Advert.Colour = { Advert.R or 255, Advert.G or 255, Advert.B or 255 }
					Advert.R = nil
					Advert.G = nil
					Advert.B = nil
				end
			end
		end
	}
}

Plugin.TimerName = "Adverts"

function Plugin:Initialise()
	self.AdvertsList = TableQuickCopy( self.Config.Adverts )
	self:SetupTimer()
	self.Enabled = true

	return true
end

local function UnpackColour( Colour )
	if not Colour then return 255, 255, 255 end

	return tonumber( Colour[ 1 ] ) or 255,
		tonumber( Colour[ 2 ] ) or 255,
		tonumber( Colour[ 3 ] ) or 255
end

function Plugin:ParseAdvert( ID, Advert )
	if IsType( Advert, "string" ) then
		Shine:NotifyColour( nil, 255, 255, 255, Advert )

		return true
	end

	if not IsType( Advert, "table" ) then
		self:Print( "Misconfigured advert #%i, neither a table nor a string.", true, ID )

		TableRemove( self.AdvertsList, ID )

		return false
	end

	local Message = Advert.Message
	if not IsType( Message, "string" ) then
		self:Print( "Misconfigured advert #%i, missing or invalid \"Message\" value.",
			true, ID )

		TableRemove( self.AdvertsList, ID )

		return false
	end

	local R, G, B = UnpackColour( Advert.Colour )
	local Type = Advert.Type

	if not Type or Type == "chat" then
		if IsType( Advert.Prefix, "string" ) then
			-- Send the advert with a coloured prefix.
			local PR, PG, PB = UnpackColour( Advert.PrefixColour or { 255, 255, 255 } )

 			Shine:NotifyDualColour( nil, PR, PG, PB, Advert.Prefix, R, G, B, Message )

 			return true
		end

		Shine:NotifyColour( nil, R, G, B, Message )
	else
		local Position = ( Advert.Position or "top" ):lower()

		local X, Y = 0.5, 0.2
		local Align = 1

		if Position == "bottom" then
			X, Y = 0.5, 0.8
		end

		Shine.ScreenText.Add( 20, {
			X = X, Y = Y,
			Text = Message,
			Duration = 7,
			R = R, G = G, B = B,
			Alignment = Align,
			Size = 2, FadeIn = 1
		} )
	end

	return true
end

function Plugin:SetupTimer()
	if self:TimerExists( self.TimerName ) then
		self:DestroyTimer( self.TimerName )
	end

	if #self.AdvertsList == 0 then return end

	local Message = 1

	self:CreateTimer( self.TimerName, self.Config.Interval, -1, function()
		-- Back to the start, randomise the order again.
		if Message == 1 and self.Config.RandomiseOrder then
			TableQuickShuffle( self.AdvertsList )
		end

		if self:ParseAdvert( Message, self.AdvertsList[ Message ] ) then
			Message = ( Message % #self.AdvertsList ) + 1
		elseif #self.AdvertsList == 0 then
			self:DestroyTimer( self.TimerName )
		end
	end )
end

Shine:RegisterExtension( "adverts", Plugin )
