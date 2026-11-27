# Usage, from performance/ingame-2026-11-08 (for tw.py): PYTHONPATH=$PWD python3 <this> <dir holding the probe .luau>
# The probe it injects is the matching studio-*.client.luau here; copy it into that dir under the name it opens.
# One arm of the Animator-step bench: probe in, playtest, god mode, probe out, crowd in, read the probe's lines.
import json, sys, time, tw
S = sys.argv[1]
PROBE = open(S + "/probe_hud.client.luau").read()
sid = tw.session()
def call(name, args, timeout_ok=False):
    r, _ = tw.post({"jsonrpc": "2.0", "id": 3, "method": "tools/call", "params": {"name": name, "arguments": args}}, sid)
    if r is None: return None
    return r["result"]["content"][0]["text"] if "result" in r else json.dumps(r.get("error"))
call("set_active_studio", {"studio": "c07a93ac-d4c9-417c-a70c-74b5d81b8994"})
call("create_instance", {"className": "LocalScript", "name": "PerfProbe", "parentPath": "StarterPlayer.StarterPlayerScripts"})
call("update_script_source", {"path": "StarterPlayer.StarterPlayerScripts.PerfProbe", "source": PROBE})
call("start_playtest", {})
time.sleep(14)
print(call("run_luau_live", {"code": "local p = game:GetService('Players'):GetPlayers()[1]; local CS = require(game:GetService('ServerScriptService').Server.Services.CharacterService); return CS.ToggleGod(p)"}))
print(call("delete_instance", {"path": "StarterPlayer.StarterPlayerScripts.PerfProbe"}))
spawn = """local RS = game:GetService("ReplicatedStorage")
local SSS = game:GetService("ServerScriptService")
local EnemiesService = require(SSS.Server.Services.EnemiesService)
local RoundService = require(SSS.Server.Services.RoundService)
local DataCore = require(RS.GlobalShared.Core.DataCore)
local ArenaCore = require(RS.Shared.Core.ArenaCore)
RoundService.IsSpawningPaused = true
local root = game:GetService("Players"):GetPlayers()[1].Character.HumanoidRootPart
local roster = {}
for _, e in DataCore.Enemies.All do if not e.IsBoss and not e.Boss then table.insert(roster, e.Id) end end
local spawned = 0
for i = 1, 230 do
	local a = math.random() * math.pi * 2
	local r = 30 + math.random() * 70
	local x, z = root.Position.X + math.cos(a) * r, root.Position.Z + math.sin(a) * r
	local y = ArenaCore.GetFloorY(x, z, root.Position.Y + 20)
	if y and EnemiesService.Spawn(roster[i % #roster + 1], vector.create(x, y, z)) then spawned += 1 end
end
return spawned"""
print("spawned", call("run_luau_live", {"code": spawn}))

fight = """local RS = game:GetService("ReplicatedStorage")
local SSS = game:GetService("ServerScriptService")
local EnemiesService = require(SSS.Server.Services.EnemiesService)
local EnemyWorld = require(RS.GlobalShared.ECS.Worlds.EnemyWorld)
local Components = require(RS.GlobalShared.ECS.Components)
local Tags = require(RS.GlobalShared.ECS.Tags)
local getCE = require(RS.GlobalShared.Utils.Functions.getCharacterEntityFromPlayer)
local player = game:GetService("Players"):GetPlayers()[1]
local ce = getCE(player)
local q = EnemyWorld:query(Components.Position):with(Tags.Enemy)
local t0 = os.clock()
local blows = 0
while os.clock() - t0 < 27 do
	local list = {}
	for e in q do
		if math.random() < 0.02 then list[#list + 1] = e end
		if #list >= 4 then break end
	end
	if #list > 0 then EnemiesService.DamageMultiple(ce, list, if math.random() < 0.5 then 1e6 else 15) blows += 1 end
	task.wait(0.1)
end
return blows"""
print("fight blows", call("run_luau_live", {"code": fight}))
import subprocess
r=subprocess.run(["studio-shot","-o","SCRATCH/split_ingame.png"],capture_output=True,text=True)
time.sleep(2)
out = call("get_playtest_output", {})
d = json.loads(out)
lines = [e["message"].split("] ", 1)[1] for e in d["entries"] if "PERF_PROBE" in e["message"]]
errs = [e["message"][:200] for e in d["entries"] if e["type"] == "MessageError" and "access permission" not in e["message"] and "not authorized" not in e["message"]]
for l in lines: print(l)
print("errors:", len(errs)); [print("  ", x) for x in errs[:10]]
call("stop_playtest", {})
