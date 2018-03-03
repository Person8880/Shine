--[[
	Shine class method replacement system.
]]

local function RecursivelyReplaceMethod( Class, Method, Func, Original )
	local ClassTable = _G[ Class ]

	if ClassTable[ Method ] ~= Original then return end

	ClassTable[ Method ] = Func

	local DerivedClasses = Script.GetDerivedClasses( Class )

	if DerivedClasses then
		for i = 1, #DerivedClasses do
			RecursivelyReplaceMethod( DerivedClasses[ i ], Method, Func, Original )
		end
	end
end

function Shine.ReplaceClassMethod( Class, Method, Func )
	local Original = _G[ Class ] and _G[ Class ][ Method ]

	if not Original then return nil, "class method does not exist." end

	RecursivelyReplaceMethod( Class, Method, Func, Original )

	return Original
end

--[[
	Updates the network variables for a given class, ensuring that the update
	is performed after the class has been loaded.
]]
function Shine.UpdateClassNetVars( ClassName, FileName, NetVars )
	local function AddNetVars()
		Shared.LinkClassToMap( ClassName, nil, NetVars )
	end

	if _G[ ClassName ] then
		AddNetVars()
	else
		Shine.Hook.Add( "PostLoadScript", tostring( NetVars ), function( Script )
			if Script ~= FileName then return end
			AddNetVars()
		end )
	end
end
