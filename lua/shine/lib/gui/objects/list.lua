--[[
	List control.
]]

local SGUI = Shine.GUI

local List = {}

local Floor = math.floor
local IsType = Shine.IsType
local Max = math.max
local Min = math.min
local select = select
local TableRemove = table.remove
local TableMergeSort = table.MergeSort
local tonumber = tonumber
local Vector = Vector

local ScrollPos = Vector( 0, 32, 0 )
local ZeroColour = Colour( 0, 0, 0, 0 )
local ZeroVector = Vector( 0, 0, 0 )

local DefaultHeaderSize = 32
local DefaultLineSize = 32

local Units = SGUI.Layout.Units
local Absolute = Units.Absolute
local Percentage = Units.Percentage
local UnitVector = Units.UnitVector

SGUI.AddBoundProperty( List, "Colour", "Background:SetColor" )

function List:Initialise()
	self.BaseClass.Initialise( self )

	local Manager = GetGUIManager()

	local Background = Manager:CreateGraphicItem()

	self.Background = Background

	--This element ensures the entries aren't visible past the bounds of the list.
	local Stencil = Manager:CreateGraphicItem()
	Stencil:SetIsStencil( true )
	Stencil:SetInheritsParentStencilSettings( false )
	Stencil:SetClearsStencilBuffer( true )

	Background:AddChild( Stencil )

	self.Stencil = Stencil

	--This dummy element will be moved when scrolling.
	local ScrollParent = Manager:CreateGraphicItem()
	ScrollParent:SetAnchor( GUIItem.Left, GUIItem.Top )
	ScrollParent:SetColor( ZeroColour )

	Background:AddChild( ScrollParent )

	self.ScrollParent = ScrollParent
	self.RowCount = 0
	self.HeaderSize = DefaultHeaderSize
	self.LineSize = DefaultLineSize

	-- Sort ascending first.
	self.Descending = false

	self.HeaderLayout = SGUI.Layout:CreateLayout( "Horizontal", {
		Fill = false,
		AutoSize = UnitVector( Percentage( 100 ), self.HeaderSize )
	} )
	self.Layout = SGUI.Layout:CreateLayout( "Vertical", {
		Elements = {
			self.HeaderLayout
		}
	} )
end

--[[
	Resizes the header height.
]]
function List:SetHeaderSize( Size )
	self.HeaderSize = Size
	self.HeaderLayout.AutoSize[ 2 ] = Absolute( Size )
	self:InvalidateLayout()
end

--[[
	Sets the height of each row.
]]
function List:SetLineSize( Size )
	self.LineSize = Size

	if self.Size then
		if not self.RowSize then
			self.RowSize = Vector( self.Size.x, Size, 0 )
		else
			self.RowSize.y = Size
		end

		self.MaxRows = Floor( ( self.Size.y - self.HeaderSize ) / self.LineSize )
	end

	local Rows = self.Rows
	if not Rows then return end

	for i = 1, #Rows do
		local Row = Rows[ i ]

		if SGUI.IsValid( Row ) then
			Row:SetSize( self.RowSize )
		end
	end

	if SGUI.IsValid( self.Scrollbar ) then
		self.Scrollbar:SetScrollSize( self.MaxRows / self.RowCount )
	end

	self:InvalidateLayout()
end

function List:SetHeaderFont( Font )
	self.HeaderFont = Font
	self:ForEach( "Columns", "SetFont", Font )
end

function List:SetHeaderTextScale( Scale )
	self.HeaderTextScale = Scale
	self:ForEach( "Columns", "SetTextScale", Scale )
end

function List:SetHeaderTextColour( Col )
	self.HeaderTextColour = Col
	self:ForEach( "Columns", "SetTextColour", Col )
end

--[[
	Sets up the column names.
	Inputs: Columns names.
]]
function List:SetColumns( ... )
	-- Backwards compatibility with the old number argument.
	local Number = select( 1, ... )
	local Start = 2
	if not IsType( Number, "number" ) then
		Number = select( "#", ... )
		Start = 1
	end

	self.ColumnCount = Number

	if self.Columns then
		for i = 1, self.Columns do
			self.Columns[ i ]:Destroy()
		end
	end

	local Columns = {}
	self.Columns = Columns

	self.HeaderLayout.Elements = {}

	local Count = 1
	for i = Start, Start + Number - 1 do
		local Header = SGUI:Create( "ListHeader", self )
		Header:SetText( select( i, ... ) )
		Header:SetAnchor( GUIItem.Left, GUIItem.Top )
		Header.Index = i

		if self.HeaderFont then
			Header:SetFont( self.HeaderFont )
		end
		if self.HeaderTextScale then
			Header:SetTextScale( self.HeaderTextScale )
		end
		if self.HeaderTextColour then
			Header:SetTextColour( self.HeaderTextColour )
		end

		Columns[ Count ] = Header
		Count = Count + 1

		self.HeaderLayout:AddElement( Header )
	end

	self.HeaderLayout:InvalidateLayout()
	self:InvalidateLayout()
