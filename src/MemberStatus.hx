package mods.party_time_auto_game_joiner;

/** Current session evidence takes priority over coarse friend presence. */
class MemberStatus {
	public static function label(online:Bool, present:Bool, inDungeon:Bool, place:String, atResults:Bool):String {
		if (!online)
			return "Offline";
		if (present)
			return atResults ? "At results" : "In your dungeon";
		if (inDungeon)
			return place == null || place == "" ? "In a dungeon" : place;
		return "In town";
	}
}
