--[[
	Serialisation used to encode a list of GUIItems to be rendered in a GUIView.
]]

local pairs = pairs
local StringFormat = string.format

local Keys = {
	"X", "Y", "Width", "Height", "AnchorX", "AnchorY", "HotSpotX", "HotSpotY", "ScaleX", "ScaleY", "Colour",
	"Shader", "Texture", "BlendTechnique", "Type", "Text", "TextAlignmentX", "TextAlignmentY", "Font"
}

-- Generate keys upfront to avoid concatenation overhead.
local function GenerateObjectKeys( Index )
	local ObjectKeys = {}
	for i = 1, #Keys do
		local Key = Keys[ i ]
		local ObjectKey = StringFormat( "Object%d%s", Index, Key )
		ObjectKeys[ Key ] = ObjectKey
	end
	return ObjectKeys
end

local KeysForIndex = setmetatable( {}, {
	-- Lazy-generate additional keys.
	__index = function( self, Index )
		local ObjectKeys = GenerateObjectKeys( Index )
		self[ Index ] = ObjectKeys
		return ObjectKeys
	end
} )

-- Pre-generate keys for less runtime overhead.
for i = 1, 10 do
	KeysForIndex[ i ] = GenerateObjectKeys( i )
end

local Serialiser = {}

Serialiser.ItemType = {
	BOX = 1,
	TEXT = 2
}

local function GetShaderParamsPrefix( Index )
	return StringFormat( "Object%dShaderParam", Index )
end

local function GetShaderParamsCountKey( Prefix )
	return StringFormat( "%sCount", Prefix )
end

local function GetShaderParamKeys( Prefix, Index )
	return StringFormat( "%s%dKey", Prefix, Index ), StringFormat( "%s%dValue", Prefix, Index )
end

local function SerialiseShaderParameters( Index, Params, Values, Count )
	local Prefix = GetShaderParamsPrefix( Index )
	local NumParams = #Params

	Count = Count + 1
	Values[ Count ] = { Key = GetShaderParamsCountKey( Prefix ), Value = NumParams }

	for i = 1, #Params do
		local Key, Value = GetShaderParamKeys( Prefix, i )
		Count = Count + 1
		Values[ Count ] = { Key = Key, Value = Params[ i ].Key }
		Count = Count + 1
		Values[ Count ] = { Key = Value, Value = Params[ i ].Value }
	end

	return Count
end

--[[
	Serialises the given list of objects into a list of key-value pairs that can be passed into a GUIView as global
	values.
]]
function Serialiser.SerialiseObjects( Objects )
	local NumObjects = #Objects
	local Values = {
		{ Key = "NumObjects", Value = NumObjects }
	}
	local Count = 1

	for i = 1, NumObjects do
		local Keys = KeysForIndex[ i ]
		for Key, Value in pairs( Objects[ i ] ) do
			local SerialisedKey = Keys[ Key ]
			if SerialisedKey then
				Count = Count + 1
				Values[ Count ] = { Key = SerialisedKey, Value = Value }
			end
		end

		if Objects[ i ].ShaderParams then
			Count = SerialiseShaderParameters( i, Objects[ i ].ShaderParams, Values, Count )
		end
	end

	return Values
end