end

function List:SetNumericColumn( Col )
	self.NumericColumns = self.NumericColumns or {}

	self.NumericColumns[ Col ] = true
end

--[[
	Sets up the column spacing. These should be proportions and add up to 1!
	Inputs: Column proportions.
]]
function List:SetSpacing( ... )
	local HeaderSizes = {}
	self.HeaderSizes = HeaderSizes

	for i = 1, select( "#", ... ) do
		local Size = select( i, ... )

		HeaderSizes[ i ] = Size
		self.Columns[ i ]:SetAutoSize( UnitVector( Percentage( Size * 100 ), Percentage( 100 ) ) )
	end

	self:InvalidateLayout()
end

--[[
	Sets the list's size, just a simple vector input.
]]
function List:SetSize( Size )
	self.Background:SetSize( Size )
	self.Stencil:SetSize( Size )
	self.Size = Size
	self:InvalidateLayout()
end

function List:PerformLayout()
	local Size = self.Size
	self.ScrollPos = Vector( 0, self.HeaderSize, 0 )

	self.MaxRows = Floor( ( Size.y - self.HeaderSize ) / self.LineSize )

	if self.RowCount > self.MaxRows then
		if self.Scrollbar then
			self.Scrollbar:SetScrollSize( self.MaxRows / self.RowCount )
			self.Scrollbar:SetPos( self.ScrollPos )
		else
			self:AddScrollbar()
		end
	elseif self.Scrollbar then
		self.Scrollbar:Destroy()

		self.Scrollbar = nil
		self.ScrollParent:SetPosition( Vector( 0, 0, 0 ) )
	end

	if not self.RowSize then
		self.RowSize = Vector( Size.x, self.LineSize, 0 )
	else
		self.RowSize.x = Size.x
	end

	self.BaseClass.PerformLayout( self )
end

function List:SetRowFont( Font )
	self.RowFont = Font
	self:ForEach( "Rows", "SetFont", Font )
end

function List:SetRowTextScale( Scale )
	self.RowTextScale = Scale
	self:ForEach( "Rows", "SetTextScale", Scale )
end

--[[
	Adds a row to the list.
	Inputs: Column values in the row.
]]
function List:AddRow( ... )
	if not self.RowSize then
		self:InvalidateLayout( true )
	end

	local Rows = self.Rows or {}
	self.Rows = Rows

	local RowCount = self.RowCount

	local Row = SGUI:Create( "ListEntry" )
	Row:SetParent( self, self.ScrollParent )
	Row.Background:SetInheritsParentStencilSettings( false )
	Row.Background:SetStencilFunc( GUIItem.NotEqual )
	Row:SetAnchor( GUIItem.Top, GUIItem.Left )

	if self.RowFont then
		Row:SetFont( self.RowFont )
	end

	if self.RowTextScale then
		Row:SetTextScale( self.RowTextScale )
	end

	RowCount = RowCount + 1
	Row:Setup( RowCount, self.ColumnCount, self.RowSize, ... )

	self.Layout:AddElement( Row )

	local Spacing = {}
	local X = self.RowSize.x

	local HeaderSizes = self.HeaderSizes

	for i = 1, self.ColumnCount do
		local Size = HeaderSizes[ i ]

		Spacing[ i ] = Size * X
	end

	Row:SetSpacing( Spacing )

	Rows[ RowCount ] = Row

	self.RowCount = RowCount

	if RowCount > self.MaxRows then
		if not self.Scrollbar then
			self:AddScrollbar()
		else
			self.Scrollbar:SetScrollSize( self.MaxRows / self.RowCount )
		end
	end

	if self.SortedColumn then
		self:RefreshSorting()
	else
		self:InvalidateLayout()
	end

	return Row
end

--[[
	Adds a scrollbar and sets it up to scroll the rows.
]]
function List:AddScrollbar()
	local Scrollbar = SGUI:Create( "Scrollbar", self )
	Scrollbar:SetAnchor( GUIItem.Right, GUIItem.Top )
	Scrollbar:SetPos( self.ScrollPos or ScrollPos )
	Scrollbar:SetSize( Vector( 10, self.Size.y - self.HeaderSize, 0 ) )
	Scrollbar:SetScrollSize( self.MaxRows / self.RowCount )
	Scrollbar._CallEventsManually = true

	self.Scrollbar = Scrollbar

	function self:OnScrollChange( Pos, MaxPos, Smoothed )
		local Fraction = Pos / MaxPos

		local RowDiff = self.RowCount - self.MaxRows

		if self.ScrollParentPos then
			self.ScrollParentPos.y = -RowDiff * self.LineSize * Fraction
		else
			self.ScrollParentPos = Vector( 0, -RowDiff * self.LineSize * Fraction, 0 )
		end

		if Smoothed then
			self:MoveTo( self.ScrollParent, nil, self.ScrollParentPos, 0, 0.3, nil, math.EaseOut, 3 )
		else
			self.ScrollParent:SetPosition( self.ScrollParentPos )
		end
	end
