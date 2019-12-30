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
SGUI.AddProperty( Menu, "MaxVisibleButtons" )
SGUI.AddProperty( Menu, "Font" )
SGUI.AddProperty( Menu, "TextScale" )

function Menu:Initialise()
	Controls.Panel.Initialise( self )

	self.ButtonSize = DefaultSize
	self.Buttons = {}
	self.ButtonCount = 0
	self.ButtonSpacing = Units.Absolute( 0 )

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
end

function Menu:SetButtonSize( Vec )
	self.ButtonSize = Vec
	self.UseAutoSize = Shine.Implements( Vec, Units.UnitVector )
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
		Button:SetAutoSize( self.ButtonSize )
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

function Menu:SetFont( Font )
	self.Font = Font
	self:ForEach( "Buttons", "SetFont", Font )
end

function Menu:SetTextScale( TextScale )
	self.TextScale = TextScale
	self:ForEach( "Buttons", "TextScale", TextScale )
end

function Menu:AddPanel( Panel )
	Panel:SetParent( self )
	Panel:SetStyleName( "MenuPanel" )
	Panel:SetAnchor( GUIItem.Left, GUIItem.Top )

	if self.UseAutoSize then
		Panel:SetAutoSize( self.ButtonSize )
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
