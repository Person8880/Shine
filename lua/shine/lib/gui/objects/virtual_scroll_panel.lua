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

	self.DataRevision = 0
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

	self.RowElements = {}

	self:SetLayout( SGUI.Layout:CreateLayout( "Vertical" ), true )
end

function VirtualScrollPanel:ComputeRowHeight()
	return self.RowHeight:GetValue( self.Size.y, self, 2 )
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
	self.DataRevision = self.DataRevision + 1
	self.MaxHeight = #self.Rows * RowHeight
	self.Scrollbar:SetIsVisible( self.MaxHeight > self.Size.y )

	-- Clamp the scroll offset into the visible range, this will also trigger a refresh of the row contents.
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
	for i = 1, #self.RowElements do
		local RowElement = self.RowElements[ i ]
		if SGUI.IsValid( RowElement ) then
			RowElement:Destroy()
		end
		self.RowElements[ i ] = nil
	end
	self:RefreshContents()

	return true
end

function VirtualScrollPanel:GetOrCreateRow( Index )
	local RowElement = self.RowElements[ Index ]
	if not SGUI.IsValid( RowElement ) then
		RowElement = self.RowElementGenerator()
		RowElement:SetParent( self, self.ScrollParent )
		self.Layout:InsertElement( RowElement, Index )
		self:InvalidateLayout()
		self.RowElements[ Index ] = RowElement
	end
	return RowElement
end

function VirtualScrollPanel:SetScrollOffset( Offset )
	Offset = Clamp( Offset, 0, Max( self.MaxHeight - self.Size.y, 0 ) )

	if not SetScrollOffset( self, Offset ) then return false end

	local RowHeight = self:ComputeRowHeight()
	self.ScrollParentPos.y = -( Offset % RowHeight )
	self.ScrollParent:SetPosition( self.ScrollParentPos )

	local DataRevision = self.DataRevision
	local MaxVisibleRows = Ceil( self.Size.y / RowHeight ) + 1
	local RowIndex = Floor( self.ScrollOffset / RowHeight ) + 1

	-- For every visible row, update the contents to match the row from the data that's currently visible.
	for i = 1, MaxVisibleRows do
		local RowElement = self:GetOrCreateRow( i )
		-- If this row is already setup with the row at the given index for the same data, stop here as that means all
		-- subsequent rows are also setup correctly. Nothing should be mutating the built rows.
		if RowElement.RowIndex == RowIndex and RowElement.DataRevision == DataRevision then
			break
		end

		RowElement.RowIndex = RowIndex
		RowElement.DataRevision = DataRevision

		local Content = self.Rows[ RowIndex ]
		if Content then
			RowElement:SetAutoSize( Units.UnitVector( Units.Percentage.ONE_HUNDRED, RowHeight ) )
			RowElement:SetIsVisible( true )
			RowElement:SetContents( Content )
		else
			RowElement:SetIsVisible( false )
		end

		RowIndex = RowIndex + 1
	end

	-- Clear out any additional elements that are no longer required (if the max visible rows decreased).
	for i = #self.RowElements, MaxVisibleRows + 1, -1 do
		local RowElement = self.RowElements[ i ]
		if SGUI.IsValid( RowElement ) then
			RowElement:Destroy()
		end
		self.RowElements[ i ] = nil
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