end

--[[
	Reorders the row elements.
	Should call after altering the self.Rows table or changing the line size.
]]
function List:Reorder()
	local Rows = self.Rows

	for i = 1, self.RowCount do
		local Row = Rows[ i ]
		Row.Index = i
		Row:OnReorder()
		self.Layout.Elements[ i + 1 ] = Row
	end

	self:InvalidateLayout( true )
end

local function UpdateHeaderHighlighting( self, Column, OldSortingColumn )
	local ColumnHeader = self.Columns[ Column ]
	if not ColumnHeader then return end

	ColumnHeader.ForceHighlight = true
	ColumnHeader:SetHighlighted( true, true )

	if OldSortingColumn then
		local OldHeader = self.Columns[ OldSortingColumn ]
		if not OldHeader then return end

		OldHeader.ForceHighlight = false
		OldHeader:SetHighlighted( false )
	end
end

--[[
	Sets a secondary column to sort by when sorting by the given column.
]]
function List:SetSecondarySortColumn( Column, SecondaryColumn )
	self.SecondarySortColumns = self.SecondarySortColumns or {}
	self.SecondarySortColumns[ Column ] = SecondaryColumn
end

function List:GetComparator( Column, Direction )
	local IsNumeric = self.NumericColumns and self.NumericColumns[ Column ]
	return Shine.Comparator( "Method", Direction or ( self.Descending and -1 or 1 ), "GetData",
		Column, IsNumeric and tonumber or string.UTF8Lower )
end

function List:RefreshSorting( Now )
	if not self.SortedColumn then return end

	if Now then
		self.NeedsSortingRefresh = false
		self:SortRows( self.SortedColumn, self.SortingFunc, self.Descending )
		return
	end

	self.NeedsSortingRefresh = true
end

--[[
	Sorts the rows, generally used to sort by column values.
	Inputs: Column to sort by, optional sorting function.
]]
function List:SortRows( Column, SortFunc, Desc )
	local OldSortingColumn = self.SortedColumn
	local Rows = self.Rows

	if not Rows then
		self.SortedColumn = Column
		self.Descending = Desc or false
		self.SortingFunc = SortFunc

		UpdateHeaderHighlighting( self, Column, OldSortingColumn )

		return
	end

	if Desc == nil then
		--Only flip the sort order if we're selecting the same column twice.
		if OldSortingColumn == Column then
			self.Descending = not self.Descending
		else
			self.Descending = false
		end
	else
		self.Descending = Desc
	end

	local Comparator = SortFunc
	if not Comparator then
		local SecondarySortColumn = self.SecondarySortColumns and self.SecondarySortColumns[ Column ]

		if SecondarySortColumn then
			Comparator = Shine.Comparator( "Composition", self:GetComparator( SecondarySortColumn, 1 ),
				self:GetComparator( Column ) ):CompileStable()
		else
			Comparator = self:GetComparator( Column ):CompileStable()
		end
	end

	TableMergeSort( Rows, Comparator )

	self.SortedColumn = Column
	self.SortingFunc = SortFunc

	if OldSortingColumn ~= Column then
		UpdateHeaderHighlighting( self, Column, OldSortingColumn )
	end

	self:Reorder()
end

--[[
	Does exactly what it says it does, pass it the row index to remove.
]]
function List:RemoveRow( Index )
	local Rows = self.Rows
	if not Rows then return end

	local OldRow = Rows[ Index ]
	if not OldRow then return end

	OldRow:Destroy()

	TableRemove( Rows, Index )
	self.Layout:RemoveElement( OldRow )

	self.RowCount = self.RowCount - 1

	if self.RowCount <= self.MaxRows then
		if self.Scrollbar then
			self.Scrollbar:Destroy()
			self.Scrollbar = nil
		end

		--Make sure the scrolling is reset if there's no longer a scrollbar.
		self.ScrollParent:SetPosition( Vector( 0, 0, 0 ) )
	else
		self.Scrollbar:SetScrollSize( self.MaxRows / self.RowCount )
	end

	if self.SelectedRow == OldRow then
		self.SelectedRow = nil
	end
	if self.RootMultiSelectRow == OldRow then
		self.RootMultiSelectRow = nil
	end

	self:Reorder()
end

