--[[
	Shine GUI system.

	I'm sorry UWE, but I don't like your class system.
]]

Shine.GUI = Shine.GUI or {}

local CodeGen = require "shine/lib/codegen"

local SGUI = Shine.GUI
local Hook = Shine.Hook
local IsType = Shine.IsType
local UnorderedMap = Shine.UnorderedMap

local assert = assert
local getmetatable = getmetatable
local include = Script.Load
local Min = math.min
local setmetatable = setmetatable
local StringFormat = string.format
local TableRemove = table.remove
local xpcall = xpcall

SGUI.Shaders = {
	-- A shader that causes a GUIItem to be invisible, but still be able to contribute an alpha multiplier.
	Invisible = PrecacheAsset "shaders/shine/gui_none.surface_shader",
	-- A shader that can be used to add rounded corners to boxes.
	RoundedRect = PrecacheAsset "shaders/shine/gui_rounded_rect.surface_shader"
}

-- Useful functions for colours.
include "lua/shine/lib/colour.lua"

do
	local Vector = Vector

	-- A little easier than having to always include that 0 z value.
	-- The return is wrapped to avoid a tail-call which doesn't compile.
	function Vector2( X, Y )
		return ( Vector( X, Y, 0 ) )
	end
end

SGUI.GUIItemType = {
	Text = "Text",
	Graphic = "Graphic"
}

SGUI.Controls = {}
SGUI.KeyboardFocusControls = Shine.Set()
SGUI.MouseEnabledControls = {}

SGUI.ActiveControls = UnorderedMap()
SGUI.Windows = {}
SGUI.NumWindows = 0

-- Used to adjust the appearance of all elements at once.
SGUI.Skins = {}

-- Base visual layer.
SGUI.BaseLayer = 20

SGUI.ScreenHeight = {
	Small = 768,
	Normal = 1080,
	Large = 1600
}

-- Global control meta-table.
local ControlMeta = {}
SGUI.BaseControl = ControlMeta

