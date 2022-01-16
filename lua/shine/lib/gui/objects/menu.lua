--[[
	Shine popup menu.

	Think right clicking the desktop in Windows, that kind of menu.
]]

local IsType = Shine.IsType
local SGUI = Shine.GUI
local Controls = SGUI.Controls
local Units = SGUI.Layout.Units

local Max = math.max
local Min = math.min

local Menu = {}

Menu.IsWindow = true

local DefaultSize = Vector( 200, 32, 0 )

SGUI.AddProperty( Menu, "ButtonSpacing" )
SGUI.AddProperty( Menu, "ButtonWidthPadding" )
SGUI.AddProperty( Menu, "MaxVisibleButtons" )
SGUI.AddProperty( Menu, "Font" )
SGUI.AddProperty( Menu, "TextScale" )

function Menu:Initialise()
	Controls.Panel.Initialise( self )

	self.ButtonSize = DefaultSize
	self.Buttons = {}
	self.ButtonCount = 0
	self.ButtonSpacing = Units.Absolute( 0 )
	self.ButtonWidthPadding = Units.Absolute( 0 )

	self.Font = Fonts.kAgencyFB_Small
	self:SetLayout( SGUI.Layout:CreateLayout( "Vertical" ) )
end

function Menu:SetMaxVisibleButtons( Max, ScrollbarWidth )
	local Width = ScrollbarWidth or Units.HighResScaled( 8 ):GetValue()

	self.MaxVisibleButtons = Max
	self:SetScrollable()
	self:SetScrollbarPos( Vector( -Width, 0, 0 ) )
	self:SetScrollbarWidth( Width )
	self:SetScrollbarHeightOffset( 0 )
	self.BufferAmount = 0
	self:SetHorizontalScrollingEnabled( false )
end

function Menu:SetButtonSize( Vec )
	self.ButtonSize = Vec
	self.UseAutoSize = not IsType( Vec, "cdata" )

	if self.UseAutoSize then
		local IsUnitVector = Shine.Implements( Vec, Units.UnitVector )
		local InitialWidth = IsUnitVector and Vec[ 1 ] or nil

		self.ButtonHeight = IsUnitVector and Vec[ 2 ] or Vec
		self.ButtonWidth = Units.Max( InitialWidth )
	else
		self.ButtonHeight = nil
		self.ButtonWidth = nil
	end
end

function Menu:SetButtonSpacing( ButtonSpacing )
	if IsType( Vec, "cdata" ) then
		self.ButtonSpacing = SGUI.Layout.ToUnit( ButtonSpacing.y )
	else
		self.ButtonSpacing = ButtonSpacing
	end

	self.Layout:SetPadding( Units.Spacing( 0, 0, 0, self.ButtonSpacing ) )
	for i = 1, self.ButtonCount do
		self.Buttons[ i ]:SetMargin( Units.Spacing( 0, self.ButtonSpacing, 0, 0 ) )
	end
end

function Menu:AddButton( Text, DoClick, Tooltip )
	local Button = self.MaxVisibleButtons and self:Add( "Button" ) or SGUI:Create( "Button", self )
	Button:SetDoClick( DoClick )

	if self.UseAutoSize then
		self.ButtonWidth:AddValue( Units.Auto( Button ) + self.ButtonWidthPadding )
		Button:SetAutoSize( Units.UnitVector( self.ButtonWidth, self.ButtonHeight ) )
	else
		Button:SetSize( self.ButtonSize )
	end
	Button:SetMargin( Units.Spacing( 0, self.ButtonSpacing, 0, 0 ) )

	Button:SetText( Text )
	if self.Font then
		Button:SetFont( self.Font )
	end
	if self.TextScale then
		Button:SetTextScale( self.TextScale )
	end
	Button:SetStyleName( "MenuButton" )
	if Tooltip then
		Button:SetTooltip( Tooltip )
	end

	self.ButtonCount = self.ButtonCount + 1
	self.Buttons[ self.ButtonCount ] = Button

	self.Layout:AddElement( Button )
	self:Resize()

	return Button
