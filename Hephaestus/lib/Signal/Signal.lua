-----------------------------------------------------------------------------------------------
-- Lua Signal implementation
-- Copyright (c) DoctorVanGogh on Wildstar forums
-----------------------------------------------------------------------------------------------

local MAJOR,MINOR = "DoctorVanGogh:Lib:Signal", 1

-- Get a reference to the package information if any
local APkg = Apollo.GetPackage(MAJOR)
-- If there was an older version loaded we need to see if this is newer
if APkg and (APkg.nVersion or 0) >= MINOR then
	return -- no upgrade needed
end

local oo = Apollo.GetPackage("DoctorVanGogh:Lib:Loop:Base").tPackage

local Signal = APkg and APkg.tPackage or oo.class{}

function Signal:__add(tfnCallback) 
	if type(tfnCallback) == "function" then
		table.insert(self, tfnCallback)
	elseif type(tfnCallback) == "table" then
		if not getmetatable(tfnCallback).__call then
			error("Signal.Add requires a callable argument")
			return
		end	
		table.insert(self, tfnCallback)
	end
	
	return self
end

function Signal:__sub(tfnCallback)
	for idx, tfn in ipairs(self) do
		if tfn == tfnCallback then
			table.remove(self, idx)
			break
		end	
	end		
	
	return self		
end

function Signal:Remove(tfnCallback)
	return self - tfnCallback
end

function Signal:__call(...) 
	for idx, tfn in ipairs(self) do
		tfn(unpack(arg))
	end	
end


local function CreateCallable(tOwner, strCallbackKey)
	assert(tOwner)
	assert(strCallbackKey)
	assert(tOwner[strCallbackKey])
	
	local fnCall = function(luaCaller, ...) 
		local t = luaCaller.tOwner
		local strClb = luaCaller.strCallbackKey
		if t and strClb then
			t[strClb](t, unpack(arg))
		end
	end		
	
	local tCallable = setmetatable({}, {__mode="v", __call = fnCall})
	tCallable.tOwner = tOwner
	tCallable.strCallbackKey = strCallbackKey

	return tCallable
end


function Signal:Add(tfnTarget, strCallback)
		
	if strCallback then		
		assert(type(tfnTarget) == "table")
		local tmp = self + CreateCallable(tfnTarget, strCallback)		
		return tCallback	
	else
		return self + tfnTarget
	end
end


Apollo.RegisterPackage(Signal, MAJOR, MINOR, {})