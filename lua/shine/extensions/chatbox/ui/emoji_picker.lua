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

function EmojiRow:SetContents( EmojiList )
	local NumEmoji = #EmojiList
	for i = 1, NumEmoji do
		local EmojiDefinition = EmojiList[ i ]
		local Button = self:GetOrCreateButton( i )
		Button:SetAutoSize( Units.UnitVector( self.AutoSize[ 2 ], self.AutoSize[ 2 ] ) )
		EmojiUtil.ApplyEmojiToImage( Button.Image, EmojiDefinition )
		Button:SetTooltip( StringFormat( ":%s:", EmojiDefinition.Name ) )
		Button:SetIsVisible( true )
		Button.Emoji = EmojiDefinition.Name
	end

	for i = NumEmoji + 1, #self.Buttons do
		local Button = self.Buttons[ i ]
		if SGUI.IsValid( Button ) then
			Button:SetIsVisible( false )
		end
	end

	self:InvalidateLayout( true )
end

function EmojiPicker:Initialise()
	Controls.Column.Initialise( self )

	self.InheritsParentAlpha = true
	self:SetPropagateAlphaInheritance( true )

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

					for i = 1, #EmojiList, NumEmojiPerRow do
						local Row = {}
						for j = 1, NumEmojiPerRow do
							Row[ j ] = EmojiList[ i + j - 1 ]
						end
						RowCount = RowCount + 1
						Rows[ RowCount ] = Row
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

	function self.Elements.SearchInput.OnTextChanged( TextEntry, OldText, NewText )
		if #NewText == 0 then
			self.Elements.EmojiGrid:SetData( self.EmojiList )
			return
		end

		local Results = Hook.Call( "OnChatBoxEmojiAutoComplete", self, NewText )
		if not IsType( Results, "table" ) or #Results == 0 then
			self.Elements.EmojiGrid:SetData( {} )
			return
		end

		self.Elements.EmojiGrid:SetData( Results )
	end

	SGUI:EnableMouse( true, self )
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
