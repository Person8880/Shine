--[[
	Shine GUI system.

	I'm sorry UWE, but I don't like your class system.
]]

Shine.GUI = Shine.GUI or {}

local SGUI = Shine.GUI
local Hook = Shine.Hook
local IsType = Shine.IsType
local Map = Shine.Map

local getmetatable = getmetatable
local include = Script.Load
local Min = math.min
local setmetatable = setmetatable
local StringFormat = string.format
local TableInsert = table.insert
local TableRemove = table.remove
local xpcall = xpcall

-- Useful functions for colours.
include "lua/shine/lib/colour.lua"

do
	local Vector = Vector

	-- A little easier than having to always include that 0 z value.
	function Vector2( X, Y )
		return Vector( X, Y, 0 )
	end
end

SGUI.GUIItemType = {
	Text = "Text",
	Graphic = "Graphic"
}

SGUI.Controls = {}
SGUI.KeyboardFocusControls = Shine.Set()

SGUI.ActiveControls = Map()
SGUI.Windows = {}

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
	InvalidatesLayout = function( self, Value )
		self:InvalidateLayout()
	end,
	InvalidatesLayoutNow = function( self, Value )
		self:InvalidateLayout( true )
	end,
	InvalidatesParent = function( self, Value )
		self:InvalidateParent()
	end,
	InvalidatesParentNow = function( self, Value )
		self:InvalidateParent( true )
	end
}
do
	local function GetModifiers( Modifiers )
		local RealModifiers = {}

		for i = 1, #Modifiers do
			RealModifiers[ #RealModifiers + 1 ] = SGUI.PropertyModifiers[ Modifiers[ i ] ]
		end

		return RealModifiers, #RealModifiers
	end

	--[[
		Adds Get and Set functions for a property name, with an optional default value.
	]]
	function SGUI.AddProperty( Table, Name, Default, Modifiers )
		local TableSetter = "Set"..Name
		local TableGetter = "Get"..Name

		Table[ TableSetter ] = function( self, Value )
			local OldValue = self[ TableGetter ]( self )

			self[ Name ] = Value

			if OldValue == Value then return false end

			self:OnPropertyChanged( Name, Value )

			return true
		end

		Table[ TableGetter ] = function( self )
			local Value = self[ Name ]
			if Value == nil then
				Value = Default
			end
			return Value
		end

		if not Modifiers then return end

		local RealModifiers, NumModifiers = GetModifiers( Modifiers )

		local Old = Table[ TableSetter ]
		Table[ TableSetter ] = function( self, Value )
			if Old( self, Value ) then
				for i = 1, NumModifiers do
					RealModifiers[ i ]( self, Value )
				end
			end
		end
	end

	local StringExplode = string.Explode
	local unpack = unpack

	local function GetBindingInfo( BoundObject, PropertyName )
		if IsType( BoundObject, "string" ) then
			BoundObject = { BoundObject }
		end

		local BoundFields = {}

		for i = 1, #BoundObject do
			local Entry = BoundObject[ i ]
			if IsType( Entry, "string" ) then
				local FieldName, Setter = unpack( StringExplode( Entry, ":", true ) )
				Setter = Setter or "Set"..PropertyName

				BoundFields[ i ] = function( self, Value )
					local Object = self[ FieldName ]
					if Object then
						Object[ Setter ]( Object, Value )
					end
				end
			else
				BoundFields[ i ] = Entry
			end
		end

		return BoundFields
	end

	--[[
		Adds Get/Set property methods that pass through the value to a field
		on the table as well as storing it.

		Used to perform actions on GUIItems without boilerplate code.
	]]
	function SGUI.AddBoundProperty( Table, Name, BoundObject, Modifiers )
		local BoundFields = GetBindingInfo( BoundObject, Name )

		Table[ "Get"..Name ] = function( self )
			return self[ Name ]
		end

		local TableSetter = "Set"..Name
		Table[ TableSetter ] = function( self, Value )
			local OldValue = self[ Name ]

			self[ Name ] = Value

			for i = 1, #BoundFields do
				BoundFields[ i ]( self, Value )
			end

			if OldValue == Value then return false end

			self:OnPropertyChanged( Name, Value )

			return true
		end

		if not Modifiers then return end

		local RealModifiers, NumModifiers = GetModifiers( Modifiers )

		local Old = Table[ TableSetter ]
		Table[ TableSetter ] = function( self, Value )
			if Old( self, Value ) then
				for i = 1, NumModifiers do
					RealModifiers[ i ]( self, Value )
				end
			end
		end
	end
end

do
	local WideStringToString

	function SGUI.GetChar( Char )
		WideStringToString = WideStringToString or ConvertWideStringToString
		return WideStringToString( Char )
	end
end

do
	local Max = math.max
	local StringExplode = string.Explode
	local StringUTF8Encode = string.UTF8Encode
	local TableConcat = table.concat

	--[[
		Wraps text to fit the size limit. Used for long words...

		Returns two strings, first one fits entirely on one line, the other may not, and should be
		added to the next word.
	]]
	local function TextWrap( Label, Text, XPos, MaxWidth )
		local i = 1
		local FirstLine = Text
		local SecondLine = ""
		local Chars = StringUTF8Encode( Text )
		local Length = #Chars

		-- Character by character, extend the text until it exceeds the width limit.
		repeat
			local CurText = TableConcat( Chars, "", 1, i )

			-- Once it reaches the limit, we go back a character, and set our first and second line results.
			if XPos + Label:GetTextWidth( CurText ) > MaxWidth then
				-- The max makes sure we're cutting at least one character out of the text,
				-- to avoid an infinite loop.
				FirstLine = TableConcat( Chars, "", 1, Max( i - 1, 1 ) )
				SecondLine = TableConcat( Chars, "", Max( i, 2 ) )

				break
			end

			i = i + 1
		until i > Length

		return FirstLine, SecondLine
	end

	--[[
		Word wraps text, adding new lines where the text exceeds the width limit.

		This time, it shouldn't freeze the game...
	]]
	function SGUI.WordWrap( Label, Text, XPos, MaxWidth, MaxLines )
		local Words = StringExplode( Text, " ", true )
		local StartIndex = 1
		local Lines = {}
		local i = 1

		-- While loop, as the size of the Words table may increase.
		while i <= #Words do
			local CurText = TableConcat( Words, " ", StartIndex, i )

			if XPos + Label:GetTextWidth( CurText ) > MaxWidth then
				-- This means one word is wider than the whole chatbox, so we need to cut it part way through.
				if StartIndex == i then
					local FirstLine, SecondLine = TextWrap( Label, CurText, XPos, MaxWidth )

					Lines[ #Lines + 1 ] = FirstLine

					-- Add the second line as the next word, or as a new next word if none exists.
					if Words[ i + 1 ] then
						TableInsert( Words, i + 1, SecondLine )
					else
						-- This is just a micro-optimisation really, it's slightly quicker than table.insert.
						Words[ i + 1 ] = SecondLine
					end

					StartIndex = i + 1
				else
					Lines[ #Lines + 1 ] = TableConcat( Words, " ", StartIndex, i - 1 )

					-- We need to jump back a step, as we've still got another word to check.
					StartIndex = i
					i = i - 1
				end

				if MaxLines and #Lines >= MaxLines then
					break
				end
			elseif i == #Words then -- We're at the end!
				Lines[ #Lines + 1 ] = CurText
			end

			i = i + 1
		end

		Label:SetText( TableConcat( Lines, "\n" ) )

		if MaxLines then
			return TableConcat( Words, " ", StartIndex )
		end
	end
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
	local TableRemoveByValue = table.RemoveByValue

	local function RefreshFocusedWindow( self, Window )
		local Windows = self.Windows
		for i = 1, #Windows do
			local Window = Windows[ i ]
			Window:SetLayer( Window.OverrideLayer or self.BaseLayer + i )
		end

		if Window ~= self.FocusedWindow and self.IsValid( self.FocusedWindow )
		and self.FocusedWindow.OnLoseWindowFocus then
			self.FocusedWindow:OnLoseWindowFocus( Window )
		end

		self.FocusedWindow = Window
	end

	--[[
		Sets the current in-focus window.
		Inputs: Window object, windows index.
	]]
	function SGUI:SetWindowFocus( Window )
		if Window == self.FocusedWindow or not self.Windows[ Window ] then
			return
		end

		local Windows = self.Windows
		for i = #Windows, 1, -1 do
			local CurWindow = Windows[ i ]
			if CurWindow == Window then
				TableRemove( Windows, i )
				Windows[ #Windows + 1 ] = Window
				break
			end
		end

		RefreshFocusedWindow( self, Window )
	end

	function SGUI:AddWindow( Window )
		if self.Windows[ Window ] then return end

		self.Windows[ #self.Windows + 1 ] = Window
		self.Windows[ Window ] = true
	end

	function SGUI:RemoveWindow( Window )
		if not self.Windows[ Window ] then return end

		self.Windows[ Window ] = nil
		TableRemoveByValue( self.Windows, Window )

		RefreshFocusedWindow( self, self.Windows[ #self.Windows ] )
	end

	function SGUI:MoveWindowToBottom( Window )
		local Windows = self.Windows
		for i = 1, #Windows do
			if Windows[ i ] == Window then
				TableRemove( Windows, i )
				break
			end
		end

		TableInsert( Windows, 1, Window )

		RefreshFocusedWindow( self, Windows[ #Windows ] )
	end
end

function SGUI:IsWindow( Window )
	return self.Windows[ Window ]
end

function SGUI:IsWindowInFocus( Window )
	if Window == self.FocusedWindow then return true end

	local Windows = self.Windows
	for i = #Windows, 1, -1 do
		local OtherWindow = Windows[ i ]
		if Window == OtherWindow then
			return Window.AlwaysInMouseFocus or Window:MouseInCached()
		end

		if not OtherWindow.IgnoreMouseFocus and OtherWindow:GetIsVisible() and OtherWindow:MouseInCached() then
			return false
		end
	end

	return false
end

local OnError = Shine.BuildErrorHandler( "SGUI Error" )

function SGUI:PostCallEvent( Result, Control )
	local PostEventActions = self.PostEventActions
	if not PostEventActions then return end

	for i = 1, #PostEventActions do
		xpcall( PostEventActions[ i ], OnError, Result, Control )
	end

	self.PostEventActions = nil
end

function SGUI:AddPostEventAction( Action )
	if not self.PostEventActions then
		self.PostEventActions = {}
	end

	self.PostEventActions[ #self.PostEventActions + 1 ] = Action
end

--[[
	Passes an event to all active SGUI windows.

	If an SGUI object is classed as a window, it MUST call all events on its children.
	Then its children must call their events on their children and so on.

	Inputs: Event name, arguments.
]]
function SGUI:CallEvent( FocusChange, Name, ... )
	local Windows = SGUI.Windows
	local WindowCount = #Windows

	--The focused window is the last in the list, so we call backwards.
	for i = WindowCount, 1, - 1 do
		local Window = Windows[ i ]

		if Window and Window[ Name ] and Window:GetIsVisible() then
			local Success, Result, Control = xpcall( Window[ Name ], OnError, Window, ... )

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


do
	SGUI.MouseObjects = 0

	local IsCommander
	local ShowMouse

	--[[
		Allow for multiple windows to "enable" the mouse, without
		disabling it after one closes.
	]]
	function SGUI:EnableMouse( Enable )
		if not ShowMouse then
			ShowMouse = MouseTracker_SetIsVisible
			IsCommander = CommanderUI_IsLocalPlayerCommander
		end

		if Enable then
			self.MouseObjects = self.MouseObjects + 1

			if self.MouseObjects == 1 then
				if not ( IsCommander and IsCommander() ) then
					ShowMouse( true )
					self.EnabledMouse = true
				end
			end

			return
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

		Hook.Call( "OnSGUIControlRegistered", Name, Table, Parent )
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
		local MetaTable = self.Controls[ Class ]
		Shine.AssertAtLevel( MetaTable, "[SGUI] '%s' is not a registered SGUI class!", 3, Class )

		return MakeControl( self, MetaTable, Class, Parent, ParentElement )
	end

	function SGUI:BuildTree( Parent, Tree )
		local GlobalProps = Tree.GlobalProps
		local Elements = {}

		local function BuildChildren( Parent, Tree )
			for i = 1, #Tree do
				local ElementDef = Tree[ i ]
				local Element
				if ElementDef.Type == "Layout" then
					Element = self.Layout:CreateLayout( ElementDef.Class )
					if Parent.IsLayout then
						Parent:AddElement( Element )
					elseif Parent.Layout then
						Parent.Layout:AddElement( Element )
					else
						Parent:SetLayout( Element, true )
					end
				else
					if Parent.IsLayout then
						Element = self:Create( ElementDef.Class, Parent:GetParentControl() )
						Parent:AddElement( Element )
					else
						Element = Parent.Add and Parent:Add( ElementDef.Class ) or self:Create( ElementDef.Class, Parent )
						if Parent.Layout then
							Parent.Layout:AddElement( Element )
						end
					end
				end

				if GlobalProps then
					Element:SetupFromTable( GlobalProps )
				end

				if ElementDef.Props then
					Element:SetupFromTable( ElementDef.Props )
				end

				if ElementDef.ID then
					Elements[ ElementDef.ID ] = Element
				end

				if ElementDef.Children then
					BuildChildren( Element, ElementDef.Children )
				end
			end
		end
		BuildChildren( Parent, Tree )

		return Elements
	end
end

do
	local DebugGetInfo = debug.getinfo
	local rawget = rawget
	local ValidityKey = "IsValid"
	local function CheckDestroyed( self, Key )
		local Destroyed = rawget( self, "__Destroyed" )
		if Destroyed and Key ~= ValidityKey and Destroyed < SGUI.FrameNumber() then
			local Caller = DebugGetInfo( 2, "f" ).func
			-- Allow access in __tostring(), otherwise the element can't be printed.
			if Caller ~= getmetatable( self ).__tostring then
				error( "Attempted to use a destroyed SGUI object!", 3 )
			end
		end

		return rawget( self, "__OriginalIndex" )[ Key ]
	end

	local OnCallOnRemoveError = Shine.BuildErrorHandler( "SGUI CallOnRemove callback error" )

	--[[
		Destroys an SGUI control.

		This runs the control's cleanup function. Do not attempt to use the object again.

		Input: SGUI control object.
	]]
	function SGUI:Destroy( Control )
		if Control.Parent then
			Control:SetParent( nil )
		end

		if Control.LayoutParent then
			Control.LayoutParent:RemoveElement( Control )
		end

		self.ActiveControls:Remove( Control )
		self.KeyboardFocusControls:Remove( Control )

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

local GetCursorPosScreen = Client.GetCursorPosScreen
function SGUI.GetCursorPos()
	return GetCursorPosScreen()
end

local ScrW = Client.GetScreenWidth
local ScrH = Client.GetScreenHeight

function SGUI.GetScreenSize()
	return ScrW(), ScrH()
end

--[[
	If we don't load after everything, things aren't registered properly.
]]
Hook.Add( "OnMapLoad", "LoadGUIElements", function()
	GetCursorPosScreen = Client.GetCursorPosScreen
	ScrW = Client.GetScreenWidth
	ScrH = Client.GetScreenHeight

	Shine.LoadScriptsByPath( "lua/shine/lib/gui/objects" )
	include( "lua/shine/lib/gui/skin_manager.lua" )

	Shine.Hook.SetupGlobalHook( "Client.SetMouseVisible", "OnMouseVisibilityChange", "PassivePost" )
end )

Hook.CallAfterFileLoad( "lua/menu/MouseTracker.lua", function()
	local Listener = {
		OnMouseMove = function( _, LMB )
			SGUI:CallEvent( false, "OnMouseMove", LMB )
		end,
		OnMouseWheel = function( _, Down )
			return SGUI:CallEvent( false, "OnMouseWheel", Down )
		end,
		OnMouseDown = function( _, Key, DoubleClick )
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
