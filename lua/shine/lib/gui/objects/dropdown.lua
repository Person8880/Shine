--[[
	Simple dropdown menu.
]]

local SGUI = Shine.GUI
local Controls = SGUI.Controls

local Binder = require "shine/lib/gui/binding/binder"

local Max = math.max
local TableEmpty = table.Empty
local TableRemoveByValue = table.RemoveByValue

local Dropdown = {}

SGUI.AddProperty( Dropdown, "MaxVisibleOptions", 16 )
SGUI.AddProperty( Dropdown, "SelectedOption" )

function Dropdown:Initialise()
	Controls.Button.Initialise( self )

	self:SetHorizontal( true )
	self:SetTextAlignment( SGUI.LayoutAlignment.MIN )
	self:SetIconAlignment( SGUI.LayoutAlignment.MAX )

	self.Options = {}

	self:SetOpenMenuOnClick( function( self )
		return {
			MenuPos = self.MenuPos.BOTTOM,
			Populate = function( Menu )
				Menu:SetMaxVisibleButtons( Max( self:GetMaxVisibleOptions(), 1 ) )
				Menu:SetFontScale( self:GetFont(), self:GetTextScale() )

				for i = 1, #self.Options do
					local Option = self.Options[ i ]

					local function DoClick( Button )
						local Result = true
						if Option.DoClick then
							Result = Option.DoClick( Button )
						end

						self:SetSelectedOption( Option )

						Menu:Destroy()

						return Result
					end

					local Button = Menu:AddButton( Option.Text, DoClick, Option.Tooltip )
					if Option.Icon then
						Button:SetIcon( Option.Icon, Option.IconFont, Option.IconScale )
					end
					Button:SetStyleName( "DropdownButton" )
				end
			end
		}
	end )

	Binder():FromElement( self, "SelectedOption" )
		:ToElement( self, "Text", {
			Transformer = function( Option ) return Option and Option.Text or "" end
		} )
		:BindProperty()
end

function Dropdown:SelectOption( Value )
	for i = 1, #self.Options do
		local Option = self.Options[ i ]
		if Option.Value == Value or Option.Text == Value then
			self:SetSelectedOption( Option )
			return true
		end
	end

	return false
end

function Dropdown:AddOption( Option )
	Shine.TypeCheck( Option, "table", 1, "AddOption" )
	Shine.TypeCheckField( Option, "Text", "string", "Option" )

	self.Options[ #self.Options + 1 ] = Option
end

function Dropdown:AddOptions( Options )
	for i = 1, #Options do
		self:AddOption( Options[ i ] )
	end
end

function Dropdown:RemoveOption( Option )
	return TableRemoveByValue( self.Options, Option )
end

function Dropdown:Clear()
	TableEmpty( self.Options )
end

SGUI:Register( "Dropdown", Dropdown, "Button" )
