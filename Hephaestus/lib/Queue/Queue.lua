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

local Queue = APkg and APkg.tPackage or {}

local mtQueue = {}

function Queue.new(t)
	t = t or {}
	t.items = t.items or {}

	return setmetatable(
		t, 
		{ 
			__index = mtQueue
		}
	)
end

function Queue.GetMetatable()
	return mtQueue
end

function mtQueue:GetItems()
	return self.items
end

function mtQueue:Push(oItem)
	table.insert(self.items, oItem)
end

function mtQueue:Pop()
	if #self.items == 0 then
		return nil
	else
		local result = self[1]
		table.remove(self.items, 1)	
		return result
	end		
end

function mtQueue:Peek()
	if #self.items == 0 then
		return nil
	else
		return self.items[1]
	end		
end

function mtQueue:Clear()
	while #self.items ~= 0 do
		table.remove(self.items)	
	end
end

function mtQueue:Remove(tItem)
	for idx, item in ipairs(self.items) do
		if item == tItem then
			table.remove(self.items, idx)
			return true	
		end
	end
	return false
end

function mtQueue:GetCount()
	return #self.items
end

Apollo.RegisterPackage(Queue, MAJOR, MINOR, {})