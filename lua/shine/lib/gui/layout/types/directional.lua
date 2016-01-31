--[[
	Directional layout.

	Positions elements one after the other, in a given direction.

	Note that directional layouts assume that all elements are using the top-left anchor because it's
	easier to compute the positions that way.

	Anchoring to the right or bottom makes nested layouts essentially require a dummy GUIItem to hold
	them which I'm not willing to do.
]]

local Directional = {}
Directional.IsAbstract = true

local LayoutAlignment = Shine.GUI.LayoutAlignment

function Directional:SetElementSize( Element, RealSize, Margin )
	local Width = Element:GetComputedSize( 1, RealSize.x - Margin[ 1 ] - Margin[ 3 ] )
	local Height = Element:GetComputedSize( 2, RealSize.y - Margin[ 2 ] - Margin[ 4 ] )

	local CurrentSize = Element:GetSize()
	CurrentSize.x = Width
	CurrentSize.y = Height

	Element:SetSize( CurrentSize )

	return CurrentSize
end

--[[
	This method handles laying out elements, including keeping track of margins between them.
]]
function Directional:LayoutElements( Elements, Context )
	local Alignment = Context.Alignment
	local IsMin = Alignment == LayoutAlignment.MIN

	local Padding = Context.Padding
	local Pos = Context.Pos
	local RealSize = Context.RealSize
	local Size = Context.Size

	-- These keep track of how much space we have left over after all the fixed size elements
	-- have been accounted for.
	local AvailableFillSize = Context.AvailableFillSize
	local NumberOfFillElements = Context.NumberOfFillElements

	-- The start position depends on the direction and alignment.
	-- Vertical will start either top left or bottom left, horizontal top left or top right.
	local X, Y = self:GetStartPos( Pos, Size, Padding, Alignment )

	for i = 1, #Elements do
		local Element = Elements[ i ]

		if Element:GetIsVisible() then
			local Margin = Element:GetComputedMargin()
			local CurrentSize = self:SetElementSize( Element, RealSize, Margin )

			if not Element:GetFill() then
				-- If the element is not set to fill the space, then it will use up its margin + size.
				AvailableFillSize = AvailableFillSize - self:GetFillSize( CurrentSize ) - self:GetMarginSize( Margin )
			else
				-- Otherwise, only the margin is used up.
				AvailableFillSize = AvailableFillSize - self:GetMarginSize( Margin )
				NumberOfFillElements = NumberOfFillElements + 1
			end

			local MinW, MinH = self:GetMinMargin( Margin )
			local MaxW, MaxH = self:GetMaxMargin( Margin )
			local SizeW, SizeH = self:GetElementSizeOffset( CurrentSize )

			-- Margin before, if going from min to max, this is the left/top margin, otherwise the right/bottom.
			if IsMin then
				X, Y = X + MinW, Y + MinH
			else
				X, Y = X - MaxW - SizeW, Y - MaxH - SizeH
			end

			self:SetElementPos( Element, X, Y, Margin )

			-- Reverse for after.
			if IsMin then
				X, Y = X + MaxW + SizeW, Y + MaxH + SizeH
			else
				X, Y = X - MinW, Y - MinH
			end
		end
	end

	Context.AvailableFillSize = AvailableFillSize
	Context.NumberOfFillElements = NumberOfFillElements
end

--[[
	This method handles elements that have been set to fill any remaining space.

	It will evenly distribute the remaining space to all of them, and re-position
	everything else to compensate for size changes.
]]
function Directional:FillElements( Elements, Context )
	local Alignment = Context.Alignment
	local IsMin = Alignment == LayoutAlignment.MIN

	local FillSize = Context.FillSize
	local Padding = Context.Padding
	local Pos = Context.Pos
	local Size = Context.Size

	local X, Y = self:GetStartPos( Pos, Size, Padding, Alignment )
	local OffsetX, OffsetY = 0, 0

	for i = 1, #Elements do
		local Element = Elements[ i ]

		if Element:GetIsVisible() then
			local Pos = Element:GetPos()
			local Size = Element:GetSize()

			-- If we're coming from min to max, then we add the offset before
			-- we increase it.
			if IsMin then
				Pos.x = Pos.x + OffsetX
				Pos.y = Pos.y + OffsetY
			end

			if Element:GetFill() then
				local OldW, OldH = Size.x, Size.y
				self:ModifyFillElementSize( Size, FillSize )
				Element:SetSize( Size )

				OffsetX = OffsetX + Size.x - OldW
				OffsetY = OffsetY + Size.y - OldH
			end

			-- Otherwise, max to min subtracts the offset after changing size, as positioning
			-- is always from the top left of an element.
			if not IsMin then
				Pos.x = Pos.x - OffsetX
				Pos.y = Pos.y - OffsetY
			end

			Element:SetPos( Pos )
		end
	end
end

function Directional:PerformLayout()
	local Elements = self.Elements
	local Size = self.Size

	-- Real size is size - padding.
	local Padding = self:GetComputedPadding()
	local RealSize = Size - Vector2( Padding[ 1 ] + Padding[ 3 ], Padding[ 2 ] + Padding[ 4 ] )
	-- If we're attached to an element, this will return our margin, otherwise we're attached to another layout,
	-- which means our position will be somewhere inside the element at the top of the layout tree.
	local Pos = self:GetPos()

	-- Keep track of min and max aligned elements separately, as they need different layout rules.
	local MinAlignedElements = {}
	local MaxAlignedElements = {}

	for i = 1, #Elements do
		local Element = Elements[ i ]

		if Element:GetAlignment() == LayoutAlignment.MAX then
			MaxAlignedElements[ #MaxAlignedElements + 1 ] = Element
		else
			MinAlignedElements[ #MinAlignedElements + 1 ] = Element
		end
	end

	-- This table "context" just saves a lot of method parameters.
	local Context = {
		Alignment = LayoutAlignment.MIN,
		AvailableFillSize = self:GetFillSize( RealSize ),
		NumberOfFillElements = 0,
		Padding = Padding,
		Pos = Pos,
		RealSize = RealSize,
		Size = Size
	}

	-- Layout min then max aligned.
	self:LayoutElements( MinAlignedElements, Context )
	Context.Alignment = LayoutAlignment.MAX
	self:LayoutElements( MaxAlignedElements, Context )

	-- If there's no elements requesting to use the remaining space, we can stop.
	if Context.NumberOfFillElements == 0 then return end

	-- Run through again, setting the size of all fill elements to
	-- evenly use up the remaining size.
	Context.FillSize = Context.AvailableFillSize / Context.NumberOfFillElements

	self:FillElements( MaxAlignedElements, Context )
	Context.Alignment = LayoutAlignment.MIN
	self:FillElements( MinAlignedElements, Context )
end

Shine.GUI.Layout:RegisterType( "Directional", Directional )
