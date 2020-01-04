--[[
	Element to add an arbitrary space to rich text.
]]

local StringFormat = string.format

local BaseElement = require "shine/lib/gui/richtext/elements/base"
local Spacer = Shine.TypeDef( BaseElement )

function Spacer:Init( Params )
	self.AutoWidth = Params.AutoWidth
	self.IgnoreOnNewLine = Params.IgnoreOnNewLine
	return self
end

function Spacer:Split( Index, TextSizeProvider, Segments, MaxWidth )
	self.OriginalElement = Index
	self.Width = self.AutoWidth:GetValue( MaxWidth, 1 )
	self.WidthWithoutSpace = self.IgnoreOnNewLine and 0 or self.Width

	Segments[ #Segments + 1 ] = self
end

function Spacer:GetWidth( TextSizeProvider, MaxWidth )
	local Width = self.AutoWidth:GetValue( MaxWidth, 1 )
	return Width, self.IgnoreOnNewLine and 0 or Width
end

function Spacer:MakeElement( Context )
	if Context.CurrentIndex == 1 and self.IgnoreOnNewLine then
		return
	end

	Context.NextMargin = ( Context.NextMargin or 0 ) + self.Width
end

function Spacer:Copy()
	return Spacer( self )
end

function Spacer:__tostring()
	return StringFormat( "Spacer (%s)", self.Width or self.AutoWidth )
end

return Spacer