end

--[[
	Ensures all icons use up the same amount of horizontal space.
	This is useful when aligning button text/icons to the left as it aligns the text vertically across all buttons.
]]
function Menu:AutoSizeButtonIcons()
	local Size = Units.Max()
	for i = 1, self.ButtonCount do
		local Button = self.Buttons[ i ]
		if Button.Icon then
			Size:AddValue( Units.Auto( Button.Icon ) )
			Button:SetIconMargin( Units.Spacing( 0, 0, Size - Units.Auto.INSTANCE + Units.HighResScaled( 8 ), 0 ) )
		end
	end
end

function Menu:SetFont( Font )
	self.Font = Font
	self:ForEach( "Buttons", "SetFont", Font )
end

function Menu:SetTextScale( TextScale )
	self.TextScale = TextScale
	self:ForEach( "Buttons", "SetTextScale", TextScale )
end

function Menu:AddPanel( Panel )
	Panel:SetParent( self )
	Panel:SetStyleName( "MenuPanel" )
	Panel:SetAnchor( GUIItem.Left, GUIItem.Top )

	if self.UseAutoSize then
		self.ButtonWidth:AddValue( Units.Auto( Panel ) + self.ButtonWidthPadding )
		Panel:SetAutoSize( Units.UnitVector( self.ButtonWidth, self.ButtonHeight ) )
	else
		Panel:SetSize( self.ButtonSize )
	end

	Panel:SetMargin( Units.Spacing( 0, self.ButtonSpacing, 0, 0 ) )

	self.ButtonCount = self.ButtonCount + 1
	self.Buttons[ self.ButtonCount ] = Panel

	self.Layout:AddElement( Panel )
	self:Resize()

	return Panel
end

function Menu:Resize()
	local MenuWidth = 0
	local MenuHeight = 0

	self.Layout:InvalidateLayout( true )

	local LayoutPadding = self.Layout:GetComputedPadding()
	local MaxHeightIndex = self.MaxVisibleButtons or self.ButtonCount
	if self.UseAutoSize then
		local MaxWidth = 0

		for i = 1, self.ButtonCount do
			local Button = self.Buttons[ i ]
			local Size = Button:GetSize()
			MaxWidth = Max( Size.x, MaxWidth )

			if i <= MaxHeightIndex then
				MenuHeight = Button:GetPos().y + Size.y + LayoutPadding[ 4 ]
			end
		end

		MenuWidth = MaxWidth
	else
		local NumButtons = Min( MaxHeightIndex, self.ButtonCount )
		MenuWidth = self.ButtonSize.x
		MenuHeight = self.ButtonSize.y * NumButtons + LayoutPadding[ 4 ] * ( NumButtons + 1 )
	end

	if self.MaxVisibleButtons and self.OverflowY then
		-- Account for the scrollbar to ensure text isn't cut off.
		MenuWidth = MenuWidth + self.ScrollbarWidth
	end

	self:SetSize( Vector2( MenuWidth, MenuHeight ) )
end

------------------- Event calling -------------------
function Menu:OnMouseDown( Key, DoubleClick )
	if not self:GetIsVisible() then return end

	if SGUI.IsValid( self.Scrollbar ) then
		if self.Scrollbar:OnMouseDown( Key, DoubleClick ) then
			return true, self.Scrollbar
		end
	end

	local Result, Child = self:CallOnChildren( "OnMouseDown", Key, DoubleClick )
	if Result ~= nil then return true, Child end

	-- Delay so we don't mess up the event calling.
	SGUI:AddPostEventAction( function( Result, Control )
		if not self:IsValid() then return end

		self.DestroyedBy = Control
		self:Destroy()
	end )
end

SGUI:Register( "Menu", Menu, "Panel" )
