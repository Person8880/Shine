--[[
	List control.
]]

local SGUI = Shine.GUI

local List = {}

local Floor = math.floor
local select = select
local TableRemove = table.remove
local TableSort = table.sort
local tonumber = tonumber
local Vector = Vector

local ScrollPos = Vector( 10, 32, 0 )
local ZeroColour = Colour( 0, 0, 0, 0 )
local ZeroVector = Vector( 0, 0, 0 )

local DefaultHeaderSize = 32
local DefaultLineSize = 32

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

	local Scheme = SGUI:GetSkin()

	Background:SetColor( Scheme.InactiveButton )

	self.RowCount = 0

	self.HeaderSize = DefaultHeaderSize
	self.LineSize = DefaultLineSize

	local ListData = Scheme.List

	if ListData.HeaderSize then
		self:SetHeaderSize( ListData.HeaderSize )
	end

	if ListData.LineSize then
		self:SetLineSize( ListData.LineSize )
	end

	if ListData.HeaderFont then
		self:SetHeaderFont( ListData.HeaderFont )
	end

	if ListData.HeaderTextColour then
		self:SetHeaderTextColour( ListData.HeaderTextColour )
	end

	--Sort descending first.
	self.Descending = true
end

function List:OnSchemeChange( Scheme )
	self.Background:SetColor( Scheme.InactiveButton )

	if not Scheme.List then return end

	local ListData = Scheme.List

	if ListData.HeaderSize then
		self:SetHeaderSize( ListData.HeaderSize )
	end

	if ListData.LineSize then
		self:SetLineSize( ListData.LineSize )
	end

	if ListData.HeaderFont then
		self:SetHeaderFont( ListData.HeaderFont )
	end

	if ListData.HeaderTextColour then
		self:SetHeaderTextColour( ListData.HeaderTextColour )
	end
end

--[[
	Resizes the header height.
]]
function List:SetHeaderSize( Size )
	self.HeaderSize = Size

	local Columns = self.Columns

	if not Columns then return end

	if self.Size then
		self:SetSize( self.Size )
	end
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

	self:Reorder()
end

function List:SetHeaderFont( Font )
	self.HeaderFont = Font

	local Columns = self.Columns

	if not Columns then return end

	for i = 1, #Columns do
		local Header = Columns[ i ]

		Header:SetFont( Font )
	end
end

function List:SetHeaderTextScale( Scale )
	self.HeaderTextScale = Scale

	local Columns = self.Columns

	if not Columns then return end

	for i = 1, #Columns do
		local Header = Columns[ i ]

		Header:SetTextScale( Scale )
	end
end

function List:SetHeaderTextColour( Col )
	self.HeaderTextColour = Col

	local Columns = self.Columns

	if not Columns then return end

	for i = 1, #Columns do
		local Header = Columns[ i ]

		Header:SetTextColour( Col )
	end
end

--[[
	Sets up the column names.
	Inputs: Number of columns, columns names.
]]
function List:SetColumns( Number, ... )
	self.ColumnCount = Number

	local Columns = {}
	self.Columns = Columns

	for i = 1, Number do
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

		Columns[ i ] = Header
	end

	if self.Size then
		self:SetSize( self.Size )
	end
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
	end

	if self.Size then
		self:SetSize( self.Size )
	end
end

--[[
	Sets the list's size, just a simple vector input.
]]
function List:SetSize( Size )
	self.Background:SetSize( Size )
	self.Stencil:SetSize( Size )
	self.Size = Size

	self.ScrollPos = Vector( 10, self.HeaderSize, 0 )

	self.MaxRows = Floor( ( Size.y - self.HeaderSize ) / self.LineSize )

	if self.RowCount > self.MaxRows then
		if self.Scrollbar then
			self.Scrollbar:SetScrollSize( self.MaxRows / self.RowCount )
		else
			self:AddScrollbar()
		end
	elseif self.Scrollbar then
		self.Scrollbar:SetParent()
		self.Scrollbar:Destroy()

		self.Scrollbar = nil
		self.ScrollParent:SetPosition( Vector( 0, 0, 0 ) )
	end

	if not self.RowSize then
		self.RowSize = Vector( Size.x, self.LineSize, 0 )
	else
		self.RowSize.x = Size.x
	end

	local Columns = self.Columns

	if Columns then
		local HeaderSizes = self.HeaderSizes

		if not HeaderSizes then return end

		for i = 1, self.ColumnCount do
			local Obj = Columns[ i ]

			local X = HeaderSizes[ i ] * Size.x

			Obj:SetSize( Vector( X, self.HeaderSize, 0 ) )

			local LastColumn = Columns[ i - 1 ]
			local LastSize = LastColumn and LastColumn:GetSize() or ZeroVector
			LastSize.y = 0

			local LastPos = LastColumn and LastColumn:GetPos() or ZeroVector

			Obj:SetPos( LastPos + LastSize )
		end
	end
end

