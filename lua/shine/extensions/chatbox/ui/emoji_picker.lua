--[[
	Provides an emoji picker window.
]]

local EmojiUtil = require "shine/extensions/chatbox/ui/emoji_util"

local Floor = math.floor
local IsType = Shine.IsType
local StringFormat = string.format

local Hook = Shine.Hook
local SGUI = Shine.GUI
local Controls = SGUI.Controls
local Units = SGUI.Layout.Units

local AgencyFB = {
	Family = "kAgencyFB",
	Size = Units.GUIScaled( 27 )
}
local AgencyFBMedium = {
	Family = "kAgencyFB",
	Size = Units.GUIScaled( 33 )
}
local EmojiImageSize = Units.Percentage( 80 )

local EmojiPicker = SGUI:DefineControl( "EmojiPicker", "Column" )
local EmojiRow = SGUI:DefineControl( "EmojiRow", "Row" )

function EmojiRow:Initialise()
	Controls.Row.Initialise( self )

	self.Background:SetShader( SGUI.Shaders.Invisible )
	self.Buttons = {}
end

local function OnClickEmojiButton( self )
	local Picker = self.Parent
	while Picker and Picker.Class ~= "EmojiPicker" do
		Picker = Picker.Parent
	end
	Picker:OnEmojiSelected( self.Emoji )
	Picker.Elements.SearchInput:RequestFocus()
end

function EmojiRow:GetOrCreateButton( Index )
	local Button = self.Buttons[ Index ]
	if not SGUI.IsValid( Button ) then
		Button = SGUI:Create( "Button", self )
		Button:SetStyleName( "EmojiButton" )
		Button:SetDoClick( OnClickEmojiButton )

		local Image = SGUI:Create( "Image", Button )
		Image:SetAlignment( SGUI.LayoutAlignment.CENTRE )
		Image:SetCrossAxisAlignment( SGUI.LayoutAlignment.CENTRE )
		Image:SetAutoSize( Units.UnitVector( EmojiImageSize, EmojiImageSize ) )
		Button.Image = Image
		Button.Layout:InsertElement( Image, 1 )

		self.Layout:InsertElement( Button, Index )
		self.Buttons[ Index ] = Button
	end
	return Button
end

function EmojiRow:GetOrCreateTitleLabel()
	local Label = self.TitleLabel
	if not SGUI.IsValid( Label ) then
		Label = SGUI:Create( "Label", self )
		Label:SetStyleName( "EmojiCategoryHeader" )
		Label:SetAutoFont( AgencyFBMedium )
		Label:SetCrossAxisAlignment( SGUI.LayoutAlignment.CENTRE )
		Label:SetAutoEllipsis( true )
		Label:SetFill( true )
		self.Layout:AddElement( Label )
		self.TitleLabel = Label
	end
	return Label
end

function EmojiRow:SetContents( Contents )
	if IsType( Contents, "string" ) then
		-- Is a category title, show the title label and hide all buttons.
		local Label = self:GetOrCreateTitleLabel()
		Label:SetText( Contents )
		Label:SetIsVisible( true )

		for i = 1, #self.Buttons do
			local Button = self.Buttons[ i ]
			if SGUI.IsValid( Button ) then
				Button:SetIsVisible( false )
			end
		end

		self:InvalidateLayout()

		return
	end

	-- Is a row of emoji, hide the title label and show the relevant buttons.
	if SGUI.IsValid( self.TitleLabel ) then
		self.TitleLabel:SetIsVisible( false )
	end

	local NumEmoji = #Contents
	for i = 1, NumEmoji do
		local EmojiDefinition = Contents[ i ]
		local Button = self:GetOrCreateButton( i )
		Button:SetAutoSize( Units.UnitVector( self.AutoSize[ 2 ], self.AutoSize[ 2 ] ) )
		EmojiUtil.ApplyEmojiToImage( Button.Image, EmojiDefinition )

		-- Whenever a row's contents change, the button should be treated as if it is a new element, as that's what
		-- would be the case if scrolling was not virtualised. Hence any old tooltip needs to be hidden immediately
		-- without changing its text, and any hover highlighting state needs to be reset.
		Button:ResetTooltip( StringFormat( ":%s:", EmojiDefinition.Name ) )
		Button:SetHighlighted( false, true )

		Button:SetIsVisible( true )
		Button.Emoji = EmojiDefinition.Name
	end

	for i = NumEmoji + 1, #self.Buttons do
		local Button = self.Buttons[ i ]
		if SGUI.IsValid( Button ) then
			Button:SetIsVisible( false )
		end
	end

	self:InvalidateLayout()
end

