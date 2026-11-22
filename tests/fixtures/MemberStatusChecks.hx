import mods.party_auto_join.MemberStatus;
class MemberStatusChecks {
 static function main() {
  if(!MemberStatus.online(false,true)||MemberStatus.online(false,false)||!MemberStatus.online(true,false))throw "live hero presence lost to stale friend status";
  if (MemberStatus.label(true, true, false, null, true) != "At results") throw "results replaced by town";
  if (MemberStatus.label(true, true, true, "Old dungeon", true) != "At results") throw "stale dungeon replaced results";
  if (MemberStatus.label(true, true, false, null, false) != "In your dungeon") throw "live hero replaced by town";
  if (MemberStatus.label(false, true, false, null, true) != "Offline") throw "offline ignored";
  if (MemberStatus.label(true, false, false, null, true) != "In Town") throw "departed member retained at results";
  if (MemberStatus.label(true, false, true, "Barrows", true) != "Barrows") throw "other dungeon lost";
  trace("PASS: results/live session evidence, offline, departure and other dungeon statuses");
 }
}
