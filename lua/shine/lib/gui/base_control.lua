--[[
	Base SGUI control. All controls inherit from this.
]]

local SGUI = Shine.GUI
local ControlMeta = SGUI.BaseControl

local assert = assert
local Clock = os.clock
local IsType = Shine.IsType
local pairs = pairs
local StringFormat = string.format
local Vector2 = Vector2

local Map = Shine.Map

SGUI.AddBoundProperty( ControlMeta, "Texture", "Background" )
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
end

--[[
	Generic cleanup, for most controls this is adequate.

	The only time you need to override it is if you have more than a background object.
]]
function ControlMeta:Cleanup()
	if self.Parent then return end

	if self.Background then
		GUI.DestroyItem( self.Background )
	end
end

--[[
	Destroys a control.
]]
function ControlMeta:Destroy( RemoveFromParent )
	return SGUI:Destroy( self, RemoveFromParent )
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

--[[
	Sets a new styling state, which will potentially apply different styling
	values to the control.

	This can be used to easily define focus/hover behaviour.
]]
function ControlMeta:SetStylingState( Name )
	self.StylingState = Name
	SGUI.SkinManager:ApplySkin( self )
end

function ControlMeta:GetStylingState()
	return self.StylingState
end

function ControlMeta:SetStyleName( Name )
	self.StyleName = Name
	SGUI.SkinManager:ApplySkin( self )
end

function ControlMeta:SetSkin( Skin )
	self.Skin = Skin
	SGUI.SkinManager:ApplySkin( self )
end

function ControlMeta:GetStyleValue( Key )
	return SGUI.SkinManager:GetStyleForElement( self )[ Key ]
end

--[[
	Sets up a control's properties using a table.
]]
function ControlMeta:SetupFromTable( Table )
	for Property, Value in pairs( Table ) do
		local Method = "Set"..Property

		if self[ Method ] then
			self[ Method ]( self, Value )
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

	if self.Parent then
		self.Parent.Children:Remove( self )
		if self.ParentElement and self.Background then
			self.ParentElement:RemoveChild( self.Background )
		end
	end

	if not Control then
		self.Parent = nil
		self.ParentElement = nil
		self.TopLevelWindow = nil
		return
	end

	-- Parent to a specific part of a control.
	if not Element then
		Element = Control.Background
	end

	self.Parent = Control
	self.ParentElement = Element
	self:SetTopLevelWindow( Control.IsAWindow and Control or Control.TopLevelWindow )

	Control.Children = Control.Children or Map()
	Control.Children:Add( self, true )

	if Element and self.Background then
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

--[[
	Calls an SGUI event on every child of the object.

	Ignores children with the _CallEventsManually flag.
]]
function ControlMeta:CallOnChildren( Name, ... )
	if not self.Children then return nil end

	--Call the event on every child of this object in the order they were added.
	for Child in self.Children:Iterate() do
		if Child[ Name ] and not Child._CallEventsManually then
			local Result, Control = Child[ Name ]( Child, ... )

			if Result ~= nil then
				return Result, Control
			end
		end
	end

	return nil
end

function ControlMeta:ForEach( TableKey, MethodName, ... )
	local Objects = self[ TableKey ]
	if not Objects then return end

	for i = 1, #Objects do
		local Object = Objects[ i ]
		Object[ MethodName ]( Object, ... )
	end
end

--[[
	Add a GUIItem as a child.
]]
function ControlMeta:AddChild( GUIItem )
	if not self.Background then return end

	self.Background:AddChild( GUIItem )
end

function ControlMeta:SetLayer( Layer )
	if not self.Background then return end

	self.Background:SetLayer( Layer )
end

--[[
	Override to get child elements inheriting stencil settings from their background.
]]
function ControlMeta:SetupStencil()
	self.Background:SetInheritsParentStencilSettings( false )
	self.Background:SetStencilFunc( GUIItem.NotEqual )

	self.Stencilled = true
end

--[[
	Determines if the given control should use the global skin.
]]
function ControlMeta:SetIsSchemed( Bool )
	self.UseScheme = Bool and true or false
end

--[[
	Sets visibility of the control.
]]
function ControlMeta:SetIsVisible( Bool )
	if not self.Background then return end
	if self.Background.GetIsVisible and self.Background:GetIsVisible() == Bool then return end

	self.Background:SetIsVisible( Bool )
	self:InvalidateLayout()

	if self.IsAWindow then
		if Bool then --Take focus on show.
			if SGUI.FocusedWindow == self then return end
			local Windows = SGUI.Windows

			for i = 1, #Windows do
				local Window = Windows[ i ]

				if Window == self then
					SGUI:SetWindowFocus( self, i )
					break
				end
			end
		else --Give focus to the next window down on hide.
			if SGUI.WindowFocus ~= self then return end

			local Windows = SGUI.Windows
			local NextDown = #Windows - 1

			if NextDown > 0 then
				SGUI:SetWindowFocus( Windows[ NextDown ], NextDown )
			end
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
	if not self.Background.GetIsVisible then return false end

	return self.Background:GetIsVisible()
