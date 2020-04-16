--[[
	Base SGUI control. All controls inherit from this.
]]

local CodeGen = require "shine/lib/codegen"

local SGUI = Shine.GUI
local ControlMeta = SGUI.BaseControl
local Set = Shine.Set

local assert = assert
local Clock = Shared.GetSystemTimeReal
local IsType = Shine.IsType
local IsGUIItemValid = debug.isvalid
local Max = math.max
local pairs = pairs
local select = select
local StringFormat = string.format
local TableNew = require "table.new"
local TableRemoveByValue = table.RemoveByValue
local Vector2 = Vector2

local Map = Shine.Map
local Multimap = Shine.Multimap
local Source = require "shine/lib/gui/binding/source"

local SetterKeys = SGUI.SetterKeys

SGUI.AddBoundProperty( ControlMeta, "BlendTechnique", "Background" )
SGUI.AddBoundProperty( ControlMeta, "InheritsParentAlpha", "Background" )
SGUI.AddBoundProperty( ControlMeta, "InheritsParentScaling", "Background" )
SGUI.AddBoundProperty( ControlMeta, "Scale", "Background" )
SGUI.AddBoundProperty( ControlMeta, "Shader", "Background" )
SGUI.AddBoundProperty( ControlMeta, "Texture", "Background" )

SGUI.AddProperty( ControlMeta, "PropagateSkin", true )
SGUI.AddProperty( ControlMeta, "Skin" )
SGUI.AddProperty( ControlMeta, "StyleName" )

function ControlMeta:__tostring()
	return StringFormat( "[SGUI - %s] %s | %s | %i Children", self.ID, self.Class,
		self:IsValid() and "ACTIVE" or "DESTROYED",
		self.Children and self.Children:GetCount() or 0 )
end

--[[
	Base initialise. Be sure to override this!
]]
function ControlMeta:Initialise()
	self.UseScheme = true
	self.PropagateSkin = true
	self.Stencilled = false

	self.MouseHasEntered = false
	self.MouseStateIsInvalid = false
end

