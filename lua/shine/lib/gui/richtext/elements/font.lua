--[[
	Element to set the current font for rich text.
]]

local IsType = Shine.IsType
local StringFormat = string.format

local BaseElement = require "shine/lib/gui/richtext/elements/base"
local Font = Shine.TypeDef( BaseElement )

function Font.FromFontScale( FontName, Scale )
	return Font( {
		Font = FontName,
		Scale = Scale
	} )
end

function Font:Init( Params )
	self.Font = Params.Font
	self.Scale = Params.Scale
	if IsType( self.Font, "function" ) then
		-- Some fonts may depend on resolution, this provides a way to compute the right font just-in-time.
		self.GetFontScale = self.GetFontScaleComputed
	end
	return self
end

function Font:GetFontScale()
	return self.Font, self.Scale
end

function Font:GetFontScaleComputed()
	return self:Font()
end

function Font:Split( Index, TextSizeProvider )
	TextSizeProvider:SetFontScale( self:GetFontScale() )
end

function Font:GetWidth( TextSizeProvider )
	TextSizeProvider:SetFontScale( self:GetFontScale() )
	return 0, 0
end

function Font:MakeElement( Context )
	local Font, Scale = self:GetFontScale()
	if not Font then
		Font, Scale = Context.DefaultFont, Context.DefaultScale
	end
	Context.CurrentFont = Font
	Context.CurrentScale = Scale
end

function Font:Copy()
	return Font( self )
end

function Font:__tostring()
	return StringFormat( "Font (%s with scale %s)", self.Font, self.Scale )
end

return Font