end

SGUI.AddProperty( ControlMeta, "Layout" )

--[[
	Sets a layout handler for the element. This will be updated every time
	a layout-changing property on the element is altered (such as size).
]]
function ControlMeta:SetLayout( Layout )
	self.Layout = Layout
	Layout:SetParent( self )
	self:InvalidateLayout( true )
end

--[[
	This event is called whenever layout is invalidated by a property change.

	By default, it updates the set layout handler.
]]
function ControlMeta:PerformLayout()
	if not self.Layout then return end

	local Margin = self.Layout:GetComputedMargin()
	local Size = self:GetSize()

	self.Layout:SetPos( Vector2( Margin[ 1 ], Margin[ 2 ] ) )
	-- Setting its size will trigger the layout's PerformLayout event.
	self.Layout:SetSize( Vector2( Size.x - Margin[ 1 ] - Margin[ 3 ],
		Size.y - Margin[ 2 ] - Margin[ 4 ] ) )
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

--[[
	Sets the size of the control (background), and invalidates the control's layout.
]]
function ControlMeta:SetSize( SizeVec )
	if not self.Background then return end

	self.Background:SetSize( SizeVec )
	self:InvalidateLayout()
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

SGUI.AddProperty( ControlMeta, "Alignment", SGUI.LayoutAlignment.MIN )
-- AutoSize controls how to resize the control during layout. You should pass a UnitVector, with
-- your dynamic units (e.g. GUIScaled, Percentage).
SGUI.AddProperty( ControlMeta, "AutoSize" )
-- Fill controls whether the element should have its size computed automatically during layout.
SGUI.AddProperty( ControlMeta, "Fill", nil, { "InvalidatesParent" } )
-- Margin controls separation of elements in layouts.
SGUI.AddProperty( ControlMeta, "Margin", nil, { "InvalidatesParent" } )
-- Padding controls the space from the element borders to where the layout may place elements.
SGUI.AddProperty( ControlMeta, "Padding", nil, { "InvalidatesLayout" } )

function ControlMeta:GetParentSize()
	return self.Parent and self.Parent:GetSize() or Vector2( SGUI.GetScreenSize() )
end

-- You can either use AutoSize as part of a layout, or on its own by passing true for UpdateNow.
function ControlMeta:SetAutoSize( AutoSize, UpdateNow )
	self.AutoSize = AutoSize
	if not UpdateNow then return end

	local ParentSize = self:GetParentSize()

	self:SetSize( Vector2( self:GetComputedSize( 1, ParentSize.x ),
		self:GetComputedSize( 2, ParentSize.y ) ) )
end

--[[
	Computes the size of the control based on the units provided.
]]
function ControlMeta:GetComputedSize( Index, ParentSize )
	-- Fill means take the size given.
	if self:GetFill() then
		return ParentSize
	end

	-- No auto-size means the element has a fixed size.
	local Size = self.AutoSize
	if not Size then
		return self:GetSize()[ Index == 1 and "x" or "y" ]
	end

	-- Auto-size means use our set auto-size units relative to the passed in size.
	return Size[ Index ]:GetValue( ParentSize, self, Index )
end

function ControlMeta:ComputeSpacing( Spacing )
	local Computed = {}

	local Parent = self.Parent
	local ParentSize = self:GetParentSize()

	for i = 1, 4 do
		Computed[ i ] = Spacing and Spacing[ i ]:GetValue( ParentSize[ i % 2 == 0 and "y" or "x" ] ) or 0
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
function ControlMeta:SetPos( Vec )
	if not self.Background then return end

	self.Background:SetPosition( Vec )
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

	--[[
		Sets the origin anchors for the control.
	]]
	function ControlMeta:SetAnchor( X, Y )
		if not self.Background then return end

		if IsType( X, "string" ) then
			local Anchor = Anchors[ X ]

			if Anchor then
				self.Background:SetAnchor( Anchor[ 1 ], Anchor[ 2 ] )
			end
		else
			self.Background:SetAnchor( X, Y )
		end
	end
end

function ControlMeta:GetAnchor()
	local X = self.Background:GetXAnchor()
	local Y = self.Background:GetYAnchor()

	return X, Y
end

