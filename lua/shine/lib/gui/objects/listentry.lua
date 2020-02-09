--[[
	List entry for use in the list control.
]]

local SGUI = Shine.GUI

local ListEntry = {}

local select = select
local StringUTF8Encode = string.UTF8Encode
local TableConcat = table.concat
local tostring = tostring

local Padding = Vector2( 5, 0 )
local ZeroVector = Vector2( 0, 0 )

local function IsEven( Num )
	return Num % 2 == 0
end

function ListEntry:Initialise()
	self.BaseClass.Initialise( self )

	-- Real data may be different to what's displayed (e.g. time values)
	self.Data = {}

	self.Background = self:MakeGUIItem()
	self:SetHighlightOnMouseOver( true )
end

function ListEntry:IsDefaultStyle( TextObj, Index )
	return not self.TextOverrides or not self.TextOverrides[ Index ]
end

function ListEntry:SetTextColour( Colour )
	self.TextColour = Colour
	self:ForEachFiltered( "TextObjs", "SetColour", self.IsDefaultStyle, Colour )
end

function ListEntry:SetFont( Font )
	self.Font = Font
	self:ForEachFiltered( "TextObjs", "SetFont", self.IsDefaultStyle, Font )
end

function ListEntry:SetTextScale( Scale )
	self.TextScale = Scale
	self:ForEachFiltered( "TextObjs", "SetTextScale", self.IsDefaultStyle, Scale )
end

function ListEntry:Setup( Index, Columns, Size, ... )
	self.Index = Index
	self.Size = Size
	self.Columns = Columns

	if IsEven( Index ) then
		self:SetStyleName( "DefaultEven" )
	end

	local TextObjs = {}
	self.TextObjs = TextObjs

	local Background = self.Background
	Background:SetSize( Size )

	local TextCol = self.TextColour

	self.ColumnText = {}

	for i = 1, Columns do
		local Text = tostring( select( i, ... ) )

		self.ColumnText[ i ] = Text

		local TextObj = SGUI:Create( "Label", self )
		TextObj:SetIsSchemed( false )
		TextObj:SetAnchorFraction( 0, 0.5 )
		TextObj:SetTextAlignmentY( GUIItem.Align_Center )
		TextObj:SetText( Text )
		TextObj:SetColour( TextCol )

		if self.Font then
			TextObj:SetFont( self.Font )
		end

		if self.TextScale then
			TextObj:SetTextScale( self.TextScale )
		end

		TextObjs[ i ] = TextObj
	end
end

function ListEntry:SetTextOverride( Column, Override )
	self.TextOverrides = self.TextOverrides or {}
	self.TextOverrides[ Column ] = Override

	return self:ApplyTextOverride( Column, Override )
end

function ListEntry:ApplyTextOverride( Column, Override )
	local TextObj = self.TextObjs[ Column ]
	Shine.AssertAtLevel( TextObj, "Invalid column for text override!", 3 )

	TextObj:SetFont( Override.Font or self.Font )
	TextObj:SetTextScale( Override.TextScale or TextScale )
	TextObj:SetColour( Override.Colour or self.TextColour )
end

function ListEntry:RefreshOverrides()
	if not self.TextOverrides then return end

	for i = 1, self.Columns do
		local Override = self.TextOverrides[ i ]
		if Override then
			self:ApplyTextOverride( i, Override )
		end
	end
end

function ListEntry:OnReorder()
	local Font, TextScale = self.Font, self.TextScale
	self:SetStyleName( IsEven( self.Index ) and "DefaultEven" or nil )
	if Font then
		self:SetFont( Font )
	end
	if TextScale then
		self:SetTextScale( TextScale )
	end

	self:RefreshOverrides()

	if self.Selected then
		self.Background:SetColor( self.ActiveCol )
	end
end

