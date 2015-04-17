--[[
	Screen text rendering shared file.
]]

Shine.ScreenText = {}

--DEPRECATED! Please use Shine.ScreenText.Add( ID, Params[, Player] )
function Shine.BuildScreenMessage( ID, X, Y, Text, Duration, R, G, B, Alignment, Size, FadeIn )
	return {
		ID = ID,
		R = R, G = G, B = B,
		X = X, Y = Y,
		Text = Text,
		Duration = Duration,
		Alignment = Alignment,
		Size = Size,
		FadeIn = FadeIn
	}
end

Shared.RegisterNetworkMessage( "Shine_ScreenText", {
	R = "integer (0 to 255)",
	G = "integer (0 to 255)",
	B = "integer (0 to 255)",
	Text = "string (255)",
	X = "float (0 to 1 by 0.05)",
	Y = "float (0 to 1 by 0.05)",
	Duration = "integer (0 to 1800)",
	ID = "integer (0 to 100)",
	Alignment = "integer (0 to 2)",
	Size = "integer (1 to 3)",
	FadeIn = "float (0 to 2 by 0.05)"
} )
Shared.RegisterNetworkMessage( "Shine_ScreenTextUpdate", {
	ID = "integer (0 to 100)",
	Text = "string (255)"
} )
Shared.RegisterNetworkMessage( "Shine_ScreenTextRemove", {
	ID = "integer (0 to 100)"
} )
