--[[
	Horizontal layout.

	Positions elements one after the other, starting from the left.
]]

local Vector2 = Vector2

local Horizontal = {}

local LayoutAlignment = Shine.GUI.LayoutAlignment

function Horizontal:GetStartPos( Pos, Size, Padding, Alignment, Context )
	if Alignment == LayoutAlignment.CENTRE then
		local X = Pos.x + Size.x * 0.5 - Context.CentreAlignedSize * 0.5
		local Y = Context.MinY

		return X, Y
	end

	local IsMin = Alignment == LayoutAlignment.MIN
	local X = IsMin and Context.MinX or Context.MaxX
	local Y = Context.MinY

	return X, Y
end

function Horizontal:GetFillSize( Size )
	return Size.x
end

function Horizontal:GetMinMargin( Margin )
	return Margin[ 1 ], 0
end

function Horizontal:GetMarginSize( Margin )
	return Margin[ 5 ]
end

function Horizontal:SetElementPos( Element, X, Y, Margin, LayoutSize )
	local CrossAxisAlignment = Element:GetCrossAxisAlignment()
	if CrossAxisAlignment == LayoutAlignment.CENTRE then
		Y = Y + LayoutSize.y * 0.5 - Element:GetLayoutSize().y * 0.5
	elseif CrossAxisAlignment == LayoutAlignment.MAX then
		Y = Y + LayoutSize.y - Element:GetLayoutSize().y
	end

	local LayoutOffset = Element:GetLayoutOffset()
	Element:SetLayoutPos( Vector2( X + LayoutOffset.x, Y + Margin[ 2 ] + LayoutOffset.y ) )
end

function Horizontal:GetMaxMargin( Margin )
	return Margin[ 3 ], 0
end

function Horizontal:GetElementSizeOffset( Size )
	return Size.x, 0
end

function Horizontal:GetCrossAxisSize( Size )
	return Size.y
end

function Horizontal:GetFillElementWidth( Element, FillSizePerElement, ParentWidth, ParentHeight )
	return FillSizePerElement
end

function Horizontal:GetFillElementHeight( Element, FillSizePerElement, ParentHeight, ParentWidth )
	return Element:GetComputedSize( 2, ParentHeight, ParentWidth )
end

function Horizontal:ApplyContentSize( MainAxisSize, CrossAxisSize )
	return MainAxisSize, CrossAxisSize
end

Shine.GUI.Layout:RegisterType( "Horizontal", Horizontal, "Directional" )
