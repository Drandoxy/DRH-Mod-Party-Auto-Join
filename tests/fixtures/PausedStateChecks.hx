import mods.party_time_auto_game_joiner.PartyState;
class PausedStateChecks {
 static function main() {
  var path=Sys.getEnv("TEMP")+"/party-pause-test-"+Std.random(1000000)+".json";
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
