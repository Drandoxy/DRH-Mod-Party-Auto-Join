import mods.party_auto_join.StagePresence;
class StagePresenceChecks {
 static function main() {
  var s = new StagePresence();
  s.observe("castle", 1, true, 0); s.present(2, 0);
  if(s.loading(2, 1)) throw "normal floor must not retain";
  s.observe("", 0, true, 100);
  if(!s.loading(2, 5099) || s.loading(3, 200)) throw "retain only prior companions";
  s.observe("castle", 2, true, 200);
  if(!s.loading(2, 5099) || s.loading(2, 5100)) throw "five-second boundary extended";
  s.present(2, 5101); if(s.loading(2, 5101)) throw "returned hero still loading";
  s.observe("other", 1, true, 5200); if(s.loading(2, 5200)) throw "other dungeon retained";
  s.present(2, 5200);s.observe("", 0, true, 5300);s.observe("",0,false,5400);
  if(s.loading(2,5400)) throw "town/results retained";
  s.observe("castle",1,true,5500);s.present(2,5500);s.observe("",0,true,5600);s.observe("castle",1,true,5700);
  if(s.loading(2,5700)) throw "same-floor gap retained";
  trace("PASS: stage-only grace, prior members, exact timeout, return, town and dungeon reset");
 }
}
