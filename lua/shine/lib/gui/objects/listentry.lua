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

	self.Background = GetGUIManager():CreateGraphicItem()
	self:SetHighlightOnMouseOver( true, 0.9 )
end

function ListEntry:SetTextColour( Colour )
	self.TextColour = Colour
	self:ForEach( "TextObjs", "SetColor", Colour )
end

function ListEntry:SetFont( Font )
	self.Font = Font
	self:ForEach( "TextObjs", "SetFontName", Font )
end

function ListEntry:SetTextScale( Scale )
	self.TextScale = Scale
	self:ForEach( "TextObjs", "SetScale", Scale )
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

	local Manager = GetGUIManager()
	local TextCol = self.TextColour

	self.ColumnText = {}

	for i = 1, Columns do
		local Text = tostring( select( i, ... ) )

		self.ColumnText[ i ] = Text

		local TextObj = Manager:CreateTextItem()
		TextObj:SetAnchor( GUIItem.Left, GUIItem.Center )
		TextObj:SetTextAlignmentY( GUIItem.Align_Center )
		TextObj:SetText( Text )
		TextObj:SetColor( TextCol )

		if self.Font then
			TextObj:SetFontName( self.Font )
		end

		if self.TextScale then
			TextObj:SetScale( self.TextScale )
		end

		Background:AddChild( TextObj )
		TextObj:SetInheritsParentStencilSettings( true )
		TextObjs[ i ] = TextObj
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

	if self.Selected then
		self.Background:SetColor( self.ActiveCol )
	end
end

function ListEntry:UpdateText( Obj, Size )
	local Text = Obj:GetText()
	local Scale = Obj:GetScale().x
	local Width = Obj:GetTextWidth( Text ) * Scale

	if Width > Size then
		local Chars = StringUTF8Encode( Text )
		local End = #Chars

		repeat
			End = End - 1
			Text = TableConcat( Chars, "", 1, End )

			Width = Obj:GetTextWidth( Text ) * Scale
		until Width < Size or End == 0

		Text = TableConcat( Chars, "", 1, End - 4 ).."..."

		Obj:SetText( Text )
	end
end

function ListEntry:SetSpacing( SpacingTable )
	local TextObjs = self.TextObjs

	local Spacing = {}
	self.Spacing = Spacing

	for i = 1, self.Columns do
		local Obj = TextObjs[ i ]
		local LastObj = TextObjs[ i - 1 ]
		local LastPos = LastObj and LastObj:GetPosition() or ZeroVector
		LastPos.y = 0

		Obj:SetPosition( Padding + ( Spacing[ i - 1 ] or ZeroVector ) + LastPos )

		local Size = SpacingTable[ i ]
		Spacing[ i ] = Vector2( Size, 0 )

		self:UpdateText( Obj, Size )
	end
end

function ListEntry:SetColumnText( Index, Text )
	local TextObjs = self.TextObjs
	if not TextObjs or not TextObjs[ Index ] then return end

	self.ColumnText[ Index ] = Text

	TextObjs[ Index ]:SetText( Text )
	self:UpdateText( TextObjs[ Index ], self.Spacing[ Index ].x )
end

function ListEntry:GetColumnText( Index )
	return self.ColumnText[ Index ] or ""
end

SGUI.AddProperty( ListEntry, "Selected" )

--Visibility checking should account for being outside the stencil box of the parent list.
function ListEntry:GetIsVisible()
	local Pos = self.Parent.ScrollParent:GetPosition() + self:GetPos()

	local ParentY = self.Parent.Size.y

	if Pos.y >= ParentY or Pos.y + self:GetSize().y <= 0 then
		return false
	end

	if not self.Parent:GetIsVisible() then return false end

	return self.Background:GetIsVisible()
end

function ListEntry:Think( DeltaTime )
	if not self:GetIsVisible() then return end
	if self.Selected then return end

	self.BaseClass.Think( self, DeltaTime )
end

function ListEntry:OnMouseDown( Key, DoubleClick )
	if not self.Parent then return end
	if Key ~= InputKey.MouseButton0 then return end
	if not self:GetIsVisible() then return end
	if not self:MouseIn( self.Background, 0.9 ) then return end

	return true, self
end

function ListEntry:OnMouseUp( Key )
	if not self.Parent then return end
	if Key ~= InputKey.MouseButton0 then return end
	if not self:GetIsVisible() then return end
	if not self:MouseIn( self.Background, 0.9 ) then return end

	if not self.Selected and self.Parent.OnRowSelect then
		self.Parent:OnRowSelect( self.Index, self )

		self.Selected = true
	elseif self.Selected and self.Parent.OnRowDeselect then
		self.Parent:OnRowDeselect( self.Index, self )

		self.Selected = false
	end

	return true
end

SGUI:Register( "ListEntry", ListEntry, "Button" )