function List:SetRowFont( Font )
	self.RowFont = Font

	local Rows = self.Rows
	if not Rows then return end
	for i = 1, #Rows do
		Rows[ i ]:SetFont( Font )
	end
end

function List:SetRowTextScale( Scale )
	self.RowTextScale = Scale

	local Rows = self.Rows
	if not Rows then return end
	for i = 1, #Rows do
		Rows[ i ]:SetTextScale( Scale )
	end
end

--[[
	Adds a row to the list.
	Inputs: Column values in the row.
]]
function List:AddRow( ... )
	local Rows = self.Rows or {}
	self.Rows = Rows

	local RowCount = self.RowCount

	local Row = SGUI:Create( "ListEntry" )
	Row:SetParent( self, self.ScrollParent )
	Row.Background:SetInheritsParentStencilSettings( false )
	Row.Background:SetStencilFunc( GUIItem.NotEqual )
	Row:SetAnchor( GUIItem.Top, GUIItem.Left )
	Row:SetPos( Vector( 0, self.HeaderSize + RowCount * self.LineSize, 0 ) )

	if self.RowFont then
		Row:SetFont( self.RowFont )
	end

	if self.RowTextScale then
		Row:SetTextScale( self.RowTextScale )
	end

	RowCount = RowCount + 1

	Row:Setup( RowCount, self.ColumnCount, self.RowSize, ... )

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
		self:SortRows( self.SortedColumn, self.SortingFunc, self.Descending )
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

		Row:SetPos( Vector( 0, self.HeaderSize + ( i - 1 ) * self.LineSize, 0 ) )
		Row.Index = i
		Row:OnReorder()
	end
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
	Sorts the rows, generally used to sort by column values.
	Inputs: Column to sort by, optional sorting function.
]]
function List:SortRows( Column, SortFunc, Desc )
	local OldSortingColumn = self.SortedColumn
	local Rows = self.Rows

	if not Rows then
		self.SortedColumn = Column
		self.Descending = Desc
		self.SortingFunc = SortFunc

		UpdateHeaderHighlighting( self, Column, OldSortingColumn )

		return
	end

	if Desc == nil then
		--Only flip the sort order if we're selecting the same column twice.
		if OldSortingColumn == Column then
			self.Descending = not self.Descending
		else
			self.Descending = true
		end
	else
		self.Descending = Desc
	end

	if not self.NumericColumns or not self.NumericColumns[ Column ] then
		if self.Descending then
			TableSort( Rows, SortFunc or function( A, B )
				return A:GetColumnText( Column ):lower() < B:GetColumnText( Column ):lower()
			end )
		else
			TableSort( Rows, SortFunc or function( A, B )
				return A:GetColumnText( Column ):lower() > B:GetColumnText( Column ):lower()
			end )
		end
	else
		if self.Descending then
			TableSort( Rows, SortFunc or function( A, B )
				return tonumber( A:GetColumnText( Column ) ) < tonumber( B:GetColumnText( Column ) )
			end )
		else
			TableSort( Rows, SortFunc or function( A, B )
				return tonumber( A:GetColumnText( Column ) ) > tonumber( B:GetColumnText( Column ) )
			end )
		end
	end

	self.SortedColumn = Column
	self.SortingFunc = SortFunc

	if OldSortingColumn ~= Column then
		UpdateHeaderHighlighting( self, Column, OldSortingColumn )
	end

	return self:Reorder()
end

--[[
	Does exactly what it says it does, pass it the row index to remove.
]]
function List:RemoveRow( Index )
	local Rows = self.Rows

	if not Rows then return end

	local OldRow = Rows[ Index ]

	if not OldRow then return end

	OldRow:SetParent() --This allows it to run its cleanup function.
	OldRow:Destroy()

	TableRemove( Rows, Index )

	self.RowCount = self.RowCount - 1

	if self.RowCount <= self.MaxRows then
		if self.Scrollbar then
			self.Scrollbar:SetParent()
			self.Scrollbar:Destroy()

			self.Scrollbar = nil
		end

		--Make sure the scrolling is reset if there's no longer a scrollbar.
		self.ScrollParent:SetPosition( Vector( 0, 0, 0 ) )
	else
		self.Scrollbar:SetScrollSize( self.MaxRows / self.RowCount )
	end

	return self:Reorder()
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

function List:OnRowSelect( Index, Row )
	if self.MultiSelect then return end

	if self.SelectedRow and self.SelectedRow ~= Row then
		self.SelectedRow.Selected = false
	end

	self.SelectedRow = Row

	if self.OnRowSelected then
		self:OnRowSelected( Index, Row )
	end
end

function List:OnRowDeselect( Index, Row )
	self.SelectedRow = nil

	if self.OnRowDeselected then
		self:OnRowDeselected( Index, Row )
	end
end

function List:SetMultiSelect( Bool )
	self.MultiSelect = Bool and true or false
end

function List:GetMultiSelect()
	return self.MultiSelect
end

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
end

function List:PlayerType( Char )
	if self:CallOnChildren( "PlayerType", Char ) then
		return true
	end
end

SGUI:Register( "List", List )
