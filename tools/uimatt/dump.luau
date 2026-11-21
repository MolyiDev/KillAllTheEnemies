local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")
local process = require("@lune/process")
local db = roblox.getReflectionDatabase()
local game = roblox.deserializePlace(fs.readFile(process.args[1]))

local SKIP = { Name = true, Parent = true, Archivable = true, SourceAssetId = true, UniqueId = true, HistoryId = true,
	Capabilities = true, Sandboxed = true, DefinesCapabilities = true, Tags = true, AttributesSerialize = true,
	Font = true, FontSize = true, BorderColor = true, TextColor = true, Transparency = true, Style = true, Localize = true, RootLocalizationTable = true }

local propCache = {}
local function classProps(className)
	if propCache[className] then return table.unpack(propCache[className]) end
	local props, defaults = {}, {}
	local c = db:GetClass(className)
	while c do
		for name, p in c.Properties do
			local tags = table.concat(p.Tags, ",")
			if not SKIP[name] and p.Scriptability == "ReadWrite" and not tags:find("Deprecated") and not tags:find("Hidden") and not tags:find("NotScriptable") and props[name] == nil then
				props[name] = p.Datatype
			end
		end
		for name, v in c.DefaultProperties do if defaults[name] == nil then defaults[name] = v end end
		c = if c.Superclass then db:GetClass(c.Superclass) else nil
	end
	propCache[className] = { props, defaults }
	return props, defaults
end

local function r(n) return math.round(n * 10000) / 10000 end
local function enc(v)
	local t = typeof(v)
	if t == "UDim2" then return { r(v.X.Scale), v.X.Offset, r(v.Y.Scale), v.Y.Offset } end
	if t == "UDim" then return { r(v.Scale), v.Offset } end
	if t == "Vector2" then return { r(v.X), r(v.Y) } end
	if t == "Vector3" then return { r(v.X), r(v.Y), r(v.Z) } end
	if t == "Color3" then return string.format("#%02X%02X%02X", math.round(v.R * 255), math.round(v.G * 255), math.round(v.B * 255)) end
	if t == "Rect" then return { r(v.Min.X), r(v.Min.Y), r(v.Max.X), r(v.Max.Y) } end
	if t == "EnumItem" then return v.Name end
	if t == "Font" then return { family = v.Family, weight = v.Weight.Name, style = v.Style.Name } end
	if t == "ColorSequence" then local o = {} for _, k in v.Keypoints do table.insert(o, { r(k.Time), enc(k.Value) }) end return o end
	if t == "NumberSequence" then local o = {} for _, k in v.Keypoints do table.insert(o, { r(k.Time), r(k.Value), r(k.Envelope) }) end return o end
	if t == "NumberRange" then return { r(v.Min), r(v.Max) } end
	if t == "number" then return r(v) end
	if t == "Content" then return tostring(v.Uri or v) end
	if t == "Instance" then return v:GetFullName() end
	if t == "boolean" or t == "string" then return v end
	return tostring(v)
end

local function same(a, b)
	if a == b then return true end
	local ok, res = pcall(function() return serde.encode("json", enc(a)) == serde.encode("json", enc(b)) end)
	return ok and res
end

local errs = {}
local function node(inst)
	local props, defaults = classProps(inst.ClassName)
	local out = {}
	for name in props do
		local ok, v = pcall(function() return inst[name] end)
		if ok and v ~= nil then
			local d = defaults[name]
			if d == nil or not same(v, d) then
				local okE, e = pcall(enc, v)
				out[name] = if okE then e else tostring(v)
			end
		elseif not ok then errs[inst.ClassName .. "." .. name] = tostring(v) end
	end
	local attrs = inst:GetAttributes()
	local a = {}
	local hasA = false
	for k, v in attrs do a[k] = enc(v); hasA = true end
	local okT, tags = pcall(function() return inst:GetTags() end)
	local kids = {}
	for _, c in inst:GetChildren() do table.insert(kids, node(c)) end
	return { name = inst.Name, class = inst.ClassName, props = out, attrs = if hasA then a else nil,
		tags = if okT and #tags > 0 then tags else nil, children = kids }
end

local root = {}
for _, svc in { "StarterGui", "Workspace", "ReplicatedStorage", "ReplicatedFirst", "ServerStorage", "StarterPlayer", "Lighting", "TextChatService", "StarterPack", "ServerScriptService" } do
	local s = game:FindFirstChildOfClass(svc) or game:FindFirstChild(svc)
	if s then root[svc] = node(s) end
end
fs.writeFile("dump.json", serde.encode("json", root, true))
for k, v in errs do print("err", k, v) end
