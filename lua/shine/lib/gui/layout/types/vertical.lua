--[[
	Vertical layout.

	Positions elements one after the other, starting from the top.
]]

local Vertical = {}

local LayoutAlignment = Shine.GUI.LayoutAlignment

function Vertical:GetStartPos( Pos, Size, Padding, Alignment )
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
	return Margin[ 2 ] + Margin[ 4 ]
end

function Vertical:SetElementPos( Element, X, Y, Margin )
	Element:SetPos( Vector( X + Margin[ 1 ], Y, 0 ) )
end

function Vertical:GetMaxMargin( Margin )
	return 0, Margin[ 4 ]
end

function Vertical:GetElementSizeOffset( Size )
	return 0, Size.y
end

function Vertical:GetFillElementSize( Element, Width, Height, FillSizePerElement )
	local Size = Element:GetSize()
	Size.x = Width
	Size.y = FillSizePerElement
	return Size
end

Shine.GUI.Layout:RegisterType( "Vertical", Vertical, "Directional" )
