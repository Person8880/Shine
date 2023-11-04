--[[
	Horizontal layout.

	Positions elements one after the other, starting from the left.
]]

local Vector2 = Vector2

local Horizontal = {}

local LayoutAlignment = Shine.GUI.LayoutAlignment
local StartPositionGetters = {
	[ LayoutAlignment.MIN ] = function( Pos, Size, Context )
		return Context.MinX, Context.MinY
	end,
	[ LayoutAlignment.CENTRE ] = function( Pos, Size, Context )
		return Pos.x + Size.x * 0.5 - Context.CentreAlignedSize * 0.5, Context.MinY
	end,
	[ LayoutAlignment.MAX ] = function( Pos, Size, Context )
		return Context.MaxX, Context.MinY
	end
}

function Horizontal:GetStartPos( Pos, Size, Alignment, Context )
	return StartPositionGetters[ Alignment ]( Pos, Size, Context )
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

local CrossAxisAlignmentGetters = {
	[ LayoutAlignment.MIN ] = function( Element, X, Y, LayoutSize, ElementSize )
		return X, Y
	end,
	[ LayoutAlignment.CENTRE ] = function( Element, X, Y, LayoutSize, ElementSize )
		return X, Y + LayoutSize.y * 0.5 - ElementSize.y * 0.5
	end,
	[ LayoutAlignment.MAX ] = function( Element, X, Y, LayoutSize, ElementSize )
		return X, Y + LayoutSize.y - ElementSize.y
	end
}

function Horizontal:SetElementPos( Element, X, Y, Margin, LayoutSize, ElementSize )
	local CrossAxisAlignment = Element:GetCrossAxisAlignment()

	X, Y = CrossAxisAlignmentGetters[ CrossAxisAlignment ]( Element, X, Y, LayoutSize, ElementSize )

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
