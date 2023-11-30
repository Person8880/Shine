--[[
	A panel that scrolls elements virtually, never creating more than the number of rows that can be visible.

	The panel must be configured with the following:

	* A pre-determined row height (can be a unit value).
	* A table of data values that can be split into rows based on the horizontal size of the virtual scroll space.
	* A row generator function, which performs the above splitting:

	function RowGenerator( Size, RowHeight, Data )
		-- Split rows based on the available width and a pre-determined element size.
		return {
			-- Row 1
			{ ... },
			-- Row 2
			{ ... },
			...
		}
	end

	* A row element generator function, which builds an element to represent a row of values:

	local ExampleRowElement = SGUI:DefineControl( "ExampleRowElement", "Row" )
	-- Row elements must implement a "SetContents" method. This will be called whenever a row's visible content changes.
	function ExampleRowElement:SetContents( Contents )
		-- Contents is one of the row tables split above which should be used to populate this row element.
	end
	function RowElementGenerator()
		return SGUI:CreateFromDefinition( ExampleRowElement )
	end

	Every row element will have their size set automatically to be (100%, RowHeight).
]]

local Ceil = math.ceil
local Clamp = math.Clamp
local Floor = math.floor
local Max = math.max

local SGUI = Shine.GUI
local Units = SGUI.Layout.Units

local VirtualScrollPanel = {}

local DefaultRowHeight = Units.GUIScaled( 32 )
local DefaultScrollbarWidth = Units.GUIScaled( 8 )

local SetScrollOffset = SGUI.AddProperty( VirtualScrollPanel, "ScrollOffset" )
local SetRowHeight = SGUI.AddProperty( VirtualScrollPanel, "RowHeight", DefaultRowHeight )
local SetScrollbarWidth = SGUI.AddProperty( VirtualScrollPanel, "ScrollbarWidth", DefaultScrollbarWidth )
local SetRowGenerator = SGUI.AddProperty( VirtualScrollPanel, "RowGenerator" )
local SetRowElementGenerator = SGUI.AddProperty( VirtualScrollPanel, "RowElementGenerator" )

function VirtualScrollPanel:Initialise()
	self.BaseClass.Initialise( self )

	local Background = self:MakeGUIItem()
	Background:SetShader( SGUI.Shaders.Invisible )
	self.Background = Background

	local CroppingBox = self:MakeGUICroppingItem()
	CroppingBox:SetShader( SGUI.Shaders.Invisible )
	self.Background:AddChild( CroppingBox )
	self.CroppingBox = CroppingBox

	local ScrollParent = self:MakeGUIItem()
	ScrollParent:SetShader( SGUI.Shaders.Invisible )
	CroppingBox:AddChild( ScrollParent )
	self.ScrollParent = ScrollParent
	self.ScrollParentPos = Vector2( 0, 0 )

	self.MaxHeight = 0
	self.ScrollOffset = 0
	self.RowHeight = DefaultRowHeight

	local Scrollbar = SGUI:Create( "Scrollbar", self )
	Scrollbar:SetPositionType( SGUI.PositionType.ABSOLUTE )
	Scrollbar:SetLeftOffset( Units.Percentage.ONE_HUNDRED )
	Scrollbar:SetAutoSize( Units.UnitVector( DefaultScrollbarWidth, Units.Percentage.ONE_HUNDRED ) )
	Scrollbar._CallEventsManually = true
	Scrollbar:SetIsVisible( false )
	self.Scrollbar = Scrollbar

	self:SetLayout( SGUI.Layout:CreateLayout( "Vertical" ), true )
end

function VirtualScrollPanel:ComputeRowHeight()
	return self.RowHeight:GetValue( self.Size.y, self, 2, self.Size.x )
end

function VirtualScrollPanel:SetScrollbarWidth( ScrollbarWidth )
	if not SetScrollbarWidth( self, ScrollbarWidth ) then return false end

	self.Scrollbar.AutoSize[ 1 ] = SGUI.Layout.ToUnit( ScrollbarWidth )
	self:InvalidateLayout()

	return true
end

function VirtualScrollPanel:RefreshContents()
	if not self.Data or not self.Size or not self.RowGenerator or not self.RowElementGenerator then return end

	local RowHeight = self:ComputeRowHeight()
	self.Rows = self.RowGenerator( self.Size, RowHeight, self.Data )
	self.MaxHeight = #self.Rows * RowHeight
	self.Scrollbar:SetIsVisible( self.MaxHeight > self.Size.y )

	-- Update the scrollbar with the new scroll size, and force a refresh of the row contents.
	self.ScrollOffset = nil
	self.Scrollbar:SetScrollSize( self.Size.y / Max( self.MaxHeight, self.Size.y ), true )
