--[[
	Provides auto-completion of emoji.
]]

local EmojiUtil = require "shine/extensions/chatbox/ui/emoji_util"

local assert = assert
local StringFormat = string.format

local SGUI = Shine.GUI
local Controls = SGUI.Controls
local Units = SGUI.Layout.Units

local EmojiAutoComplete = SGUI:DefineControl( "EmojiAutoComplete", "Row" )
local EmojiAutoCompleteEntry = SGUI:DefineControl( "EmojiAutoCompleteEntry", "Button" )

function EmojiAutoCompleteEntry:SetEmoji( EmojiDefinition )
	local EmojiName = assert( EmojiDefinition.Name, "No name provided for emoji!" )
	if EmojiName == self.EmojiName then return end

	self:SetText( StringFormat( ":%s:", EmojiName ) )

	local Image = self.Image
	if not Image then
		Image = SGUI:Create( "Image", self )
		Image:SetAlignment( SGUI.LayoutAlignment.CENTRE )
		Image:SetCrossAxisAlignment( SGUI.LayoutAlignment.CENTRE )
		Image:SetMargin( Units.Spacing( 0, 0, Units.Integer( Units.GUIScaled( 4 ) ), 0 ) )
		Image:SetAutoSize( Units.UnitVector( self.AutoFont.Size, self.AutoFont.Size ) )
		self.Image = Image
		self.Layout:InsertElement( Image, 1 )
	end

	EmojiUtil.ApplyEmojiToImage( Image, EmojiDefinition )

	self.EmojiName = EmojiName
end

function EmojiAutoCompleteEntry:DoClick()
	self.Parent:SetSelectedEmojiName( self.EmojiName )
end

SGUI.AddProperty( EmojiAutoComplete, "SelectedEmojiName" )

function EmojiAutoComplete:Initialise()
	Controls.Row.Initialise( self )

	self.Emoji = {}
	self.SelectedIndex = 1
	self.NumEmoji = 0

	self:SetHideHorizontalScrollbar( true )
	self:SetScrollable()
end

function EmojiAutoComplete:ResolveSelectedEmojiName()
	if self.SelectedEmojiName then
		return self.SelectedEmojiName
	end

	local Emoji = self.Emoji[ self.SelectedIndex ]
	if SGUI.IsValid( Emoji ) then
		return Emoji.EmojiName
	end

	return nil
end

function EmojiAutoComplete:SetSelectedIndex( SelectedIndex )
	if self.SelectedIndex == SelectedIndex then return end

	self.SelectedIndex = SelectedIndex

	for i = 1, #self.Emoji do
		self.Emoji[ i ]:SetForceHighlight( i == SelectedIndex )
		if i == SelectedIndex then
			self:ScrollIntoView( self.Emoji[ i ] )
		end
	end
end

function EmojiAutoComplete:MoveSelection( Offset )
	local SelectedIndex = self.SelectedIndex + Offset

	if SelectedIndex < 1 then
		SelectedIndex = self.NumEmoji + SelectedIndex
	elseif SelectedIndex > self.NumEmoji then
		SelectedIndex = SelectedIndex - self.NumEmoji
	end

	self:SetSelectedIndex( SelectedIndex )
end

function EmojiAutoComplete:SetEmoji( EmojiEntries )
	for i = 1, #EmojiEntries do
		local EmojiEntry = EmojiEntries[ i ]
		local Emoji = self.Emoji[ i ]
		if not Emoji then
			Emoji = self:Add( EmojiAutoCompleteEntry )
			Emoji:SetCrossAxisAlignment( SGUI.LayoutAlignment.CENTRE )
			Emoji:SetAutoSize( Units.UnitVector(
				Units.Integer( Units.Auto() + Units.GUIScaled( 8 ) ),
				Units.Integer( Units.Percentage( 100 ) - Units.GUIScaled( 8 ) ) )
			)
			self.Emoji[ i ] = Emoji
			self.Layout:AddElement( Emoji )
		end
		Emoji:SetIsVisible( true )
		Emoji:SetEmoji( EmojiEntry )
		Emoji:SetForceHighlight( i == self.SelectedIndex )
	end

	for i = #EmojiEntries + 1, #self.Emoji do
		if SGUI.IsValid( self.Emoji[ i ] ) then
			self.Emoji[ i ]:SetIsVisible( false )
		end
	end

	self.NumEmoji = #EmojiEntries
	self:InvalidateLayout()
end

return EmojiAutoComplete
