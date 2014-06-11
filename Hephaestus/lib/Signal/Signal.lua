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

local Signal = APkg and APkg.tPackage or {}

local mtSignal = {}

function mtSignal:__add(tfnCallback) 
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


function mtSignal:__sub(tfnCallback)
	for idx, tfn in ipairs(self) do
		if tfn == tfnCallback then
			table.remove(self, idx)
			break
		end	
	end		
	
	return self		
end

function mtSignal:__call(...) 
	for idx, tfn in ipairs(self) do
		tfn(unpack(arg))
	end	
end

function mtSignal:Add(tOwner, strCallback)
	local fnCall = function(luaCaller, ...) 
		local t = luaCaller.tOwner
		local strClb = luaCaller.strCallback
		if t and strClb then
			t[strClb](t, unpack(arg))
		end
	end
	
	local tCallback = setmetatable({}, {__mode="v", __call = fnCall})
	tCallback.tOwner = tOwner
	tCallback.strCallback = strCallback	
		
	local tmp = self + tCallback
	
	return tCallback
end

mtSignal.__index = mtSignal

function Signal:new(t)
	return setmetatable(t or {}, mtSignal)
end

Apollo.RegisterPackage(Signal, MAJOR, MINOR, {})