end

function VirtualScrollPanel:SetSize( Size )
	if not self.BaseClass.SetSize( self, Size ) then return false end

	self.CroppingBox:SetSize( Size )
	-- Force the scrollbar to update before changing anything else.
	self:UpdateAbsolutePositionChildren()
	self:RefreshContents()

	return true
end

function VirtualScrollPanel:SetRowHeight( RowHeight )
	if not SetRowHeight( self, RowHeight ) then return false end

	self:RefreshContents()

	return true
end

function VirtualScrollPanel:SetData( Data )
	self.Data = Data
	self:RefreshContents()
end

function VirtualScrollPanel:SetRowGenerator( RowGenerator )
	if not SetRowGenerator( self, RowGenerator ) then return false end

	self:RefreshContents()

	return true
end

function VirtualScrollPanel:SetRowElementGenerator( RowElementGenerator )
	if not SetRowElementGenerator( self, RowElementGenerator ) then return false end

	-- As the generated element is likely different, destroy any existing rows.
	for i = 1, #self.Layout.Elements do
		local RowElement = self.Layout.Elements[ i ]
		if SGUI.IsValid( RowElement ) then
			RowElement:Destroy()
		end
	end
	self:RefreshContents()

	return true
end

local function CreateRowIfMissing( self, ExistingRowElement )
	local RowElement = ExistingRowElement
	if not SGUI.IsValid( RowElement ) then
		RowElement = self.RowElementGenerator()
		RowElement:SetParent( self, self.ScrollParent )
		self.Layout:AddElement( RowElement )
		self:InvalidateLayout()
	end
	return RowElement
end

function VirtualScrollPanel:GetOrCreateRow( Index )
	local Elements = self.Layout.Elements
	-- Populate all rows behind this one as well as the requested index to avoid addings gaps to the element list.
	for i = #Elements + 1, Index - 1 do
		CreateRowIfMissing( self, Elements[ i ] )
	end
	return CreateRowIfMissing( self, Elements[ Index ] )
end

local function ComputeRowIndexFromScrollOffset( ScrollOffset, RowHeight )
	return Floor( ScrollOffset / RowHeight ) + 1
end

local function SetupRow( self, RowElement, RowIndex, RowHeight )
	RowElement.RowIndex = RowIndex

	local Content = self.Rows[ RowIndex ]
	if Content then
		RowElement:SetAutoSize( Units.UnitVector( Units.Percentage.ONE_HUNDRED, RowHeight ) )
		RowElement:SetIsVisible( true )
		RowElement:SetContents( Content )
	else
		RowElement:SetIsVisible( false )
	end
end

function VirtualScrollPanel:SetScrollOffset( Offset )
	Offset = Clamp( Offset, 0, Max( self.MaxHeight - self.Size.y, 0 ) )

	local OldScrollOffset = self.ScrollOffset
	if not SetScrollOffset( self, Offset ) then return false end

	local RowHeight = self:ComputeRowHeight()
	self.ScrollParentPos.y = -( Offset % RowHeight )
	self.ScrollParent:SetPosition( self.ScrollParentPos )

	local MaxVisibleRows = Ceil( self.Size.y / RowHeight ) + 1
	local RowIndex = ComputeRowIndexFromScrollOffset( self.ScrollOffset, RowHeight )

	local Delta
	if OldScrollOffset then
		-- If there's an old scroll offset, then all rows should have been setup for the current size, and thus the
		-- changes to apply depend on whether the first row index has changed.
		Delta = RowIndex - ComputeRowIndexFromScrollOffset( OldScrollOffset, RowHeight )
		if Delta >= MaxVisibleRows then
			-- All rows need changing, treat it the same as having no previous offset.
			Delta = nil
		end
	end

	if Delta then
		if Delta > 0 then
			-- Moved down, need to remove from the start of the row list and insert back at the end.
			-- Start from the old last row index and work forwards.
			local NewStartIndex = RowIndex - Delta + MaxVisibleRows - 1
			for i = 1, Delta do
				local RowElement = self:GetOrCreateRow( i )
				self.Layout:RemoveElement( RowElement )
				self.Layout:AddElement( RowElement )

				SetupRow( self, RowElement, NewStartIndex + i, RowHeight )
			end

			self:InvalidateLayout()
		elseif Delta < 0 then
			-- Moved up, need to remove from the end of the row list and insert back at the start.
			-- Start from the old first row index and work backwards.
			local NewStartIndex = RowIndex - Delta
			for i = -1, Delta, -1 do
				-- Inverted loop, but effectively just going Max + 0, Max - 1, Max -2...
				local RowElement = self:GetOrCreateRow( MaxVisibleRows + i + 1 )
				self.Layout:RemoveElement( RowElement )
				self.Layout:InsertElement( RowElement, 1 )

				SetupRow( self, RowElement, NewStartIndex + i, RowHeight )
			end

			self:InvalidateLayout()
		end
		-- If Delta == 0 then there's nothing to do, everything that should be visible is already visible.
	else
		-- There was no old scroll offset (i.e. this is a forced re-population) or the delta effectively means no rows
		-- can be re-used. For every visible row, update the contents to match the row from the data that's currently
		-- visible.
		for i = 1, MaxVisibleRows do
			local RowElement = self:GetOrCreateRow( i )
			SetupRow( self, RowElement, RowIndex, RowHeight )
			RowIndex = RowIndex + 1
		end

		-- Clear out any additional elements that are no longer required (if the max visible rows decreased).
		for i = #self.Layout.Elements, MaxVisibleRows + 1, -1 do
			local RowElement = self.Layout.Elements[ i ]
			if SGUI.IsValid( RowElement ) then
				RowElement:Destroy()
			end
		end
	end

	if self.LayoutIsInvalid then
		self:InvalidateLayout( true )
	end

	self:InvalidateMouseState( true )

	return true