local function AddEmojiRows( EmojiList, NumEmojiPerRow, Rows, RowCount )
	for i = 1, #EmojiList, NumEmojiPerRow do
		local Row = {}
		for j = 1, NumEmojiPerRow do
			Row[ j ] = EmojiList[ i + j - 1 ]
		end
		RowCount = RowCount + 1
		Rows[ RowCount ] = Row
	end
	return RowCount
end

function EmojiPicker:Initialise()
	Controls.Column.Initialise( self )

	self.InheritsParentAlpha = true
	self:SetPropagateAlphaInheritance( true )

	self.ShowCategories = true

	self.Elements = SGUI:BuildTree( {
		Parent = self,
		{
			Class = "TextEntry",
			ID = "SearchInput",
			Props = {
				AutoSize = Units.UnitVector(
					Units.Percentage.ONE_HUNDRED,
					Units.GUIScaled( 32 )
				),
				AutoFont = AgencyFB,
				Margin = Units.Spacing( 0, 0, 0, Units.GUIScaled( 4 ) ),
				StyleName = "EmojiPickerSearch"
			}
		},
		{
			Class = "VirtualScrollPanel",
			ID = "EmojiGrid",
			Props = {
				Fill = true,
				ScrollbarWidth = Units.GUIScaled( 4 ),
				RowGenerator = function( Size, RowHeight, EmojiList )
					local NumEmojiPerRow = Floor( Size.x / RowHeight )
					local Rows = {}
					local RowCount = 0

					if self.ShowCategories then
						local RowsByCategory = Shine.Multimap()
						for i = 1, #EmojiList do
							local EmojiDefinition = EmojiList[ i ]
							RowsByCategory:Add( EmojiDefinition.Category.Name, EmojiDefinition )
						end

						for Category, Emoji in RowsByCategory:Iterate() do
							RowCount = RowCount + 1
							Rows[ RowCount ] = Shine.Locale:SelectPhrase( Emoji[ 1 ].Category.Translations, Category )
							RowCount = AddEmojiRows( Emoji, NumEmojiPerRow, Rows, RowCount )
						end
					else
						RowCount = AddEmojiRows( EmojiList, NumEmojiPerRow, Rows, RowCount )
					end

					return Rows
				end,
				RowElementGenerator = function()
					return SGUI:CreateFromDefinition( EmojiRow )
				end,
				RowHeight = Units.GUIScaled( 48 )
			}
		}
	} )

	self.Elements.SearchInput:AddPropertyChangeListener( "Text", function( TextEntry, NewText )
		if #NewText == 0 then
			self.ShowCategories = true
			self.Elements.EmojiGrid:SetData( self.EmojiList )
			return
		end

		self.ShowCategories = false

		local Results = Hook.Call( "OnChatBoxEmojiAutoComplete", self, NewText )
		if not IsType( Results, "table" ) or #Results == 0 then
			self.Elements.EmojiGrid:SetData( {} )
			return
		end

		self.Elements.EmojiGrid:SetData( Results )
	end )

	SGUI:EnableMouse( true, self )
end

function EmojiPicker:GetState()
	return {
		SearchText = self.Elements.SearchInput:GetText(),
		ScrollOffset = self.Elements.EmojiGrid.Scrollbar:GetScroll()
	}
end

function EmojiPicker:RestoreFromState( State )
	self.Elements.SearchInput:SetText( State.SearchText )

	if self.Elements.EmojiGrid.Scrollbar:GetIsVisible() then
		self.Elements.EmojiGrid.Scrollbar:SetScroll( State.ScrollOffset )
	end
end

function EmojiPicker:Close()
	SGUI:EnableMouse( false, self )
	self:Destroy()
end

function EmojiPicker:SetSearchPlaceholderText( SearchPlaceholderText )
	self.Elements.SearchInput:SetPlaceholderText( SearchPlaceholderText )
end

function EmojiPicker:SetEmojiList( EmojiList )
	self.EmojiList = EmojiList
	self.Elements.EmojiGrid:SetData( EmojiList )
end

function EmojiPicker:OnMouseDown( Key, DoubleClick )
	local Handled, Child = Controls.Panel.OnMouseDown( self, Key, DoubleClick )
	if not Handled then
		-- Close if clicking outside the window.
		self:Close()
	end
	return Handled, Child
end

function EmojiPicker:PlayerKeyPress( Key, Down )
	if not self:GetIsVisible() then return end

	if self:CallOnChildren( "PlayerKeyPress", Key, Down ) then
		return true
	end

	if Key == InputKey.Escape then
		self:Close()
		return true
	end
end

return EmojiPicker
