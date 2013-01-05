--[[
	Screen text rendering shared file.
]]

Shine = Shine or {}

local NWMessage = {
	r = "integer (0 to 255)",
	g = "integer (0 to 255)",
	b = "integer (0 to 255)",
	Message = "string (255)",
	x = "float (0 to 1 by 0.05)",
	y = "float (0 to 1 by 0.05)",
	Duration = "integer (0 to 1800)",
	ID = "integer (0 to 100)",
	Align = "integer (0 to 2)"
}

function Shine.BuildScreenMessage( ID, x, y, Message, Duration, r, g, b, Align )
	return {
		ID = ID,
		r = r,
		g = g,
		b = b,
		x = x,
		y = y,
		Message = Message,
		Duration = Duration,
		Align = Align
	}
end

Shared.RegisterNetworkMessage( "Shine_ScreenText", NWMessage )

local UpdateMessage = {
	ID = "integer (0 to 100)",
	Message = "string (255)"
}

Shared.RegisterNetworkMessage( "Shine_ScreenTextUpdate", UpdateMessage )
