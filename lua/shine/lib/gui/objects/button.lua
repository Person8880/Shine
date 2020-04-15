--[[
	Button control.
]]

local Binder = require "shine/lib/gui/binding/binder"

local SGUI = Shine.GUI
local Units = SGUI.Layout.Units

local Max = math.max
local rawget = rawget

local Button = {}

local ClickSound = "sound/NS2.fev/common/button_enter"
Client.PrecacheLocalSound( ClickSound )
Button.Sound = ClickSound

SGUI.AddBoundProperty( Button, "Font", "Label:SetFont" )
SGUI.AddBoundProperty( Button, "TextAlignment", "Label:SetAlignment" )
SGUI.AddBoundProperty( Button, "TextAlignmentX", "Label:SetTextAlignmentX" )
SGUI.AddBoundProperty( Button, "TextAlignmentY", "Label:SetTextAlignmentY" )
SGUI.AddBoundProperty( Button, "TextColour", {
	"Label:SetColour",
	function( self, Colour )
		if self.Icon and not self.IconColour then
			self.Icon:SetColour( Colour )
		end
	end
} )
SGUI.AddBoundProperty( Button, "TextInheritsParentAlpha", { "Label:SetInheritsParentAlpha", "Icon:SetInheritsParentAlpha" } )
SGUI.AddBoundProperty( Button, "TextIsVisible", "Label:SetIsVisible" )
SGUI.AddBoundProperty( Button, "TextScale", "Label:SetTextScale" )
SGUI.AddBoundProperty( Button, "TextShadow", "Label:SetShadow" )

SGUI.AddBoundProperty( Button, "IconAlignment", "Icon:SetAlignment" )
SGUI.AddBoundProperty( Button, "IconColour", "Icon:SetColour" )
SGUI.AddBoundProperty( Button, "IconAutoFont", "Icon:SetAutoFont" )
SGUI.AddBoundProperty( Button, "IconIsVisible", "Icon:SetIsVisible" )
SGUI.AddBoundProperty( Button, "IconMargin", "Icon:SetMargin" )
SGUI.AddBoundProperty( Button, "IconShadow", "Icon:SetShadow" )

function Button:Initialise()
	self.BaseClass.Initialise( self )
	self.Background = self:MakeGUIItem()
	self:SetHighlightOnMouseOver( true )
	self:SetTextInheritsParentAlpha( true )

	self.Horizontal = true
	self.TextIsVisible = true
	self.IconIsVisible = true

	self:SetLayout( SGUI.Layout:CreateLayout( "Horizontal" ) )
end

function Button:SetCustomSound( Sound )
	self.Sound = Sound
end

local function UpdateIconMargin( self )
	if not self.Icon then return end

	if self.Label then
		self.Icon:SetMargin(
			self.IconMargin or ( self.Horizontal and Units.Spacing( 0, 0, Units.HighResScaled( 8 ), 0 ) or nil )
		)
	else
		self.Icon:SetMargin( nil )
	end
end

function Button:SetText( Text )
	if SGUI.IsValid( self.Label ) then
		if not Text then
			self.Label:Destroy()
			self.Label = nil
			self:InvalidateParent()
			self:OnPropertyChanged( "Text", nil )
			return
		end

		if self.Label:GetText() == Text then return end

		self.Label:SetText( Text )
		self:InvalidateParent()
		self:InvalidateLayout()
		self:OnPropertyChanged( "Text", Text )

		return
	end

	if not Text then return end

	local Description = SGUI:Create( "Label", self )
	Description:SetIsSchemed( false )
	Description:SetAlignment( self.TextAlignment or SGUI.LayoutAlignment.CENTRE )
	Description:SetCrossAxisAlignment( SGUI.LayoutAlignment.CENTRE )
	Description:SetText( Text )
	if self.TextColour then
		Description:SetColour( self.TextColour )
	end
	Description:SetInheritsParentAlpha( self.TextInheritsParentAlpha )
	Description:SetIsVisible( self.TextIsVisible )
	-- Need to offset the text based on its internal alignment.
	Description:SetUseAlignmentCompensation( true )

	if self.TextShadow then
		Description:SetShadow( self.TextShadow )
	end

	Binder():FromElement( self, "Horizontal" )
		:ToElement( Description, "AutoWrap", {
			Transformer = function( Horizontal )
				return not Horizontal
			end
		} )
		:ToElement( Description, "AutoSize", {
			Transformer = function( Horizontal )
				if Horizontal then
					return nil
				end
				return Units.UnitVector( Units.Percentage( 100 ), Units.Auto() )
			end
		} )
		:ToElement( Description, "TextAlignmentX", {
			Transformer = function( Horizontal )
				return Horizontal and GUIItem.Align_Min or GUIItem.Align_Center
			end
		} ):BindProperty()

	if self.Font then
		Description:SetFont( self.Font )
	end

	if self.TextScale then
		Description:SetTextScale( self.TextScale )
	end

	self.Layout:AddElement( Description )
	self.Label = Description
	self:InvalidateParent()

	UpdateIconMargin( self )

	self:OnPropertyChanged( "Text", Text )
