--[[
	Horizontal layout.

	Positions elements one after the other, starting from the left.
]]

local Horizontal = {}

local LayoutAlignment = Shine.GUI.LayoutAlignment

function Horizontal:GetStartPos( Pos, Size, Padding, Alignment, Context )
	if Alignment == LayoutAlignment.CENTRE then
		local X = Pos.x + Size.x * 0.5 - Context.CentreAlignedSize * 0.5
		local Y = Pos.y + Padding[ 2 ]

		return X, Y
	end

	local IsMin = Alignment == LayoutAlignment.MIN
	local X = IsMin and ( Pos.x + Padding[ 1 ] ) or ( Pos.x + Size.x - Padding[ 3 ] )
	local Y = Pos.y + Padding[ 2 ]

	return X, Y
end

function Horizontal:GetFillSize( Size )
	return Size.x
end

function Horizontal:GetMinMargin( Margin )
	return Margin[ 1 ], 0
end

function Horizontal:GetMarginSize( Margin )
	return Margin[ 1 ] + Margin[ 3 ]
end

function Horizontal:SetElementPos( Element, X, Y, Margin, LayoutSize )
	local CrossAxisAlignment = Element:GetCrossAxisAlignment()
	if CrossAxisAlignment == LayoutAlignment.CENTRE then
		Y = Y + LayoutSize.y * 0.5 - Element:GetSize().y * 0.5
	elseif CrossAxisAlignment == LayoutAlignment.MAX then
		Y = Y + LayoutSize.y - Element:GetSize().y
	end

	local LayoutOffset = Element:GetLayoutOffset()
	Element:SetPos( Vector2( X + LayoutOffset.x, Y + Margin[ 2 ] + LayoutOffset.y ) )
end

function Horizontal:GetMaxMargin( Margin )
	return Margin[ 3 ], 0
end

function Horizontal:GetElementSizeOffset( Size )
	return Size.x, 0
end

function Horizontal:GetFillElementWidth( Element, Width, FillSizePerElement )
	return FillSizePerElement
end

function Horizontal:GetFillElementHeight( Element, Height, FillSizePerElement )
	return Height
end

function Horizontal:GetFillElementSize( Element, Width, Height, FillSizePerElement )
	local Size = Element:GetSize()
	Size.x = FillSizePerElement
	Size.y = Height
	return Size
end

local ContentSizes = {
	function( self )
		-- This only makes sense if all elements are using the same alignment.
		-- Otherwise the size returned will be larger than the actual size consumed.
		return self.BaseClass.GetContentSizeForAxis( self, 1 )
	end,
	function( self )
		return self:GetMaxSizeAlongAxis( 2 )
	end
}
function Horizontal:GetContentSizeForAxis( Axis )
	return ContentSizes[ Axis ]( self )
end

Shine.GUI.Layout:RegisterType( "Horizontal", Horizontal, "Directional" )