SGUI.PropertyModifiers = {
	InvalidatesLayout = [[self:InvalidateLayout()]],
	InvalidatesLayoutNow = [[self:InvalidateLayout( true )]],
	InvalidatesParent = [[self:InvalidateParent()]],
	InvalidatesParentNow = [[self:InvalidateParent( true )]],
	InvalidatesMouseState = [[self:InvalidateMouseState()]],
	InvalidatesMouseStateNow = [[self:InvalidateMouseState( true )]]
}
do
	local DebugGetInfo = debug.getinfo
	local StringMatch = string.match
	local TableConcat = table.concat

	-- This exists to avoid constant concatenation every time properties are set dynamically.
	local SetterKeys = setmetatable( require "table.new"( 0, 100 ), {
		__index = function( self, Key )
			local Setter = "Set"..Key

			self[ Key ] = Setter

			return Setter
		end
	} )
	SGUI.SetterKeys = SetterKeys

	local function GetModifiers( Modifiers )
		local RealModifiers = {}

		for i = 1, #Modifiers do
			RealModifiers[ #RealModifiers + 1 ] = SGUI.PropertyModifiers[ Modifiers[ i ] ]
		end

		return TableConcat( RealModifiers, "\n" )
	end

	local SetterTemplate = [[return function( self, Value )
		local OldValue = self:Get{Name}()

		self.{Name} = Value

		if OldValue == Value then return false end

		self:OnPropertyChanged( "{Name}", Value )
		{Modifiers}

		return true
	end]]

	local GetterWithoutDefaultTemplate = [[return function( self )
		return self.{Name}
	end]]

	local GetterWithDefaultTemplate = [[local Default = ...
	return function( self )
		local Value = self.{Name}
		if Value == nil then
			Value = Default
		end
		return Value
	end]]

	local BaseSource = "@lua/shine/lib/gui.lua"
	local function GetCallerName()
		local Caller = DebugGetInfo( 4, "S" ).source
		return Caller and StringMatch( Caller, "/([^/]+)%.lua$" ) or "?"
	end

	local function GetSetterSource( Name )
		return StringFormat( "%s/Property/%s/Set%s", BaseSource, GetCallerName(), Name )
	end
	local function GetGetterSource( Name )
		return StringFormat( "%s/Property/%s/Get%s", BaseSource, GetCallerName(), Name )
	end

	--[[
		Adds Get and Set functions for a property name, with an optional default value.
	]]
	function SGUI.AddProperty( Table, Name, Default, Modifiers )
		local TableSetter = SetterKeys[ Name ]
		local TableGetter = "Get"..Name

		local ModifierLines = Modifiers and GetModifiers( Modifiers ) or ""
		local SetterSource = GetSetterSource( Name )
		Table[ TableSetter ] = CodeGen.GenerateTemplatedFunction( SetterTemplate, SetterSource, {
			Name = Name,
			Modifiers = ModifierLines
		} )

		local GetterSource = GetGetterSource( Name )
		if Default ~= nil then
			Table[ TableGetter ] = CodeGen.GenerateTemplatedFunction( GetterWithDefaultTemplate, GetterSource, {
				Name = Name
			}, Default )
		else
			Table[ TableGetter ] = CodeGen.GenerateTemplatedFunction( GetterWithoutDefaultTemplate, GetterSource, {
				Name = Name
			} )
		end

		return Table[ TableSetter ], Table[ TableGetter ]
	end

	local BoundCallTemplate = [[do
		local Object = self.{FieldName}
		if Object then Object:{Setter}( Value ) end
	end]]
	local AliasCallTemplate = [[self:{Setter}( Value )]]

	local StringExplode = string.Explode
	local unpack = unpack

	local function GetBindingInfo( BoundObject, PropertyName )
		if not IsType( BoundObject, "table" ) then
			BoundObject = { BoundObject }
		end

		local BoundFields = {}
		local Callbacks = {}

		for i = 1, #BoundObject do
			local Entry = BoundObject[ i ]
			if IsType( Entry, "string" ) then
				local FieldName, Setter = unpack( StringExplode( Entry, ":", true ) )
				Setter = Setter or "Set"..PropertyName

				if FieldName == "self" then
					-- Special case, aliasing another setter on the object. No control should ever have a field called
					-- 'self'.
					BoundFields[ #BoundFields + 1 ] = CodeGen.ApplyTemplateValues( AliasCallTemplate, {
						Setter = Setter
					} )
				else
					-- Pointing at a setter on a field.
					BoundFields[ #BoundFields + 1 ] = CodeGen.ApplyTemplateValues( BoundCallTemplate, {
						Setter = Setter,
						FieldName = FieldName
					} )
				end
			else
				Callbacks[ #Callbacks + 1 ] = Entry
			end
		end

		return TableConcat( BoundFields, "\n" ), Callbacks
	end

	local BoundWithoutCallbacksTemplate = [[return function( self, Value )
		local OldValue = self:Get{Name}()

		self.{Name} = Value

		{BoundFields}

		if OldValue == Value then return false end

		self:OnPropertyChanged( "{Name}", Value )
		{Modifiers}

		return true
	end]]

	local CallbacksCallTemplate = [[Callback%d( self, Value )]]

	local BoundWithCallbacksTemplate = [[local {CallbackVariables} = ...
	return function( self, Value )
		local OldValue = self:Get{Name}()

		self.{Name} = Value

		{BoundFields}

		{Callbacks}

		if OldValue == Value then return false end

		self:OnPropertyChanged( "{Name}", Value )
		{Modifiers}

		return true
	end]]

	local function BuildCallbacks( Callbacks )
		local CallbackVariables = {}
		local CallbackLines = {}
		for i = 1, #Callbacks do
			CallbackVariables[ i ] = StringFormat( "Callback%d", i )
			CallbackLines[ i ] = StringFormat( CallbacksCallTemplate, i )
		end
		return CallbackLines, CallbackVariables
	end

	--[[
		Adds Get/Set property methods that pass through the value to a field
		on the table as well as storing it.

		Used to perform actions on GUIItems without boilerplate code.
	]]
	function SGUI.AddBoundProperty( Table, Name, BoundObject, Modifiers )
		local BoundFields, Callbacks = GetBindingInfo( BoundObject, Name )

		local GetterSource = GetGetterSource( Name )
		local TableGetter = "Get"..Name
		Table[ TableGetter ] = CodeGen.GenerateTemplatedFunction( GetterWithoutDefaultTemplate, GetterSource, {
			Name = Name
		} )

		local SetterSource = GetSetterSource( Name )
		local TableSetter = SetterKeys[ Name ]
		local ModifierLines = Modifiers and GetModifiers( Modifiers ) or ""

		if #Callbacks > 0 then
			-- Unroll the loop upfront.
			local CallbackLines, CallbackVariables = BuildCallbacks( Callbacks )

			Table[ TableSetter ] = CodeGen.GenerateTemplatedFunction( BoundWithCallbacksTemplate, SetterSource, {
				Name = Name,
				BoundFields = BoundFields,
				Modifiers = ModifierLines,
				CallbackVariables = TableConcat( CallbackVariables, ", " ),
				Callbacks = TableConcat( CallbackLines, "\n" )
			}, unpack( Callbacks ) )
		else
			Table[ TableSetter ] = CodeGen.GenerateTemplatedFunction( BoundWithoutCallbacksTemplate, SetterSource, {
				Name = Name,
				BoundFields = BoundFields,
				Modifiers = ModifierLines
			} )
		end

		return Table[ TableSetter ], Table[ TableGetter ]
	end

	local CompensatedAlphaSetterTemplate = [[local Setter{CallbackVariables} = ...
	return function( self, Value )
		if not Setter( self, Value ) then return false end

		if self:ShouldAutoInheritAlpha() then
			Value = self:ApplyAlphaCompensationToChildItemColour( Value, {ParentTargetAlpha} )
		end

		{BoundFields}

		{Callbacks}

		return true
	end]]

	local function WrapColourSetterWithAlphaCompensation( FieldName, Setter, BoundObject, ParentTargetAlphaExpression )
		local BoundFields, Callbacks = GetBindingInfo( BoundObject, Name )

		ParentTargetAlphaExpression = ParentTargetAlphaExpression or "self:GetTargetAlpha()"

		local SetterSource = GetSetterSource( FieldName )
		local CallbackLines, CallbackVariables = BuildCallbacks( Callbacks )

		return CodeGen.GenerateTemplatedFunction( CompensatedAlphaSetterTemplate, SetterSource, {
			BoundFields = BoundFields,
			CallbackVariables = #CallbackVariables > 0 and ( ", "..TableConcat( CallbackVariables, ", " ) ) or "",
			Callbacks = TableConcat( CallbackLines, "\n" ),
			ParentTargetAlpha = ParentTargetAlphaExpression
		}, Setter, unpack( Callbacks ) )
	end

	--[[
		Adds a bound colour property to the given control table.

		This is a specialisation of AddBoundProperty that adds automatic support for alpha inheritance.

		The value passed through to the bound object(s) will have its alpha field altered to compensate for the parent
		element's target alpha if automatic alpha compensation is enabled.
	]]
	function SGUI.AddBoundColourProperty( Table, Name, BoundObject, Modifiers, ParentTargetAlphaExpression )
		local Setter, Getter = SGUI.AddProperty( Table, Name, nil, Modifiers )
		Setter = WrapColourSetterWithAlphaCompensation( Name, Setter, BoundObject, ParentTargetAlphaExpression )
		Table[ SetterKeys[ Name ] ] = Setter
		return Setter, Getter
	end
end

do
	local WideStringToString

	function SGUI.GetChar( Char )
		WideStringToString = WideStringToString or ConvertWideStringToString
		return WideStringToString( Char )
	end
end

function SGUI.IsApproximatelyGreaterEqual( Left, Right )
	-- Account for tiny floating point errors.
	return Left >= Right - 1e-4
end

do
	local Wrapping = require "shine/lib/gui/util/wrapping"

	-- For backwards compatibility, export word wrapping under SGUI.
	SGUI.WordWrap = Wrapping.WordWrap
end

function SGUI.TenEightyPScale( Value )
	return math.scaledown( Value, 1080, 1280 ) * ( 2 - ( 1080 / 1280 ) )
end

function SGUI.LinearScale( Value )
	return Min( SGUI.GetScreenSize() ) / 1080 * Value
end

function SGUI.LinearScaleByScreenHeight( Value )
	local W, H = SGUI.GetScreenSize()
	return H / 1080 * Value
end

SGUI.SpecialKeyStates = {
	Ctrl = false,
	Alt = false,
	Shift = false
}

Hook.Add( "PlayerKeyPress", "SGUICtrlMonitor", function( Key, Down )
	if SGUI.IsControlKey( Key ) then
		SGUI.SpecialKeyStates.Ctrl = Down or false
	elseif Key == InputKey.LeftAlt then
		SGUI.SpecialKeyStates.Alt = Down or false
	elseif SGUI.IsShiftKey( Key ) then
		SGUI.SpecialKeyStates.Shift = Down or false
	end
end, Hook.MAX_PRIORITY )

function SGUI.IsShiftKey( Key )
	return Key == InputKey.LeftShift or Key == InputKey.RightShift
end
function SGUI.IsControlKey( Key )
	return Key == InputKey.LeftControl or Key == InputKey.RightControl
end

function SGUI:IsControlDown()
	return self.SpecialKeyStates.Ctrl
end

function SGUI:IsAltDown()
	return self.SpecialKeyStates.Alt
end

function SGUI:IsShiftDown()
	return self.SpecialKeyStates.Shift
end

do
	local ClipboardText = ""

	function SGUI.GetClipboardText()
		return ClipboardText
	end

	function SGUI.SetClipboardText( Text )
		ClipboardText = Text
	end
end

do
	local function RefreshFocusedWindow( self, FocusedWindow )
		local Windows = self.Windows
		for i = 1, self.NumWindows do
			local Window = Windows[ i ]
			Windows[ Window ] = i
			Window:SetLayer( Window.OverrideLayer or self.BaseLayer + i )
		end

		local NewWindowIsValid = self.IsValid( FocusedWindow )
		if NewWindowIsValid then
			-- Let the window refresh its mouse state to reflect the new hierarchy. This will recursively invalidate
			-- down the window stack. This is done after updating the index lookup above to ensure window order is
			-- correct.
			FocusedWindow:InvalidateMouseState( true )
		end

		if FocusedWindow ~= self.FocusedWindow then
			if self.IsValid( self.FocusedWindow ) and self.FocusedWindow.OnLoseWindowFocus then
				self.FocusedWindow:OnLoseWindowFocus( FocusedWindow )
			end

			if NewWindowIsValid and FocusedWindow.OnGainWindowFocus then
				FocusedWindow:OnGainWindowFocus()
			end
		end

		self.FocusedWindow = FocusedWindow
	end

	--[[
		Sets the current in-focus window.
		Inputs: Window object, windows index.
	]]
	function SGUI:SetWindowFocus( FocusedWindow )
		if FocusedWindow == self.FocusedWindow then return end

		local Index = self.Windows[ FocusedWindow ]
		if not Index then return end

		TableRemove( self.Windows, Index )
		self.Windows[ self.NumWindows ] = FocusedWindow

		RefreshFocusedWindow( self, FocusedWindow )
	end

	function SGUI:FocusNextWindowDown()
		local Index = self.Windows[ self.FocusedWindow ]
		if not Index then return end

		for i = Index - 1, 1, -1 do
			local Window = self.Windows[ i ]
			if Window:GetIsVisible() then
				self:SetWindowFocus( Window )
				break
			end
		end
	end

	function SGUI:AddWindow( Window )
		if self.Windows[ Window ] then return end

		self.NumWindows = self.NumWindows + 1
		self.Windows[ self.NumWindows ] = Window
		self.Windows[ Window ] = self.NumWindows
	end

	function SGUI:RemoveWindow( Window )
		local Index = self.Windows[ Window ]
		if not Index then return end

		self.Windows[ Window ] = nil
		TableRemove( self.Windows, Index )
		self.NumWindows = self.NumWindows - 1

		RefreshFocusedWindow( self, self.Windows[ self.NumWindows ] )
	end

	function SGUI:MoveWindowToBottom( Window )
		local Windows = self.Windows
		local Index = Windows[ Window ] or ( self.NumWindows + 1 )
		for i = Index, 1, -1 do
			Windows[ i ] = Windows[ i - 1 ]
		end
		Windows[ 1 ] = Window

		self.NumWindows = #Windows

		RefreshFocusedWindow( self, Windows[ self.NumWindows ] )
	end

	function SGUI:IsWindow( Window )
		return self.Windows[ Window ] ~= nil
	end

	function SGUI:FindMatchingWindow( Predicate )
		for i = 1, self.NumWindows do
			local Window = self.Windows[ i ]
			if Predicate( Window ) then return true, Window end
		end
		return false
	end

	function SGUI:ForEachWindowBelow( Window, Action, Context )
		local Index = self.Windows[ Window ]
		if not Index then return end

		for i = Index - 1, 1, -1 do
			Action( self.Windows[ i ], Context )
		end
	end

	local function IsMouseWithinWindow( Window )
		-- In focus if the mouse is currently within it and the window is visible and focusable.
		return Window:GetIsVisible() and not Window.IgnoreMouseFocus and
			( Window.AlwaysInMouseFocus or Window:HasMouseEntered() )
	end

	local function IsWindowCapturingMouse( Window )
		-- Must be blocking mouse events to be considered capturing, otherwise lower windows can still see mouse
		-- movement.
		return ( Window.GetBlockEventsIfFocusedWindow and Window:GetBlockEventsIfFocusedWindow() ) and
			IsMouseWithinWindow( Window )
	end

	--[[
		Indicates whether the given window has been obstructed by another window (i.e. if a higher window has captured
		the mouse).
	]]
	function SGUI:IsWindowFocusObstructed( Window )
		local Windows = self.Windows
		local Index = Windows[ Window ]
		if not Index then return true end

		for i = self.NumWindows, Index + 1, -1 do
			local OtherWindow = Windows[ i ]
			if IsWindowCapturingMouse( OtherWindow ) then
				-- A higher window has captured the mouse, so the target window is obstructed.
				return true
			end
		end

		-- Reached the target window without any higher window having captured the mouse, not obstructed.
		return false
	end

	--[[
		Indicates whether the given window is currently in focus (i.e. its the top window, or its a lower window that
		is not covered by a higher window and it currently contains the mouse cursor).
	]]
	function SGUI:IsWindowInFocus( Window )
		if Window == self.FocusedWindow then return true end
		return not self:IsWindowFocusObstructed( Window ) and IsMouseWithinWindow( Window )
	end

	function SGUI:IsMouseInVisibleWindow()
		local Windows = self.Windows
		for i = self.NumWindows, 1, -1 do
			local Window = Windows[ i ]
			if IsWindowCapturingMouse( Window ) then
				return true
			end
		end
		return false
	end
end

local OnError = Shine.BuildErrorHandler( "SGUI Error" )

SGUI.PostEventActions = {}

function SGUI:PostCallEvent( Result, Control )
	self.CallingEvent = nil

	local PostEventActions = self.PostEventActions
	for i = 1, #PostEventActions do
		xpcall( PostEventActions[ i ], OnError, Result, Control )
		PostEventActions[ i ] = nil
	end
end

function SGUI:AddPostEventAction( Action )
	self.PostEventActions[ #self.PostEventActions + 1 ] = Action
end

do
	local select = select

	local Callers = CodeGen.MakeFunctionGenerator( {
		Template = [[local OnError, xpcall = ...
			return function( self, FocusChange, Name{Arguments} )
				local Windows = self.Windows
				local WindowCount = self.NumWindows

				self.CallingEvent = Name

				-- The focused window is the last in the list, so we call backwards.
				for i = WindowCount, 1, -1 do
					local Window = Windows[ i ]

					if Window and Window[ Name ] and Window:GetIsVisible() then
						local Success, Result, Control = xpcall( Window[ Name ], OnError, Window{Arguments} )

						if Success then
							if Result ~= nil then
								if i ~= WindowCount and FocusChange and self.IsValid( Window ) then
									self:SetWindowFocus( Window )
								end

								self:PostCallEvent( Result, Control )

								return Result, Control
							end
						else
							Window:Destroy()
						end
					end
				end

				self:PostCallEvent()
			end
		]],
		ChunkName = "@lua/shine/lib/gui.lua/SGUI:CallEvent",
		InitialSize = 2,
		Args = { OnError, xpcall }
	} )

	--[[
		Passes an event to all active SGUI windows.

		If an SGUI object is classed as a window, it MUST call all events on its children.
		Then its children must call their events on their children and so on.

		Inputs: Event name, arguments.
	]]
	function SGUI:CallEvent( FocusChange, Name, ... )
		return Callers[ select( "#", ... ) ]( self, FocusChange, Name, ... )
	end
end

do
	SGUI.MouseObjects = 0

	local IsCommander
	local ShowMouse

	--[[
		Allow for multiple windows to "enable" the mouse, without
		disabling it after one closes.
	]]
	function SGUI:EnableMouse( Enable, Control )
		if not ShowMouse then
			ShowMouse = MouseTracker_SetIsVisible
			IsCommander = CommanderUI_IsLocalPlayerCommander
		end

		if Enable then
			if Control and self.MouseEnabledControls[ Control ] then
				return
			end

			self.MouseObjects = self.MouseObjects + 1

			if self.MouseObjects == 1 then
				if not ( IsCommander and IsCommander() ) then
					ShowMouse( true )
					self.EnabledMouse = true
				end
			end

			if Control then
				self.MouseEnabledControls[ Control ] = true
			end

			return
		end

		if Control then
			if not self.MouseEnabledControls[ Control ] then return end

			self.MouseEnabledControls[ Control ] = nil
		end

		if self.MouseObjects <= 0 then return end

		self.MouseObjects = self.MouseObjects - 1

		if self.MouseObjects == 0 then
			if not ( IsCommander and IsCommander() ) or self.EnabledMouse then
				ShowMouse( false )
				self.EnabledMouse = false
			end
		end
	end
end

SGUI.Mixins = {}

function SGUI:RegisterMixin( Name, Table )
	self.Mixins[ Name ] = Table
end

do
	local TableShallowMerge = table.ShallowMerge

	function SGUI:AddMixin( Table, Name )
		local Mixin = self.Mixins[ Name ]

		TableShallowMerge( Mixin, Table )

		Table.Mixins = Table.Mixins or {}
		Table.Mixins[ Name ] = Mixin
	end
end

do
	local ControlTypesWaitingForParent = Shine.Multimap()
	local InheritFromBaseControl = {
		__index = ControlMeta
	}

	local function AfterParentSet( Table )
		-- This exists for backwards compatibility reasons. The base control Think doesn't call Think on its children,
		-- so changing that would end up calling Think twice on any control that had previously implemented it.
		if Table.Think == ControlMeta.Think then
			Table.Think = ControlMeta.ThinkWithChildren
		end

		Table.__tostring = Table.__tostring or ControlMeta.__tostring
	end

	local function SetupControlType( self, Name, Table, Parent )
		Table.__index = Table
		Table.__Name = Name

		if Parent then
			Table.ParentControl = Parent

			local ParentTable = IsType( Parent, "table" ) and Parent or self.Controls[ Parent ]
			if ParentTable and ParentTable.ParentControl == Name then
				error( StringFormat( "[SGUI] Cyclic dependency detected. %s depends on %s while %s also depends on %s.",
					Name, Parent, Parent, Name ) )
			end

			if not ParentTable then
				-- Parent is not yet registered, queue the control table to have inheritance setup when it is.
				ControlTypesWaitingForParent:Add( Parent, Table )
				-- In case the parent is never registered, assign the base type now.
				setmetatable( Table, InheritFromBaseControl )
			else
				-- Parent is available, inherit values now.
				setmetatable( Table, {
					__index = ParentTable
				} )
				AfterParentSet( Table )
			end
		else
			-- No parent means only look in its meta-table and the base meta-table.
			setmetatable( Table, InheritFromBaseControl )
			AfterParentSet( Table )
		end

		-- Used to call base class functions for things like :MoveTo()
		Table.BaseClass = ControlMeta
	end

	--[[
		Defines a new control type but does not register it.

		This can be useful for specific components that have little re-use value.

		Inputs:
			1. Control name (does not have to be unique as it is not registered).
			2. The parent name (taken from registered controls) or table.
		Output:
			A new control definition that can be passed into SGUI:CreateFromDefinition().
	]]
	function SGUI:DefineControl( Name, Parent )
		local Table = {}
		SetupControlType( self, Name, Table, Parent )
		return Table
	end

	--[[
		Registers a control meta-table.
		We'll use this to create instances of it (instead of loading a script
		file every time like UWE).

		Inputs:
			1. Control name
			2. Control meta-table.
			3. Optional parent name. This will make the object inherit the parent's table keys.
	]]
	function SGUI:Register( Name, Table, Parent )
		SetupControlType( self, Name, Table, Parent )

		self.Controls[ Name ] = Table

		local ChildTypes = ControlTypesWaitingForParent:Get( Name )
		if ChildTypes then
			-- Some child types were waiting for this parent type, so assign their
			-- parent now to this type.
			local InheritFromParent = {
				__index = Table
			}
			for i = 1, #ChildTypes do
				setmetatable( ChildTypes[ i ], InheritFromParent )
				AfterParentSet( ChildTypes[ i ] )
			end

			ControlTypesWaitingForParent:Remove( Name )
		end

		Hook.Broadcast( "OnSGUIControlRegistered", Name, Table, Parent )
	end

	function SGUI:RegisterAlias( Name, AliasName )
		if self.Controls[ Name ] then
			self.Controls[ AliasName ] = self.Controls[ Name ]
			return
		end

		local Key = StringFormat( "RegisterAlias: %s -> %s", Name, AliasName )
		Hook.Add( "OnSGUIControlRegistered", Key, function( RegisteredName, Table )
			if RegisteredName == Name then
				Hook.Remove( "OnSGUIControlRegistered", Key )
				self.Controls[ AliasName ] = Table
			end
		end )
	end
end

--[[
	Destroys a classic GUI script.
	Input: GUIItem script.
]]
function SGUI.DestroyScript( Script )
	return GetGUIManager():DestroyGUIScript( Script )
end

do
	local ID = 0

	local function MakeControl( self, MetaTable, Class, Parent, ParentElement )
		ID = ID + 1

		local Table = {}
		local IsWindow = MetaTable.IsWindow and not Parent and true or false

		local Control = setmetatable( Table, MetaTable )
		Control.Class = Class
		Control.ID = ID
		Control.IsAWindow = IsWindow
		if IsWindow then
			-- Add before initialise so the control is marked as a window, and thus any children
			-- have their TopLevelWindow assigned.
			self:AddWindow( Control )
		end

		Control:Initialise()

		if IsWindow then
			self:SetWindowFocus( Control )
		end

		self.ActiveControls:Add( Control, true )
		self.SkinManager:ApplySkin( Control )

		if Control.UsesKeyboardFocus and Control.OnFocusChange then
			self.KeyboardFocusControls:Add( Control )
		end

		if Parent then
			Control:SetParent( Parent, ParentElement )
		end

		return Control
	end

	--[[
		Creates an SGUI control directly from a given definition table.
		Inputs:
			1. SGUI control definition table.
			2. Optional parent object.
			3. Optional parent GUIItem.
		Output:
			SGUI control object.
	]]
	function SGUI:CreateFromDefinition( Definition, Parent, ParentElement )
		Shine.AssertAtLevel( Shine.IsAssignableTo( Definition, ControlMeta ), "Definition must be an SGUI control!", 3 )

		return MakeControl( self, Definition, Definition.__Name, Parent, ParentElement )
	end

	--[[
		Creates an SGUI control.
		Input: SGUI control class name, optional parent object.
		Output: SGUI control object.
	]]
	function SGUI:Create( Class, Parent, ParentElement )
		if IsType( Class, "table" ) then
			return self:CreateFromDefinition( Class, Parent, ParentElement )
		end

		local MetaTable = self.Controls[ Class ]
		Shine.AssertAtLevel( MetaTable, "[SGUI] '%s' is not a registered SGUI class!", 3, Class )

		return MakeControl( self, MetaTable, Class, Parent, ParentElement )
	end

	local Binder = require "shine/lib/gui/binding/binder"
	local TableAdd = table.Add

	local function ShouldAddToLayout( ElementDef )
		return not ( ElementDef.Props and ElementDef.Props.PositionType == SGUI.PositionType.ABSOLUTE )
	end

	local function DeferBinding( Element, Binding, DeferredBindings )
		DeferredBindings[ #DeferredBindings + 1 ] = {
			Element = Element,
			Binding = Binding
		}
	end

	local function SetupBinder( Element, Binding, From, To )
		local Builder = Binder()
		Builder:WithReducer( Binding.Reducer )
		Builder:WithInitialState( Binding.InitialState )

		if #To == 0 then
			Builder:ToElement( Element, To.Property, To )
		else
			for j = 1, #To do
				Builder:ToElement( Element, To[ j ].Property, To[ j ] )
			end
		end

		return Builder
	end

	local function ProcessBindings( Element, Bindings, DeferredBindings )
		for i = 1, #Bindings do
			local Binding = Bindings[ i ]
			local From = Binding.From
			local To = Binding.To

			local Builder = SetupBinder( Element, Binding, From, To )
			if #From == 0 then
				if IsType( From.Element, "string" ) then
					-- Referring to another element in the tree, wait for the entire tree to be created before binding.
					DeferBinding( Element, Binding, DeferredBindings )
				else
					Builder:FromElement( From.Element, From.Property )
					Builder:BindProperty()
				end
			else
				local Deferred = false
				for j = 1, #From do
					local Source = From[ j ]
					if IsType( Source.Element, "string" ) then
						Deferred = true
						DeferBinding( Element, Binding, DeferredBindings )
						break
					end
					Builder:FromElement( Source.Element, Source.Property )
				end

				if not Deferred then
					Builder:BindProperties()
				end
			end
		end
	end

	local function ProcessPropertyChangeListeners( Element, Listeners )
		for i = 1, #Listeners do
			Element:AddPropertyChangeListener( Listeners[ i ].Property, Listeners[ i ].Listener )
		end
	end

	local ElementFactories = {
		Layout = function( ElementDef, Parent )
			local Element = SGUI.Layout:CreateLayout( ElementDef.Class )

			if Parent.IsLayout then
				Parent:AddElement( Element )
			elseif Parent.Layout then
				Parent.Layout:AddElement( Element )
			else
				Parent:SetLayout( Element, true )
			end

			return Element
		end,

		Control = function( ElementDef, Parent )
			local Element

			if Parent then
				if Parent.IsLayout then
					Element = SGUI:Create( ElementDef.Class, Parent:GetParentControl() )
					Parent:AddElement( Element )
				else
					Element = Parent.Add and Parent:Add( ElementDef.Class ) or SGUI:Create( ElementDef.Class, Parent )
					if Parent.Layout and ShouldAddToLayout( ElementDef ) then
						Parent.Layout:AddElement( Element )
					end
				end
			else
				Element = SGUI:Create( ElementDef.Class )
			end

			return Element
		end
	}

	local function ShouldAddElement( ElementDef )
		-- Elements can define a condition, either as a plain boolean or a method. This makes it easier to conditionally
		-- add elements in the middle of a list of children.
		return ElementDef.If ~= false and not ( Shine.IsCallable( ElementDef.If ) and not ElementDef:If() )
	end

	local function BuildChildren( Context, Parent, Tree, GlobalProps, Level )
		local DeferredBindings = Context.DeferredBindings
		local Elements = Context.Elements

		for i = 1, #Tree do
			local ElementDef = Tree[ i ]
			if ShouldAddElement( ElementDef ) then
				local FactoryFunc = ElementFactories[ ElementDef.Type or "Control" ]
				Shine.AssertAtLevel( FactoryFunc, "Unknown element type in tree: %s", 4 + Level, ElementDef.Type )

				local Element = FactoryFunc( ElementDef, Parent )

				if GlobalProps then
					Element:SetupFromTable( GlobalProps )
				end

				if ElementDef.Props then
					Element:SetupFromTable( ElementDef.Props )
				end

				if ElementDef.ID then
					Elements[ ElementDef.ID ] = Element
				end

				if ElementDef.Bindings then
					ProcessBindings( Element, ElementDef.Bindings, DeferredBindings )
				end

				if ElementDef.PropertyChangeListeners then
					ProcessPropertyChangeListeners( Element, ElementDef.PropertyChangeListeners )
				end

				if ElementDef.Children then
					BuildChildren( Context, Element, ElementDef.Children, GlobalProps, Level + 1 )
				end

				if Shine.IsCallable( ElementDef.OnBuilt ) then
					ElementDef:OnBuilt( Element, Elements )
				end
			end
		end
	end

	local function ProcessDeferredBindings( Elements, DeferredBindings )
		for i = 1, #DeferredBindings do
			local Params = DeferredBindings[ i ]

			local Element = Params.Element
			local Binding = Params.Binding
			local From = Binding.From
			local To = Binding.To

			local Builder = SetupBinder( Element, Binding, From, To )
			if #From == 0 then
				local FromElement = Elements[ From.Element ]
				Shine.AssertAtLevel(
					FromElement,
					"Binding specified source element '%s' but it does not exist in the tree. Did you forget to assign an ID to it?",
					4,
					From.Element
				)
				Builder:FromElement( FromElement, From.Property )
				Builder:BindProperty()
			else
				for j = 1, #From do
					local Source = From[ j ]
					local FromElement = Source.Element
					if IsType( FromElement, "string" ) then
						FromElement = Elements[ From.Element ]
						Shine.AssertAtLevel(
							FromElement,
							"Binding specified source element '%s' but it does not exist in the tree. Did you forget to assign an ID to it?",
							4,
							Source.Element
						)
					end
					Builder:FromElement( FromElement, Source.Property )
				end
				Builder:BindProperties()
			end
		end
	end

	local function CallOnBuiltCallbacks( Elements, Callbacks )
		if IsType( Callbacks, "function" ) then
			Callbacks( Elements )
		else
			for i = 1, #Callacks do
				Callbacks[ i ]( Elements )
			end
		end
	end

	--[[
		Takes a table that defines an element tree, and creates all elements.

		Elements may be given an ID, in which case they will be present in the returned table under that ID.

		Input:
			A table containing element definitions.
		Output:
			A table with all elements that were assigned an ID.
	]]
	function SGUI:BuildTree( Tree )
		local Context = {
			Elements = {},
			DeferredBindings = {}
		}

		BuildChildren( Context, Tree.Parent, Tree, Tree.GlobalProps, 0 )
		ProcessDeferredBindings( Context.Elements, Context.DeferredBindings )

		if Tree.OnBuilt then
			CallOnBuiltCallbacks( Context.Elements, Tree.OnBuilt )
		end

		return Context.Elements
	end
end

do
	local DebugGetInfo = debug.getinfo
	local rawget = rawget
	local ValidityKey = "IsValid"
	local function CheckDestroyed( self, Key )
		local Destroyed = rawget( self, "__Destroyed" )
		if Destroyed and Key ~= ValidityKey and Key ~= "DebugName" and Destroyed < SGUI.FrameNumber() then
			local Caller = DebugGetInfo( 2, "f" ).func
			-- Allow access in __tostring(), otherwise the element can't be printed.
			if Caller ~= getmetatable( self ).__tostring then
				error( "Attempted to use a destroyed SGUI object!", 3 )
			end
		end

		return rawget( self, "__OriginalIndex" )[ Key ]
	end

	local OnCallOnRemoveError = Shine.BuildErrorHandler( "SGUI CallOnRemove callback error" )
	local DestructionAction = Shine.TypeDef()
	function DestructionAction:Init( Control )
		self.Control = Control
		return self
	end

	function DestructionAction:__call()
		if SGUI.IsValid( self.Control ) then
			self.Control:Destroy()
		end
	end

	--[[
		Destroys an SGUI control.

		This runs the control's cleanup function. Do not attempt to use the object again.

		Input: SGUI control object.
	]]
	function SGUI:Destroy( Control )
		-- Remove the control from its parent immediately regardless of the running event. This avoids it showing
		-- up in child iterations.
		if Control.Parent then
			Control:SetParent( nil )
		end

		if Control.LayoutParent then
			Control.LayoutParent:RemoveElement( Control )
		end

		if self.CallingEvent then
			-- Wait until after the running event to destroy the control. This avoids needing loads of validity checks
			-- in event code paths.
			self:AddPostEventAction( DestructionAction( Control ) )
			return
		end

		self.ActiveControls:Remove( Control )
		self.KeyboardFocusControls:Remove( Control )

		if self.MouseEnabledControls[ Control ] then
			SGUI:EnableMouse( false, Control )
		end

		if self.IsValid( Control.Tooltip ) then
			Control.Tooltip:Destroy()
		end

		if Control.Children then
			for Control in Control.Children:Iterate() do
				Control:Destroy()
			end
		end

		local DeleteOnRemove = Control.__DeleteOnRemove
		if DeleteOnRemove then
			for i = 1, #DeleteOnRemove do
				if self.IsValid( DeleteOnRemove[ i ] ) then
					DeleteOnRemove[ i ]:Destroy()
				end
			end
		end

		local CallOnRemove = Control.__CallOnRemove
		if CallOnRemove then
			for i = 1, #CallOnRemove do
				-- Important to avoid errors here, otherwise the control will be left
				-- in an inconsistent state.
				xpcall( CallOnRemove[ i ], OnCallOnRemoveError, Control )
			end
		end

		self:RemoveWindow( Control )

		Control:Cleanup()

		-- Re-assign the metatable to ensure usage causes an error next frame.
		-- This avoids needing to check for validity constantly on every field access
		-- while a control is still valid.
		local OldMetatable = getmetatable( Control )
		Control.__OriginalIndex = OldMetatable.__index
		Control.__Destroyed = SGUI.FrameNumber()
		setmetatable( Control, {
			__index = CheckDestroyed,
			__tostring = OldMetatable.__tostring
		} )
	end
end

--[[
	Combines a nil and validity check into one.

	Input: SGUI control to check for existence and validity.
	Output: Existence and validity.
]]
function SGUI.IsValid( Control )
	return Control and Control.IsValid and Control:IsValid() or false
end

do
	local FrameNumber = 0
	function SGUI.FrameNumber()
		return FrameNumber
	end

	Hook.Add( "Think", "UpdateSGUI", function( DeltaTime )
		FrameNumber = FrameNumber + 1
		SGUI:CallEvent( false, "Think", DeltaTime )
	end )
end

-- Clock used for high-precision tasks such as animations.
SGUI.GetTime = Shared.GetSystemTimeReal

Hook.Add( "PlayerKeyPress", "UpdateSGUI", function( Key, Down )
	if SGUI:CallEvent( false, "PlayerKeyPress", Key, Down ) then
		return true
	end
end )

Hook.Add( "PlayerType", "UpdateSGUI", function( Char )
	if SGUI:CallEvent( false, "PlayerType", SGUI.GetChar( Char ) ) then
		return true
	end
end )

local function NotifyFocusChange( Element, ClickingOtherElement )
	SGUI.FocusedControl = Element

	for Control in SGUI.KeyboardFocusControls:Iterate() do
		Control:OnFocusChange( Element, ClickingOtherElement )
	end
end
SGUI.NotifyFocusChange = NotifyFocusChange

local GetCursorPos = MouseTracker_GetCursorPos
function SGUI.GetCursorPos()
	local Pos = GetCursorPos()
	return Pos.x, Pos.y
end

local GetMouseVisible = MouseTracker_GetIsVisible
function SGUI.IsMouseVisible()
	return GetMouseVisible()
end

local ScrW = Client.GetScreenWidth
local ScrH = Client.GetScreenHeight

function SGUI.GetScreenSize()
	return ScrW(), ScrH()
end

function SGUI.IsHighRes()
	return Min( SGUI.GetScreenSize() ) > 1080
end

local CreateItem = GUI.CreateItem
local function CreateGUIItem()
	local Item = CreateItem()
	assert( Item and Item.isa and Item:isa( "GUIItem" ), "Failed to create new GUIItem!" )
	return Item
end
SGUI.CreateGUIItem = CreateGUIItem

function SGUI.CreateTextGUIItem()
	local Item = CreateGUIItem()
	Item:SetOptionFlag( GUIItem.ManageRender )
	return Item
end

local function SetupRenderDeviceResetCheck()
	local GetLastPresentTime = Client.GetLastPresentTime
	local GetLastRenderResetTime = Client.GetLastRenderResetTime

	local LastSeenRenderResetTime = GetLastRenderResetTime()
	local LastPresentTime

	local STATE_RENDERING = 1
	local STATE_RESETTING = 2

	local State = STATE_RENDERING

	local SharedTime = Shared.GetTime

	local function HasRenderDeviceReset()
		local ResetTime = GetLastRenderResetTime()
		if ResetTime > LastSeenRenderResetTime then
			LastSeenRenderResetTime = ResetTime
			return true
		end
		return false
	end

	-- This should have really been done in the engine...
	Hook.Add( "Think", "CheckRenderDevice", function()
		if HasRenderDeviceReset() then
			LastPresentTime = SharedTime()
			State = STATE_RESETTING
		end

		if State == STATE_RENDERING then return end

		local PresentingTime = GetLastPresentTime()
		if PresentingTime > LastPresentTime then
			LastPresentTime = PresentingTime
			State = STATE_RENDERING

			-- Notify anything that may need to re-render itself after a render device reset.
			Hook.Broadcast( "OnRenderDeviceReset" )
		end
	end )

	Shine:RegisterClientCommand( "sh_sgui_simulate_render_reset", function()
		if not Shared.GetDevMode() then return end

		Hook.Broadcast( "OnRenderDeviceReset" )
	end )
end

local IsMainMenuOpen = MainMenu_GetIsOpened

--[[
	If we don't load after everything, things aren't registered properly.
]]
Hook.Add( "OnMapLoad", "LoadGUIElements", function()
	CreateItem = GUI.CreateItem
	ScrW = Client.GetScreenWidth
	ScrH = Client.GetScreenHeight
	IsMainMenuOpen = MainMenu_GetIsOpened

	if IsType( GetLayerConstant, "function" ) then
		-- Make sure SGUI renders above the top bar HUD (for whatever reason, this was put way above the rest of the
		-- HUD...)
		SGUI.BaseLayer = GetLayerConstant( "Hud_TopBar", 500 ) + 1
	end

	Shine.LoadScriptsByPath( "lua/shine/lib/gui/objects" )
	include( "lua/shine/lib/gui/skin_manager.lua" )

	Hook.SetupGlobalHook( "Client.SetMouseVisible", "OnMouseVisibilityChange", "PassivePost" )

	SetupRenderDeviceResetCheck()

	Hook.Broadcast( "OnSGUILoaded" )
end, Hook.MAX_PRIORITY )

Hook.CallAfterFileLoad( "lua/Commander_Client.lua", function()
	local GetMouseIsOverUI = CommanderUI_GetMouseIsOverUI
	if GetMouseIsOverUI then
		function CommanderUI_GetMouseIsOverUI()
			if SGUI:IsMouseInVisibleWindow() then
				return true
			end
			return GetMouseIsOverUI()
		end
	end
end )

Hook.CallAfterFileLoad( "lua/menu/MouseTracker.lua", function()
	GetCursorPos = MouseTracker_GetCursorPos
	GetMouseVisible = MouseTracker_GetIsVisible

	local function NotifyMouseLossToRelevantWindows( Window, LMB )
		local Windows = SGUI.Windows
		local Index = Windows[ Window ]
		if not Index then return end

		for i = Index - 1, 1, -1 do
			local OtherWindow = Windows[ i ]
			if OtherWindow:HasMouseEntered() then
				-- Window had previously seen the mouse enter, but is now obstructed. Notify it so it can clean up its
				-- mouse state. This should always result in the window setting its mouse state to false as mouse
				-- checks in windows require the mouse to not be obstructed by another window.
				if not xpcall( OtherWindow.OnMouseMove, OnError, OtherWindow, LMB ) then
					OtherWindow:Destroy()
				end
			end
		end
	end

	local Listener = {
		OnMouseMove = function( _, LMB )
			local Blocked, Window = SGUI:CallEvent( false, "OnMouseMove", LMB )
			if Blocked and SGUI:IsWindow( Window ) then
				-- Window captured the mouse movement, make sure any other windows below the blocking window get
				-- notified that they've lost the mouse.
				NotifyMouseLossToRelevantWindows( Window, LMB )
			end

			local MouseDownControl = SGUI.MouseDownControl
			if
				SGUI.IsValid( MouseDownControl ) and
				MouseDownControl.__LastMouseMove ~= SGUI.FrameNumber()
			then
				-- Make sure the focused control still sees mouse movements until releasing the mouse button.
				xpcall( MouseDownControl.OnMouseMove, OnError, MouseDownControl, LMB )
			end
		end,
		OnMouseWheel = function( _, Down )
			if IsMainMenuOpen() then return end

			return SGUI:CallEvent( false, "OnMouseWheel", Down )
		end,
		OnMouseDown = function( _, Key, DoubleClick )
			-- Main menu receives mouse events after mouse tracker, so need to manually check for it here.
			if IsMainMenuOpen() then return end

			local Result, Control = SGUI:CallEvent( true, "OnMouseDown", Key, DoubleClick )

			if Result and Control then
				if not Control.UsesKeyboardFocus then
					NotifyFocusChange( nil, true )
				end

				if Control.OnMouseUp then
					SGUI.MouseDownControl = Control
				end
			end

			return Result
		end,
		OnMouseUp = function( _, Key )
			local Control = SGUI.MouseDownControl
			if not SGUI.IsValid( Control ) then return end

			local Success, Result = xpcall( Control.OnMouseUp, OnError, Control, Key )

			SGUI.MouseDownControl = nil

			return Result
		end
	}

	MouseTracker_ListenToMovement( Listener )
	MouseTracker_ListenToButtons( Listener )
	MouseTracker_ListenToWheel( Listener )
end )

include( "lua/shine/lib/gui/base_control.lua" )
include( "lua/shine/lib/gui/font_manager.lua" )
include( "lua/shine/lib/gui/layout/layout.lua" )
include( "lua/shine/lib/gui/notification_manager.lua" )
Shine.LoadScriptsByPath( "lua/shine/lib/gui/mixins" )
