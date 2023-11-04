--[[
	Vertical layout.

	Positions elements one after the other, starting from the top.
]]

local Vector2 = Vector2

local Vertical = {}

local LayoutAlignment = Shine.GUI.LayoutAlignment
local StartPositionGetters = {
	[ LayoutAlignment.MIN ] = function( Pos, Size, Context )
		return Context.MinX, Context.MinY
	end,
	[ LayoutAlignment.CENTRE ] = function( Pos, Size, Context )
		return Context.MinX, Pos.y + Size.y * 0.5 - Context.CentreAlignedSize * 0.5
	end,
	[ LayoutAlignment.MAX ] = function( Pos, Size, Context )
		return Context.MinX, Context.MaxY
	end
}

function Vertical:GetStartPos( Pos, Size, Alignment, Context )
	return StartPositionGetters[ Alignment ]( Pos, Size, Context )
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

local CrossAxisAlignmentGetters = {
	[ LayoutAlignment.MIN ] = function( Element, X, Y, LayoutSize, ElementSize )
		return X, Y
	end,
	[ LayoutAlignment.CENTRE ] = function( Element, X, Y, LayoutSize, ElementSize )
		return X + LayoutSize.x * 0.5 - ElementSize.x * 0.5, Y
	end,
	[ LayoutAlignment.MAX ] = function( Element, X, Y, LayoutSize, ElementSize )
		return X + LayoutSize.x - ElementSize.x, Y
	end
}

function Vertical:SetElementPos( Element, X, Y, Margin, LayoutSize, ElementSize )
	local CrossAxisAlignment = Element:GetCrossAxisAlignment()

	X, Y = CrossAxisAlignmentGetters[ CrossAxisAlignment ]( Element, X, Y, LayoutSize, ElementSize )

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
