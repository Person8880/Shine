--[[
	Directional layout.

	Positions elements one after the other, in a given direction.

	Note that directional layouts assume that all elements are using the top-left anchor because it's
	easier to compute the positions that way.

	Anchoring to the right or bottom makes nested layouts essentially require a dummy GUIItem to hold
	them which I'm not willing to do.
]]

local Max = math.max
local Vector2 = Vector2

local Directional = {}
Directional.IsAbstract = true

local LayoutAlignment = Shine.GUI.LayoutAlignment

function Directional:SetElementSize( Element, RealSize, Margin )
	Element:PreComputeWidth()

	local Width = Element:GetComputedSize( 1, RealSize.x - Margin[ 5 ] )

	Element:PreComputeHeight( Width )

	local Height = Element:GetComputedSize( 2, RealSize.y - Margin[ 6 ] )

	local NewSize = Vector2( Width, Height )
	Element:SetLayoutSize( NewSize )

	return NewSize
end

function Directional:GetComputedFillSize( Element, RealSize, FillSizePerElement )
	local Margin = Element:GetComputedMargin()

	Element:PreComputeWidth()

	local Width = Element:GetComputedSize( 1, RealSize.x - Margin[ 5 ] )
	Width = self:GetFillElementWidth( Element, Width, FillSizePerElement )

	Element:PreComputeHeight( Width )

	local Height = Element:GetComputedSize( 2, RealSize.y - Margin[ 6 ] )
	Height = self:GetFillElementHeight( Element, Height, FillSizePerElement )

	return self:GetFillElementSize( Element, Width, Height, FillSizePerElement )
end

local PositionUpdaters = {
	Before = {
		-- Before a MIN aligned element, move forward by the margin at the start.
		[ true ] = function( X, Y, MinW, MinH, MaxW, MaxH, SizeW, SizeH )
			return X + MinW, Y + MinH
		end,
		-- Before a MAX aligned element, move back by the size of the element plus the margin at the end.
		[ false ] = function( X, Y, MinW, MinH, MaxW, MaxH, SizeW, SizeH )
			return X - MaxW - SizeW, Y - MaxH - SizeH
		end
	},
	After = {
		-- After a MIN aligned element, move forward by its size and margin at the end.
		[ true ] = function( X, Y, MinW, MinH, MaxW, MaxH, SizeW, SizeH )
			return X + MaxW + SizeW, Y + MaxH + SizeH
		end,
		-- After a MAX aligned element, move backwards by the margin at the start.
		[ false ] = function( X, Y, MinW, MinH, MaxW, MaxH, SizeW, SizeH )
			return X - MinW, Y - MinH
		end
	}
}

--[[
	This method handles laying out elements, including keeping track of margins between them.
]]
function Directional:LayoutElements( Elements, Context )
	if #Elements == 0 then return 0, 0 end

	local Alignment = Context.Alignment
	local IsMin = Alignment ~= LayoutAlignment.MAX
	local UpdatePositionBefore = PositionUpdaters.Before[ IsMin ]
	local UpdatePositionAfter = PositionUpdaters.After[ IsMin ]

	local Padding = Context.Padding
	local Pos = Context.Pos
	local RealSize = Context.RealSize
	local Size = Context.Size
	local FillSizePerElement = Context.FillSizePerElement

	-- The start position depends on the direction and alignment.
	-- Vertical will start either top left or bottom left, horizontal top left or top right.
	local X, Y = self:GetStartPos( Pos, Size, Padding, Alignment, Context )

	for i = 1, #Elements do
		local Element = Elements[ i ]
		local Margin = Element:GetComputedMargin()
		if Element:GetFill() then
			-- Fixed size elements have already been resized, just need to resize fill elements.
			Element:SetLayoutSize( self:GetComputedFillSize( Element, RealSize, FillSizePerElement ) )
		end

		local CurrentSize = Element:GetLayoutSize()
		local MinW, MinH = self:GetMinMargin( Margin )
		local MaxW, MaxH = self:GetMaxMargin( Margin )
		local SizeW, SizeH = self:GetElementSizeOffset( CurrentSize )

		X, Y = UpdatePositionBefore( X, Y, MinW, MinH, MaxW, MaxH, SizeW, SizeH )

		self:SetElementPos( Element, X, Y, Margin, RealSize )

		X, Y = UpdatePositionAfter( X, Y, MinW, MinH, MaxW, MaxH, SizeW, SizeH )
	end

	return X, Y
