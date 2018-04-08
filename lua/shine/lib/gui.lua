--[[
	Shine GUI system.

	I'm sorry UWE, but I don't like your class system.
]]

Shine.GUI = Shine.GUI or {}

local SGUI = Shine.GUI
local Hook = Shine.Hook
local IsType = Shine.IsType
local Map = Shine.Map

local assert = assert
local getmetatable = getmetatable
local include = Script.Load
local setmetatable = setmetatable
local StringFormat = string.format
local TableInsert = table.insert
local TableRemove = table.remove
local xpcall = xpcall

--Useful functions for colours.
include "lua/shine/lib/colour.lua"

do
	local Vector = Vector

	-- A little easier than having to always include that 0 z value.
	function Vector2( X, Y )
		return Vector( X, Y, 0 )
	end
end

SGUI.Controls = {}

SGUI.ActiveControls = Map()
SGUI.Windows = {}

--Used to adjust the appearance of all elements at once.
SGUI.Skins = {}

--Base visual layer.
SGUI.BaseLayer = 20

SGUI.ScreenHeight = {
	Small = 768,
	Normal = 1080,
	Large = 1600
}

--Global control meta-table.
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

		Table[ TableSetter ] = function( self, Value )
			self[ Name ] = Value
		end

		Table[ "Get"..Name ] = function( self )
			return self[ Name ] or Default
		end

		if not Modifiers then return end

		local RealModifiers, NumModifiers = GetModifiers( Modifiers )

		local Old = Table[ TableSetter ]
		Table[ TableSetter ] = function( self, Value )
			Old( self, Value )
			for i = 1, NumModifiers do
				RealModifiers[ i ]( self, Value )
			end
		end
	end

	local StringExplode = string.Explode
	local unpack = unpack

	local function GetBindingInfo( BoundObject )
		return unpack( StringExplode( BoundObject, ":" ) )
	end

	--[[
		Adds Get/Set property methods that pass through the value to a field
		on the table as well as storing it.

		Used to perform actions on GUIItems without boilerplate code.
	]]
	function SGUI.AddBoundProperty( Table, Name, BoundObject, Modifiers )
		local BoundField, Setter = GetBindingInfo( BoundObject )
		Setter = Setter or "Set"..Name

		Table[ "Get"..Name ] = function( self )
			return self[ Name ]
		end

		local TableSetter = "Set"..Name
		Table[ TableSetter ] = function( self, Value )
			self[ Name ] = Value

			local Object = self[ BoundField ]
			if not Object then return end

			Object[ Setter ]( Object, Value )
		end

		if not Modifiers then return end

		local RealModifiers, NumModifiers = GetModifiers( Modifiers )

		local Old = Table[ TableSetter ]
		Table[ TableSetter ] = function( self, Value )
			Old( self, Value )
			for i = 1, NumModifiers do
				RealModifiers[ i ]( self, Value )
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
		local Words = StringExplode( Text, " " )
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

do
	local ScrW, ScrH

	function SGUI.GetScreenSize()
		ScrW = ScrW or Client.GetScreenWidth
		ScrH = ScrH or Client.GetScreenHeight

		return ScrW(), ScrH()
	end
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