end

function Button:GetText()
	if not self.Label then return "" end
	return self.Label:GetText()
end

function Button:SetIcon( IconName, Font, Scale )
	if not IconName then
		if SGUI.IsValid( self.Icon ) then
			self.Icon:Destroy()
			self.Icon = nil
		end

		self.IconName = nil
		self.IconFont = nil
		self.IconTextScale = nil

		return
	end

	if not Font and not Scale then
		Font, Scale = SGUI.FontManager.GetHighResFont( SGUI.FontFamilies.Ionicons, 32 )
	else
		Font = Font or SGUI.Fonts.Ionicons
		Scale = Scale or 1
	end

	self.IconName = IconName
	self.IconFont = Font
	self.IconTextScale = Scale

	if self.Icon then
		self.Icon:SetText( IconName )
		self.Icon:SetFontScale( Font, Scale )
		return
	end

	local Icon = SGUI:Create( "Label", self )
	Icon:SetIsSchemed( false )
	Icon:SetAlignment( self.IconAlignment or SGUI.LayoutAlignment.CENTRE )
	Icon:SetCrossAxisAlignment( SGUI.LayoutAlignment.CENTRE )
	Icon:SetFontScale( Font, Scale )
	if self.IconColour or self.TextColour then
		Icon:SetColour( self.IconColour or self.TextColour )
	end
	if self.IconAutoFont then
		Icon:SetAutoFont( self.IconAutoFont )
	end
	Icon:SetText( IconName )
	Icon:SetInheritsParentAlpha( self.TextInheritsParentAlpha )
	Icon:SetIsVisible( self.IconIsVisible )
	if self.IconShadow then
		Icon:SetShadow( self.IconShadow )
	end

	self.Layout:InsertElement( Icon, 1 )
	self.Icon = Icon

	UpdateIconMargin( self )
end

function Button:GetIcon()
	return self.IconName, self.IconFont, self.IconTextScale
end

function Button:SetHorizontal( Horizontal )
	Horizontal = not not Horizontal

	if Horizontal == self.Horizontal then return end

	self.Horizontal = Horizontal

	self:SetLayout( SGUI.Layout:CreateLayout( Horizontal and "Horizontal" or "Vertical" ), true )

	if self.Icon then
		self.Layout:AddElement( self.Icon )
		UpdateIconMargin( self )
	end

	if self.Label then
		self.Layout:AddElement( self.Label )
	end

	self:OnPropertyChanged( "Horizontal", Horizontal )
end

function Button:SetActiveCol( Col )
	self.ActiveCol = Col

	if self.Highlighted then
		self:StopFade( self.Background )
		self.Background:SetColor( Col )
	end
end

function Button:SetInactiveCol( Col )
	self.InactiveCol = Col

	if not self.Highlighted then
		self:StopFade( self.Background )
		self.Background:SetColor( Col )
	end
end

function Button:SetDoClick( Func )
	self.DoClick = Func
end

function Button:SetHighlightTexture( Texture )
	self.HighlightTexture = Texture
end

Button.MenuPos = {
	RIGHT = "RIGHT",
	BOTTOM = "BOTTOM"
}

