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
local TableNew = require "table.new"

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

	-- Return the final layout size from the element, in case it manages its own size.
	return Element:GetLayoutSize()
end

function Directional:SetComputedFillSize( Element, InnerBoxSize, FillSizePerElement, Margin )
	local OriginalSize = Element:GetLayoutSize()

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

	Element:SetLayoutSize( NewSize )

	-- Return the final layout size from the element, in case it manages its own size.
	return Element:GetLayoutSize()
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

	local InnerBoxSize = Context.InnerBoxSize
	local Margins = Elements.Margins
	local Sizes = Elements.Sizes

	-- The start position depends on the direction and alignment.
	-- Vertical will start either top left or bottom left, horizontal top left or top right.
	local X, Y = self:GetStartPos( Context.Pos, Context.Size, Alignment, Context )

	for i = 1, Elements[ 0 ] do
		local Element = Elements[ i ]
		local Margin = Margins[ Element ]
		local MinW, MinH = self:GetMinMargin( Margin )
		local MaxW, MaxH = self:GetMaxMargin( Margin )
		local ElementSize = Sizes[ Element ]
		local SizeW, SizeH = self:GetElementSizeOffset( ElementSize )

		X, Y = UpdatePositionBefore( X, Y, MinW, MinH, MaxW, MaxH, SizeW, SizeH )

		self:SetElementPos( Element, X, Y, Margin, InnerBoxSize, ElementSize )

		X, Y = UpdatePositionAfter( X, Y, MinW, MinH, MaxW, MaxH, SizeW, SizeH )
	end
end

local function NewElementList( NumElements )
	local ElementList = TableNew( NumElements + 1, 3 )
	ElementList[ 0 ] = 0
	ElementList.TotalSize = 0
	ElementList.Margins = TableNew( 0, NumElements )
	ElementList.Sizes = TableNew( 0, NumElements )
	return ElementList
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
	local AlignedElements = TableNew( 4, 0 )
	AlignedElements[ LayoutAlignment.MIN ] = NewElementList( NumElements )
	AlignedElements[ LayoutAlignment.MAX ] = NewElementList( NumElements )
	AlignedElements[ LayoutAlignment.CENTRE ] = NewElementList( NumElements )
	AlignedElements[ 4 ] = TableNew( NumElements, 0 )

	-- Pre-compute the size of each fill element by setting the size of fixed-size elements upfront.
	local FillSize = self:GetFillSize( InnerBoxSize )
	local NumberOfFillElements = 0
	local CrossAxisSize = 0

	for i = 1, NumElements do
		local Element = Elements[ i ]
		if Element:GetIsVisible() then
			local ElementList = AlignedElements[ Element:GetAlignment() ]
			local Count = ElementList[ 0 ] + 1

			ElementList[ Count ] = Element
			ElementList[ 0 ] = Count

			local Margin = Element:GetComputedMargin()
			ElementList.Margins[ Element ] = Margin

			if not Element:GetFill() then
				local CurrentSize = self:SetElementSize( Element, InnerBoxSize, Margin )
				local SizeUsedUp = self:GetFillSize( CurrentSize ) + self:GetMarginSize( Margin )

				ElementList.TotalSize = ElementList.TotalSize + SizeUsedUp
				ElementList.Sizes[ Element ] = CurrentSize

				-- If the element is not set to fill the space, then it will use up its margin + size.
				FillSize = FillSize - SizeUsedUp
				CrossAxisSize = Max( CrossAxisSize, self:GetCrossAxisSize( CurrentSize ) )
			else
				local SizeUsedUp = self:GetMarginSize( Margin )

				ElementList.TotalSize = ElementList.TotalSize + SizeUsedUp

				-- Otherwise, only the margin is used up.
				FillSize = FillSize - SizeUsedUp
				NumberOfFillElements = NumberOfFillElements + 1

				AlignedElements[ 4 ][ NumberOfFillElements ] = Element
			end
		end
	end

	-- Once the fill size is known, apply it to every fill element to get the total content size.
	local FillSizePerElement = NumberOfFillElements == 0 and 0 or Max( FillSize, 0 ) / NumberOfFillElements
	for i = 1, NumberOfFillElements do
		local Element = AlignedElements[ 4 ][ i ]
		local ElementList = AlignedElements[ Element:GetAlignment() ]
		local CurrentSize = self:SetComputedFillSize(
			Element,
			InnerBoxSize,
			FillSizePerElement,
			ElementList.Margins[ Element ]
		)

		ElementList.TotalSize = ElementList.TotalSize + self:GetFillSize( CurrentSize )
		ElementList.Sizes[ Element ] = CurrentSize
		CrossAxisSize = Max( CrossAxisSize, self:GetCrossAxisSize( CurrentSize ) )
	end

	local Width, Height = self:ApplyContentSize(
		Max(
			AlignedElements[ LayoutAlignment.MIN ].TotalSize,
			AlignedElements[ LayoutAlignment.CENTRE ].TotalSize,
			AlignedElements[ LayoutAlignment.MAX ].TotalSize
		),
		CrossAxisSize
	)

	-- Record the final width and height of the layout. One of these will be the sum of the layout's direction, the
	-- other will be the max of the cross-axis sizes.
	-- Including padding here avoids surprises where a panel with a layout ends up ignoring the padding when adding
	-- scrolling.
	self.ContentWidth = Width + Padding[ 5 ]
	self.ContentHeight = Height + Padding[ 6 ]

	if self.IsScrollable then
		-- Update the inner box size to reflect the layout's actual size given its contents.
		-- This will affect how elements are positioned (e.g. max/centre aligned elements).
		InnerBoxSize.x = Max( Width, InnerBoxSize.x )
		InnerBoxSize.y = Max( Height, InnerBoxSize.y )

		Size.x = Max( self.ContentWidth, Size.x )
		Size.y = Max( self.ContentHeight, Size.y )
	end

	local MinX, MinY = Pos.x + Padding[ 1 ], Pos.y + Padding[ 2 ]

	-- This table "context" just saves a lot of method parameters.
	local Context = TableNew( 0, 9 )
	Context.Alignment = LayoutAlignment.MIN
	Context.Pos = Pos
	Context.InnerBoxSize = InnerBoxSize
	Context.Size = Size
	Context.MinX = MinX
	Context.MinY = MinY

	-- Layout each alignment in sequence, starting with the MIN aligned elements.
	Elements = AlignedElements[ Context.Alignment ]

	if Elements[ 0 ] > 0 then
		self:LayoutElements( Elements, Context )
	end

	Context.Alignment = LayoutAlignment.MAX
	Elements = AlignedElements[ Context.Alignment ]

	if Elements[ 0 ] > 0 then
		Context.MaxX = MinX + InnerBoxSize.x
		Context.MaxY = MinY + InnerBoxSize.y
		self:LayoutElements( Elements, Context )
	end

	Context.Alignment = LayoutAlignment.CENTRE
	Elements = AlignedElements[ Context.Alignment ]

	if Elements[ 0 ] > 0 then
		Context.CentreAlignedSize = AlignedElements[ LayoutAlignment.CENTRE ].TotalSize
		self:LayoutElements( Elements, Context )
	end

	return self.BaseClass.PerformLayout( self )
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
