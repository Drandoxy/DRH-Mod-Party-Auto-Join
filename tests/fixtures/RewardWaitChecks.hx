import mods.party_auto_join.SummaryRules;
class RewardWaitChecks {static function main(){
 var s:Dynamic={mRevealState:11,mTownHeader:{},mItemCount:0};if(SummaryRules.blocked(s)==null)throw "XP/reveal not ready";
 s.mRevealState=12;s.mItemCount=2;if(SummaryRules.blocked(s)==null)throw "crates abandoned";
 s.mItemCount=0;s.mChestRevealPopUp={};if(SummaryRules.blocked(s)==null)throw "open reward popup ignored";
 s.mChestRevealPopUp=null;s.mDungeonReport=[{valid:1,chest_type_1:0,chest_type_2:0,chest_type_3:0,chest_type_4:0}];if(SummaryRules.blocked(s)!=null)throw "finished rewards still blocked";
 for(slot in 1...5){Reflect.setField(s.mDungeonReport[0],"chest_type_"+slot,123);if(SummaryRules.blocked(s)==null)throw "unconfirmed slot "+slot;Reflect.setField(s.mDungeonReport[0],"chest_type_"+slot,0);}
 Reflect.deleteField(s.mDungeonReport[0],"chest_type_4");if(SummaryRules.blocked(s)==null)throw "unknown fourth slot accepted";
 trace("PASS: reward reveal, crates and popup guards");}}
