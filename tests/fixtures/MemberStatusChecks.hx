import mods.party_time_auto_game_joiner.MemberStatus;
class MemberStatusChecks {
 static function main() {
  if (MemberStatus.label(true, true, false, null, true) != "At results") throw "results replaced by town";
  if (MemberStatus.label(true, true, true, "Old dungeon", true) != "At results") throw "stale dungeon replaced results";
  if (MemberStatus.label(true, true, false, null, false) != "In your dungeon") throw "live hero replaced by town";
  if (MemberStatus.label(false, true, false, null, true) != "Offline") throw "offline ignored";
  if (MemberStatus.label(true, false, false, null, true) != "In town") throw "departed member retained at results";
  if (MemberStatus.label(true, false, true, "Barrows", true) != "Barrows") throw "other dungeon lost";
  trace("PASS: results/live session evidence, offline, departure and other dungeon statuses");
 }
}