--[[
	Generic cleanup, for most controls this is adequate.

	The only time you need to override it is if you have more than a background object.
]]
function ControlMeta:Cleanup()
	if self.Parent then return end

	if self.GUIItems then
		local FoundBackground = false
		local TopLevelElements = {}
		for Item in self.GUIItems:Iterate() do
			if Item == self.Background then
				FoundBackground = true
			end

			-- Destroy all GUIItems that are not parented to another element
			-- in this element's GUIItem children.
			if IsGUIItemValid( Item ) and not self.GUIItems:Get( Item:GetParent() ) then
				TopLevelElements[ #TopLevelElements + 1 ] = Item
			end
		end

		for i = 1, #TopLevelElements do
			GUI.DestroyItem( TopLevelElements[ i ] )
		end

		-- If the background element was removed above, then stop.
		if FoundBackground then return end
	end

	-- This retains backwards compatibility, in case anyone made custom SGUI controls
	-- before Control:MakeGUIItem() existed.
	if self.Background then
		GUI.DestroyItem( self.Background )
	end
end

--[[
	Destroys a control.
]]
function ControlMeta:Destroy()
	return SGUI:Destroy( self )
end

--[[
	Sets a control to be destroyed when this one is.
]]
function ControlMeta:DeleteOnRemove( Control )
	self.__DeleteOnRemove = self.__DeleteOnRemove or {}

	local Table = self.__DeleteOnRemove

	Table[ #Table + 1 ] = Control
end

--[[
	Adds a function to be called when this control is destroyed.

	It will be passed this control when called as its argument.
]]
function ControlMeta:CallOnRemove( Func )
	self.__CallOnRemove = self.__CallOnRemove or {}

	local Table = self.__CallOnRemove

	Table[ #Table + 1 ] = Func
end

function ControlMeta:OnPropertyChanged( Name, Value )
	-- By default, do nothing until a listener is added.
end

local function BroadcastPropertyChange( self, Name, Value )
	local Listeners = self.PropertyChangeListeners:Get( Name )
	if not Listeners then return end

	for i = 1, #Listeners do
		Listeners[ i ]( self, Value )
	end
end

function ControlMeta:AddPropertyChangeListener( Name, Listener )
	-- Now listening for changes, so need to broadcast them.
	self.OnPropertyChanged = BroadcastPropertyChange

	self.PropertyChangeListeners = self.PropertyChangeListeners or Shine.Multimap()
	self.PropertyChangeListeners:Add( Name, Listener )

	return Listener
end

function ControlMeta:GetPropertySource( Name )
	self.PropertySources = self.PropertySources or {}

	local SourceInstance = self.PropertySources[ Name ]
	if SourceInstance then
		return SourceInstance
	end

	local Getter = self[ "Get"..Name ]
	local Value = Getter and Getter( self ) or self[ Name ]

	SourceInstance = Source( Value )
	SourceInstance.Element = self

	self.PropertySources[ Name ] = SourceInstance
	self:AddPropertyChangeListener( Name, SourceInstance )

	return SourceInstance
end

function ControlMeta:GetPropertyTarget( Name )
	self.PropertyTargets = self.PropertyTargets or {}

	local Target = self.PropertyTargets[ Name ]
	if Target then
		return Target
	end

	local SetterName = SetterKeys[ Name ]
	Target = function( ... )
		return self[ SetterName ]( self, ... )
	end

	self.PropertyTargets[ Name ] = Target

	return Target
end

function ControlMeta:RemovePropertyChangeListener( Name, Listener )
	local Listeners = self.PropertyChangeListeners
	if not Listeners then return end

	Listeners:Remove( Name, Listener )

	if Listeners:GetCount() == 0 then
		-- No more listeners, stop adding overhead.
		self.PropertyChangeListeners = nil
		self.OnPropertyChanged = ControlMeta.OnPropertyChanged
	end
end

-- Deprecated single state setter. Use AddStylingState(s)/RemoveStylingState(s) to allow for multiple states.
function ControlMeta:SetStylingState( Name )
	if Name then
		self:GetStylingStates():Clear():Add( Name )
	else
		self.StylingStates = nil
		self.GetStylingStates = ControlMeta.GetStylingStates
	end

	self:RefreshStyling()
end

function ControlMeta:AddStylingState( Name )
	local States = self:GetStylingStates()
	if not States:Contains( Name ) then
		States:Add( Name )
		self:RefreshStyling()
	end
end

function ControlMeta:AddStylingStates( Names )
	local States = self:GetStylingStates()
	local PreviousCount = States:GetCount()

	States:AddAll( Names )

	if States:GetCount() > PreviousCount then
		self:RefreshStyling()
	end
end

function ControlMeta:RemoveStylingState( Name )
	local States = self.StylingStates
	if States and States:Contains( Name ) then
		States:Remove( Name )
		self:RefreshStyling()
	end
end

function ControlMeta:RemoveStylingStates( Names )
	local States = self.StylingStates
	if not States then return end

	local PreviousCount = States:GetCount()

	States:RemoveAll( Names )

	if States:GetCount() < PreviousCount then
		self:RefreshStyling()
	end
end

-- Deprecated single-style state accessor. Controls may have more than one active state.
function ControlMeta:GetStylingState()
	return self.StylingStates and self.StylingStates:AsList()[ 1 ]
end

do
	local function GetStylingStatesUnsafe( self )
		return self.StylingStates
	end

	function ControlMeta:GetStylingStates()
		if not self.StylingStates then
			self.StylingStates = Set()
			self.GetStylingStates = GetStylingStatesUnsafe
		end

		return self.StylingStates
	end
end

function ControlMeta:SetStyleName( Name )
	if self.StyleName == Name then return end

	self.StyleName = Name
	self:RefreshStyling()
end

function ControlMeta:RefreshStyling()
	SGUI.SkinManager:ApplySkin( self )
end

function ControlMeta:SetSkin( Skin )
	local OldSkin = self.Skin
	if OldSkin == Skin then return end

	if Skin then
		-- Trigger skin compilation upfront to make later state changes faster.
		SGUI.SkinManager:GetCompiledSkin( Skin )
	end

	self.Skin = Skin
	self:RefreshStyling()

	self:OnPropertyChanged( "Skin", Skin )

	if self.PropagateSkin and self.Children then
		for Child in self:IterateChildren() do
			Child:SetSkin( Skin )
		end
	end
end

function ControlMeta:GetStyleValue( Key )
	local Style = SGUI.SkinManager:GetStyleForElement( self )
	if not Style then
		return nil
	end
	return Style.PropertiesByName[ Key ]
end

--[[
	Sets up a control's properties using a table.
]]
function ControlMeta:SetupFromTable( Table )
	for Property, Value in pairs( Table ) do
		local Method = self[ SetterKeys[ Property ] ]
		if Method then
			Method( self, Value )
		end
	end
end

--[[
	Sets up a control's properties using a map.
]]
function ControlMeta:SetupFromMap( Map )
	for Property, Value in Map:Iterate() do
		local Method = self[ SetterKeys[ Property ] ]
		if Method then
			Method( self, Value )
		end
	end
end

do
	local TableShallowMerge = table.ShallowMerge

	--[[
		Use to more easily setup multiple callback methods.
	]]
	function ControlMeta:AddMethods( Methods )
		TableShallowMerge( Methods, self, true )
	end
end

--[[
	Sets a control's parent manually.
]]
function ControlMeta:SetParent( Control, Element )
	assert( Control ~= self, "[SGUI] Cannot parent an object to itself!" )

	if Control and not Element then
		Element = Control.Background
	end

	local ParentControlChanged = self.Parent ~= Control
	local ParentElementChanged = self.ParentElement ~= Element

	if not ParentControlChanged and not ParentElementChanged then
		return
	end

	if ParentControlChanged and self.Parent then
		self.Parent.Children:Remove( self )
		self.Parent.ChildrenByPositionType:RemoveKeyValue( self:GetPositionType(), self )
	end

	if ParentElementChanged and self.ParentElement and IsGUIItemValid( self.ParentElement ) and self.Background then
		self.ParentElement:RemoveChild( self.Background )
	end

	self:InvalidateMouseState()

	if not Control then
		self.Parent = nil
		self.ParentElement = nil
		self.TopLevelWindow = nil
		self:SetStencilled( false )
		return
	end

	-- Parent to a specific part of a control.
	self.Parent = Control
	self.ParentElement = Element
	self:SetTopLevelWindow( SGUI:IsWindow( Control ) and Control or Control.TopLevelWindow )
	self:SetStencilled( Control.Stencilled )
	if Control.Stencilled then
		self:SetInheritsParentStencilSettings( true )
	end
	if Control.PropagateSkin then
		self:SetSkin( Control.Skin )
	end

	-- If the control was a window, now it's not.
	self.IsAWindow = false
	SGUI:RemoveWindow( self )

	Control.Children = Control.Children or Map()
	Control.Children:Add( self, true )

	Control.ChildrenByPositionType = Control.ChildrenByPositionType or Multimap()
	Control.ChildrenByPositionType:Add( self:GetPositionType(), self )

	if ParentElementChanged and Element and self.Background then
		Element:AddChild( self.Background )
	end
end

function ControlMeta:SetTopLevelWindow( Window )
	self.TopLevelWindow = Window

	if Window and self.Children then
		for Child in self.Children:Iterate() do
			Child:SetTopLevelWindow( Window )
		end
	end
end

do
	local Callers = CodeGen.MakeFunctionGenerator( {
		Template = [[return function( self, Name{Arguments} )
				if not self.Children then return nil end

				-- Call the event on every child of this object in the order they were added.
				for Child in self.Children:Iterate() do
					if Child[ Name ] and not Child._CallEventsManually then
						local Result, Control = Child[ Name ]( Child{Arguments} )

						if Result ~= nil then
							return Result, Control
						end
					end
				end

				return nil
			end
		]],
		ChunkName = "@lua/shine/lib/gui/base_control.lua/ControlMeta:CallOnChildren",
		InitialSize = 2
	} )

	--[[
		Calls an SGUI event on every child of the object.

		Ignores children with the _CallEventsManually flag.
	]]
	function ControlMeta:CallOnChildren( Name, ... )
		return Callers[ select( "#", ... ) ]( self, Name, ... )
	end
end

function ControlMeta:ForEach( TableKey, MethodName, ... )
	local Objects = self[ TableKey ]
	if not Objects then return end

	for i = 1, #Objects do
		local Object = Objects[ i ]
		local Method = Object[ MethodName ]
		if Method then
			Method( Object, ... )
		end
	end
end

function ControlMeta:ForEachFiltered( TableKey, MethodName, Filter, ... )
	local Objects = self[ TableKey ]
	if not Objects then return end

	for i = 1, #Objects do
		local Object = Objects[ i ]
		local Method = Object[ MethodName ]
		if Method and Filter( self, Object, i ) then
			Method( Object, ... )
		end
	end
end

--[[
	Add a GUIItem as a child.
]]
function ControlMeta:AddChild( GUIItem )
	if not self.Background then return end

	self.Background:AddChild( GUIItem )
end

local GUIItemTypes = {
	[ SGUI.GUIItemType.Text ] = SGUI.CreateTextGUIItem,
	[ SGUI.GUIItemType.Graphic ] = SGUI.CreateGUIItem
}

function ControlMeta:MakeGUIItem( Type )
	local Factory = GUIItemTypes[ Type or SGUI.GUIItemType.Graphic ]
	if not Factory then
		error( "Unknown GUIItem type: "..Type, 2 )
	end

	local Item = Factory()
	Item:SetOptionFlag( GUIItem.CorrectScaling )
	Item:SetOptionFlag( GUIItem.CorrectRotationOffset )
	if self.Stencilled then
		-- This element is currently under the effect of a stencil, so inherit
		-- settings.
		Item:SetInheritsParentStencilSettings( true )
	end

	self.GUIItems = self.GUIItems or Shine.Map()
	self.GUIItems:Add( Item, true )

	return Item
end

function ControlMeta:MakeGUITextItem()
	return self:MakeGUIItem( SGUI.GUIItemType.Text )
end

function ControlMeta:MakeGUICroppingItem()
	local CroppingBox = self:MakeGUIItem()
	CroppingBox:SetMinCrop( 0, 0 )
	CroppingBox:SetMaxCrop( 1, 1 )
	return CroppingBox
end

function ControlMeta:DestroyGUIItem( Item )
	GUI.DestroyItem( Item )

	if self.GUIItems then
		self.GUIItems:Remove( Item )
	end
end

function ControlMeta:SetLayer( Layer )
	if not self.Background then return end

	self.Background:SetLayer( Layer )
end

local function IsDescendantOf( Child, Ancestor )
	local Parent = Child:GetParent()
	while Parent and Parent ~= Ancestor do
		Parent = Parent:GetParent()
	end
	return Parent == Ancestor
end

function ControlMeta:SetCropToBounds( CropToBounds )
	if CropToBounds then
		self.Background:SetMinCrop( 0, 0 )
		self.Background:SetMaxCrop( 1, 1 )
	else
		self.Background:ClearCropRectangle()
	end
end

--[[
	This is called when the element is added as a direct child of another element that
	has a stencil component.

	Direct children need to have a GUIItem.NotEqual stencil function set. Their descendants
	can then inherit this.
]]
function ControlMeta:SetupStencil()
	local Background = self.Background
	Background:SetInheritsParentStencilSettings( false )
	Background:SetStencilFunc( GUIItem.NotEqual )

	if self.GUIItems then
		for Child in self.GUIItems:Iterate() do
			if not IsDescendantOf( Child, Background ) then
				Child:SetInheritsParentStencilSettings( false )
				Child:SetStencilFunc( GUIItem.NotEqual )
			else
				Child:SetInheritsParentStencilSettings( true )
			end
		end
	end

	self:SetStencilled( true )
end

function ControlMeta:SetStencilled( Stencilled )
	if Stencilled == self.Stencilled then return end

	self.Stencilled = Stencilled
	self:OnStencilChanged( Stencilled )
	-- Notify all children of the new stencil state.
	self:PropagateStencilSettings( Stencilled )
end

function ControlMeta:OnStencilChanged( Stencilled )
	if not self.Stencil then return end

	if Stencilled and not ( self.Parent and self.Parent.IgnoreStencilWarnings ) then
		-- Stencils inside stencils currently don't work correctly. They obey only the top-level
		-- stencil, any further restrictions are ignored (and appear to render as if GetIsStencil() == false).
		Print(
			"[SGUI] [Warn] [ %s ] has been placed under another stencil, this will not render correctly!",
			self
		)
	end
end

function ControlMeta:SetInheritsParentStencilSettings( InheritsParentStencil )
	if self.Background then
		self.Background:SetInheritsParentStencilSettings( InheritsParentStencil )
	end

	if self.GUIItems then
		for Item in self.GUIItems:Iterate() do
			Item:SetInheritsParentStencilSettings( InheritsParentStencil )
		end
	end
end

function ControlMeta:PropagateStencilSettings( Stencilled )
	if self.Children then
		for Child in self.Children:Iterate() do
			Child:SetInheritsParentStencilSettings( Stencilled )
			Child:SetStencilled( Stencilled )
		end
	end
end

--[[
	Determines if the given control should use the global skin.
]]
function ControlMeta:SetIsSchemed( Bool )
	self.UseScheme = not not Bool
end

--[[
	Sets visibility of the control.
]]
function ControlMeta:SetIsVisible( IsVisible )
	if not self.Background then return end
	if self.Background.GetIsVisible and self.Background:GetIsVisible() == IsVisible then return end

	self.Background:SetIsVisible( IsVisible )
	self:InvalidateParent()
	self:OnPropertyChanged( "IsVisible", IsVisible )

	if not IsVisible then
		self:HideTooltip()
	else
		self:InvalidateMouseState()
	end

	if not SGUI:IsWindow( self ) then return end

	if IsVisible then
		-- Take focus on show.
		SGUI:SetWindowFocus( self )
	else
		if SGUI.FocusedWindow ~= self then return end

		-- Give focus to the next visible window down on hide.
		local Windows = SGUI.Windows
		local NextDownIndex = 0
		for i = #Windows, 1, -1 do
			if Windows[ i ] ~= self and Windows[ i ]:GetIsVisible() then
				NextDownIndex = i
				break
			end
		end

		if NextDownIndex > 0 then
			SGUI:SetWindowFocus( Windows[ NextDownIndex ], NextDownIndex )
		end
	end
end

--[[
	Computes the actual visibility state of the object, based on
	whether it is set to be invisible, or otherwise if it has a parent
	that is not visible.
]]
function ControlMeta:ComputeVisibility()
	local OurVis = self:GetIsVisible()
	if not OurVis then return false end

	if SGUI.IsValid( self.Parent ) then
		return self.Parent:ComputeVisibility()
	end

	return OurVis
end

--[[
	Override this for stencilled stuff.
]]
function ControlMeta:GetIsVisible()
	if not self.Background then return false end
	return self.Background:GetIsVisible()
end

SGUI.AddProperty( ControlMeta, "Layout" )

--[[
	Sets a layout handler for the element. This will be updated every time
	a layout-changing property on the element is altered (such as size).
]]
function ControlMeta:SetLayout( Layout, DeferInvalidation )
	self.Layout = Layout
	if Layout then
		Layout:SetParent( self )
	end
	self:InvalidateLayout( not DeferInvalidation )
end

--[[
	This event is called whenever layout is invalidated by a property change.

	By default, it updates the set layout handler.
]]
function ControlMeta:PerformLayout()
	self:UpdateAbsolutePositionChildren()

	if not self.Layout then return end

	local Margin = self.Layout:GetComputedMargin()
	local Padding = self:GetComputedPadding()
	local Size = self:GetSize()

	self.Layout:SetPos( Vector2( Margin[ 1 ] + Padding[ 1 ], Margin[ 2 ] + Padding[ 2 ] ) )
	self.Layout:SetSize( Vector2(
		Max( Size.x - Margin[ 1 ] - Margin[ 3 ] - Padding[ 1 ] - Padding[ 3 ], 0 ),
		Max( Size.y - Margin[ 2 ] - Margin[ 4 ] - Padding[ 2 ] - Padding[ 4 ], 0 )
	) )
	self.Layout:InvalidateLayout( true )
end

function ControlMeta:UpdateAbsolutePositionChildren()
	if not self.ChildrenByPositionType then return end

	local Children = self.ChildrenByPositionType:Get( SGUI.PositionType.ABSOLUTE )
	if not Children then return end

	local Size = self:GetSize()
	for i = 1, #Children do
		local Child = Children[ i ]
		local Pos = Child:ComputeAbsolutePosition( Size )

		Child:PreComputeWidth()

		local Width = Child:GetComputedSize( 1, Size.x )

		Child:PreComputeHeight( Width )

		local ChildSize = Vector2( Width, Child:GetComputedSize( 2, Size.y ) )

		Child:SetPos( Pos )
		Child:SetSize( ChildSize )
		Child:InvalidateLayout( true )
	end
end

--[[
	Marks the element's parent's layout as invalid, if the element has a parent.

	Pass true to force the layout to update immediately, or leave false/nil to defer until
	the next frame.
]]
function ControlMeta:InvalidateParent( Now )
	if not self.Parent then return end

	self.Parent:InvalidateLayout( Now )
end

--[[
	Marks the element's layout as invalid.

	Pass true to force the layout to update immediately, or leave false/nil to defer until
	the next frame. Deferring is preferred, as there may be multiple property changes in a
	single frame that all trigger layout invalidation.
]]
function ControlMeta:InvalidateLayout( Now )
	if Now then
		self.LayoutIsInvalid = false
		self:PerformLayout()

		if self.Layout then
			self.Layout:InvalidateLayout( true )
		end

		return
	end

	self.LayoutIsInvalid = true
end

do
	-- By default, don't offset an element's position during layout.
	local ZERO = Vector2( 0, 0 )
	function ControlMeta:GetLayoutOffset()
		return ZERO
	end
end

--[[
	Sets the size of the control (background), and invalidates the control's layout.
]]
function ControlMeta:SetSize( SizeVec )
	if not self.Background then return end

	local OldSize = self.Background:GetSize()
	if OldSize == SizeVec then return end

	self.Background:SetSize( SizeVec )
	self:InvalidateLayout()
	self:InvalidateMouseState()
	self:OnPropertyChanged( "Size", SizeVec )
end

--[[
	A simple shortcut method for setting font and potentially scale
	simultaneously.
]]
function ControlMeta:SetFontScale( Font, Scale )
	self:SetFont( Font )
	if Scale then
		self:SetTextScale( Scale )
	end
end

function ControlMeta:SetAlpha( Alpha )
	local Colour = self.Background:GetColor()
	Colour.a = Alpha
	self.Background:SetColor( Colour )
end

function ControlMeta:GetAlpha()
	return self.Background:GetColor().a
end

function ControlMeta:GetTextureWidth()
	return self.Background:GetTextureWidth()
end

function ControlMeta:GetTextureHeight()
	return self.Background:GetTextureHeight()
end

function ControlMeta:SetTextureCoordinates( X1, Y1, X2, Y2 )
	self.Background:SetTextureCoordinates( X1, Y1, X2, Y2 )
end

function ControlMeta:SetTexturePixelCoordinates( X1, Y1, X2, Y2 )
	self.Background:SetTexturePixelCoordinates( X1, Y1, X2, Y2 )
end

--[[
	Alignment controls whether elements are placed at the start or end of a layout.

	For example, MIN in vertical layout places from the top, while MAX places from
	the bottom.
]]
SGUI.LayoutAlignment = {
	MIN = 1,
	MAX = 2,
	CENTRE = 3
}

SGUI.AddProperty( ControlMeta, "Alignment", SGUI.LayoutAlignment.MIN, { "InvalidatesParent" } )

-- Cross-axis alignment controls how an element is aligned on the opposite axis to the layout direction.
-- For example, an element in a horizontal layout uses the cross-axis alignment to align itself vertically.
SGUI.AddProperty( ControlMeta, "CrossAxisAlignment", SGUI.LayoutAlignment.MIN, { "InvalidatesParent" } )

-- AutoSize controls how to resize the control during layout. You should pass a UnitVector, with
-- your dynamic units (e.g. GUIScaled, Percentage).
SGUI.AddProperty( ControlMeta, "AutoSize", nil, { "InvalidatesParent" } )

-- AutoFont provides a way to set the font size automatically at layout time.
SGUI.AddProperty( ControlMeta, "AutoFont", nil, { "InvalidatesParent" } )

-- AspectRatio provides a way to make a control's height depend on its width, computed at layout time.
-- This only works if the control has an AutoSize set, and will ignore the height value of the AutoSize entirely.
SGUI.AddProperty( ControlMeta, "AspectRatio", nil, { "InvalidatesParent" } )

-- Fill controls whether the element should have its size computed automatically during layout.
SGUI.AddProperty( ControlMeta, "Fill", nil, { "InvalidatesParent" } )

-- Margin controls separation of elements in layouts.
SGUI.AddProperty( ControlMeta, "Margin", nil, { "InvalidatesParent" } )

-- Padding controls the space from the element borders to where the layout may place elements.
SGUI.AddProperty( ControlMeta, "Padding", nil, { "InvalidatesLayout" } )

-- Offsets for absolutely positioned elements.
SGUI.AddProperty( ControlMeta, "LeftOffset", nil, { "InvalidatesParent" } )
SGUI.AddProperty( ControlMeta, "TopOffset", nil, { "InvalidatesParent" } )

SGUI.PositionType = {
	NONE = 1,
	ABSOLUTE = 2
}

SGUI.AddProperty( ControlMeta, "PositionType", SGUI.PositionType.NONE, { "InvalidatesParent" } )

function ControlMeta:SetPositionType( PositionType )
	local OldPositionType = self:GetPositionType()
	if OldPositionType == PositionType then return end

	self.PositionType = PositionType

	local Parent = self.Parent
	if Parent then
		Parent.ChildrenByPositionType:RemoveKeyValue( OldPositionType, self )
		Parent.ChildrenByPositionType:Add( PositionType, self )
	end
end

function ControlMeta:ComputeAbsolutePosition( ParentSize )
	local LeftOffset = SGUI.Layout.ToUnit( self:GetLeftOffset() )
	local TopOffset = SGUI.Layout.ToUnit( self:GetTopOffset() )

	return Vector2(
		LeftOffset:GetValue( ParentSize.x, self, 1 ),
		TopOffset:GetValue( ParentSize.y, self, 2 )
	)
end

function ControlMeta:IterateChildren()
	return self.Children:Iterate()
end

function ControlMeta:GetParentSize()
	if self.LayoutParent then
		return self.LayoutParent:GetSize()
	end

	return self.Parent and self.Parent:GetSize() or Vector2( SGUI.GetScreenSize() )
end

function ControlMeta:GetMaxSizeAlongAxis( Axis )
	local Padding = self:GetComputedPadding()

	local Total = 0
	if Axis == 1 then
		Total = Total + Padding[ 1 ] + Padding[ 3 ]
	else
		Total = Total + Padding[ 2 ] + Padding[ 4 ]
	end

	local ParentSize = self:GetParentSize()[ Axis == 1 and "x" or "y" ]
	local MaxChildSize = 0

	for Child in self:IterateChildren() do
		Child:PreComputeWidth()

		-- This only works if the child's size does not depend on the parent's.
		-- Otherwise it's a circular dependency and it won't be correct.
		local ChildSize = Child:GetComputedSize( Axis, ParentSize )

		local Margin = Child:GetComputedMargin()
		if Axis == 1 then
			ChildSize = ChildSize + Margin[ 1 ] + Margin[ 3 ]
		else
			ChildSize = ChildSize + Margin[ 2 ] + Margin[ 4 ]
		end

		MaxChildSize = Max( MaxChildSize, ChildSize )
	end

	return Max( Total + MaxChildSize, 0 )
end

function ControlMeta:GetContentSizeForAxis( Axis )
	local Padding = self:GetComputedPadding()

	local Total = 0
	if Axis == 1 then
		Total = Total + Padding[ 1 ] + Padding[ 3 ]
	else
		Total = Total + Padding[ 2 ] + Padding[ 4 ]
	end

	local ParentSize = self:GetParentSize()[ Axis == 1 and "x" or "y" ]

	for Child in self:IterateChildren() do
		Child:PreComputeWidth()

		-- This only works if the child's size does not depend on the parent's.
		-- Otherwise it's a circular dependency and it won't be correct.
		Total = Total + Child:GetComputedSize( Axis, ParentSize )

		local Margin = Child:GetComputedMargin()
		if Axis == 1 then
			Total = Total + Margin[ 1 ] + Margin[ 3 ]
		else
			Total = Total + Margin[ 2 ] + Margin[ 4 ]
		end
	end

	return Max( Total, 0 )
end

-- You can either use AutoSize as part of a layout, or on its own by passing true for UpdateNow.
function ControlMeta:SetAutoSize( AutoSize, UpdateNow )
	self.AutoSize = AutoSize
	if not UpdateNow then return end

	local ParentSize = self:GetParentSize()

	self:SetSize( Vector2( self:GetComputedSize( 1, ParentSize.x ),
		self:GetComputedSize( 2, ParentSize.y ) ) )
end

-- Called before a layout computes the current width of the element.
function ControlMeta:PreComputeWidth()
	if not self.AutoFont then return end

	local FontFamily = self.AutoFont.Family
	local Size = self.AutoFont.Size:GetValue()

	self:SetFontScale( SGUI.FontManager.GetFontForAbsoluteSize( FontFamily, Size, self.GetText and self:GetText() ) )
end

-- Called before a layout computes the current height of the element.
-- Override to add wrapping logic.
function ControlMeta:PreComputeHeight( Width )
	if not self.AspectRatio or not self.AutoSize then return end

	-- Make height always relative to width.
	self.AutoSize[ 2 ] = SGUI.Layout.Units.Absolute( Width * self.AspectRatio )
end

--[[
	Computes the size of the control based on the units provided.
]]
function ControlMeta:GetComputedSize( Index, ParentSize )
	local Size = self.AutoSize
	if Size then
		-- Auto-size means use our set auto-size units relative to the passed in size.
		return Max( Size[ Index ]:GetValue( ParentSize, self, Index ), 0 )
	end

	-- Fill means take the size given.
	if self:GetFill() then
		return ParentSize
	end

	-- No auto-size means the element has a fixed size.
	return self:GetSize()[ Index == 1 and "x" or "y" ]
end

function ControlMeta:ComputeSpacing( Spacing )
	if not Spacing then
		return { 0, 0, 0, 0 }
	end

	local Computed = {}

	local Parent = self.Parent
	local ParentSize = self:GetParentSize()

	for i = 1, 4 do
		local IsYAxis = i % 2 == 0
		Computed[ i ] = Spacing[ i ]:GetValue(
			ParentSize[ IsYAxis and "y" or "x" ],
			self,
			IsYAxis and 2 or 1
		)
	end

	return Computed
end

function ControlMeta:GetComputedPadding()
	return self:ComputeSpacing( self.Padding )
end

function ControlMeta:GetComputedMargin()
	return self:ComputeSpacing( self.Margin )
end

function ControlMeta:GetSize()
	if not self.Background then return end

	return self.Background:GetSize()
end

--[[
	Sets the position of an SGUI control.

	Controls may override this.
]]
function ControlMeta:SetPos( Pos )
	if not self.Background then return end

	local OldPos = self.Background:GetPosition()
	if Pos == OldPos then return end

	self.Background:SetPosition( Pos )
	self:InvalidateMouseState()
	self:OnPropertyChanged( "Pos", Pos )
end

function ControlMeta:GetPos()
	if not self.Background then return end

	return self.Background:GetPosition()
end

--[[
	Returns the absolute position of the control on the screen.
]]
function ControlMeta:GetScreenPos()
	if not self.Background then return end
	return self.Background:GetScreenPosition( SGUI.GetScreenSize() )
end

do
	local Anchors = {
		TopLeft = { GUIItem.Left, GUIItem.Top },
		TopMiddle = { GUIItem.Middle, GUIItem.Top },
		TopRight = { GUIItem.Right, GUIItem.Top },

		CentreLeft = { GUIItem.Left, GUIItem.Center },
		CentreMiddle = { GUIItem.Middle, GUIItem.Center },
		CentreRight = { GUIItem.Right, GUIItem.Center },

		CenterLeft = { GUIItem.Left, GUIItem.Center },
		CenterMiddle = { GUIItem.Middle, GUIItem.Center },
		CenterRight = { GUIItem.Right, GUIItem.Center },

		BottomLeft = { GUIItem.Left, GUIItem.Bottom },
		BottomMiddle = { GUIItem.Middle, GUIItem.Bottom },
		BottomRight = { GUIItem.Right, GUIItem.Bottom }
	}
	SGUI.Anchors = Anchors

	local AnchorFractions = {
		TopLeft = Vector2( 0, 0 ),
		TopMiddle = Vector2( 0.5, 0 ),
		TopRight = Vector2( 1, 0 ),

		CentreLeft = Vector2( 0, 0.5 ),
		CentreMiddle = Vector2( 0.5, 0.5 ),
		CentreRight = Vector2( 1, 0.5 ),

		CenterLeft = Vector2( 0, 0.5 ),
		CenterMiddle = Vector2( 0.5, 0.5 ),
		CenterRight = Vector2( 1, 0.5 ),

		BottomLeft = Vector2( 0, 1 ),
		BottomMiddle = Vector2( 0.5, 1 ),
		BottomRight = Vector2( 1, 1 ),

		[ GUIItem.Left ] = 0,
		[ GUIItem.Middle ] = 0.5,
		[ GUIItem.Right ] = 1,
		[ GUIItem.Top ] = 0,
		[ GUIItem.Center ] = 0.5,
		[ GUIItem.Bottom ] = 1
	}

	local NewScalingFlag = GUIItem.CorrectScaling

	--[[
		Sets the origin anchors for the control.
	]]
	function ControlMeta:SetAnchor( X, Y )
		if not self.Background then return end

		local UsesNewScaling = self.Background:IsOptionFlagSet( NewScalingFlag )
		if IsType( X, "string" ) then
			if UsesNewScaling then
				local Anchor = Shine.AssertAtLevel( AnchorFractions[ X ], "Unknown anchor type: %s", 3, X )
				self.Background:SetAnchor( Anchor )
				return
			end

			local Anchor = Shine.AssertAtLevel( Anchors[ X ], "Unknown anchor type: %s", 3, X )
			self.Background:SetAnchor( Anchor[ 1 ], Anchor[ 2 ] )
		else
			if UsesNewScaling then
				self.Background:SetAnchor( Vector2( AnchorFractions[ X ], AnchorFractions[ Y ] ) )
				return
			end

			self.Background:SetAnchor( X, Y )
		end
	end

	--[[
		Sets the origin anchors using a fractional value for the control.
	]]
	function ControlMeta:SetAnchorFraction( X, Y )
		if not self.Background then return end

		Shine.AssertAtLevel(
			self.Background:IsOptionFlagSet( NewScalingFlag ),
			"Background element must have GUIItem.CorrectScaling flag set to use SetAnchorFraction!",
			3
		)

		self.Background:SetAnchor( Vector2( X, Y ) )
	end

	--[[
		Sets the local origin of the given element (i.e. 0, 0 means position determines where the top-left corner is,
		0.5, 0.5 means position determines where the centre of the element is).

		This also affects the origin of scaling applied to the element.
	]]
	function ControlMeta:SetHotSpot( X, Y )
		if not self.Background then return end

		Shine.AssertAtLevel(
			self.Background:IsOptionFlagSet( NewScalingFlag ),
			"Background element must have GUIItem.CorrectScaling flag set to use SetHotSpot!",
			3
		)

		if IsType( X, "string" ) then
			local HotSpot = Shine.AssertAtLevel( AnchorFractions[ X ], "Unknown hotspot type: %s", 3, X )
			self.Background:SetHotSpot( HotSpot )
		else
			self.Background:SetHotSpot( X, Y )
		end
	end
end

function ControlMeta:GetAnchor()
	local X = self.Background:GetXAnchor()
	local Y = self.Background:GetYAnchor()

	return X, Y
end

do
	-- We call this so many times it really needs to be local, not global.
	local GetCursorPos = SGUI.GetCursorPos

	local function IsInBox( BoxW, BoxH, X, Y )
		return X >= 0 and X < BoxW and Y >= 0 and Y < BoxH
	end

	local function IsInElementBox( ElementPos, ElementSize )
		local X, Y = GetCursorPos()
		X = X - ElementPos.x
		Y = Y - ElementPos.y
		return IsInBox( ElementSize.x, ElementSize.y, X, Y ), X, Y, ElementSize, ElementPos
	end

	local function ApplyMultiplier( Size, Mult )
		if Mult then
			if IsType( Mult, "number" ) then
				Size = Size * Mult
			else
				Size.x = Size.x * Mult.x
				Size.y = Size.y * Mult.y
			end
		end
		return Size
	end

	--[[
		Gets whether the mouse cursor is inside the given bounds, relative to the given GUIItem.

		Inputs:
			1. Element to check.
			2. Width of the bounding box.
			3. Height of the bounding box.
		Outputs:
			1. Boolean value to indicate whether the mouse is inside.
			2. X position of the mouse relative to the element.
			3. Y position of the mouse relative to the element.
			4. The size of the bounding box used.
			5. The element's absolute screen position.
	]]
	function ControlMeta:MouseInBounds( Element, BoundsW, BoundsH )
		local Pos = Element:GetScreenPosition( SGUI.GetScreenSize() )
		return IsInElementBox( Pos, Vector2( BoundsW, BoundsH ) )
	end

	--[[
		Gets whether the mouse cursor is inside the bounds of a GUIItem.
		The multiplier will increase or reduce the size we use to calculate this.

		Inputs:
			1. Element to check.
			2. Multiplier value to increase/reduce the size of the bounding box.
		Outputs:
			1. Boolean value to indicate whether the mouse is inside.
			2. X position of the mouse relative to the element.
			3. Y position of the mouse relative to the element.
			4. The size of the bounding box used.
			5. The element's absolute screen position.
	]]
	function ControlMeta:MouseIn( Element, Mult )
		if not Element then return end

		local Pos = Element:GetScreenPosition( SGUI.GetScreenSize() )
		local Size = Element:GetScaledSize()

		return IsInElementBox( Pos, ApplyMultiplier( Size, Mult ) )
	end

	--[[
		Gets the bounds to use when checking whether the mouse is in a control.

		Override this to change how mouse enter/leave detection works.
	]]
	function ControlMeta:GetMouseBounds()
		return self:GetSize()
	end

	--[[
		Similar to MouseIn, but uses the control's native GetScreenPos and GetMouseBounds instead
		of a GUIItem's.

		Useful for controls whose size/position does not match a GUIItem directly.
	]]
	function ControlMeta:MouseInControl( Mult )
		local Pos = self:GetScreenPos()
		local Size = self:GetMouseBounds()

		return IsInElementBox( Pos, ApplyMultiplier( Size, Mult ) )
	end

	function ControlMeta:MouseInCached()
		local LastCheck = self.__LastMouseInCheckFrame
		local FrameNum = SGUI.FrameNumber()

		if LastCheck ~= FrameNum then
			self.__LastMouseInCheckFrame = FrameNum

			local In, X, Y, Size, Pos = self:MouseInControl()
			local CachedResult = self.__LastMouseInCheck
			if not CachedResult then
				CachedResult = TableNew( 5, 0 )
				self.__LastMouseInCheck = CachedResult
			end

			CachedResult[ 1 ] = In
			CachedResult[ 2 ] = X
			CachedResult[ 3 ] = Y
			CachedResult[ 4 ] = Size
			CachedResult[ 5 ] = Pos

			return In, X, Y, Size, Pos
		end

		local Check = self.__LastMouseInCheck
		return Check[ 1 ], Check[ 2 ], Check[ 3 ], Check[ 4 ], Check[ 5 ]
	end
end

function ControlMeta:HasMouseFocus()
	return SGUI.MouseDownControl == self
end

do
	local function SubtractValues( End, Start )
		if IsType( End, "number" ) or not End.r then
			return End - Start
		end

		return SGUI.ColourSub( End, Start )
	end

	local function CopyValue( Value )
		if IsType( Value, "number" ) then
			return Value
		end

		if SGUI.IsColour( Value ) then
			return SGUI.CopyColour( Value )
		end

		return Vector2( Value.x, Value.y )
	end

	local function LinearEase( Progress )
		return Progress
	end

	local Max = math.max

	function ControlMeta:EaseValue( Element, Start, End, Delay, Duration, Callback, EasingHandlers )
		self.EasingProcesses = self.EasingProcesses or Map()

		local Easers = self.EasingProcesses:Get( EasingHandlers )
		if not Easers then
			Easers = Map()
			self.EasingProcesses:Add( EasingHandlers, Easers )
		end

		Element = Element or self.Background

		local EasingData = Easers:Get( Element )
		if not EasingData then
			EasingData = {}
			Easers:Add( Element, EasingData )
		end

		EasingData.Element = Element
		Start = Start or EasingHandlers.Getter( self, Element )
		EasingData.Start = Start
		EasingData.End = End
		EasingData.Diff = SubtractValues( End, Start )
		EasingData.CurValue = CopyValue( Start )
		EasingData.Easer = EasingHandlers.Easer
		EasingData.EaseFunc = LinearEase

		EasingData.StartTime = Clock() + Delay
		EasingData.Duration = Duration
		EasingData.Elapsed = Max( -Delay, 0 )
		EasingData.LastUpdate = Clock()

		EasingData.Callback = Callback

		if EasingHandlers.Init then
			EasingHandlers.Init( self, Element, EasingData )
		end

		if Delay <= 0 then
			EasingHandlers.Setter( self, Element, Start, EasingData )
		end

		return EasingData
	end
end

do
	local function UpdateEasing( self, Time, DeltaTime, EasingHandler, Easings, Element, EasingData )
		EasingData.Elapsed = EasingData.Elapsed + Max( DeltaTime, Time - EasingData.LastUpdate )

		local Duration = EasingData.Duration
		local Elapsed = EasingData.Elapsed
		if Elapsed <= Duration then
			local Progress = EasingData.EaseFunc( Elapsed / Duration, EasingData.Power )
			EasingData.Easer( self, Element, EasingData, Progress )
			EasingHandler.Setter( self, Element, EasingData.CurValue, EasingData )
		else
			EasingHandler.Setter( self, Element, EasingData.End, EasingData )
			if EasingHandler.OnComplete then
				EasingHandler.OnComplete( self, Element, EasingData )
			end

			Easings:Remove( Element )

			if EasingData.Callback then
				EasingData.Callback( self, Element )
			end
		end
	end

	function ControlMeta:HandleEasing( Time, DeltaTime )
		if not self.EasingProcesses or self.EasingProcesses:IsEmpty() then return end

		for EasingHandler, Easings in self.EasingProcesses:Iterate() do
			for Element, EasingData in Easings:Iterate() do
				local Start = EasingData.StartTime

				if Start <= Time then
					UpdateEasing( self, Time, DeltaTime, EasingHandler, Easings, Element, EasingData )
				end

				EasingData.LastUpdate = Time
			end

			if Easings:IsEmpty() then
				self.EasingProcesses:Remove( EasingHandler )
			end
		end
	end
end

local function Easer( Table, Name )
	return setmetatable( Table, { __tostring = function() return Name end } )
end

local Easers = {
	Fade = Easer( {
		Easer = function( self, Element, EasingData, Progress )
			SGUI.ColourLerp( EasingData.CurValue, EasingData.Start, Progress, EasingData.Diff )
		end,
		Setter = function( self, Element, Colour )
			Element:SetColor( Colour )
		end,
		Getter = function( self, Element )
			return Element:GetColor()
		end
	}, "Fade" ),
	Alpha = Easer( {
		Init = function( self, Element, EasingData )
			EasingData.Colour = Element:GetColor()
		end,
		Easer = function( self, Element, EasingData, Progress )
			EasingData.CurValue = EasingData.Start + EasingData.Diff * Progress
			EasingData.Colour.a = EasingData.CurValue
		end,
		Setter = function( self, Element, Alpha, EasingData )
			EasingData.Colour.a = Alpha
			Element:SetColor( EasingData.Colour )
		end,
		Getter = function( self, Element )
			return Element:GetColor().a
		end
	}, "Alpha" ),
	Move = Easer( {
		Easer = function( self, Element, EasingData, Progress )
			local CurValue = EasingData.CurValue
			local Start = EasingData.Start
			local Diff = EasingData.Diff

			CurValue.x = Start.x + Diff.x * Progress
			CurValue.y = Start.y + Diff.y * Progress
		end,
		Setter = function( self, Element, Pos )
			Element:SetPosition( Pos )
		end,
		Getter = function( self, Element )
			return Element:GetPosition()
		end,
		OnComplete = function( self, Element, EasingData )
			self:InvalidateMouseState()
		end
	}, "Move" ),
	Size = Easer( {
		Setter = function( self, Element, Size )
			if Element == self.Background then
				self:SetSize( Size )
			else
				Element:SetSize( Size )
			end
		end,
		Getter = function( self, Element )
			return Element:GetSize()
		end,
		OnComplete = function( self, Element, EasingData )
			if Element == self.Background then
				self:InvalidateMouseState()
			end
		end
	}, "Size" ),
	Scale = Easer( {
		Setter = function( self, Element, Scale )
			Element:SetScale( Scale )
		end,
		Getter = function( self, Element )
			return Element:GetScale()
		end
	}, "Scale" )
}
Easers.Size.Easer = Easers.Move.Easer
Easers.Scale.Easer = Easers.Move.Easer

function ControlMeta:GetEasing( Type, Element )
	if not self.EasingProcesses then return end

	local Easers = self.EasingProcesses:Get( Easers[ Type ] )
	if not Easers then return end

	return Easers:Get( Element or self.Background )
end

function ControlMeta:StopEasing( Element, EasingHandler )
	if not self.EasingProcesses then return end

	local Easers = self.EasingProcesses:Get( EasingHandler )
	if not Easers then return end

	Element = Element or self.Background

	local EasingData = Easers:Get( Element )
	if EasingData and EasingHandler.OnComplete then
		EasingHandler.OnComplete( self, Element, EasingData )
	end

	Easers:Remove( Element )
end

local function AddEaseFunc( EasingData, EaseFunc, Power )
	EasingData.EaseFunc = EaseFunc or math.EaseOut
	EasingData.Power = Power or 3
end

do
	local function GetEaserForTransition( Transition )
		return Easers[ Transition.Type ] or Transition.Easer
	end

	--[[
		Adds a new easing transition to the control.

		Transitions are a table like the following:
		{
			-- The element the easing should apply to (if omitted, self.Background is used).
			Element = self.Background,

			-- The starting value (if omitted, the current value for the specified type is used).
			StartValue = self:GetPos(),

			-- The end value to ease towards.
			EndValue = self:GetPos() + Vector2( 100, 0 ),

			-- The time to wait (in seconds) from now until the transition should start (if omitted, no delay is applied).
			Delay = 0,

			-- How long (in seconds) to take to ease between the start and end values.
			Duration = 0.3,

			-- An optional callback that is executed once the transition is complete. It will be passed the element
			-- that was transitioned.
			Callback = function( Element ) end,

			-- The type of easer to use (if using a standard easer)
			Type = "Move",

			-- A custom easer to use if "Type" is not specified.
			Easer = ...,

			-- The easing function to use (if omitted, math.EaseOut is used).
			EasingFunction = math.EaseOut,

			-- The power value to pass to the easing function (if omitted, 3 is used).
			EasingPower = 3
		}
	]]
	function ControlMeta:ApplyTransition( Transition )
		local EasingData = self:EaseValue(
			Transition.Element,
			Transition.StartValue,
			Transition.EndValue,
			Transition.Delay or 0,
			Transition.Duration,
			Transition.Callback,
			GetEaserForTransition( Transition )
		)
		AddEaseFunc( EasingData, Transition.EasingFunction, Transition.EasingPower )

		return EasingData
	end

	function ControlMeta:StopTransition( Transition )
		self:StopEasing( Transition.Element, GetEaserForTransition( Transition ) )
	end
end

--[[
	Sets an SGUI control to move from its current position.

	Inputs:
		1. Element to move, nil uses self.Background.
		2. Starting position, nil uses current position.
		3. Ending position.
		4. Delay in seconds to wait before moving.
		5. Duration of movement.
		6. Callback function to run once movement is complete.
		7. Easing function to use to perform movement, otherwise linear movement is used.
		8. Power to pass to the easing function.
]]
function ControlMeta:MoveTo( Element, Start, End, Delay, Duration, Callback, EaseFunc, Power )
	local EasingData = self:EaseValue( Element, Start, End, Delay, Duration, Callback,
		Easers.Move )
	AddEaseFunc( EasingData, EaseFunc, Power )

	return EasingData
end

function ControlMeta:StopMoving( Element )
	self:StopEasing( Element, Easers.Move )
end

--[[
	Fades an element from one colour to another.

	You can fade as many GUIItems in an SGUI control as you want at once.

	Inputs:
		1. GUIItem to fade.
		2. Starting colour.
		3. Final colour.
		4. Delay from when this is called to wait before starting the fade.
		5. Duration of the fade.
		6. Callback function to run once the fading has completed.
]]
function ControlMeta:FadeTo( Element, Start, End, Delay, Duration, Callback, EaseFunc, Power )
	local EasingData = self:EaseValue( Element, Start, End, Delay, Duration, Callback, Easers.Fade )
	AddEaseFunc( EasingData, EaseFunc, Power )

	return EasingData
end

function ControlMeta:StopFade( Element )
	self:StopEasing( Element, Easers.Fade )
end

function ControlMeta:AlphaTo( Element, Start, End, Delay, Duration, Callback, EaseFunc, Power )
	local EasingData = self:EaseValue( Element, Start, End, Delay, Duration, Callback, Easers.Alpha )
	AddEaseFunc( EasingData, EaseFunc, Power )

	return EasingData
end

function ControlMeta:StopAlpha( Element )
	self:StopEasing( Element, Easers.Alpha )
end

--[[
	Resizes an element from one size to another.

	Inputs:
		1. GUIItem to resize.
		2. Starting size, leave nil to use the element's current size.
		3. Ending size.
		4. Delay before resizing should start.
		5. Duration of resizing.
		6. Callback to run when resizing is complete.
		7. Optional easing function to use.
		8. Optional power to pass to the easing function.
]]
function ControlMeta:SizeTo( Element, Start, End, Delay, Duration, Callback, EaseFunc, Power )
	local EasingData = self:EaseValue( Element, Start, End, Delay, Duration, Callback,
		Easers.Size )
	AddEaseFunc( EasingData, EaseFunc, Power )

	return EasingData
end

function ControlMeta:StopResizing( Element )
	self:StopEasing( Element, Easers.Size )
end

SGUI.AddProperty( ControlMeta, "ActiveCol" )
SGUI.AddProperty( ControlMeta, "InactiveCol" )

do
	local function HandleHighlightOnVisibilityChange( self, IsVisible )
		if not IsVisible then
			self:SetHighlighted( false, true )
		else
			self:SetHighlighted( self:ShouldHighlight(), true )
		end
	end

	-- Basic highlight on mouse over handling.
	local function HandleHightlighting( self )
		if self:ShouldHighlight() then
			self:SetHighlighted( true )
		elseif self.Highlighted and not self.ForceHighlight then
			self:SetHighlighted( false )
		end
	end

	local function NoOpHighlighting() end

	ControlMeta.HandleHightlighting = NoOpHighlighting

	--[[
		Sets an SGUI control to highlight on mouse over automatically.

		Requires the values:
			self.ActiveCol - Colour when highlighted.
			self.InactiveCol - Colour when not highlighted.

		Will set the value:
			self.Highlighted - Will be true when highlighted.

		Only applies to the background.

		Inputs:
			1. Boolean should hightlight.
			2. Muliplier to the element's size when determining if the mouse is in the element.
	]]
	function ControlMeta:SetHighlightOnMouseOver( HighlightOnMouseOver, TextureMode )
		local WasHighlightOnMouseOver = self.HighlightOnMouseOver

		self.HighlightOnMouseOver = not not HighlightOnMouseOver

		if not WasHighlightOnMouseOver and self.HighlightOnMouseOver then
			self.HandleHightlighting = HandleHightlighting
			self:AddPropertyChangeListener( "IsVisible", HandleHighlightOnVisibilityChange )
		elseif WasHighlightOnMouseOver and not self.HighlightOnMouseOver then
			self.HandleHightlighting = NoOpHighlighting
			self:RemovePropertyChangeListener( "IsVisible", HandleHighlightOnVisibilityChange )
		end

		if not HighlightOnMouseOver then
			if not self.ForceHighlight then
				self:SetHighlighted( false, true )
				self:StopFade( self.Background )
			end

			self.TextureHighlight = TextureMode
		else
			self.TextureHighlight = TextureMode
			self:HandleHightlighting()
		end
	end
end

do
	local function ResetHoveringState( self )
		self.MouseHoverStart = nil

		if self.MouseHovered then
			self.MouseHovered = nil

			if self.OnLoseHover then
				self:OnLoseHover()
			end
		end
	end

	local function HandleVisibilityChange( self, IsVisible )
		if not IsVisible then
			ResetHoveringState( self )
		end
	end

	function ControlMeta:ListenForHoverEvents( OnHover, OnLoseHover )
		local OldOnHover = self.OnHover

		self.OnHover = OnHover
		self.OnLoseHover = OnLoseHover

		if not OldOnHover then
			self:AddPropertyChangeListener( "IsVisible", HandleVisibilityChange )
		end
	end

	function ControlMeta:ResetHoverEvents()
		self.OnHover = nil
		self.OnLoseHover = nil
		self:RemovePropertyChangeListener( "IsVisible", HandleVisibilityChange )
	end

	--[[
		Sets up a tooltip for the given element.
		This should work on any element without needing special code for it.

		Input: Text value to display as a tooltip, pass in nil to remove the tooltip.
	]]
	function ControlMeta:SetTooltip( Text )
		if Text == nil then
			self.TooltipText = nil
			self:ResetHoverEvents()
			self:HideTooltip()
			return
		end

		self.TooltipText = Text
		self:ListenForHoverEvents( self.ShowTooltip, self.HideTooltip )
	end

	local DEFAULT_HOVER_TIME = 0.5
	function ControlMeta:HandleHovering( Time )
		if not self.OnHover then return end

		local MouseIn = self:HasMouseEntered() and self:GetIsVisible()

		-- If the mouse is in this object, and our window is in focus (i.e. not obstructed by a higher window)
		-- then consider the object hovered.
		if MouseIn and ( not self.TopLevelWindow or SGUI:IsWindowInFocus( self.TopLevelWindow ) ) then
			if not self.MouseHoverStart then
				self.MouseHoverStart = Time
			else
				if Time - self.MouseHoverStart > ( self.HoverTime or DEFAULT_HOVER_TIME ) and not self.MouseHovered then
					self.MouseHovered = true

					local _, X, Y = self:MouseInCached()
					self:OnHover( X, Y )
				end
			end
		else
			ResetHoveringState( self )
		end
	end
end

function ControlMeta:HandleLayout( DeltaTime )
	if self.Layout then
		self.Layout:Think( DeltaTime )
	end

	-- Sometimes layout requires multiple passes to reach the final answer (e.g. if auto-wrapping text).
	-- Allow up to 5 iterations before stopping and leaving it for the next frame.
	for i = 1, 5 do
		if not self.LayoutIsInvalid then break end

		self.LayoutIsInvalid = false
		self:PerformLayout()
	end
end

--[[
	Global update function. Called on client update.

	You must call this inside a control's custom Think function with:
		self.BaseClass.Think( self, DeltaTime )
	if you want to use MoveTo, FadeTo, SetHighlightOnMouseOver etc.

	Alternatively, call only the functions you want to use.
]]
function ControlMeta:Think( DeltaTime )
	local Time = Clock()

	self:HandleEasing( Time, DeltaTime )
	self:HandleHovering( Time )
	self:HandleLayout( DeltaTime )
	self:HandleMouseState()
end

function ControlMeta:ThinkWithChildren( DeltaTime )
	if not self:GetIsVisible() then return end

	self.BaseClass.Think( self, DeltaTime )
	self:CallOnChildren( "Think", DeltaTime )
end

function ControlMeta:GetTooltipOffset( MouseX, MouseY, Tooltip )
	local SelfPos = self:GetScreenPos()

	local X = SelfPos.x + MouseX
	local Y = SelfPos.y + MouseY

	Y = Y - Tooltip:GetSize().y - 4

	return X, Y
end

function ControlMeta:ShowTooltip( MouseX, MouseY )
	local Tooltip = self.Tooltip
	if not SGUI.IsValid( Tooltip ) then
		Tooltip = SGUI:Create( "Tooltip" )

		-- As the Tooltip element is not a child of this element, the skin must be set manually.
		if self.PropagateSkin then
			Tooltip:SetSkin( self:GetSkin() )
		end
	end

	local W, H = SGUI.GetScreenSize()
	local Font
	local TextScale

	if H <= SGUI.ScreenHeight.Small then
		Font = Fonts.kAgencyFB_Tiny
	elseif H > SGUI.ScreenHeight.Normal and H <= SGUI.ScreenHeight.Large then
		Font = Fonts.kAgencyFB_Medium
	elseif H > SGUI.ScreenHeight.Large then
		Font = Fonts.kAgencyFB_Huge
		TextScale = Vector2( 0.5, 0.5 )
	end

	Tooltip:SetTextPadding( SGUI.Layout.Units.HighResScaled( 16 ):GetValue() )
	Tooltip:SetText( self.TooltipText, Font, TextScale )

	local X, Y = self:GetTooltipOffset( MouseX, MouseY, Tooltip )
	Tooltip:SetPos( Vector2( X, Y ) )
	Tooltip:FadeIn()

	self.Tooltip = Tooltip
end

do
	local function OnTooltipHidden( self )
		self.Tooltip = nil
	end

	function ControlMeta:HideTooltip()
		if not SGUI.IsValid( self.Tooltip ) then return end

		self.Tooltip:FadeOut( OnTooltipHidden, self )
	end
end

function ControlMeta:SetHighlighted( Highlighted, SkipAnim )
	if not not Highlighted == not not self.Highlighted then return end

	if Highlighted then
		self.Highlighted = true
		self:AddStylingState( "Highlighted" )

		if not self.TextureHighlight then
			if SkipAnim then
				self:StopFade( self.Background )
				self.Background:SetColor( self.ActiveCol )
				return
			end

			self:FadeTo( self.Background, self.InactiveCol, self.ActiveCol,
				0, 0.1 )
		else
			self.Background:SetTexture( self.HighlightTexture )
		end
	else
		self.Highlighted = false
		self:RemoveStylingState( "Highlighted" )

		if not self.TextureHighlight then
			if SkipAnim then
				self:StopFade( self.Background )
				self.Background:SetColor( self.InactiveCol )
				return
			end

			self:FadeTo( self.Background, self.ActiveCol, self.InactiveCol,
				0, 0.1 )
		else
			self.Background:SetTexture( self.Texture )
		end
	end
end

function ControlMeta:ShouldHighlight()
	return self:GetIsVisible() and self:MouseInCached()
end

function ControlMeta:SetForceHighlight( ForceHighlight, SkipAnim )
	self.ForceHighlight = ForceHighlight

	if ForceHighlight and not self.Highlighted then
		self:SetHighlighted( true, SkipAnim )
	elseif not ForceHighlight and self.Highlighted and not self:ShouldHighlight() then
		self:SetHighlighted( false, SkipAnim )
	end
end

function ControlMeta:OnMouseDown( Key, DoubleClick )
	if not self:GetIsVisible() then return end
	if not self:MouseInCached() then return end

	local Result, Child = self:CallOnChildren( "OnMouseDown", Key, DoubleClick )
	if Result ~= nil then return true, Child end
end

function ControlMeta:PlayerKeyPress( Key, Down )
	if not self:GetIsVisible() then return end

	if self:CallOnChildren( "PlayerKeyPress", Key, Down ) then
		return true
	end
end

function ControlMeta:PlayerType( Char )
	if not self:GetIsVisible() then return end

	if self:CallOnChildren( "PlayerType", Char ) then
		return true
	end
end

function ControlMeta:OnMouseWheel( Down )
	if not self:GetIsVisible() then return end

	local Result = self:CallOnChildren( "OnMouseWheel", Down )
	if Result ~= nil then return true end
end

function ControlMeta:HasMouseEntered()
	return self.MouseHasEntered
end

--[[
	Called when the mouse cursor has entered the control.

	The result of the MouseInControl method determines when this occurs.
]]
function ControlMeta:OnMouseEnter()

end

--[[
	Called when the mouse cursor has left the control.

	The result of the MouseInControl method determines when this occurs.
]]
function ControlMeta:OnMouseLeave()

end

function ControlMeta:InvalidateMouseState( Now )
	self.MouseStateIsInvalid = true
	if Now then
		self:HandleMouseState()
	end
end

function ControlMeta:HandleMouseState()
	if not self.MouseStateIsInvalid or not SGUI.IsMouseVisible() then return end

	self:EvaluateMouseState()
	self:CallOnChildren( "OnMouseMove", false )
end

function ControlMeta:EvaluateMouseState()
	local IsMouseIn = self:MouseInCached()
	local StateChanged = false

	if IsMouseIn and not self.MouseHasEntered then
		StateChanged = true

		self.MouseHasEntered = true
		self:OnMouseEnter()
	elseif not IsMouseIn and self.MouseHasEntered then
		-- Need to let children see the mouse exit themselves too.
		StateChanged = true

		self.MouseHasEntered = false
		self:OnMouseLeave()
	end

	self:HandleHightlighting()
	self.MouseStateIsInvalid = false

	return IsMouseIn, StateChanged
end

function ControlMeta:OnMouseMove( Down )
	if not self:GetIsVisible() then return end

	self.__LastMouseMove = SGUI.FrameNumber()

	local IsMouseIn, StateChanged = self:EvaluateMouseState()
	if IsMouseIn or StateChanged then
		self:CallOnChildren( "OnMouseMove", Down )
	end
end

--[[
	Requests focus, for controls with keyboard input.
]]
function ControlMeta:RequestFocus()
	if not self.UsesKeyboardFocus then return end

	SGUI.NotifyFocusChange( self )
end

--[[
	Returns whether the current control has keyboard focus.
]]
function ControlMeta:HasFocus()
	return SGUI.FocusedControl == self
end

--[[
	Drops keyboard focus on the given element.
]]
function ControlMeta:LoseFocus()
	if not self:HasFocus() then return end

	SGUI.NotifyFocusChange()
end

--[[
	Returns whether the current object is still in use.
	Output: Boolean valid.
]]
function ControlMeta:IsValid()
	return SGUI.ActiveControls:Get( self ) ~= nil
end