end

function Directional:PerformLayout()
	-- If there are no elements, there's also no layout children so no need to call the base method.
	local Elements = self.Elements
	if #Elements == 0 then return end

	local Size = self.Size

	-- Real size is size - padding.
	local Padding = self:GetComputedPadding()
	local RealSize = Vector2(
		Max( Size.x - Padding[ 5 ], 0 ),
		Max( Size.y - Padding[ 6 ], 0 )
	)
	-- If we're attached to an element, this will return our margin, otherwise we're attached to another layout,
	-- which means our position will be somewhere inside the element at the top of the layout tree.
	local Pos = self:GetPos()

	-- Keep track of min and max aligned elements separately, as they need different layout rules.
	local AlignedElements = {
		[ LayoutAlignment.MIN ] = {},
		[ LayoutAlignment.MAX ] = {},
		[ LayoutAlignment.CENTRE ] = {}
	}
	local CentreAlignedSize = 0

	-- Pre-compute the size of each fill element by setting the size of fixed-size elements upfront.
	local FillSize = self:GetFillSize( RealSize )
	local NumberOfFillElements = 0
	local NumberOfCentreAlignedFillElements = 0

	for i = 1, #Elements do
		local Element = Elements[ i ]

		if Element:GetIsVisible() then
			local Alignment = Element:GetAlignment()
			local ElementList = AlignedElements[ Alignment ]

			ElementList[ #ElementList + 1 ] = Element

			local Margin = Element:GetComputedMargin()
			if not Element:GetFill() then
				local CurrentSize = self:SetElementSize( Element, RealSize, Margin )
				local SizeUsedUp = self:GetFillSize( CurrentSize ) + self:GetMarginSize( Margin )

				-- If the element is not set to fill the space, then it will use up its margin + size.
				FillSize = FillSize - SizeUsedUp

				if Alignment == LayoutAlignment.CENTRE then
					CentreAlignedSize = CentreAlignedSize + SizeUsedUp
				end
			else
				local SizeUsedUp = self:GetMarginSize( Margin )

				-- Otherwise, only the margin is used up.
				FillSize = FillSize - SizeUsedUp
				NumberOfFillElements = NumberOfFillElements + 1

				if Alignment == LayoutAlignment.CENTRE then
					CentreAlignedSize = CentreAlignedSize + SizeUsedUp
					NumberOfCentreAlignedFillElements = NumberOfCentreAlignedFillElements + 1
				end
			end
		end
	end

	local FillSizePerElement = NumberOfFillElements == 0 and 0 or Max( FillSize, 0 ) / NumberOfFillElements
	CentreAlignedSize = CentreAlignedSize + NumberOfCentreAlignedFillElements * FillSizePerElement

	-- This table "context" just saves a lot of method parameters.
	local Context = {
		Alignment = LayoutAlignment.MIN,
		AvailableFillSize = self:GetFillSize( RealSize ),
		NumberOfFillElements = 0,
		Padding = Padding,
		Pos = Pos,
		RealSize = RealSize,
		Size = Size,
		FillSizePerElement = FillSizePerElement
	}

	-- Layout each alignment in sequence, applying the fill size to elements set to fill.
	local MinAlignX, MinAlignY = self:LayoutElements( AlignedElements[ Context.Alignment ], Context )

	Context.Alignment = LayoutAlignment.MAX
	self:LayoutElements( AlignedElements[ Context.Alignment ], Context )

	Context.Alignment = LayoutAlignment.CENTRE
	Context.CentreAlignedSize = CentreAlignedSize
	local CentreX, CentreY = self:LayoutElements( AlignedElements[ Context.Alignment ], Context )

	-- MIN and CENTRE aligned elements are both capable of exceeding the layout's size, and thus
	-- the layout's furthest extents are defined by the max of the two. Including padding here avoids
	-- surprises where a panel with a layout ends up ignoring the padding when adding scrolling.
	self.MaxPosX = Max( MinAlignX, CentreX ) + Padding[ 3 ]
	self.MaxPosY = Max( MinAlignY, CentreY ) + Padding[ 4 ]

	self.BaseClass.PerformLayout( self )
end

Shine.GUI.Layout:RegisterType( "Directional", Directional )