function ListEntry:UpdateText( Index, Obj, Size )
	local Text = self.ColumnText[ Index ]
	local Width = Obj:GetTextWidth( Text )

	if Width > Size then
		local Chars = StringUTF8Encode( Text )
		local End = #Chars

		repeat
			End = End - 1
			Text = TableConcat( Chars, "", 1, End )

			Width = Obj:GetTextWidth( Text )
		until Width < Size or End == 0

		Text = TableConcat( Chars, "", 1, End - 4 ).."..."
	end

	Obj:SetText( Text )
end

function ListEntry:SetSpacing( SpacingTable )
	local TextObjs = self.TextObjs

	local Spacing = {}
	self.Spacing = Spacing

	for i = 1, self.Columns do
		local Obj = TextObjs[ i ]
		local LastObj = TextObjs[ i - 1 ]
		local LastPos = LastObj and LastObj:GetPos() or ZeroVector
		LastPos.y = 0

		Obj:SetPos( Padding + ( Spacing[ i - 1 ] or ZeroVector ) + LastPos )

		local Size = SpacingTable[ i ]
		Spacing[ i ] = Vector2( Size, 0 )

		self:UpdateText( i, Obj, Size )
	end
end

function ListEntry:SetData( Index, Data )
	if self.Data[ Index ] == Data then return end

	self.Data[ Index ] = Data
	self.Parent:RefreshSorting()
end

function ListEntry:GetData( Index )
	return self.Data[ Index ] or self.ColumnText[ Index ] or ""
end

function ListEntry:SetColumnText( Index, Text )
	local TextObjs = self.TextObjs
	if not TextObjs or not TextObjs[ Index ] then return end
	if Text == self.ColumnText[ Index ] then return end

	self.ColumnText[ Index ] = Text

	TextObjs[ Index ]:SetText( Text )
	self:UpdateText( Index, TextObjs[ Index ], self.Spacing[ Index ].x )

	if self.Data[ Index ] == nil then
		self.Parent:RefreshSorting()
	end
end

function ListEntry:GetColumnText( Index )
	return self.ColumnText[ Index ] or ""
end

SGUI.AddProperty( ListEntry, "Selected" )
function ListEntry:SetSelected( Selected, SkipAnim )
	self.Selected = Selected
	self:SetHighlighted( Selected, SkipAnim )
	self.HighlightOnMouseOver = not Selected
end

-- Visibility checking should account for being outside the stencil box of the parent list.
function ListEntry:IsInView()
	if not self:GetIsVisible() then return false end

	local Pos = self.Parent.ScrollParent:GetPosition() + self:GetPos()
	local ParentY = self.Parent.Size.y

	return Pos.y < ParentY and Pos.y + self:GetSize().y > 0
end

function ListEntry:Think( DeltaTime )
	if not self:IsInView() then return end

	self.BaseClass.Think( self, DeltaTime )
	self:CallOnChildren( "Think", DeltaTime )
end

function ListEntry:OnMouseDown( Key, DoubleClick )
	if not self:GetIsVisible() then return end
	if not self.Parent then return end
	if Key ~= InputKey.MouseButton0 then return end
	-- No need to call IsInView() here as List checks if the mouse is inside itself before
	-- passing mouse events down.
	if not self:MouseIn( self.Background ) then return end

	return true, self
end

function ListEntry:OnMouseUp( Key )
	if not self.Parent then return end
	if Key ~= InputKey.MouseButton0 then return end
	if not self:MouseIn( self.Background ) then return end

	if SGUI:IsShiftDown() then
		-- Select multiple rows, if supported.
		self.Parent:OnRowSelect( self.Index, self, true )
		return true
	end

	if not self.Selected and self.Parent.OnRowSelect then
		self.Parent:OnRowSelect( self.Index, self )
	elseif self.Selected and self.Parent.OnRowDeselect then
		self.Parent:OnRowDeselect( self.Index, self )
	end

	return true
end

SGUI:Register( "ListEntry", ListEntry, "Button" )
