--[[
	Shine GUI system.

	I'm sorry UWE, but I don't like your class system.
]]

Shine.GUI = Shine.GUI or {}

local SGUI = Shine.GUI
local Hook = Shine.Hook

local assert = assert
local Clock = os.clock
local getmetatable = getmetatable
local include = Script.Load
local next = next
local pairs = pairs
local setmetatable = setmetatable
local StringFormat = string.format
local TableRemove = table.remove
local xpcall = xpcall

--Useful functions for colours.
include "lua/shine/lib/colour.lua"

SGUI.Controls = {}

SGUI.ActiveControls = {}
SGUI.Windows = {}

--Reuse destroyed script tables to save garbage collection.
SGUI.InactiveControls = {}

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

local WideStringToString = Locale.WideStringToString

function SGUI.GetChar( Char )
	return WideStringToString( Char )
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

function SGUI:GetCtrlDown()
	return self.SpecialKeyStates.Ctrl
end

--[[
	Sets the current in-focus window.
	Inputs: Window object, windows index.
]]
function SGUI:SetWindowFocus( Window, i )
	local Windows = self.Windows

	if i then
		TableRemove( Windows, i )

		Windows[ #Windows + 1 ] = Window
	end

	for i = 1, #Windows do
		local Window = Windows[ i ]

		Window:SetLayer( self.BaseLayer + i )
	end

	self.FocusedWindow = Window
end

local Traceback = debug.traceback

local function OnError( Error )
	Shine:AddErrorReport( StringFormat( "SGUI Error: %s.", Error ), Traceback() )
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

		if Window[ Name ] and Window:GetIsVisible() then
			local Success, Result = xpcall( Window[ Name ], OnError, Window, ... )

			if Success then
				if Result ~= nil then
					if i ~= WindowCount and FocusChange and self.IsValid( Window ) then
						SGUI:SetWindowFocus( Window, i )
					end

					return Result
				end
			else
				Window:Destroy()
			end
		end
	end
end

local IsType = Shine.IsType

--[[
	Calls an event on all active SGUI controls, out of order.

	Inputs: Event name, optional check function, arguments.
]]
function SGUI:CallGlobalEvent( Name, CheckFunc, ... )
	if IsType( CheckFunc, "function" ) then
		for Control in pairs( self.ActiveControls ) do
			if Control[ Name ] and CheckFunc( Control ) then
				Control[ Name ]( Control, Name, ... )
			end
		end
	else
		for Control in pairs( self.ActiveControls ) do
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
			if not IsCommander() then
				ShowMouse( true )
			end
		end

		return
	end

	if self.MouseObjects <= 0 then return end

	self.MouseObjects = self.MouseObjects - 1

	if self.MouseObjects == 0 then
		if not IsCommander() then
			ShowMouse( false )
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

	return SGUI:CallGlobalEvent( "OnSchemeChange", CheckIsSchemed, SchemeTable ) --Notify all elements of the change.
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
	We'll use this to create instances of it (instead of loading a script file every time like UWE).
	Inputs: Control name, control meta-table.
]]
function SGUI:Register( Name, Table )
	--Inherit keys from both the control's table and the global meta-table.
	function Table:__index( Key )
		if Table[ Key ] then return Table[ Key ] end
		
		if ControlMeta[ Key ] then return ControlMeta[ Key ] end
		
		return nil
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

	local Table = next( self.InactiveControls )

	if Table then
		self.InactiveControls[ Table ] = nil
	else
		Table = {}
	end

	local Control = setmetatable( Table, MetaTable )

	Control:Initialise()

	self.ActiveControls[ Control ] = true

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
	Destroys an SGUI control, leaving the table in storage for use as a new object later.

	This runs the control's cleanup function then empties its table. 
	The cleanup function should remove all GUI elements, this will not do it.

	Input: SGUI control object.
]]
function SGUI:Destroy( Control )
	self.ActiveControls[ Control ] = nil
	self.InactiveControls[ Control ] = true

	--SGUI children, not GUIItems.
	if Control.Children then
		for Control in pairs( Control.Children ) do
			Control:Destroy()
		end
	end

	Control:Cleanup()

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

	for k in pairs( Control ) do
		Control[ k ] = nil
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

	SGUI:SetSkin( "Default" )

	local Listener = {
		OnMouseMove = function( _, LMB )
			SGUI:CallEvent( false, "OnMouseMove", LMB )
		end,
		OnMouseWheel = function( _, Down )
			SGUI:CallEvent( false, "OnMouseWheel", Down )
		end,
		OnMouseDown = function( _, Key, DoubleClick )
			return SGUI:CallEvent( true, "OnMouseDown", Key )
		end,
		OnMouseUp = function( _, Key )
			return SGUI:CallEvent( false, "OnMouseUp", Key )
		end
	}

	MouseTracker_ListenToMovement( Listener )
	MouseTracker_ListenToWheel( Listener )
	MouseTracker_ListenToButtons( Listener )
end )

--------------------- BASE CLASS ---------------------
--[[
	Base initialise. Be sure to override this!
	Though you should call it in your override if you want to be schemed.
]]
function ControlMeta:Initialise()
	self.UseScheme = true
