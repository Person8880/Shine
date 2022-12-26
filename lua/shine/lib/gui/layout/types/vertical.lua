--[[
	Vertical layout.

	Positions elements one after the other, starting from the top.
]]

local Vector2 = Vector2

local Vertical = {}

local LayoutAlignment = Shine.GUI.LayoutAlignment

function Vertical:GetStartPos( Pos, Size, Padding, Alignment, Context )
	if Alignment == LayoutAlignment.CENTRE then
		local X = Pos.x + Padding[ 1 ]
		local Y = Pos.y + Size.y * 0.5 - Context.CentreAlignedSize * 0.5

		return X, Y
	end

	local IsMin = Alignment == LayoutAlignment.MIN
	local X = Pos.x + Padding[ 1 ]
	local Y = IsMin and ( Pos.y + Padding[ 2 ] ) or ( Pos.y + Size.y - Padding[ 4 ] )

	return X, Y
end

function Vertical:GetFillSize( Size )
	return Size.y
end

function Vertical:GetMinMargin( Margin )
	return 0, Margin[ 2 ]
end

function Vertical:GetMarginSize( Margin )
	return Margin[ 6 ]
end

function Vertical:SetElementPos( Element, X, Y, Margin, LayoutSize )
	local CrossAxisAlignment = Element:GetCrossAxisAlignment()
	if CrossAxisAlignment == LayoutAlignment.CENTRE then
		X = X + LayoutSize.x * 0.5 - Element:GetSize().x * 0.5
	elseif CrossAxisAlignment == LayoutAlignment.MAX then
		X = X + LayoutSize.x - Element:GetSize().x
	end

	local LayoutOffset = Element:GetLayoutOffset()
	Element:SetPos( Vector2( X + Margin[ 1 ] + LayoutOffset.x, Y + LayoutOffset.y ) )
end

function Vertical:GetMaxMargin( Margin )
	return 0, Margin[ 4 ]
end

function Vertical:GetElementSizeOffset( Size )
	return 0, Size.y
end

function Vertical:GetFillElementWidth( Element, Width, FillSizePerElement )
	return Width
end

function Vertical:GetFillElementHeight( Element, Height, FillSizePerElement )
	return FillSizePerElement
end

function Vertical:GetFillElementSize( Element, Width, Height, FillSizePerElement )
	return Vector2( Width, FillSizePerElement )
end

local ContentSizes = {
	function( self )
		return self:GetMaxSizeAlongAxis( 1 )
	end,
	function( self )
		return self.BaseClass.GetContentSizeForAxis( self, 2 )
	end
}
function Vertical:GetContentSizeForAxis( Axis )
	return ContentSizes[ Axis ]( self )
end

Shine.GUI.Layout:RegisterType( "Vertical", Vertical, "Directional" )
