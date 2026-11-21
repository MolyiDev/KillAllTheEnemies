-- Destruction can invalidate skinned render state. Spread retired-type/restart
-- cleanup across frames; live-type rigs stay pooled for immediate reuse.
local Retirement = {}
Retirement.__index = Retirement
function Retirement.new(destroy)
	return setmetatable({ Queue = {}, First = 1, Last = 0, Destroy = destroy }, Retirement)
end
function Retirement:Enqueue(model)
	self.Last += 1
	self.Queue[self.Last] = model
end
function Retirement:Step(maxModels: number, budgetSeconds: number)
	local began = os.clock()
	local count = 0
	while self.First <= self.Last and count < maxModels do
		if os.clock() - began >= budgetSeconds then break end
		local model = self.Queue[self.First]
		self.Queue[self.First] = nil
		self.First += 1
		self.Destroy(model)
		count += 1
	end
	if self.First > self.Last then
		self.First, self.Last = 1, 0
		table.clear(self.Queue)
	end
end
return Retirement