do
	--We call this so many times it really needs to be local, not global.
	local MousePos

	local function GetMousePos()
		MousePos = MousePos or Client.GetCursorPosScreen
		return MousePos()
	end

	local function IsInBox( Pos, Size, Mult, MaxX, MaxY )
		if Mult then
			if IsType( Mult, "number" ) then
				Size = Size * Mult
			else
				Size.x = Size.x * Mult.x
				Size.y = Size.y * Mult.y
			end
		end

		MaxX = MaxX or Size.x
		MaxY = MaxY or Size.y

		local X, Y = GetMousePos()

		local InX = X >= Pos.x and X < Pos.x + MaxX
		local InY = Y >= Pos.y and Y < Pos.y + MaxY

		local PosX = X - Pos.x
		local PosY = Y - Pos.y

		if InX and InY then
			return true, PosX, PosY, Size, Pos
		end

		return false, PosX, PosY
	end

	--[[
		Gets whether the mouse cursor is inside the bounds of a GUIItem.
		The multiplier will increase or reduce the size we use to calculate this.

		Inputs:
			1. Element to check.
			2. Multiplier value to increase/reduce the size of the bounding box.
			3. X value to override the width of the bounding box.
			4. Y value to override the height of the bounding box.
		Outputs:
			1. Boolean value to indicate whether the mouse is inside.
			2. X position of the mouse relative to the element.
			3. Y position of the mouse relative to the element.
			4. If the mouse is inside, the size of the bounding box used.
			5. If the mouse is inside, the element's absolute screen position.
	]]
	function ControlMeta:MouseIn( Element, Mult, MaxX, MaxY )
		if not Element then return end

		local Pos = Element:GetScreenPosition( SGUI.GetScreenSize() )
		local Size = Element:GetSize()

		if Element.GetIsScaling and Element:GetIsScaling() and Element.scale then
			Size = Size * Element.scale
		end

		return IsInBox( Pos, Size, Mult, MaxX, MaxY )
	end

	--[[
		Similar to MouseIn, but uses the control's native GetScreenPos and GetSize instead
		of a GUIItem's.

		Useful for controls whose size/position does not match a GUIItem directly.
	]]
	function ControlMeta:MouseInControl( Mult, MaxX, MaxY )
		local Pos = self:GetScreenPos()
		local Size = self:GetSize()

		return IsInBox( Pos, Size, Mult, MaxX, MaxY )
	end

	function ControlMeta:MouseInCached()
		local LastCheck = self.__LastMouseInCheckFrame
		local FrameNum = SGUI.FrameNumber()

		if LastCheck ~= FrameNum then
			self.__LastMouseInCheckFrame = FrameNum

			local Pos = self:GetScreenPos()
			local Size = self:GetSize()

			local In, X, Y, Size, Pos = IsInBox( Pos, Size )
			self.__LastMouseInCheck = { In, X, Y, Size, Pos }

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

		EasingData.StartTime = Clock() + Delay
		EasingData.Duration = Duration
		EasingData.Elapsed = Max( -Delay, 0 )

		EasingData.Callback = Callback

		return EasingData
	end
end

function ControlMeta:HandleEasing( Time, DeltaTime )
	if not self.EasingProcesses or self.EasingProcesses:IsEmpty() then return end

	for EasingHandler, Easings in self.EasingProcesses:Iterate() do
		for Element, EasingData in Easings:Iterate() do
			local Start = EasingData.StartTime
			local Duration = EasingData.Duration

			EasingData.Elapsed = EasingData.Elapsed + DeltaTime

			local Elapsed = EasingData.Elapsed

			if Start <= Time then
				if Elapsed <= Duration then
					local Progress = Elapsed / Duration
					if EasingData.EaseFunc then
						Progress = EasingData.EaseFunc( Progress, EasingData.Power )
					end

					EasingData.Easer( self, Element, EasingData, Progress )
					EasingHandler.Setter( self, Element, EasingData.CurValue, EasingData )
				else
					EasingHandler.Setter( self, Element, EasingData.End, EasingData )
					Easings:Remove( Element )

					if EasingData.Callback then
						EasingData.Callback( Element )
					end
				end
			end
		end

		if Easings:IsEmpty() then
			self.EasingProcesses:Remove( EasingHandler )
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
		Easer = function( self, Element, EasingData, Progress )
			EasingData.CurValue = EasingData.Start + EasingData.Diff * Progress
			EasingData.Colour.a = EasingData.CurValue
		end,
		Setter = function( self, Element, Alpha, EasingData )
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
			self.BaseClass.OnMouseMove( self, false )
		end,
		Getter = function( self, Element )
			return Element:GetPosition()
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
		end
	}, "Size" )
}
Easers.Size.Easer = Easers.Move.Easer

