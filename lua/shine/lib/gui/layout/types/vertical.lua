--[[
	Vertical layout.

	Positions elements one after the other, starting from the top.
]]

local Vector2 = Vector2

local Vertical = {}

local LayoutAlignment = Shine.GUI.LayoutAlignment

function Vertical:GetStartPos( Pos, Size, Padding, Alignment, Context )
	if Alignment == LayoutAlignment.CENTRE then
		local X = Context.MinX
		local Y = Pos.y + Size.y * 0.5 - Context.CentreAlignedSize * 0.5

		return X, Y
	end

	local IsMin = Alignment == LayoutAlignment.MIN
	local X = Context.MinX
	local Y = IsMin and Context.MinY or Context.MaxY

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
		X = X + LayoutSize.x * 0.5 - Element:GetLayoutSize().x * 0.5
	elseif CrossAxisAlignment == LayoutAlignment.MAX then
		X = X + LayoutSize.x - Element:GetLayoutSize().x
	end

	local LayoutOffset = Element:GetLayoutOffset()
	Element:SetLayoutPos( Vector2( X + Margin[ 1 ] + LayoutOffset.x, Y + LayoutOffset.y ) )
end

function Vertical:GetMaxMargin( Margin )
	return 0, Margin[ 4 ]
end

function Vertical:GetElementSizeOffset( Size )
	return 0, Size.y
end

function Vertical:GetCrossAxisSize( Size )
	return Size.x
end

function Vertical:GetFillElementWidth( Element, FillSizePerElement, ParentWidth, ParentHeight )
	return Element:GetComputedSize( 1, ParentWidth, ParentHeight )
end

function Vertical:GetFillElementHeight( Element, FillSizePerElement, ParentHeight, ParentWidth )
	return FillSizePerElement
end

function Vertical:ApplyContentSize( MainAxisSize, CrossAxisSize )
	return CrossAxisSize, MainAxisSize
end

Shine.GUI.Layout:RegisterType( "Vertical", Vertical, "Directional" )
