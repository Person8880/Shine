--[[
	Shine adverts system.
]]

local Shine = Shine

local TableRemove = table.remove
local type = type

local Plugin = {}
Plugin.Version = "1.0"

Plugin.HasConfig = true
Plugin.ConfigName = "Adverts.json"

Plugin.DefaultConfig = {
	Adverts = {
		{
			Message = "Welcome to Natural Selection 2.",
			Type = "chat",
			R = 255,
			G = 255,
			B = 255
		},
		{
			Message = "This server is running the Shine administration mod.",
			Type = "chat",
			R = 255,
			G = 255,
			B = 255
		}
	},
	Interval = 60
}

Plugin.CheckConfigTypes = true

Plugin.TimerName = "Adverts"

function Plugin:Initialise()
	self:SetupTimer()

	self.Enabled = true

	return true
end

local IsType = Shine.IsType

function Plugin:ParseAdvert( ID, Advert )
	if IsType( Advert, "string" ) then
		Shine:NotifyColour( nil, 255, 255, 255, Advert )

		return
	end

	if IsType( Advert, "table" ) then
		local Message = Advert.Message

		if not Message then
			Shine:Print( "[Adverts] Misconfigured advert #%i, missing \"Message\" value.",
				true, ID )

			TableRemove( self.Config.Adverts, ID )

			return
		end

		local R = Advert.R or Advert.r or 255
		local G = Advert.G or Advert.g or 255
		local B = Advert.B or Advert.b or 255

		local Type = Advert.Type

		if not Type or Type == "chat" then
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
	end
end

function Plugin:SetupTimer()
	if self:TimerExists( self.TimerName ) then
		self:DestroyTimer( self.TimerName )
	end

	if #self.Config.Adverts == 0 then return end

	local Message = 1

	self:CreateTimer( self.TimerName, self.Config.Interval, -1, function()
		self:ParseAdvert( Message, self.Config.Adverts[ Message ] )
		Message = ( Message % #self.Config.Adverts ) + 1
	end )
end

Shine:RegisterExtension( "adverts", Plugin )
