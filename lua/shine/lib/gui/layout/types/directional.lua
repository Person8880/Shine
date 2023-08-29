--[[
	Directional layout.

	Positions elements one after the other, in a given direction.

	Note that directional layouts assume that all elements are using the top-left anchor because it's
	easier to compute the positions that way.

	Anchoring to the right or bottom makes nested layouts essentially require a dummy GUIItem to hold
	them which I'm not willing to do.
]]

local Max = math.max
local Min = math.min
local Vector2 = Vector2

local Directional = {}
Directional.IsAbstract = true

local LayoutAlignment = Shine.GUI.LayoutAlignment

function Directional:SetElementSize( Element, InnerBoxSize, Margin )
	local OriginalSize = Element:GetLayoutSize()

	Element:PreComputeWidth()

	local ParentWidth, ParentHeight = InnerBoxSize.x - Margin[ 5 ], InnerBoxSize.y - Margin[ 6 ]
	local Width = Element:GetComputedSize( 1, ParentWidth, ParentHeight )

	-- Update the width immediately, this helps prevent needing to auto-wrap text twice.
	local NewSize = Vector2( Width, OriginalSize.y )
	Element:SetLayoutSize( NewSize )

	Element:PreComputeHeight( Width )

	-- Now compute the height and set the final size from it.
	local Height = Element:GetComputedSize( 2, ParentHeight, ParentWidth )
	NewSize.y = Height

	Element:SetLayoutSize( NewSize )

	return NewSize
end

function Directional:GetComputedFillSize( Element, InnerBoxSize, FillSizePerElement )
	local OriginalSize = Element:GetLayoutSize()
	local Margin = Element:GetComputedMargin()

	Element:PreComputeWidth()

	local ParentWidth, ParentHeight = InnerBoxSize.x - Margin[ 5 ], InnerBoxSize.y - Margin[ 6 ]
	local Width = self:GetFillElementWidth( Element, FillSizePerElement, ParentWidth, ParentHeight )

	-- Update the width immediately, this helps prevent needing to auto-wrap text twice.
	local NewSize = Vector2( Width, OriginalSize.y )
	Element:SetLayoutSize( NewSize )

	Element:PreComputeHeight( Width )

	-- Now compute the height and set the final size from it.
	local Height = self:GetFillElementHeight( Element, FillSizePerElement, ParentHeight, ParentWidth )
	NewSize.y = Height

	return NewSize
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
	local Alignment = Context.Alignment
	local IsMin = Alignment ~= LayoutAlignment.MAX
	local UpdatePositionBefore = PositionUpdaters.Before[ IsMin ]
	local UpdatePositionAfter = PositionUpdaters.After[ IsMin ]

	local Padding = Context.Padding
	local Pos = Context.Pos
	local InnerBoxSize = Context.InnerBoxSize
	local Size = Context.Size
	local FillSizePerElement = Context.FillSizePerElement

	-- The start position depends on the direction and alignment.
	-- Vertical will start either top left or bottom left, horizontal top left or top right.
	local X, Y = self:GetStartPos( Pos, Size, Padding, Alignment, Context )
	local StartX, StartY = X, Y
	local CrossAxisSize = 0

	for i = 1, Elements[ 0 ] do
		local Element = Elements[ i ]
		local Margin = Element:GetComputedMargin()
		if Element:GetFill() then
			-- Fixed size elements have already been resized, just need to resize fill elements.
			Element:SetLayoutSize( self:GetComputedFillSize( Element, InnerBoxSize, FillSizePerElement ) )
		end

		local CurrentSize = Element:GetLayoutSize()
		local MinW, MinH = self:GetMinMargin( Margin )
		local MaxW, MaxH = self:GetMaxMargin( Margin )
		local SizeW, SizeH = self:GetElementSizeOffset( CurrentSize )

		CrossAxisSize = Max( CrossAxisSize, self:GetCrossAxisSize( CurrentSize ) )

		X, Y = UpdatePositionBefore( X, Y, MinW, MinH, MaxW, MaxH, SizeW, SizeH )

		self:SetElementPos( Element, X, Y, Margin, InnerBoxSize )

		X, Y = UpdatePositionAfter( X, Y, MinW, MinH, MaxW, MaxH, SizeW, SizeH )
	end

	return X, Y, StartX, StartY, CrossAxisSize
end

