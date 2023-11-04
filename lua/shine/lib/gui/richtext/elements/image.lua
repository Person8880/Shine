--[[
	Element to add images to rich text.
]]

local StringFormat = string.format
local unpack = unpack

local BaseElement = require "shine/lib/gui/richtext/elements/base"
local Image = Shine.TypeDef( BaseElement )

function Image:Init( Params )
	self.Texture = Params.Texture
	-- Absolute size should be a vector.
	self.AbsoluteSize = Params.AbsoluteSize
	-- AutoSize should be a UnitVector.
	self.AutoSize = Params.AutoSize
	self.AspectRatio = Params.AspectRatio
	self.Think = Params.Think
	self.TextureCoordinates = Params.TextureCoordinates
	self.TexturePixelCoordinates = Params.TexturePixelCoordinates
	self.Tooltip = Params.Tooltip

	self.DoClick = Params.DoClick
	self.DoRightClick = Params.DoRightClick
	self.Setup = Params.Setup

	return self
end

function Image:IsVisibleElement()
	return true
end

function Image:ConfigureSize( TextSizeProvider, MaxWidth )
	self.Size = self.AbsoluteSize or self.AutoSize:GetValue(
		Vector2( MaxWidth, TextSizeProvider.TextHeight )
	)
	if self.AspectRatio then
		self.Size.x = self.Size.y * self.AspectRatio
	end
end

function Image:Split( Index, TextSizeProvider, Segments, MaxWidth )
	self.OriginalElement = Index
	self:ConfigureSize( TextSizeProvider, MaxWidth )
	self.Width = self.Size.x
	self.WidthWithoutSpace = self.Width

	Segments[ #Segments + 1 ] = self
end

function Image:GetWidth( TextSizeProvider, MaxWidth )
	self:ConfigureSize( TextSizeProvider, MaxWidth )
	return self.Size.x, self.Size.x
end

function Image:MakeElement( Context )
	local Image = Context.MakeElement( "Image" )
	Image:SetIsSchemed( false )
	Image:SetTexture( self.Texture )
	-- Size already computed from auto-size in wrapping step.
	Image:SetSize( self.Size )
	Image:SetTooltip( self.Tooltip )

	if self.TextureCoordinates then
		Image:SetTextureCoordinates( unpack( self.TextureCoordinates, 1, 4 ) )
	elseif self.TexturePixelCoordinates then
		Image:SetTexturePixelCoordinates( unpack( self.TexturePixelCoordinates, 1, 4 ) )
	else
		Image:SetTextureCoordinates( 0, 0, 1, 1 )
	end

	self.AddThinkFunction( Image, self.Think )

	Image.DoClick = self.DoClick
	Image.DoRightClick = self.DoRightClick

	self:Setup( Image )

	return Image
end

function Image:Copy()
	return Image( self )
end

function Image:__tostring()
	return StringFormat( "Image (Texture = %s, Size = %s)", self.Texture, self.Size )
end

return Image
