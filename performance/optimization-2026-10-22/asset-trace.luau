-- Temporary early-startup tracer; remove from the DataModel after diagnosis.
local connections={}
local reported={}
local function check(v,property)
 local ok,value=pcall(function() return v[property] end)
 if ok and type(value)=="string" and (value=="rbxassetid://" or string.find(value,"203785492",1,true)) then
  local key=v:GetFullName().." "..property.." "..value
  if not reported[key] then reported[key]=true;print("[BALLARC_ASSET_TRACE] "..key) end
 end
end
local function inspect(v)
 local props=if v:IsA("ImageLabel") or v:IsA("ImageButton") then {"Image"}
  elseif v:IsA("Sound") then {"SoundId"}
  elseif v:IsA("Decal") or v:IsA("Texture") then {"Texture"}
  elseif v:IsA("MeshPart") then {"MeshId","TextureID"}
  elseif v:IsA("SpecialMesh") then {"MeshId","TextureId"}
  elseif v:IsA("Animation") then {"AnimationId"}
  elseif v:IsA("ShirtGraphic") then {"Graphic"}
  elseif v:IsA("Shirt") then {"ShirtTemplate"}
  elseif v:IsA("Pants") then {"PantsTemplate"}
  else {}
 for _,property in props do
  check(v,property)
  connections[#connections+1]=v:GetPropertyChangedSignal(property):Connect(function() check(v,property) end)
 end
end
connections[#connections+1]=game.DescendantAdded:Connect(inspect)
for _,v in game:GetDescendants() do inspect(v) end
task.delay(8,function() for _,c in connections do c:Disconnect() end;table.clear(connections) end)
