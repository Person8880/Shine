--[[
	Shine radio control.

	Combines multiple checkboxes into a single-choice or multi-choice radio control.
]]

local SGUI = Shine.GUI

local TableEmpty = table.Empty
local TableRemoveByValue = table.RemoveByValue
local TypeCheck = Shine.TypeCheck
local TypeCheckField = Shine.TypeCheckField

local Radio = {}

SGUI.AddBoundProperty( Radio, "BackgroundColour", "Background:SetColor" )

function Radio:Initialise()
	self.BaseClass.Initialise( self )
	self.Background = self:MakeGUIItem()

	self.CheckBoxes = {}
	self:SetLayout( SGUI.Layout:CreateLayout( "Vertical" ), true )

	self.MultipleChoice = false
end

function Radio:SetMultipleChoice( MultipleChoice )
	self.MultipleChoice = MultipleChoice
	self:ForEach( "CheckBoxes", "SetRadio", not MultipleChoice )
end

function Radio:SetFont( Font )
	self.Font = Font
	self:ForEach( "CheckBoxes", "SetFont", Font )
end

function Radio:SetTextScale( TextScale )
	self.TextScale = TextScale
	self:ForEach( "CheckBoxes", "SetTextScale", TextScale )
end

function Radio:SetFontScale( Font, Scale )
	self.Font = Font
	self.TextScale = Scale
	self:ForEach( "CheckBoxes", "SetFontScale", Font, Scale )
end

function Radio:SetCheckBoxAutoSize( AutoSize )
	self.CheckBoxAutoSize = AutoSize
	self:ForEach( "CheckBoxes", "SetAutoSize", AutoSize )
end

function Radio:SetCheckBoxMargin( Margin )
	self.CheckBoxMargin = Margin
	for i = 2, #self.CheckBoxes do
		self.CheckBoxes[ i ]:SetMargin( Margin )
	end
end

function Radio:SetCheckBoxStyleName( StyleName )
	self.CheckBoxStyleName = StyleName
	self:ForEach( "CheckBoxes", "SetStyleName", StyleName )
end

function Radio:SetOptions( Options )
	self:ForEach( "CheckBoxes", "Destroy" )

	TableEmpty( self.CheckBoxes )

	for i = 1, #Options do
		self:AddOption( Options[ i ] )
	end
end

function Radio:AddOption( Option )
	TypeCheck( Option, "table", 1, "AddOption" )
	TypeCheckField( Option, "Description", "string", "Option" )

	local Index = #self.CheckBoxes + 1

	local CheckBox = SGUI:Create( "CheckBox", self )
	CheckBox:SetFontScale( self.Font, self.TextScale )
	CheckBox:AddLabel( Option.Description )
	CheckBox:SetRadio( not self.MultipleChoice )
	CheckBox:SetAutoSize( self.CheckBoxAutoSize )
	CheckBox:SetStyleName( self.CheckBoxStyleName )
	CheckBox.RadioOption = Option

	if Index > 1 then
		CheckBox:SetMargin( self.CheckBoxMargin )
	end

	CheckBox:AddPropertyChangeListener( "Checked", function( CheckBox, IsChecked )
		if not self.MultipleChoice then
			if not IsChecked then return end

			for i = 1, #self.CheckBoxes do
				local Box = self.CheckBoxes[ i ]
				if Box ~= CheckBox then
					Box:SetChecked( false )
				end
			end

			self:OnPropertyChanged( "SelectedOption", Option )
		else
			local Options = {}

			for i = 1, #self.CheckBoxes do
				local Box = self.CheckBoxes[ i ]
				if Box:GetChecked() then
					Options[ #Options + 1 ] = Box.RadioOption
				end
			end

			self:OnPropertyChanged( "SelectedOptions", Options )
		end
	end )

	self.CheckBoxes[ Index ] = CheckBox
	self.CheckBoxes[ Option ] = CheckBox

	self.Layout:AddElement( CheckBox )
end

function Radio:RemoveOption( Option )
	local CheckBox = self.CheckBoxes[ Option ]
	if not CheckBox then return false end

	if SGUI.IsValid( CheckBox ) then
		CheckBox:SetChecked( false )
		CheckBox:Destroy()
	end

	self.CheckBoxes[ Option ] = nil
	TableRemoveByValue( self.CheckBoxes, CheckBox )

	return true
end

function Radio:SetSelectedOption( Option )
	local CheckBox = self.CheckBoxes[ Option ]
	if not SGUI.IsValid( CheckBox ) then return end

	CheckBox:SetChecked( true )
end

function Radio:SetSelectedOptions( Options )
	if not self.MultipleChoice then return end

	for i = 1, #Options do
		self:SetSelectedOption( Options[ i ] )
	end
end

SGUI:Register( "Radio", Radio )
