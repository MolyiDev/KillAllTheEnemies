-- Run from the repository root through checks.py (Lune adapters are temporary).
local S=require("./SpatialHash")
local Decoder=require("./SpatialHashDecoder")
local Partitions=require("./MovementPartitions")
local nearest=require("./nearestEnemy")
local V=vector.create
math.randomseed(19351)
local s=S.new(5)
s:AddPoint(1,V(1,0,1));s:Update(1,V(26,2,-17))
assert(s.Records[1].x==26 and s.Records[1].z==-17 and s.Records[1].y==2)
s:Reset()
-- Mix center-indexed and recursively indexed shapes, then compare with brute force.
for id=1,300 do
 local p=V(math.random(-100,100),0,math.random(-100,100))
 if id%3==0 then s:AddPoint(id,p)
 elseif id%3==1 then
  if id%2==0 then s:AddCircleRecursively(id,p,math.random(1,15)) else s:AddCircle(id,p,math.random(1,15)) end
 else
  if id%2==0 then s:AddAABBRecursively(id,p,V(math.random(1,15),1,math.random(1,15))) else s:AddAABB(id,p,V(math.random(1,15),1,math.random(1,15))) end
 end
end
for rep=1,300 do
 local x,z,r=math.random(-100,100),math.random(-100,100),math.random(1,30)
 local shapes,points={},{}
 s:QueryRadius(x,z,r,function(id) assert(not shapes[id],"duplicate shape");shapes[id]=true end)
 s:QueryRadiusAsPoints(x,z,r,function(id) assert(not points[id],"duplicate point");points[id]=true end)
 for id,rec in s.Records do
  local dx,dz=math.abs(rec.x-x),math.abs(rec.z-z)
  local shapeHit
  if rec.shape==0 then shapeHit=dx*dx+dz*dz<=r*r
  elseif rec.shape==1 then shapeHit=dx*dx+dz*dz<=(r+rec.radius)^2
  else local a,b=math.max(0,dx-rec.halfx),math.max(0,dz-rec.halfz);shapeHit=a*a+b*b<=r*r end
  assert((shapes[id]==true)==shapeHit,`shape mismatch {rep} {id}`)
  assert((points[id]==true)==(dx*dx+dz*dz<=r*r),`point mismatch {rep} {id}`)
 end
end
s:Update(2,V(250,0,250));assert(s.Records[2].x==250);s:Remove(2);assert(s.Records[2]==nil)
-- Persistent decode retains identity for surviving rows and prunes removed rows.
local center=S.new(5)
for id=1,1200 do center:AddAABB(id,V(math.random(-100,100),id%5,math.random(-100,100)),V(1,1,1)) end
local d=Decoder.new();d:Decode(S.PackRecords(center.Records),S.PackBuckets(center.FineBuckets))
local rec=d.Records[3]
center:Remove(4);center:Update(3,V(18,0,18))
d:Decode(S.PackRecords(center.Records),S.PackBuckets(center.FineBuckets))
assert(d.Records[3]==rec and d.Records[4]==nil and rec.x==18)
local positions={}
for id,p in d.Records do positions[id]=V(p.x,p.y,p.z) end
for id=1,1200 do
 local p=V(math.random(-130,130),0,math.random(-130,130))
 local expected,offset,absolute=nearest(p,id,positions)
 local found,actual,point=nearest(p,id,nil,d.Buckets,d.Records)
 assert(found==expected and actual==offset and point==absolute,`nearest mismatch {id}`)
end
-- Archetype coalescing aligns all seven columns and caps job count.
local archetypes={}
local nextId=0
for a=1,91 do
 local cols,entities={},{}
 for col=1,7 do cols[col]={} end
 for i=1,a%31+1 do
  nextId+=1;entities[i]=nextId
  for col=1,7 do cols[col][i]=nextId*10+col end
 end
 archetypes[a]={entities=entities,columns_map=cols}
end
local q={ids={1,2,3,4,5,6,7},archetypes=function() return archetypes end}
local b=Partitions.new(16)
local chunks,entities,jobs=b:Build(q)
assert(jobs<=16)
local seen=0
for j=1,jobs do
 for i,id in entities[j] do
  seen+=1;for col=1,7 do assert(chunks[j][col][i]==id*10+col) end
 end
end
assert(seen==nextId)
table.clear(archetypes);local _,_,empty=b:Build(q);assert(empty==0)
print("PASS: hash brute force, recursive update/removal, persistent decoder/pruning, 1200 nearest comparisons, 91-archetype partition alignment")
-- Execute the actual extracted commit guards against the installed jecs version.
local jecs=require("./Jecs")
local w=jecs.world()
local components={MovementRevision=w:component(),InstanceId=w:component(),Position=w:component()}
local tags={Flying=w:entity(),Charmed=w:entity(),Stunned=w:entity(),Telegraphing=w:entity()}
local entities,revisions={},{}
for i=1,1000 do
 local e=w:entity();entities[i]=e;revisions[e]=i
 w:set(e,components.MovementRevision,i)
 w:set(e,components.InstanceId,i)
 w:set(e,components.Position,V(i,0,i))
 if i%4>=2 then w:add(e,tags.Flying) end
 if i%2==0 then w:add(e,tags.Charmed) end
 if i%11==0 then w:add(e,tags.Stunned) end
 if i%13==0 then w:add(e,tags.Telegraphing) end
 if i%17==0 then w:set(e,components.MovementRevision,i+1) end
 if i%19==0 then w:remove(e,components.Position) end
 if i%23==0 then w:delete(e);w:entity() end
end
for _,spec in {{"EnemiesActor",false,false},{"FlyingEnemiesActor",true,false},{"CharmEnemiesActor",false,true},{"CharmFlyingEnemiesActor",true,true}} do
 local commit=require("./"..spec[1])
 for _,e in entities do
  local expectedId,expectedPos
  if w:contains(e) and w:get(e,components.MovementRevision)==revisions[e]
   and w:has(e,tags.Flying)==spec[2] and w:has(e,tags.Charmed)==spec[3]
   and not w:has(e,tags.Stunned) and not w:has(e,tags.Telegraphing) then
   expectedId,expectedPos=w:get(e,components.InstanceId,components.Position)
   if not expectedId or not expectedPos then expectedId,expectedPos=nil,nil end
  end
  local id,pos=commit(w,e,revisions,components,tags,jecs)
  assert(id==expectedId and pos==expectedPos,`commit guard mismatch {spec[1]} {e}`)
 end
end
print("PASS: 4000 real-jecs commit guard comparisons including deleted/recycled entities, revisions, roles, stun and removed columns")