end

local ScrollEaser = {
	Easer = function( self, Element, EasingData, Progress )
		EasingData.CurValue = EasingData.Start + EasingData.Diff * Progress
	end,
	Setter = function( self, Element, ScrollOffset )
		self:SetScrollOffset( ScrollOffset )
	end,
	Getter = function( self, Element )
		return self.ScrollOffset or 0
	end
}

local ScrollTransition = {
	Duration = 0.3,
	Easer = ScrollEaser
}

function VirtualScrollPanel:OnScrollChange( Pos, MaxPos, Smoothed )
	local Fraction = MaxPos == 0 and 0 or Pos / MaxPos
	local ScrollOffset = Fraction * ( self.MaxHeight - self.Size.y )

	if Smoothed then
		ScrollTransition.Element = self.Background
		ScrollTransition.StartValue = self.ScrollOffset or 0
		ScrollTransition.EndValue = ScrollOffset
		self:ApplyTransition( ScrollTransition )
	else
		self:StopEasing( self.Background, ScrollEaser )
		self:SetScrollOffset( ScrollOffset )
	end
end

function VirtualScrollPanel:OnMouseDown( Key, DoubleClick )
	if not self:GetIsVisible() then return end

	if SGUI.IsValid( self.Scrollbar ) then
		if self.Scrollbar:OnMouseDown( Key, DoubleClick ) then
			return true, self.Scrollbar
		end
	end

	if not self:HasMouseEntered() then return end

	local Result, Child = self:CallOnChildren( "OnMouseDown", Key, DoubleClick )
	if Result ~= nil then return true, Child end
end

function VirtualScrollPanel:OnMouseMove( Down )
	if not self:GetIsVisible() then return end

	self.__LastMouseMove = SGUI.FrameNumber()

	if SGUI.IsValid( self.Scrollbar ) then
		self.Scrollbar:OnMouseMove( Down )
	end

	local MouseIn, StateChanged = self:EvaluateMouseState()
	if MouseIn or StateChanged then
		self:CallOnChildren( "OnMouseMove", Down )
	end
end

function VirtualScrollPanel:Think( DeltaTime )
	if not self:GetIsVisible() then return end

	self.BaseClass.ThinkWithChildren( self, DeltaTime )

	if SGUI.IsValid( self.Scrollbar ) then
		self.Scrollbar:Think( DeltaTime )
	end
end

function VirtualScrollPanel:OnMouseWheel( Down )
	if not self:GetIsVisible() then return end

	-- Call children first, so they scroll before the main panel scroll.
	local Result = self:CallOnChildren( "OnMouseWheel", Down )
	if Result ~= nil then return true end

	if SGUI.IsValid( self.Scrollbar ) then
		if self.Scrollbar:OnMouseWheel( Down ) then
			return true
		end
	end
end

SGUI:Register( "VirtualScrollPanel", VirtualScrollPanel )