--[[
	Sets the current in-focus window.
	Inputs: Window object, windows index.
]]
function SGUI:SetWindowFocus( Window, i )
	local Windows = self.Windows

	if Window ~= self.FocusedWindow and not i then
		for j = 1, #Windows do
			local CurWindow = Windows[ j ]

			if CurWindow == Window then
				i = j
				break
			end
		end
	end

	if i then
		TableRemove( Windows, i )

		Windows[ #Windows + 1 ] = Window
	end

	for i = 1, #Windows do
		local Window = Windows[ i ]

		Window:SetLayer( self.BaseLayer + i )
	end

	if self.IsValid( self.FocusedWindow ) and self.FocusedWindow.OnLoseWindowFocus then
		self.FocusedWindow:OnLoseWindowFocus( Window )
	end

	self.FocusedWindow = Window
end

local OnError = Shine.BuildErrorHandler( "SGUI Error" )

function SGUI:PostCallEvent()
	local PostEventActions = self.PostEventActions
	if not PostEventActions then return end

	for i = 1, #PostEventActions do
		xpcall( PostEventActions[ i ], OnError )
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
						self:SetWindowFocus( Window, i )
					end

					self:PostCallEvent()

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
	local rawget = rawget
	local ValidityKey = "IsValid"

	local function CheckDestroyed( self, Key )
		local Destroyed = rawget( self, "__Destroyed" )
		if Destroyed and Key ~= ValidityKey and Destroyed < SGUI.FrameNumber() then
			error( "Attempted to use a destroyed SGUI object!", 3 )
		end
	end

	--If we have set a parent, then we want to setup a slightly different __index function.
	if Parent then
		Table.ParentControl = Parent

		--This may not be defined yet, so we get it when needed.
		local ParentTable = self.Controls[ Parent ]

		if ParentTable and ParentTable.ParentControl == Name then
			error( StringFormat( "[SGUI] Cyclic dependency detected. %s depends on %s while %s also depends on %s.",
				Name, Parent, Parent, Name ) )
		end

		function Table:__index( Key )
			CheckDestroyed( self, Key )

			ParentTable = ParentTable or SGUI.Controls[ Parent ]

			if Table[ Key ] then return Table[ Key ] end
			if ParentTable and ParentTable[ Key ] then return ParentTable[ Key ] end
			if ControlMeta[ Key ] then return ControlMeta[ Key ] end

			return nil
		end
	else
		--No parent means only look in its meta-table and the base meta-table.
		function Table:__index( Key )
			CheckDestroyed( self, Key )

			if Table[ Key ] then return Table[ Key ] end

			if ControlMeta[ Key ] then return ControlMeta[ Key ] end

			return nil
		end
	end

	Table.__tostring = Table.__tostring or ControlMeta.__tostring

	--Used to call base class functions for things like :MoveTo()
	Table.BaseClass = ControlMeta

	self.Controls[ Name ] = Table
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

	--[[
		Creates an SGUI control.
		Input: SGUI control class name, optional parent object.
		Output: SGUI control object.
	]]
	function SGUI:Create( Class, Parent )
		local MetaTable = self.Controls[ Class ]

		assert( MetaTable, "[SGUI] Invalid SGUI class passed to SGUI:Create!" )

		ID = ID + 1

		local Table = {}

		local Control = setmetatable( Table, MetaTable )
		Control.Class = Class
		Control.ID = ID
		Control:Initialise()

		self.ActiveControls:Add( Control, true )

		--If it's a window then we give it focus.
		if MetaTable.IsWindow and not Parent then
			local Windows = self.Windows

			Windows[ #Windows + 1 ] = Control

			self:SetWindowFocus( Control )

			Control.IsAWindow = true
		end

		self.SkinManager:ApplySkin( Control )

		if not Parent then return Control end

		Control:SetParent( Parent )

		return Control
	end
end

--[[
	Destroys an SGUI control.

	This runs the control's cleanup function. Do not attempt to use the object again.

	Input: SGUI control object.
]]
function SGUI:Destroy( Control )
	if Control.Parent then
		Control:SetParent( nil )
	end

	self.ActiveControls:Remove( Control )

	if self.IsValid( Control.Tooltip ) then
		Control.Tooltip:Destroy()
	end

	-- SGUI children, not GUIItems.
	if Control.Children then
		for Control in Control.Children:Iterate() do
			Control:Destroy()
		end
	end

	local DeleteOnRemove = Control.__DeleteOnRemove

	if DeleteOnRemove then
		for i = 1, #DeleteOnRemove do
			local Control = DeleteOnRemove[ i ]

			if self.IsValid( Control ) then
				Control:Destroy()
			end
		end
	end

	Control:Cleanup()

	local CallOnRemove = Control.__CallOnRemove

	if CallOnRemove then
		for i = 1, #CallOnRemove do
			CallOnRemove[ i ]( Control )
		end
	end

	-- If it's a window, then clean it up.
	if Control.IsAWindow then
		local Windows = self.Windows

		for i = 1, #Windows do
			local Window = Windows[ i ]

			if Window == Control then
				TableRemove( Windows, i )
				break
			end
		end

		self:SetWindowFocus( Windows[ #Windows ] )
	end

	Control.__Destroyed = SGUI.FrameNumber()
end

--[[
	Combines a nil and validity check into one.

	Input: SGUI control to check for existence and validity.
	Output: Existence and validity.
]]
function SGUI.IsValid( Control )
	return Control and Control.IsValid and Control:IsValid()
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
	if not Element then
		SGUI.FocusedControl = nil
	end

	for Control in SGUI.ActiveControls:Iterate() do
		if Control.OnFocusChange then
			if Control:OnFocusChange( Element, ClickingOtherElement ) then
				break
			end
		end
	end
end
SGUI.NotifyFocusChange = NotifyFocusChange

--[[
	If we don't load after everything, things aren't registered properly.
]]
Hook.Add( "OnMapLoad", "LoadGUIElements", function()
	Shine.LoadScriptsByPath( "lua/shine/lib/gui/objects" )
	include( "lua/shine/lib/gui/skin_manager.lua" )

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

	if Shine.IsNS2Combat then
		--Combat has a userdata listener at the top which blocks SGUI scrolling.
		--So we're going to put ourselves above it.
		local Listeners = Shine.GetUpValue( MouseTracker_ListenToWheel,
			"gMouseWheelMovementListeners" )

		TableInsert( Listeners, 1, Listener )
	else
		MouseTracker_ListenToWheel( Listener )
	end
end )

include( "lua/shine/lib/gui/base_control.lua" )
include( "lua/shine/lib/gui/font_manager.lua" )
include( "lua/shine/lib/gui/layout/layout.lua" )
Shine.LoadScriptsByPath( "lua/shine/lib/gui/mixins" )