function Button:AddMenu( Size, MenuPos )
	if SGUI.IsValid( self.Menu ) then
		return self.Menu
	end

	MenuPos = MenuPos or self.MenuPos.RIGHT

	local Pos = self:GetScreenPos()
	if MenuPos == self.MenuPos.RIGHT then
		Pos.x = Pos.x + self:GetSize().x
	elseif MenuPos == self.MenuPos.BOTTOM then
		Pos.y = Pos.y + self:GetSize().y
	elseif MenuPos then
		Pos = Pos + MenuPos
	end

	local Menu = SGUI:Create( "Menu" )
	-- As the Menu element is not a child of the button, the skin must be set manually.
	if self.PropagateSkin then
		Menu:SetSkin( self:GetSkin() )
	end

	Menu:SetPos( Pos )
	Menu:SetButtonSize( Size or self:GetSize() )

	self:SetForceHighlight( true )
	Menu:CallOnRemove( function()
		if self:IsValid() then
			self:SetForceHighlight( false )
			self:OnPropertyChanged( "Menu", nil )
		end
	end )

	self.Menu = Menu
	self:OnPropertyChanged( "Menu", Menu )

	return Menu
end

-- Provides a helper that automatically handles menu opening on click, as well as closing the menu
-- when clicked while the menu is open without re-opening it.
function Button:SetOpenMenuOnClick( PopulateMenuFunc )
	self:SetDoClick( function( self )
		if self.Menu and rawget( self.Menu, "DestroyedBy" ) == self then
			-- Clicked the button to close the menu.
			self.Menu = nil
			self:OnPropertyChanged( "Menu", nil )
			return
		end

		local MenuParams = PopulateMenuFunc( self )
		local Menu = self:AddMenu( MenuParams.Size, MenuParams.MenuPos )
		MenuParams.Populate( Menu )
	end )
end

function Button:OnMouseDown( Key, DoubleClick )
	if not self:GetIsVisible() then return end

	local Result, Child = self:CallOnChildren( "OnMouseDown", Key, DoubleClick )
	if Result then
		return true, Child
	end

	if not self:IsEnabled() then return end

	return self.Mixins.Clickable.OnMouseDown( self, Key, DoubleClick )
end

SGUI:AddMixin( Button, "AutoSizeText" )

-- Override GetContentSizeForAxis to account for both an icon and a label.
do
	local LabelSizeMethod = {
		"GetCachedTextWidth",
		"GetCachedTextHeight"
	}
	local MarginSizeMethod = {
		"GetWidth",
		"GetHeight"
	}

	local function GetTotalSize( self, Axis )
		local Size = 0

		if self.Label then
			Size = Size + self.Label[ LabelSizeMethod[ Axis ] ]( self.Label )
		end

		if self.Icon then
			Size = Size + self.Icon[ LabelSizeMethod[ Axis ] ]( self.Icon )
				+ Units.Spacing[ MarginSizeMethod[ Axis ] ]( self.Icon:GetComputedMargin() )
		end

		if self.Padding then
			Size = Size + Units.Spacing[ MarginSizeMethod[ Axis ] ]( self:GetComputedPadding() )
		end

		return Size
	end

	local function GetSize( Label, Axis )
		if not Label then return 0 end

		return Label[ LabelSizeMethod[ Axis ] ]( Label )
	end

	local function GetMaxSize( self, Axis )
		return Max( 0, GetSize( self.Label, Axis ), GetSize( self.Icon, Axis ) )
	end

	local ContentSizeHandlers = {
		[ true ] = {
			-- When horizontal, the width is the total but the height is just the max of the icon and label heights.
			GetTotalSize,
			GetMaxSize
		},
		[ false ] = {
			-- When vertical, the width is the max of the icon and label widths, and the height is the total.
			GetMaxSize,
			GetTotalSize
		}
	}

	function Button:GetContentSizeForAxis( Axis )
		return ContentSizeHandlers[ self.Horizontal ][ Axis ]( self, Axis )
	end
end

function Button:Cleanup()
	if SGUI.IsValid( self.Menu ) then
		self.Menu:Destroy()
	end
	return self.BaseClass.Cleanup( self )
end

SGUI:AddMixin( Button, "Clickable" )
SGUI:AddMixin( Button, "EnableMixin" )
SGUI:Register( "Button", Button )
