--[[
	List entry for use in the list control.
]]

local SGUI = Shine.GUI

local ListEntry = {}

local select = select
local StringUTF8Encode = string.UTF8Encode
local TableConcat = table.concat
local tostring = tostring

local Padding = Vector( 5, 0, 0 )
local ZeroVector = Vector( 0, 0, 0 )

local function IsEven( Num )
	return Num % 2 == 0
end

function ListEntry:Initialise()
	if self.Background then GUI.DestroyItem( self.Background ) end

	self.BaseClass.Initialise( self )

	local Background = GetGUIManager():CreateGraphicItem()

	self.Background = Background

	local Scheme = SGUI:GetSkin()
	Background:SetColor( Scheme.InactiveButton )

	self.InactiveCol = Scheme.InactiveButton
	self.ActiveCol = Scheme.List.EntryActive

	self:SetHighlightOnMouseOver( true, 0.9 )
end

function ListEntry:OnSchemeChange( Scheme )
	if not self.UseScheme then return end

	if self.Index then
		self.InactiveCol = IsEven( self.Index ) and Scheme.List.EntryEven or Scheme.List.EntryOdd
	else
		self.InactiveCol = Scheme.InactiveButton
	end
	self.ActiveCol = Scheme.List.EntryActive

	self.Background:SetColor( self.Highlighted and self.ActiveCol or self.InactiveCol )

	local TextObjs = self.TextObjs

	if TextObjs then
		local TextCol = Scheme.List.EntryTextColour or Scheme.DarkText

		for i = 1, self.Columns do
			local Text = TextObjs[ i ]

			Text:SetColor( TextCol )
		end
	end
end

function ListEntry:SetFont( Font )
	self.Font = Font

	local TextObjs = self.TextObjs
	if not TextObjs then return end

	for i = 1, #TextObjs do
		TextObjs[ i ]:SetFontName( Font )
	end
end

function ListEntry:SetTextScale( Scale )
	self.TextScale = Scale

	local TextObjs = self.TextObjs
	if not TextObjs then return end

	for i = 1, #TextObjs do
		TextObjs[ i ]:SetScale( Font )
	end
end

function ListEntry:Setup( Index, Columns, Size, ... )
	self.Index = Index

	local Scheme = SGUI:GetSkin()

	self.InactiveCol = IsEven( self.Index ) and Scheme.List.EntryEven or Scheme.List.EntryOdd
	self.Background:SetColor( self.Highlighted and self.ActiveCol or self.InactiveCol )

	self.Columns = Columns

	local TextObjs = {}
	self.TextObjs = TextObjs

	local Background = self.Background
	self.Size = Size

	Background:SetSize( Size )

	local Manager = GetGUIManager()
	local TextCol = Scheme.List.EntryTextColour or Scheme.DarkText

	for i = 1, Columns do
		local Text = tostring( select( i, ... ) )

		local TextObj = Manager:CreateTextItem()
		TextObj:SetAnchor( GUIItem.Left, GUIItem.Center )
		TextObj:SetTextAlignmentY( GUIItem.Align_Center )
		TextObj:SetText( Text )
		TextObj:SetColor( TextCol )

		if self.Font then
			TextObj:SetFontName( self.Font )
		elseif Scheme.List.EntryFont then
			TextObj:SetFontName( Scheme.List.EntryFont )
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
	local Scheme = SGUI:GetSkin()

	self.InactiveCol = IsEven( self.Index ) and Scheme.List.EntryEven or Scheme.List.EntryOdd
	self.Background:SetColor( ( self.Highlighted or self.Selected )
		and self.ActiveCol or self.InactiveCol )
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

		Spacing[ i ] = Vector( Size, 0, 0 )

		local Text = Obj:GetText()
		local Scale = Obj:GetScale()
		local Width = Obj:GetTextWidth( Text ) * Scale.x

		if Width > Size then
			local Chars = StringUTF8Encode( Text )
			local End = #Chars

			repeat
				End = End - 1
				Text = TableConcat( Chars, "", 1, End )

				Width = Obj:GetTextWidth( Text ) * Scale.x
			until Width < Size or #Text == 0

			Text = TableConcat( Chars, "", 1, End - 4 )
			Text = Text.."..."

			Obj:SetText( Text )
		end
	end
end

function ListEntry:SetColumnText( Index, Text )
	local TextObjs = self.TextObjs

	if not TextObjs or not TextObjs[ Index ] then return end

	TextObjs[ Index ]:SetText( Text )
end

function ListEntry:GetColumnText( Index )
	local TextObjs = self.TextObjs

	if not TextObjs or not TextObjs[ Index ] then return "" end

	return TextObjs[ Index ]:GetText()
end

function ListEntry:SetSelected( Bool )
	self.Selected = Bool and true or false
end

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

SGUI:Register( "ListEntry", ListEntry )
