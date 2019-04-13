--[[
	Directional layout.

	Positions elements one after the other, in a given direction.

	Note that directional layouts assume that all elements are using the top-left anchor because it's
	easier to compute the positions that way.

	Anchoring to the right or bottom makes nested layouts essentially require a dummy GUIItem to hold
	them which I'm not willing to do.
]]

local Max = math.max

local Directional = {}
Directional.IsAbstract = true

local LayoutAlignment = Shine.GUI.LayoutAlignment

function Directional:SetElementSize( Element, RealSize, Margin )
	Element:PreComputeWidth()

	local Width = Element:GetComputedSize( 1, RealSize.x - Margin[ 1 ] - Margin[ 3 ] )

	Element:PreComputeHeight( Width )

	local Height = Element:GetComputedSize( 2, RealSize.y - Margin[ 2 ] - Margin[ 4 ] )

	local CurrentSize = Element:GetSize()
	CurrentSize.x = Width
	CurrentSize.y = Height

	Element:SetSize( CurrentSize )

	return CurrentSize
end

function Directional:GetComputedFillSize( Element, RealSize, FillSizePerElement )
	local Margin = Element:GetComputedMargin()

	Element:PreComputeWidth()

	local Width = Element:GetComputedSize( 1, RealSize.x - Margin[ 1 ] - Margin[ 3 ] )
	Width = self:GetFillElementWidth( Element, Width, FillSizePerElement )

	Element:PreComputeHeight( Width )

	local Height = Element:GetComputedSize( 2, RealSize.y - Margin[ 2 ] - Margin[ 4 ] )
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
	if #Elements == 0 then return end

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
			Element:SetSize( self:GetComputedFillSize( Element, RealSize, FillSizePerElement ) )
		end

		local CurrentSize = Element:GetSize()
		local MinW, MinH = self:GetMinMargin( Margin )
		local MaxW, MaxH = self:GetMaxMargin( Margin )
		local SizeW, SizeH = self:GetElementSizeOffset( CurrentSize )

		X, Y = UpdatePositionBefore( X, Y, MinW, MinH, MaxW, MaxH, SizeW, SizeH )

		self:SetElementPos( Element, X, Y, Margin, RealSize )

		X, Y = UpdatePositionAfter( X, Y, MinW, MinH, MaxW, MaxH, SizeW, SizeH )
	end
end

function Directional:PerformLayout()
	local Elements = self.Elements
	if #Elements == 0 then return end

	local Size = self.Size

	-- Real size is size - padding.
	local Padding = self:GetComputedPadding()
	local RealSize = Vector2(
		Max( Size.x - Padding[ 1 ] - Padding[ 3 ], 0 ),
		Max( Size.y - Padding[ 2 ] - Padding[ 4 ], 0 )
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
	self:LayoutElements( AlignedElements[ Context.Alignment ], Context )

	Context.Alignment = LayoutAlignment.MAX
	self:LayoutElements( AlignedElements[ Context.Alignment ], Context )

	Context.Alignment = LayoutAlignment.CENTRE
	Context.CentreAlignedSize = CentreAlignedSize
	self:LayoutElements( AlignedElements[ Context.Alignment ], Context )
end

Shine.GUI.Layout:RegisterType( "Directional", Directional )
