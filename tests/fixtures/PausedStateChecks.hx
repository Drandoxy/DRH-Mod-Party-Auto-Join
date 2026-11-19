import mods.party_auto_join.PartyState;
class PausedStateChecks {
 static function main() {
  var path=Sys.getEnv("TEMP")+"/party-pause-test-"+Std.random(1000000)+".json";
  var fresh = new PartyState(path);
  if (!fresh.shown || fresh.runY < 220 || fresh.leader != 0) throw "unsafe fresh-install defaults";
  sys.io.File.saveContent(path,'{"members":[{"id":2,"name":"Friend"}],"leader":2}');
  var state=new PartyState(path);
  if(state.autoJoinPaused)throw "legacy state incorrectly paused";
  state.autoJoinPaused=true;state.save();
  var restored=new PartyState(path);
  if(!restored.autoJoinPaused||restored.leader!=2||!restored.contains(2))throw "pause not persisted with leader";
  restored.autoJoinPaused=false;restored.save();
  if(new PartyState(path).autoJoinPaused)throw "resume not persisted";
  sys.FileSystem.deleteFile(path);
  trace("PASS: legacy migration, saved pause/resume and retained leader/roster");
 }
}