function ControlMeta:GetEasing( Type, Element )
	if not self.EasingProcesses then return end

	local Easers = self.EasingProcesses:Get( Easers[ Type ] )
	if not Easers then return end

	return Easers:Get( Element or self )
end

function ControlMeta:StopEasing( Element, EasingHandler )
	if not self.EasingProcesses then return end

	local Easers = self.EasingProcesses:Get( EasingHandler )
	if not Easers then return end

	Easers:Remove( Element or self.Background )
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
	EasingData.EaseFunc = EaseFunc or math.EaseOut
	EasingData.Power = Power or 3

	return EasingData
end

function ControlMeta:StopMoving( Element )
	self:StopEasing( Element, Easers.Move )
end

local function AddEaseFunc( EasingData, EaseFunc, Power )
	EasingData.EaseFunc = EaseFunc or math.EaseOut
	EasingData.Power = Power or 3
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
	EasingData.Colour = EasingData.Element:GetColor()
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
function ControlMeta:SetHighlightOnMouseOver( Bool, Mult, TextureMode )
	self.HighlightOnMouseOver = Bool and true or false
	self.HighlightMult = Mult
	self.TextureHighlight = TextureMode

	if not Bool and not self.ForceHighlight then
		self:SetHighlighted( false, true )
		self:StopFade( self.Background )
	end
end

--[[
	Sets up a tooltip for the given element.
	This should work on any element without needing special code for it.

	Input: Text value to display as a tooltip, pass in nil to remove the tooltip.
]]
function ControlMeta:SetTooltip( Text )
	if Text == nil then
		self.TooltipText = nil

		self.OnHover = nil
		self.OnLoseHover = nil

		return
	end

	self.TooltipText = Text

	self.OnHover = self.ShowTooltip
	self.OnLoseHover = self.HideTooltip
end

local DEFAULT_HOVER_TIME = 0.5
function ControlMeta:HandleHovering( Time )
	if not self.OnHover then return end

	local MouseIn, X, Y = self:MouseIn( self.Background )

	-- If the mouse is in this object, and our window is in focus (i.e. not obstructed by a higher window)
	-- then consider the object hovered.
	if MouseIn and ( not self.TopLevelWindow or SGUI:IsWindowInFocus( self.TopLevelWindow ) ) then
		if not self.MouseHoverStart then
			self.MouseHoverStart = Time
		else
			if Time - self.MouseHoverStart > ( self.HoverTime or DEFAULT_HOVER_TIME ) and not self.MouseHovered then
				self:OnHover( X, Y )

				self.MouseHovered = true
			end
		end
	else
		self.MouseHoverStart = nil
		if self.MouseHovered then
			self.MouseHovered = nil

			if self.OnLoseHover then
				self:OnLoseHover()
			end
		end
	end
end

function ControlMeta:HandleLayout( DeltaTime )
	if self.Layout then
		self.Layout:Think( DeltaTime )
	end

	if not self.LayoutIsInvalid then return end

	self.LayoutIsInvalid = false
	self:PerformLayout()
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
end

function ControlMeta:ShowTooltip( X, Y )
	local SelfPos = self:GetScreenPos()

	X = SelfPos.x + X
	Y = SelfPos.y + Y

	local Tooltip = SGUI.IsValid( self.Tooltip ) and self.Tooltip or SGUI:Create( "Tooltip" )

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

	Tooltip:SetText( self.TooltipText, Font, TextScale )

	Y = Y - Tooltip:GetSize().y - 4

	Tooltip:SetPos( Vector2( X, Y ) )
	Tooltip:FadeIn()

	self.Tooltip = Tooltip
end

function ControlMeta:HideTooltip()
	if not SGUI.IsValid( self.Tooltip ) then return end

	self.Tooltip:FadeOut( function()
		self.Tooltip = nil
	end )
end

function ControlMeta:SetHighlighted( Highlighted, SkipAnim )
	if ( Highlighted or false ) == ( self.Highlighted or false ) then return end

	if Highlighted then
		self.Highlighted = true

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

function ControlMeta:OnMouseMove( Down )
	-- Basic highlight on mouse over handling.
	if not self.HighlightOnMouseOver then
		return
	end

	if self:GetIsVisible() and self:MouseIn( self.Background, self.HighlightMult ) then
		self:SetHighlighted( true )
	else
		if self.Highlighted and not self.ForceHighlight then
			self:SetHighlighted( false )
		end
	end
end

--[[
	Requests focus, for controls with keyboard input.
]]
function ControlMeta:RequestFocus()
	if not self.UsesKeyboardFocus then return end

	SGUI.FocusedControl = self
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