end

--[[
	Generic cleanup, for most controls this is adequate.
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
	Sets a control's parent manually.
]]
function ControlMeta:SetParent( Control, Element )
	if self.Parent then
		self.Parent.Children[ self ] = nil
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

		Control.Children = Control.Children or {}
		Control.Children[ self ] = true

		Element:AddChild( self.Background )

		return
	end

	if not Control.Background or not self.Background then return end

	self.Parent = Control
	self.ParentElement = Control.Background

	Control.Children = Control.Children or {}
	Control.Children[ self ] = true

	Control.Background:AddChild( self.Background )
end

--[[
	Calls an SGUI event on every child of the object.

	Ignores children with the _CallEventsManually flag.
]]
function ControlMeta:CallOnChildren( Name, ... )
	if not self.Children then return nil end

	--Call the event on every child of this object, no particular order.
	for Child in pairs( self.Children ) do
		if Child[ Name ] and not Child._CallEventsManually then
			local Result = Child[ Name ]( Child, ... )

			if Result ~= nil then
				return Result
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

--[[
	Sets the origin anchors for the control.
]]
function ControlMeta:SetAnchor( X, Y )
	if not self.Background then return end
	
	self.Background:SetAnchor( X, Y )
end

function ControlMeta:GetAnchor()
	local X = self.Background:GetXAnchor()
	local Y = self.Background:GetYAnchor()

	return X, Y
end

--We call this so many times it really needs to be local, not global.
local ScrW, ScrH
local MousePos

