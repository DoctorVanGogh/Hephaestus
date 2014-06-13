-----------------------------------------------------------------------------------------------
-- Lua Queue implementation
-- Copyright (c) 2014 DoctorVanGogh on Wildstar forums
-----------------------------------------------------------------------------------------------

local MAJOR,MINOR = "DoctorVanGogh:Lib:Queue", 1

-- Get a reference to the package information if any
local APkg = Apollo.GetPackage(MAJOR)
-- If there was an older version loaded we need to see if this is newer
if APkg and (APkg.nVersion or 0) >= MINOR then
	return -- no upgrade needed
end

local oo = Apollo.GetPackage("DoctorVanGogh:Lib:Loop:Base").tPackage

local Queue = APkg and APkg.tPackage or oo.class{
	items = {}
}

function Queue:GetItems()
	return self.items
end

function Queue:Push(oItem)
	table.insert(self.items, oItem)
end

function Queue:Pop()
	if #self.items == 0 then
		return nil
	else
		local result = self[1]
		table.remove(self.items, 1)	
		return result
	end		
end

function Queue:Peek()
	if #self.items == 0 then
		return nil
	else
		return self.items[1]
	end		
end

function Queue:Clear()
	while #self.items ~= 0 do
		table.remove(self.items)	
	end
end

function Queue:Remove(tItem)
	for idx, item in ipairs(self.items) do
		if item == tItem then
			table.remove(self.items, idx)
			return true	
		end
	end
	return false
end

function Queue:GetCount()
	return #self.items
end

Apollo.RegisterPackage(Queue, MAJOR, MINOR, {})