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

function Vertical:GetFillElementWidth( Element, Width, FillSizePerElement )
	return Width
end

function Vertical:GetFillElementHeight( Element, Height, FillSizePerElement )
	return FillSizePerElement
end

function Vertical:GetInitialBounds( MinX, MinY, MaxX, MaxY )
	-- Start from min Y as this is vertical, but use the existing known maximum for X as it won't change.
	return MaxX, MinY
end

function Vertical:ApplyCrossAxisSizeToContentSize( ContentWidth, ContentHeight, CrossAxisSize )
	return CrossAxisSize, ContentHeight
end

local LayoutSizeChangeGetters = {
	function( Element ) return Element:GetCrossAxisAlignment() end,
	function( Element ) return Element:GetAlignment() end
}

function Vertical:DoesSizeChangeRequireLayoutUpdate( Axis )
	local AlignmentGetter = LayoutSizeChangeGetters[ Axis ]

	for i = 1, #self.Elements do
		local Element = self.Elements[ i ]
		if AlignmentGetter( Element ) ~= LayoutAlignment.MIN then
			return true
		end
	end

	return false
end

Shine.GUI.Layout:RegisterType( "Vertical", Vertical, "Directional" )
