--[[
	Emoji related utilities.
]]

local StringFormat = string.format
local unpack = unpack

local EmojiUtil = {}

function EmojiUtil.ApplyEmojiToImage( Image, EmojiDefinition )
	local Texture = assert(
		EmojiDefinition.Texture,
		StringFormat( "No texture provided for emoji: %s", EmojiDefinition.Name )
	)
	Image:SetTexture( Texture )

	if EmojiDefinition.TextureCoordinates then
		Image:SetTextureCoordinates( unpack( EmojiDefinition.TextureCoordinates, 1, 4 ) )
	elseif EmojiDefinition.TexturePixelCoordinates then
		Image:SetTexturePixelCoordinates( unpack( EmojiDefinition.TexturePixelCoordinates, 1, 4 ) )
	else
		Image:SetTextureCoordinates( 0, 0, 1, 1 )
	end
end

return EmojiUtil
