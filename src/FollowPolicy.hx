package mods.party_auto_join;

/** Presence exposes a map node, not a server instance ID. */
class FollowPolicy {
	public function new() {}

	public var nextAttempt = 0.;
	public var failures = 0;
	public var dismissed = "";

	public function reset():Void {
		nextAttempt = 0;
		failures = 0;
		dismissed = "";
	}

	public function delay(now:Float):Void {
		failures++;
		nextAttempt = now + Math.min(60000, 8000 * Math.pow(2, Math.min(3, failures - 1)));
	}

	/** A previous shared session cannot block following after returning to town. */
	public static function waitForDeparture(inRun:Bool, wasHere:Bool, departed:Bool):Bool {
		return inRun && wasHere && !departed;
	}

	public function decide(now:Float, leader:Int, self:Int, node:Int, leaderHere:Bool, inRun:Bool, summary:Bool, transitioning:Bool, key:String):String {
		if (leader <= 0 || leader == self || node <= 0 || transitioning || leaderHere && !summary || now < nextAttempt)
			return "wait";
		if (inRun && !summary)
			return dismissed == key ? "wait" : "ask";
		return "join";
	}
}
