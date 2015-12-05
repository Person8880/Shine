--[[
	Horizontal layout.

	Positions elements one after the other, starting from the left.
]]

local Horizontal = {}

local LayoutAlignment = Shine.GUI.LayoutAlignment

function Horizontal:GetStartPos( Pos, Size, Padding, Alignment )
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

function Horizontal:SetElementPos( Element, X, Y, Margin )
	Element:SetPos( Vector( X, Y + Margin[ 2 ], 0 ) )
end

function Horizontal:GetMaxMargin( Margin )
	return Margin[ 3 ], 0
end

function Horizontal:GetElementSizeOffset( Size )
	return Size.x, 0
end

function Horizontal:ModifyFillElementSize( Size, FillSize )
	Size.x = FillSize
end

function Horizontal:ModifyFillElementPos( X, Y, Pos, Size )
	Pos.x = X
	return X + Size.x, Y
end

Shine.GUI.Layout:RegisterType( "Horizontal", Horizontal, "Directional" )