function List:GetSelectedRows()
	local Rows = self.Rows
	local Selected = {}
	local Count = 0

	for i = 1, #Rows do
		local Row = Rows[ i ]

		if SGUI.IsValid( Row ) and Row.Selected then
			Count = Count + 1

			Selected[ Count ] = Row
		end
	end

	return Selected
end

function List:GetSelectedRow()
	if self.MultiSelect then return self:GetSelectedRows() end

	if not SGUI.IsValid( self.SelectedRow ) then
		return nil
	end

	return self.SelectedRow
end

function List:OnRowMultiSelect( Index, Row, SelectFromLast )
	if not SelectFromLast or not self.RootMultiSelectRow then
		self.RootMultiSelectRow = Row

		-- Deselect all other rows if not holding CTRL.
		local NumWereSelected = 0
		if not SGUI:IsControlDown() then
			local Rows = self.Rows
			for i = 1, #Rows do
				if Rows[ i ] ~= Row then
					NumWereSelected = NumWereSelected + ( Rows[ i ]:GetSelected() and 1 or 0 )
					Rows[ i ]:SetSelected( false )
				end
			end
		end

		Row:SetSelected( NumWereSelected > 0 or not Row:GetSelected() )
	else
		local RootSelected = self.RootMultiSelectRow
		local RootIndex = RootSelected.Index

		-- Select all rows between the original root and this row.
		local MinIndex = Min( RootIndex, Index )
		local MaxIndex = Max( RootIndex, Index )
		local Rows = self.Rows
		for i = 1, #Rows do
			Rows[ i ]:SetSelected( i >= MinIndex and i <= MaxIndex )
		end
	end
end

function List:OnRowSelect( Index, Row, SelectFromLast )
	if self.MultiSelect then
		self:OnRowMultiSelect( Index, Row, SelectFromLast )
		return
	end

	if self.SelectedRow and self.SelectedRow ~= Row then
		self.SelectedRow:SetSelected( false )
		self:OnRowDeselect( self.SelectedRow.Index, self.SelectedRow )
	end

	self.SelectedRow = Row
	Row:SetSelected( true )

	if self.OnRowSelected then
		self:OnRowSelected( Index, Row )
	end
end

function List:OnRowDeselect( Index, Row )
	if self.MultiSelect then
		self:OnRowSelect( Index, Row )
		return
	end

	self.SelectedRow = nil
	Row:SetSelected( false )

	if self.OnRowDeselected then
		self:OnRowDeselected( Index, Row )
	end
end

function List:ResetSelection()
	if self.MultiSelect then
		local Rows = self.Rows
		for i = 1, #Rows do
			Rows[ i ]:SetSelected( false )
		end

		return
	end

	if self.SelectedRow then
		self:OnRowDeselect( self.SelectedRow.Index, self.SelectedRow )
	end
end

SGUI.AddProperty( List, "MultiSelect" )

------------------- Event calling -------------------
function List:OnMouseDown( Key, DoubleClick )
	if SGUI.IsValid( self.Scrollbar ) then
		if self.Scrollbar:OnMouseDown( Key, DoubleClick ) then
			return true, self.Scrollbar
		end
	end

	local Result, Child = self:CallOnChildren( "OnMouseDown", Key, DoubleClick )

	if Result ~= nil then return true, Child end
end

function List:OnMouseMove( Down )
	if SGUI.IsValid( self.Scrollbar ) then
		self.Scrollbar:OnMouseMove( Down )
	end

	self:CallOnChildren( "OnMouseMove", Down )
end

function List:Think( DeltaTime )
	if self.NeedsSortingRefresh then
		self:RefreshSorting( true )
	end

	self.BaseClass.Think( self, DeltaTime )

	if SGUI.IsValid( self.Scrollbar ) then
		self.Scrollbar:Think( DeltaTime )
	end

	self:CallOnChildren( "Think", DeltaTime )
end

function List:OnMouseWheel( Down )
	--Call children first, so they scroll before the main panel scroll.
	local Result = self:CallOnChildren( "OnMouseWheel", Down )

	if Result ~= nil then return true end

	if not SGUI.IsValid( self.Scrollbar ) then
		return
	end

	self.Scrollbar.MouseWheelScroll = ( self.LineSize or 32 ) * 3

	return self.Scrollbar:OnMouseWheel( Down )
end

function List:PlayerKeyPress( Key, Down )
	if self:CallOnChildren( "PlayerKeyPress", Key, Down ) then
		return true
	end

	-- Block modifier keys used in multi-select from leaking out.
	if self.MultiSelect and ( SGUI.IsShiftKey( Key ) or SGUI.IsControlKey( Key ) )
	and self:MouseIn( self.Background ) then
		return true
	end
end

function List:PlayerType( Char )
	if self:CallOnChildren( "PlayerType", Char ) then
		return true
	end
end

SGUI:Register( "List", List )