function Directional:PerformLayout()
	-- If there are no elements, there's also no layout children so no need to call the base method.
	local Elements = self.Elements
	local NumElements = #Elements
	if NumElements == 0 then return end

	local Size = self.Size

	-- Real size is size - padding.
	local Padding = self:GetComputedPadding()
	local InnerBoxSize = Vector2(
		Max( Size.x - Padding[ 5 ], 0 ),
		Max( Size.y - Padding[ 6 ], 0 )
	)
	-- If we're attached to an element, this will return our margin, otherwise we're attached to another layout,
	-- which means our position will be somewhere inside the element at the top of the layout tree.
	local Pos = self:GetPos()

	-- Keep track of min and max aligned elements separately, as they need different layout rules.
	local AlignedElements = {
		[ LayoutAlignment.MIN ] = { [ 0 ] = 0 },
		[ LayoutAlignment.MAX ] = { [ 0 ] = 0 },
		[ LayoutAlignment.CENTRE ] = { [ 0 ] = 0 }
	}
	local CentreAlignedSize = 0

	-- Pre-compute the size of each fill element by setting the size of fixed-size elements upfront.
	local FillSize = self:GetFillSize( InnerBoxSize )
	local NumberOfFillElements = 0
	local NumberOfCentreAlignedFillElements = 0

	for i = 1, NumElements do
		local Element = Elements[ i ]

		if Element:GetIsVisible() then
			local Alignment = Element:GetAlignment()
			local ElementList = AlignedElements[ Alignment ]
			local Count = ElementList[ 0 ] + 1

			ElementList[ Count ] = Element
			ElementList[ 0 ] = Count

			local Margin = Element:GetComputedMargin()
			if not Element:GetFill() then
				local CurrentSize = self:SetElementSize( Element, InnerBoxSize, Margin )
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

	local MinX, MinY = Pos.x + Padding[ 1 ], Pos.y + Padding[ 2 ]

	-- This table "context" just saves a lot of method parameters.
	local Context = {
		Alignment = LayoutAlignment.MIN,
		AvailableFillSize = self:GetFillSize( InnerBoxSize ),
		NumberOfFillElements = 0,
		Padding = Padding,
		Pos = Pos,
		InnerBoxSize = InnerBoxSize,
		Size = Size,
		FillSizePerElement = FillSizePerElement,
		-- These are the min and max bounds of the layout's content, after applying padding.
		-- The total size of this box is "InnerBoxSize".
		MinX = MinX,
		MinY = MinY,
		MaxX = Pos.x + Size.x - Padding[ 3 ],
		MaxY = Pos.y + Size.y - Padding[ 4 ]
	}

	-- Track the actual maximum here, not the theoretical maximum from the layout's own size.
	local MaxX, MaxY = self:GetInitialBounds( MinX, MinY, Context.MaxX, Context.MaxY )
	local ContentWidth = 0
	local ContentHeight = 0
	local ContentCrossAxisSize = 0

	-- Layout each alignment in sequence, applying the fill size to elements set to fill.
	Elements = AlignedElements[ Context.Alignment ]

	if Elements[ 0 ] > 0 then
		-- Min-algined elements advance from min to max, first two values are the final X and Y position after all
		-- elements, and the other two are the initial position alignment started from.
		local MinEndX, MinEndY, MinStartX, MinStartY, CrossAxisSize = self:LayoutElements( Elements, Context )
		MinX = Min( MinX, MinStartX )
		MinY = Min( MinY, MinStartY )
		MaxX = Max( MaxX, MinEndX )
		MaxY = Max( MaxY, MinEndY )
		ContentWidth = MinEndX - MinStartX
		ContentHeight = MinEndY - MinStartY
		ContentCrossAxisSize = CrossAxisSize
	end

	Context.Alignment = LayoutAlignment.MAX
	Elements = AlignedElements[ Context.Alignment ]

	if Elements[ 0 ] > 0 then
		-- Note that these are reversed compared to the others, the second position here is the furthest point along,
		-- while the first position is the minimum position after going backwards along every max-aligned element.
		local MaxStartX, MaxStartY, MaxEndX, MaxEndY, CrossAxisSize = self:LayoutElements( Elements, Context )
		MinX = Min( MinX, MaxStartX )
		MinY = Min( MinY, MaxStartY )
		MaxX = Max( MaxX, MaxEndX )
		MaxY = Max( MaxY, MaxEndY )
		ContentWidth = Max( ContentWidth, MaxEndX - MaxStartX )
		ContentHeight = Max( ContentHeight, MaxEndY - MaxStartY )
		ContentCrossAxisSize = Max( ContentCrossAxisSize, CrossAxisSize )
	end

	Context.Alignment = LayoutAlignment.CENTRE
	Elements = AlignedElements[ Context.Alignment ]

	if Elements[ 0 ] > 0 then
		Context.CentreAlignedSize = CentreAlignedSize

		-- These values match those of min-aligned elements, just for the centre-aligned instead.
		local CentreEndX, CentreEndY, CentreStartX, CentreStartY, CrossAxisSize = self:LayoutElements(
			Elements,
			Context
		)
		MinX = Min( MinX, CentreStartX )
		MinY = Min( MinY, CentreStartY )
		MaxX = Max( MaxX, CentreEndX )
		MaxY = Max( MaxY, CentreEndY )
		ContentWidth = Max( ContentWidth, CentreEndX - CentreStartX )
		ContentHeight = Max( ContentHeight, CentreEndY - CentreStartY )
		ContentCrossAxisSize = Max( ContentCrossAxisSize, CrossAxisSize )
	end

	-- Track the extents of the layout. These may not reflect its actual used size, those are provided by ContentWidth
	-- and ContentHeight below.
	self.MinPosX = MinX - Padding[ 1 ]
	self.MinPosY = MinY - Padding[ 2 ]
	self.MaxPosX = MaxX + Padding[ 3 ]
	self.MaxPosY = MaxY + Padding[ 4 ]

	ContentWidth, ContentHeight = self:ApplyCrossAxisSizeToContentSize(
		ContentWidth,
		ContentHeight,
		ContentCrossAxisSize
	)

	-- Record the final width and height of the layout. One of these will be the sum of the layout's direction, the
	-- other will be the max of the cross-axis sizes.
	-- Including padding here avoids surprises where a panel with a layout ends up ignoring the padding when adding
	-- scrolling.
	self.ContentWidth = ContentWidth + Padding[ 5 ]
	self.ContentHeight = ContentHeight + Padding[ 6 ]

	self.BaseClass.PerformLayout( self )
end

local ContentSizes = {
	"ContentWidth",
	"ContentHeight"
}
function Directional:GetContentSizeForAxis( Axis )
	-- Make sure the layout has been computed, which will populate the ContentWidth and ContentHeight fields.
	-- Note that it's assumed that the layout's content does not depend on the layout parent's size, as that would be
	-- unsatisfiable here.
	self:HandleLayout()
	return self[ ContentSizes[ Axis ] ]
end

Shine.GUI.Layout:RegisterType( "Directional", Directional )
