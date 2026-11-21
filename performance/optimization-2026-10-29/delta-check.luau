-- Randomized round trip: server PackFiltered state vs client UnpackInto netBase.
local roblox = require("@lune/roblox")
_G.Vector3 = roblox.Vector3
local P = require("./EnemyPacker")
math.randomseed(7)
local V = vector.create
local SCALE = 0.05
local function q(v) return math.floor(v / SCALE + 0.5) % 65536 end
local function dec(u) return (if u >= 32768 then u - 65536 else u) * SCALE end

local N = 3000
local positions, ids = {}, {}
for i = 1, N do
 ids[i] = 30000 + i
 positions[i] = V(math.random(-1600, 1600), math.random(0, 80), math.random(-1600, 1600))
end
local state = {camX=0,camY=0,camZ=0,lookX=0,lookY=0,lookZ=1,thresholdSq=-1,renderDistanceSq=1e12,
 knownEnemies={},sentAt={},sentQ=P.CreateBaseline()}
local netBase = P.CreateBaseline()
local client = {}
local expected = {}
local checked, absTotal, deltaTotal, bytes, rows = 0, 0, 0, 0, 0
local now = 0
for step = 1, 600 do
 now += 0.1
 -- subscribe / unsubscribe churn (unsubscribe = forget, like AOIService)
 for _ = 1, 40 do
  local id = ids[math.random(1, N)]
  if state.knownEnemies[id] and math.random() < 0.3 then
   state.knownEnemies[id] = nil; state.sentAt[id] = nil
  else state.knownEnemies[id] = true end
 end
 -- motion: mostly small, sometimes big jumps, some crossing the +-1638 wrap
 for i = 1, N do
  local p = positions[i]
  local r = math.random()
  if r < 0.02 then p = V(math.random(-1700, 1700), math.random(0, 80), math.random(-1700, 1700))
  elseif r < 0.9 then p = p + V((math.random()-0.5)*4, (math.random()-0.5)*2, (math.random()-0.5)*4) end
  positions[i] = p
 end
 -- a random subset per packet, with a duplicate id thrown in
 local subIds, subPos = {}, {}
 for i = 1, N do if math.random() < 0.5 then subIds[#subIds+1] = ids[i]; subPos[#subPos+1] = positions[i] end end
 if #subIds > 2 then subIds[#subIds+1] = subIds[1]; subPos[#subPos+1] = subPos[1] + V(9, 0, 0) end
 local buf = P.PackFiltered(subIds, subPos, state, now)
 for i = 1, #subIds do
  if state.sentAt[subIds[i]] == now and not expected[subIds[i] .. ":" .. now] then
   expected[subIds[i] .. ":" .. now] = true
   client[subIds[i]] = subPos[i]
  end
 end
 if buf then
  bytes += buffer.len(buf)
  absTotal += buffer.readu16(buf, 0); deltaTotal += buffer.readu16(buf, 2)
  local out = {}
  P.UnpackInto(buf, out, netBase)
  for id, v in out do
   local want = client[id]
   rows += 1
   assert(want, "decoded an id that was not sent " .. id)
   for _, axis in {"x","y","z"} do
    local got = ({x=v.X,y=v.Y,z=v.Z})[axis]
    local w = dec(q(want[axis]))
    assert(math.abs(got - w) < 1e-3, `mismatch id {id} step {step} axis {axis} got {got} want {w}`)
   end
   checked += 1
  end
 end
end
-- truncated packet must be rejected whole
local trunc = buffer.create(10); buffer.writeu16(trunc, 0, 1); buffer.writeu16(trunc, 2, 5)
local out = {}; P.UnpackInto(trunc, out, netBase); assert(next(out) == nil, "truncated packet applied")
print(`ok checked={checked} abs={absTotal} delta={deltaTotal} bytes/row={string.format("%.2f", bytes/rows)}`)
