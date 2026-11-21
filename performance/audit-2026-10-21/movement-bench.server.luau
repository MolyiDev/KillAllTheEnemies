--!native
-- Synthetic benchmark of Ballarc's actual movement function, not a full game FPS test.
local R = game:GetService("ReplicatedStorage")
local H = game:GetService("HttpService")
local S = require(R.GlobalShared.Utils.SpatialHash)
local Grid = require(R.GlobalShared.Utils.Grid)
local current = require(script.GroundCurrent)
local direct = require(script.GroundDirect)
local packer = require(script.EntityPacker)
local grid = Grid.new(20, 100, 100, {Height=0})
local actor = {SendMessage=function() end}
local targets = {[1]=vector.create(0, 0, 0)}
local empty = {}
local qIndex, qEnd = 0, 0
local positions = {}
local function query()
	if qIndex >= qEnd then return nil end
	qIndex += 1
	return qIndex, positions[qIndex], vector.zero, 2, vector.zero, 8, 0, 0
end
task.wait(5)
for _, n in {1500, 5000} do
	local hash = S.new(5)
	local width = math.ceil(math.sqrt(n))
	for i=1,n do
		local p=vector.create(100+((i-1)%width)*3, 0, 100+math.floor((i-1)/width)*3)
		positions[i]=p
		hash:AddAABB(i,p,vector.create(1,2,1))
	end
	local records, buckets = S.PackRecords(hash.Records), S.PackBuckets(hash.FineBuckets)
	local received = {}
	local chunk = math.ceil(n/16)
	local function oldTick()
		table.clear(received)
		for start=1,n,chunk do
			qIndex, qEnd = start-1, math.min(n,start+chunk-1)
			local out=current(actor,targets,empty,empty,buckets,records,0.1,grid,query)
			packer.UnpackServerInto(out,received)
		end
		return received
	end
	local function newTick()
		qIndex, qEnd = 0, n
		return direct(actor,targets,empty,empty,hash.FineBuckets,hash.Records,0.1,grid,query)
	end
	oldTick()
	local proposed=newTick()
	local maxError=0
	for id, info in received do
		local delta=vector.magnitude(info.pos-proposed[id].pos)
		maxError=math.max(maxError,delta)
	end
	assert(maxError<0.001)
	local oldSamples, newSamples = {}, {}
	for rep=1,25 do
		local function oldSample()
			local t=os.clock(); oldTick(); oldSamples[#oldSamples+1]=(os.clock()-t)*1000
		end
		local function newSample()
			local t=os.clock(); newTick(); newSamples[#newSamples+1]=(os.clock()-t)*1000
		end
		if rep%2==0 then oldSample();newSample() else newSample();oldSample() end
		task.wait()
	end
	table.sort(oldSamples);table.sort(newSamples)
	print("[BALLARC_MOVEMENT_AUDIT] "..H:JSONEncode({n=n, currentSerial16MedianMs=oldSamples[13], currentSerial16P95Ms=oldSamples[24], directSerialMedianMs=newSamples[13], directSerialP95Ms=newSamples[24], ratio=oldSamples[13]/newSamples[13],maxPositionError=maxError, excludes="Actor scheduling/copy, partition allocation, ECS/hash commit, network, combat services, client"}))
end
print("[BALLARC_MOVEMENT_AUDIT] done")
