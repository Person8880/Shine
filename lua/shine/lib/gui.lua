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
local Clock = os.clock
local getmetatable = getmetatable
local include = Script.Load
local next = next
local pairs = pairs
local setmetatable = setmetatable
local StringFormat = string.format
local TableInsert = table.insert
local TableRemove = table.remove
local xpcall = xpcall

--Useful functions for colours.
include "lua/shine/lib/colour.lua"

SGUI.Controls = {}

SGUI.ActiveControls = Map()
SGUI.Windows = {}

--Used to adjust the appearance of all elements at once.
SGUI.Skins = {}

--Base visual layer.
SGUI.BaseLayer = 20

--Global control meta-table.
local ControlMeta = {}

--[[
	Adds Get and Set functions for a property name, with an optional default value.
]]
function SGUI.AddProperty( Table, Name, Default )
	Table[ "Set"..Name ] = function( self, Value )
		self[ Name ] = Value
	end

	Table[ "Get"..Name ] = function( self )
		return self[ Name ] or Default
	end
end

local WideStringToString

function SGUI.GetChar( Char )
	WideStringToString = WideStringToString or ConvertWideStringToString
	return WideStringToString( Char )
end

do
	local Max = math.max
	local StringExplode = string.Explode
	local StringUTF8Length = string.UTF8Length
	local StringUTF8Sub = string.UTF8Sub
	local TableConcat = table.concat
	local TableInsert = table.insert

	--[[
		Wraps text to fit the size limit. Used for long words...

		Returns two strings, first one fits entirely on one line, the other may not, and should be
		added to the next word.
	]]
	local function TextWrap( Label, Text, XPos, MaxWidth )
		local i = 1
		local FirstLine = Text
		local SecondLine = ""
		local Length = StringUTF8Length( Text )

		--Character by character, extend the text until it exceeds the width limit.
		repeat
			local CurText = StringUTF8Sub( Text, 1, i )

			--Once it reaches the limit, we go back a character, and set our first and second line results.
			if XPos + Label:GetTextWidth( CurText ) > MaxWidth then
				FirstLine = StringUTF8Sub( Text, 1, Max( i - 1, 1 ) )
				SecondLine = StringUTF8Sub( Text, Max( i, 2 ) )

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

		--While loop, as the size of the Words table may increase.
		while i <= #Words do
			local CurText = TableConcat( Words, " ", StartIndex, i )

			if XPos + Label:GetTextWidth( CurText ) > MaxWidth then
				--This means one word is wider than the whole chatbox, so we need to cut it part way through.
				if StartIndex == i then
					local FirstLine, SecondLine = TextWrap( Label, CurText, XPos, MaxWidth )

					Lines[ #Lines + 1 ] = FirstLine

					--Add the second line as the next word, or as a new next word if none exists.
					if Words[ i + 1 ] then
						TableInsert( Words, i + 1, SecondLine )
					else
						Words[ i + 1 ] = SecondLine
					end

					StartIndex = i + 1
				else
					Lines[ #Lines + 1 ] = TableConcat( Words, " ", StartIndex, i - 1 )

					--We need to jump back a step, as we've still got another word to check.
					StartIndex = i
					i = i - 1
				end

				if MaxLines and #Lines >= MaxLines then
					break
				end
			elseif i == #Words then --We're at the end!
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

SGUI.SpecialKeyStates = {
	Ctrl = false,
	Alt = false,
	Shift = false
}

Hook.Add( "PlayerKeyPress", "SGUICtrlMonitor", function( Key, Down )
	if Key == InputKey.LeftControl or Key == InputKey.RightControl then
		SGUI.SpecialKeyStates.Ctrl = Down or false
	elseif Key == InputKey.LeftAlt then
		SGUI.SpecialKeyStates.Alt = Down or false
	elseif Key == InputKey.LeftShift or Key == InputKey.RightShift then
		SGUI.SpecialKeyStates.Shift = Down or false
	end
end, -20 )

function SGUI:IsControlDown()
	return self.SpecialKeyStates.Ctrl
end

function SGUI:IsAltDown()
	return self.SpecialKeyStates.Alt
end

function SGUI:IsShiftDown()
	return self.SpecialKeyStates.Shift
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

local ToDebugString = table.ToDebugString
local Traceback = debug.traceback

local function OnError( Error )
	local Trace = Traceback()

	local Locals = ToDebugString( Shine.GetLocals( 1 ) )

	Shine:DebugPrint( "SGUI Error: %s.\n%s", true, Error, Trace )
	Shine:AddErrorReport( StringFormat( "SGUI Error: %s.", Error ),
		"%s\nLocals:\n%s", true, Trace, Locals )
end

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

--[[
	Calls an event on all active SGUI controls, out of order.

	Inputs: Event name, optional check function, arguments.
]]
function SGUI:CallGlobalEvent( Name, CheckFunc, ... )
	if IsType( CheckFunc, "function" ) then
		for Control in self.ActiveControls:Iterate() do
			if Control[ Name ] and CheckFunc( Control ) then
				Control[ Name ]( Control, Name, ... )
			end
		end
	else
		for Control in self.ActiveControls:Iterate() do
			if Control[ Name ] then
				Control[ Name ]( Control, Name, ... )
			end
		end
	end
end

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

--[[
	Registers a skin.
	Inputs: Skin name, table of colour/texture/font/size values.
]]
function SGUI:RegisterSkin( Name, Values )
	self.Skins[ Name ] = Values
end

local function CheckIsSchemed( Control )
	return Control.UseScheme
end

--[[
	Sets the current skin. This will reskin all active globally skinned objects.
	Input: Skin name registered with SGUI:RegisterSkin()
]]
function SGUI:SetSkin( Name )
	local SchemeTable = self.Skins[ Name ]

	assert( SchemeTable, "[SGUI] Attempted to set a non-existant skin!" )

	self.ActiveSkin = Name
	--Notify all elements of the change.
	return SGUI:CallGlobalEvent( "OnSchemeChange", CheckIsSchemed, SchemeTable )
end

--[[
	Returns the active colour scheme data table.
]]
function SGUI:GetSkin()
	local SchemeName = self.ActiveSkin
	local SchemeTable = SchemeName and self.Skins[ SchemeName ]

	assert( SchemeTable, "[SGUI] No active skin!" )

	return SchemeTable
end

--[[
	Reloads all skin files and calls the scheme change SGUI event.
	Consistency checking will hate you and kick you if you use this with Lua files being checked.
]]
function SGUI:ReloadSkins()
	local Skins = {}
	Shared.GetMatchingFileNames( "lua/shine/lib/gui/skins/*.lua", false, Skins )

	for i = 1, #Skins do
		include( Skins[ i ], true )
	end

	if self.ActiveSkin then
		self:SetSkin( self.ActiveSkin )
	end

	Shared.Message( "[SGUI] Skins reloaded successfully." )
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
			ParentTable = ParentTable or SGUI.Controls[ Parent ]

			if Table[ Key ] then return Table[ Key ] end
			if ParentTable and ParentTable[ Key ] then return ParentTable[ Key ] end
			if ControlMeta[ Key ] then return ControlMeta[ Key ] end

			return nil
		end
	else
		--No parent means only look in its meta-table and the base meta-table.
		function Table:__index( Key )
			if Table[ Key ] then return Table[ Key ] end

			if ControlMeta[ Key ] then return ControlMeta[ Key ] end

			return nil
		end
	end

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

--[[
	Creates an SGUI control.
	Input: SGUI control class name, optional parent object.
	Output: SGUI control object.
]]
function SGUI:Create( Class, Parent )
	local MetaTable = self.Controls[ Class ]

	assert( MetaTable, "[SGUI] Invalid SGUI class passed to SGUI:Create!" )

	local Table = {}

	local Control = setmetatable( Table, MetaTable )
	Control.Class = Class
	Control:Initialise()

	self.ActiveControls:Add( Control, true )

	--If it's a window then we give it focus.
	if MetaTable.IsWindow and not Parent then
		local Windows = self.Windows

		Windows[ #Windows + 1 ] = Control

		self:SetWindowFocus( Control )

		Control.IsAWindow = true
	end

	if not Parent then return Control end

	Control:SetParent( Parent )

	return Control
end

--[[
	Destroys an SGUI control.

	This runs the control's cleanup function. Do not attempt to use the object again.

	Input: SGUI control object.
]]
function SGUI:Destroy( Control )
	self.ActiveControls:Remove( Control )

	if self.IsValid( Control.Tooltip ) then
		Control.Tooltip:Destroy()
	end

	--SGUI children, not GUIItems.
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

	--If it's a window, then clean it up.
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
end

--[[
	Combines a nil and validity check into one.

	Input: SGUI control to check for existence and validity.
	Output: Existence and validity.
]]
function SGUI.IsValid( Control )
	return Control and Control.IsValid and Control:IsValid()
end

Hook.Add( "Think", "UpdateSGUI", function( DeltaTime )
	SGUI:CallEvent( false, "Think", DeltaTime )
end )

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

--[[
	If we don't load after everything, things aren't registered properly.
]]
Hook.Add( "OnMapLoad", "LoadGUIElements", function()
	local Controls = {}
	Shared.GetMatchingFileNames( "lua/shine/lib/gui/objects/*.lua", false, Controls )

	for i = 1, #Controls do
		include( Controls[ i ] )
	end

	local Skins = {}
	Shared.GetMatchingFileNames( "lua/shine/lib/gui/skins/*.lua", false, Skins )

	for i = 1, #Skins do
		include( Skins[ i ] )
	end

	--Apparently this isn't loading for some people???
	if not SGUI.Skins.Default then
		local Skin = next( SGUI.Skins )
		--If there's a different skin, load it.
		--Otherwise whoever's running this is missing the skin file, I can't fix that.
		if Skin then
			SGUI:SetSkin( Skin )
		end
	else
		SGUI:SetSkin( "Default" )
	end

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

--------------------- BASE CLASS ---------------------
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

--[[
	Sets a control's parent manually.
]]
function ControlMeta:SetParent( Control, Element )
	assert( Control ~= self, "[SGUI] Cannot parent an object to itself!" )

	if self.Parent then
		self.Parent.Children:Remove( self )
		self.ParentElement:RemoveChild( self.Background )
	end

	if not Control then
		self.Parent = nil
		return
	end

	--Parent to a specific part of a control.
	if Element then
		self.Parent = Control
		self.ParentElement = Element

		Control.Children = Control.Children or Map()
		Control.Children:Add( self, true )

		Element:AddChild( self.Background )

		return
	end

	if not Control.Background or not self.Background then return end

	self.Parent = Control
	self.ParentElement = Control.Background

	Control.Children = Control.Children or Map()
	Control.Children:Add( self, true )

	Control.Background:AddChild( self.Background )
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
	Override this for stencilled stuff.
]]
function ControlMeta:GetIsVisible()
	if not self.Background.GetIsVisible then return false end

	return self.Background:GetIsVisible()
end

--[[
	Sets the size of the control (background).
]]
function ControlMeta:SetSize( SizeVec )
	if not self.Background then return end

	self.Background:SetSize( SizeVec )
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

local ScrW, ScrH

--[[
	Returns the absolute position of the control on the screen.
]]
function ControlMeta:GetScreenPos()
	if not self.Background then return end

	ScrW = ScrW or Client.GetScreenWidth
	ScrH = ScrH or Client.GetScreenHeight

	return self.Background:GetScreenPosition( ScrW(), ScrH() )
end

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

function ControlMeta:GetAnchor()
	local X = self.Background:GetXAnchor()
	local Y = self.Background:GetYAnchor()

	return X, Y
end

--We call this so many times it really needs to be local, not global.
local MousePos

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

	MousePos = MousePos or Client.GetCursorPosScreen
	ScrW = ScrW or Client.GetScreenWidth
	ScrH = ScrH or Client.GetScreenHeight

	local X, Y = MousePos()

	local Pos = Element:GetScreenPosition( ScrW(), ScrH() )
	local Size = Element:GetSize()

	if Element.GetIsScaling and Element:GetIsScaling() and Element.scale then
		Size = Size * Element.scale
	end

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

	local InX = X >= Pos.x and X <= Pos.x + MaxX
	local InY = Y >= Pos.y and Y <= Pos.y + MaxY

	local PosX = X - Pos.x
	local PosY = Y - Pos.y

	if InX and InY then
		return true, PosX, PosY, Size, Pos
	end

	return false, PosX, PosY
end

function ControlMeta:HasMouseFocus()
	return SGUI.MouseDownControl == self
end

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

	if Value.r then
		return SGUI.CopyColour( Value )
	end

	return Vector( Value.x, Value.y, 0 )
end

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
	EasingData.Elapsed = 0

	EasingData.Callback = Callback

	return EasingData
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

local Easers = {
	Fade = {
		Easer = function( self, Element, EasingData, Progress )
			SGUI.ColourLerp( EasingData.CurValue, EasingData.Start, Progress, EasingData.Diff )
		end,
		Setter = function( self, Element, Colour )
			Element:SetColor( Colour )
		end,
		Getter = function( self, Element )
			return Element:GetColor()
		end
	},
	Alpha = {
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
	},
	Move = {
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
	},
	Size = {
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
	}
}
Easers.Size.Easer = Easers.Move.Easer

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
	EasingData.EaseFunc = EaseFunc
	EasingData.Power = Power

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

function ControlMeta:HandleHovering( Time )
	if not self.OnHover then return end

	local MouseIn, X, Y = self:MouseIn( self.Background )
	if MouseIn then
		if not self.MouseHoverStart then
			self.MouseHoverStart = Time
		else
			if Time - self.MouseHoverStart > 1 and not self.MouseHovered then
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
end

function ControlMeta:ShowTooltip( X, Y )
	local SelfPos = self:GetScreenPos()

	X = SelfPos.x + X
	Y = SelfPos.y + Y

	local Tooltip = SGUI.IsValid( self.Tooltip ) and self.Tooltip or SGUI:Create( "Tooltip" )

	ScrW = ScrW or Client.GetScreenWidth
	ScrH = ScrH or Client.GetScreenHeight

	local W = ScrW()
	local Font
	local TextScale

	if W <= 1366 then
		Font = Fonts.kAgencyFB_Tiny
	elseif W > 1920 and W <= 2880 then
		Font = Fonts.kAgencyFB_Medium
	elseif W > 2880 then
		Font = Fonts.kAgencyFB_Huge
		TextScale = Vector( 0.5, 0.5, 0 )
	end

	Tooltip:SetText( self.TooltipText, Font, TextScale )

	Y = Y - Tooltip:GetSize().y - 4

	Tooltip:SetPos( Vector( X, Y, 0 ) )
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
	if Highlighted == self.Highlighted then return end

	if Highlighted then
		self.Highlighted = true

		if not self.TextureHighlight then
			if SkipAnim then
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
	--Basic highlight on mouse over handling.
	if not self.HighlightOnMouseOver then
		return
	end

	if self:MouseIn( self.Background, self.HighlightMult ) then
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

	NotifyFocusChange( self )
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

	NotifyFocusChange()
end

--[[
	Returns whether the current object is still in use.
	Output: Boolean valid.
]]
function ControlMeta:IsValid()
	return SGUI.ActiveControls:Get( self ) ~= nil
end
