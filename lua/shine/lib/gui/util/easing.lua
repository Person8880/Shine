--[[
	Easing helpers.
]]

Script.Load( "lua/tweener/Tweener.lua" )

local EasingFunctions = _G.Easing

local StringCaseFormatType = string.CaseFormatType
local StringTransformCase = string.TransformCase

local Easing = {}
local ConvertedEasers = {}

local function ConvertName( Name )
	return StringTransformCase( Name, StringCaseFormatType.UPPER_CAMEL, StringCaseFormatType.LOWER_CAMEL )
end

--[[
	Gets an easer by name (from _G.Easing) for use with SGUI.

	Input: Name of the easer to get.
	Output: An easing function that can be passed to SGUI easing functions.
]]
function Easing.GetEaser( TypeName )
	local ConvertedEaser = ConvertedEasers[ TypeName ]
	if not ConvertedEaser then
		local Easer = EasingFunctions[ ConvertName( TypeName ) ]
		Shine.AssertAtLevel( Easer, "Unkonwn easer: %s", 3, TypeName )

		ConvertedEaser = function( Progress )
			return Easer( Progress, 0, 1, 1 )
		end
		ConvertedEasers[ TypeName ] = ConvertedEaser
	end

	return ConvertedEaser
end

return Easing