function Serialiser.DeserialiseObjects( GlobalTable )
	local NumObjects = GlobalTable.NumObjects or 0
	local Objects = {}

	local LogMessage
	if GlobalTable.DebugLog then
		LogMessage = function( Message, ... )
			GUI.Message( string.format( "GUIView: "..Message, ... ) )
		end
	else
		LogMessage = function() end
	end

	LogMessage( "Creating %s GUIItem(s)...", NumObjects )

	for i = 1, NumObjects do
		local Type = GlobalTable[ KeysForIndex[ i ].Type ] or Serialiser.ItemType.BOX

		local Item = GUI.CreateItem()
		Item:SetOptionFlag( GUIItem.CorrectScaling )
		Item:SetOptionFlag( GUIItem.CorrectRotationOffset )
		Item:SetIsVisible( true )

		if Type == Serialiser.ItemType.TEXT then
			Item:SetOptionFlag( GUIItem.ManageRender )
			Item:SetSnapsToPixels( true )

			local Text = GlobalTable[ KeysForIndex[ i ].Text ] or ""
			local TextAlignmentX = GlobalTable[ KeysForIndex[ i ].TextAlignmentX ] or GUIItem.Align_Min
			local TextAlignmentY = GlobalTable[ KeysForIndex[ i ].TextAlignmentY ] or GUIItem.Align_Min
			local Font = GlobalTable[ KeysForIndex[ i ].Font ] or ""

			Item:SetText( Text )
			Item:SetTextAlignmentX( TextAlignmentX )
			Item:SetTextAlignmentY( TextAlignmentY )
			Item:SetFontName( Font )

			LogMessage(
				"%s: Created text '%s' with font '%s' and alignment (%s, %s)",
				i, Text, Font, TextAlignmentX, TextAlignmentY
			)
		else
			local Width = GlobalTable[ KeysForIndex[ i ].Width ] or 0
			local Height = GlobalTable[ KeysForIndex[ i ].Height ] or 0
			Item:SetSize( Vector( Width, Height, 0 ) )

			LogMessage( "%s: Created box with size (%s, %s)", i, Width, Height )
		end

		local X = GlobalTable[ KeysForIndex[ i ].X ] or 0
		local Y = GlobalTable[ KeysForIndex[ i ].Y ] or 0

		Item:SetPosition( Vector( X, Y, 0 ) )
		LogMessage( "%s: Set pos: %s, %s", i, X, Y )

		local AnchorX = GlobalTable[ KeysForIndex[ i ].AnchorX ] or 0
		local AnchorY = GlobalTable[ KeysForIndex[ i ].AnchorY ] or 0

		Item:SetAnchor( Vector( AnchorX, AnchorY, 0 ) )
		LogMessage( "%s: Set anchor: (%s, %s)", i, AnchorX, AnchorY )

		local HotSpotX = GlobalTable[ KeysForIndex[ i ].HotSpotX ] or 0
		local HotSpotY = GlobalTable[ KeysForIndex[ i ].HotSpotY ] or 0

		Item:SetHotSpot( Vector( HotSpotX, HotSpotY, 0 ) )
		LogMessage( "%s: Set hotspot: (%s, %s)", i, HotSpotX, HotSpotY )

		local ScaleX = GlobalTable[ KeysForIndex[ i ].ScaleX ] or 1
		local ScaleY = GlobalTable[ KeysForIndex[ i ].ScaleY ] or 1

		if ScaleX ~= 1 or ScaleY ~= 1 then
			Item:SetScale( Vector( ScaleX, ScaleY, 0 ) )
			LogMessage( "%s: Set scale: (%s, %s)", i, ScaleX, ScaleY )
		end

		local Colour = GlobalTable[ KeysForIndex[ i ].Colour ]
		if Colour then
			Item:SetColor( Colour )
			LogMessage( "%s: Set colour: (%s, %s, %s, %s)", i, Colour.r, Colour.g, Colour.b, Colour.a )
		end

		local Shader = GlobalTable[ KeysForIndex[ i ].Shader ]
		if Shader then
			Item:SetShader( Shader )
			LogMessage( "%s: Set shader: %s", i, Shader )
		end

		local Texture = GlobalTable[ KeysForIndex[ i ].Texture ]
		if Texture then
			Item:SetTexture( Texture )
			LogMessage( "%s: Set texture: %s", i, Texture )
		end

		local BlendTechnique = GlobalTable[ KeysForIndex[ i ].BlendTechnique ] or GUIItem.Set
		Item:SetBlendTechnique( BlendTechnique )
		LogMessage( "%s: Set blend technique: %s", i, BlendTechnique )

		local Prefix = GetShaderParamsPrefix( i )
		local ShaderParamsCount = GlobalTable[ GetShaderParamsCountKey( Prefix ) ]
		if ShaderParamsCount then
			for j = 1, ShaderParamsCount do
				local GlobalKeyName, GlobalValueName = GetShaderParamKeys( Prefix, j )
				local Key = GlobalTable[ GlobalKeyName ]
				local Value = GlobalTable[ GlobalValueName ]

				local ValueType = type( Value )
				if ValueType == "string" then
					Item:SetAdditionalTexture( Key, Value )
					LogMessage( "%s: Set shader texture param: %s = %s", i, Key, Value )
				elseif ValueType == "number" then
					Item:SetFloatParameter( Key, Value )
					LogMessage( "%s: Set shader float param: %s = %s", i, Key, Value )
				elseif ValueType == "cdata" and ValueType:isa( "Color" ) then
					Item:SetFloat4Parameter( Key, Value )
					LogMessage( "%s: Set shader colour param: %s = %s", i, Key, Value )
				else
					LogMessage( "%s: Unhandled shader parameter: %s = %s", i, Key, Value )
				end
			end
		end

		Objects[ i ] = Item
	end

	return Objects
end

if GUI and not Shared then
	-- In a GUIView, export as a global as require isn't configured with an appropriate package loader.
	_G.SGUIItemSerialiser = Serialiser
end

return Serialiser
