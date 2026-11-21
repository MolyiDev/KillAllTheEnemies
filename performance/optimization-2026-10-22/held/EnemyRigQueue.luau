-- Prioritize nearby threats; preserve arrival order for equal distances.
local Queue = {}
Queue.__index = Queue
local function before(a, b)
	return a.Priority < b.Priority or (a.Priority == b.Priority and a.Order < b.Order)
end
function Queue.new()
	return setmetatable({ Entries = {}, Order = 0 }, Queue)
end
function Queue:Push(entry, priority: number)
	self.Order += 1
	entry.Order = self.Order
	entry.Priority = priority
	local entries = self.Entries
	local i = #entries + 1
	while i > 1 do
		local parent = math.floor(i / 2)
		if not before(entry, entries[parent]) then break end
		entries[i] = entries[parent]
		i = parent
	end
	entries[i] = entry
end
function Queue:Peek()
	return self.Entries[1]
end
function Queue:Count()
	return #self.Entries
end
function Queue:Pop()
	local entries = self.Entries
	local root = entries[1]
	local last = table.remove(entries)
	local n = #entries
	if n > 0 then
		local i = 1
		while i * 2 <= n do
			local child = i * 2
			if child < n and before(entries[child + 1], entries[child]) then
				child += 1
			end
			if not before(entries[child], last) then break end
			entries[i] = entries[child]
			i = child
		end
		entries[i] = last
	end
	return root
end
function Queue:Clear()
	table.clear(self.Entries)
	self.Order = 0
end
return Queue