--[[
	Gets whether the mouse cursor is inside the bounds of a GUIItem.
	The multiplier will increase or reduce the size we use to calculate this.
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
		Size = Size * Mult
	end

	MaxX = MaxX or Size.x
	MaxY = MaxY or Size.y
	
	local InX = X >= Pos.x and X <= Pos.x + MaxX
	local InY = Y >= Pos.y and Y <= Pos.y + MaxY

	if InX and InY then
		local PosX = X - Pos.x
		local PosY = Y - Pos.y
		
		return true, PosX, PosY, Size, Pos
	end

	return false, 0, 0
end

--[[
	Sets an SGUI control to move from its current position.

	TODO: Refactor to behave like FadeTo to allow multiple elements moving at once.

	Inputs: 
		1. New position vector.
		2. Time delay before starting
		3. Duration of movement.
		4. Easing function (math.EaseIn, math.EaseOut, math.EaseInOut).
		5. Easing power (higher powers are more 'sticky', they take longer to start and stop).
		6. Callback function to run once movement is complete.
		7. Optional element to apply movement to.
]]
function ControlMeta:MoveTo( NewPos, Delay, Time, EaseFunc, Power, Callback, Element )
	self.MoveData = self.MoveData or {}

	local StartPos = Element and Element:GetPosition() or self.Background:GetPosition()

	self.MoveData.NewPos = NewPos
	self.MoveData.StartPos = StartPos
	self.MoveData.Dir = NewPos - StartPos

	self.MoveData.EaseFunc = EaseFunc or math.EaseOut
	self.MoveData.Power = Power or 3
	self.MoveData.Callback = Callback

	local CurTime = Clock()

	self.MoveData.StartTime = CurTime + Delay
	self.MoveData.Duration = Time
	self.MoveData.Elapsed = 0
	--self.MoveData.EndTime = CurTime + Delay + Time

	self.MoveData.Element = Element or self.Background

	self.MoveData.Finished = false
end

--[[
	Processes a control's movement. Internally called.
	Input: Current game time.
]]
function ControlMeta:ProcessMove()
	local MoveData = self.MoveData

	local Duration = MoveData.Duration
	local Progress = MoveData.Elapsed / Duration--( Duration - MoveData.EndTime + Time ) / Duration

	local LerpValue = MoveData.EaseFunc( Progress, MoveData.Power )

	local EndPos = MoveData.StartPos + LerpValue * MoveData.Dir

	MoveData.Element:SetPosition( EndPos )
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
function ControlMeta:FadeTo( Element, Start, End, Delay, Duration, Callback )
	self.Fades = self.Fades or {}

	self.Fades[ Element ] = self.Fades[ Element ] or {}

	local Fade = self.Fades[ Element ]

	Fade.Obj = Element

	Fade.Started = true
	Fade.Finished = false

	local Time = Clock()

	local Diff = SGUI.ColourSub( End, Start )
	local CurCol = SGUI.CopyColour( Start )

	Fade.Diff = Diff
	Fade.CurCol = CurCol

	Fade.StartCol = Start
	Fade.EndCol = End

	Fade.StartTime = Time + Delay
	Fade.Duration = Duration
	Fade.Elapsed = 0
	--Fade.EndTime = Time + Delay + Duration

	Fade.Callback = Callback
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
	self.SizeAnims = self.SizeAnims or {}
	local Sizes = self.SizeAnims

	Sizes[ Element ] = Sizes[ Element ] or {}

	local Size = Sizes[ Element ]

	Size.Obj = Element

	Size.Started = true
	Size.Finished = false

	Size.EaseFunc = EaseFunc or math.EaseOut
	Size.Power = Power or 3

	local Time = Clock()

	Start = Start or Element:GetSize()

	local Diff = End - Start
	local CurSize = Start

	Size.Diff = Diff
	Size.CurSize = Vector( CurSize.x, CurSize.y, 0 )

	Size.Start = CurSize
	Size.End = End

	Size.StartTime = Time + Delay
	Size.Duration = Duration
	Size.Elapsed = 0
	--Size.EndTime = Time + Delay + Duration

	Size.Callback = Callback
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

function ControlMeta:StopFade( Element )
	if not self.Fades then return end
	
	local Fade = self.Fades[ Element ]

	if not Fade then return end
	
	Fade.Elapsed = Fade.Duration
	Fade.Finished = true
end

--[[
	Global update function. Called on client update.

	You must call this inside a control's custom Think function with:
		self.BaseClass.Think( self, DeltaTime )
	if you want to use MoveTo, FadeTo, SetHighlightOnMouseOver etc.
]]
function ControlMeta:Think( DeltaTime )
	local Time = Clock()

	--I don't like nested if statements like this, but it's necessary.
	--Move data handling.
	if self.MoveData then
		if self.MoveData.StartTime <= Time then 
			if self.MoveData.Elapsed <= self.MoveData.Duration then
				self.MoveData.Elapsed = self.MoveData.Elapsed + DeltaTime

				self:ProcessMove()
			else
				if not self.MoveData.Finished then
					self.MoveData.Callback( self )

					self.MoveData.Finished = true
				end
			end
		end
	end

	--Fading handling.
	if self.Fades and next( self.Fades ) then
		for Element, Fade in pairs( self.Fades ) do
			local Start = Fade.StartTime
			local Duration = Fade.Duration
			
			Fade.Elapsed = Fade.Elapsed + DeltaTime

			local Elapsed = Fade.Elapsed
			--local End = Fade.EndTime

			if Start <= Time then
				if Elapsed <= Duration then
					local Progress = Elapsed / Duration--( Duration - Fade.EndTime + Time ) / Duration
					local CurCol = Fade.CurCol

					SGUI.ColourLerp( CurCol, Fade.StartCol, Progress, Fade.Diff ) --Linear progress.

					Fade.Obj:SetColor( CurCol ) --Sets the GUI element's colour.
				elseif not Fade.Finished then
					Fade.Callback( Element )
				
					Fade.Finished = true
				end
			end
		end
	end

	if self.SizeAnims and next( self.SizeAnims ) then
		for Element, Size in pairs( self.SizeAnims ) do
			local Start = Size.StartTime
			local Duration = Size.Duration

			Size.Elapsed = Size.Elapsed + DeltaTime
			
			local Elapsed = Size.Elapsed
			--local End = Size.EndTime

			if Start <= Time then
				if Elapsed <= Duration then
					local Progress = Elapsed / Duration--( Duration - Size.EndTime + Time ) / Duration
					local CurSize = Size.CurSize

					local LerpValue = Size.EaseFunc( Progress, Size.Power )

					CurSize.x = Size.Start.x + LerpValue * Size.Diff.x
					CurSize.y = Size.Start.y + LerpValue * Size.Diff.y

					if Element == self.Background then
						self:SetSize( CurSize )
					else
						Size.Obj:SetSize( CurSize )
					end
				elseif not Size.Finished then
					Size.Callback( Element )
				
					Size.Finished = true
				end
			end
		end
	end

	--Hovering handling for tooltips.
	if self.OnHover then
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
end

function ControlMeta:OnMouseMove( Down )
	--Basic highlight on mouse over handling.
	if self.HighlightOnMouseOver then
		if self:MouseIn( self.Background, self.HighlightMult ) then
			if not self.Highlighted then
				if not self.TextureHighlight then
					self:FadeTo( self.Background, self.InactiveCol, self.ActiveCol, 0, 0.25, function( Background )
						Background:SetColor( self.ActiveCol )
					end )
				else
					self.Background:SetTexture( self.HighlightTexture )
				end

				self.Highlighted = true
			end
		else
			if self.Highlighted then
				if not self.TextureHighlight then
					self:FadeTo( self.Background, self.ActiveCol, self.InactiveCol, 0, 0.25, function( Background )
						Background:SetColor( self.InactiveCol )
					end )
				else
					self.Background:SetTexture( self.Texture )
				end

				self.Highlighted = false
			end
		end
	end
end

local function NotifyFocusChange( Element )
	for Control in pairs( SGUI.ActiveControls ) do
		if Control.OnFocusChange then
			Control:OnFocusChange( Element )
		end
	end
end

--[[
	Requests focus, for text entry controls.
]]
function ControlMeta:RequestFocus()
	SGUI.FocusedControl = self

	NotifyFocusChange( self )
end

--[[
	Returns whether the current control has focus.
]]
function ControlMeta:HasFocus()
	return SGUI.FocusedControl == self
end

--[[
	Drops focus on the given element.
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
	return SGUI.InactiveControls[ self ] == nil
end
