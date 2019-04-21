--[[
	Button control.
]]

local SGUI = Shine.GUI
local Units = SGUI.Layout.Units

local Max = math.max
local rawget = rawget

local Button = {}

local ClickSound = "sound/NS2.fev/common/button_enter"
Client.PrecacheLocalSound( ClickSound )
Button.Sound = ClickSound

SGUI.AddBoundProperty( Button, "Font", "Label:SetFont" )
SGUI.AddBoundProperty( Button, "TextColour", "Label:SetColour" )
SGUI.AddBoundProperty( Button, "TextInheritsParentAlpha", { "Label:SetInheritsParentAlpha", "Icon:SetInheritsParentAlpha" } )
SGUI.AddBoundProperty( Button, "TextIsVisible", "Label:SetIsVisible" )
SGUI.AddBoundProperty( Button, "TextScale", "Label:SetTextScale" )

SGUI.AddBoundProperty( Button, "IconIsVisible", "Icon:SetIsVisible" )
SGUI.AddBoundProperty( Button, "IconMargin", "Icon:SetMargin" )

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
	self:InvalidateParent()

	if self.Label then
		self.Label:SetText( Text )
		self:InvalidateLayout()
		return
	end

	local Description = SGUI:Create( "Label", self )
	Description:SetAlignment( SGUI.LayoutAlignment.CENTRE )
	Description:SetCrossAxisAlignment( SGUI.LayoutAlignment.CENTRE )
	Description:SetText( Text )
	Description:SetColour( self.TextColour )
	Description:SetInheritsParentAlpha( self.TextInheritsParentAlpha )
	Description:SetIsVisible( self.TextIsVisible )

	if self.Font then
		Description:SetFont( self.Font )
	end

	if self.TextScale then
		Description:SetTextScale( self.TextScale )
	end

	self.Layout:AddElement( Description )
	self.Label = Description

	UpdateIconMargin( self )
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
	Icon:SetAlignment( SGUI.LayoutAlignment.CENTRE )
	Icon:SetCrossAxisAlignment( SGUI.LayoutAlignment.CENTRE )
	Icon:SetFontScale( Font, Scale )
	Icon:SetColour( self:GetTextColour() )
	Icon:SetText( IconName )
	Icon:SetInheritsParentAlpha( self.TextInheritsParentAlpha )
	Icon:SetIsVisible( self.IconIsVisible )

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
end

function Button:SetActiveCol( Col )
	self.ActiveCol = Col

	if self.Highlighted then
		self.Background:SetColor( Col )
	end
end

function Button:SetInactiveCol( Col )
	self.InactiveCol = Col

	if not self.Highlighted then
		self.Background:SetColor( Col )
	end
end

function Button:Think( DeltaTime )
	if not self.Background then return end
	if not self.Background:GetIsVisible() then return end

	self.BaseClass.Think( self, DeltaTime )

	if SGUI.IsValid( self.Tooltip ) then
		self.Tooltip:Think( DeltaTime )
	end

	self:CallOnChildren( "Think", DeltaTime )
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
	else
		Pos.y = Pos.y + self:GetSize().y
	end

	local Menu = SGUI:Create( "Menu" )
	Menu:SetPos( Pos )
	Menu:SetButtonSize( Size or self:GetSize() )

	self:SetForceHighlight( true )
	Menu:CallOnRemove( function()
		self:SetForceHighlight( false )
	end )

	self.Menu = Menu

	return Menu
end

-- Provides a helper that automatically handles menu opening on click, as well as closing the menu
-- when clicked while the menu is open without re-opening it.
function Button:SetOpenMenuOnClick( PopulateMenuFunc )
	self:SetDoClick( function( self )
		if self.Menu and rawget( self.Menu, "DestroyedBy" ) == self then
			-- Clicked the button to close the menu.
			self.Menu = nil
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

SGUI:AddMixin( Button, "Clickable" )
SGUI:AddMixin( Button, "EnableMixin" )
SGUI:Register( "Button", Button )
