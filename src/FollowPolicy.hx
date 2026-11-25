package mods.party_auto_join;

/** Presence exposes a map node, not a server instance ID. */
class FollowPolicy {
	public function new() {}

	/**
	 * Whether "Wait in current dungeon" holds this player in the current dungeon.
	 * A follower with "Auto follow everywhere" on always follows its leader, so the wait applies
	 * only when this player leads or is not following anyone automatically.
	 */
	public static function waitingCurrent(inRun:Bool, enabled:Bool, results:Bool, followingEverywhere:Bool = false):Bool {
		return inRun && enabled && !results && !followingEverywhere;
	}

	public static function joinTimedOut(now:Float, deadline:Float, automatic:Bool):Bool {
		return !automatic && now > deadline;
	}

	public static function acceptsStartup(everywhere:Bool, manual:Bool, leader:Int, self:Int):Bool {
		return everywhere && !manual && leader > 0 && leader != self;
	}

	public var nextAttempt = 0.;
	public var failures = 0;
	public var dismissed = "";

	public function reset():Void {
		awaySince = -1;
		awayKey = "";
		townSince = -1;
		townLeader = 0;
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

	var restrictedRun = false;

	/** UR cannot be rejoined: missing heroes across floors must never cause an exit. */
	public function preserveRestrictedRun(map:String, inTown:Bool, results:Bool):Bool {
		if (inTown || results)
			restrictedRun = false;
		else if (map != null && map != "")
			restrictedRun = map.indexOf("INFINITE_") == 0;
		return restrictedRun;
	}

	var observedFloor = 0;
	var stageUntil = 0.;
	var awaitingData = false;

	/**
	 * Floor arrival guard. It lasts until the floor has received everything in view
	 * (interest closure) and the local hero is present, plus one settling second.
	 * Five seconds is only a fallback cap if that signal never arrives.
	 */
	public function stageGuard(now:Float, floor:Int, countdown:Bool, inRun:Bool, dataReady:Bool = false):Bool {
		if (!inRun) {
			observedFloor = 0;
			stageUntil = 0;
			awaitingData = false;
			return false;
		}
		if (floor != observedFloor) {
			observedFloor = floor;
			stageUntil = now + 5000;
			awaitingData = true;
		}
		if (countdown || floor == 0) {
			stageUntil = now + 5000;
			awaitingData = true;
		}
		if (awaitingData && dataReady && !countdown && floor != 0) {
			awaitingData = false;
			stageUntil = Math.min(stageUntil, now + 1000);
		}
		return countdown || now < stageUntil;
	}

	var awaySince = -1.;
	var awayKey = "";

	/**
	 * Leader left this dungeon. A presence change since the leader was last seen here
	 * (another dungeon, or town and back into the same one: a new instance) is proof and
	 * follows at once. Presence has no instance ID, so without a change the absence still
	 * needs a short confirmation.
	 */
	public function confirmedAway(now:Float, enabled:Bool, online:Bool, node:Int, currentNode:Int, here:Bool, transition:Bool, moved:Bool = false):Bool {
		var key = Std.string(node);
		if (!enabled || !online || node <= 0 || here || transition) {
			awaySince = -1;
			awayKey = "";
			return false;
		}
		// The arrival guard already waited for the floor's data plus a second; absence is final.
		return true;
	}

	var townSince = -1.;
	var townLeader = 0;

	public function confirmedTown(now:Float, leader:Int, enabled:Bool, online:Bool, inDungeon:Bool, node:Int, here:Bool):Bool {
		if (!enabled || !online || inDungeon || node != 0 || here || leader <= 0 || townLeader != leader) {
			townSince = -1;
			townLeader = leader;
			if (!enabled || !online || inDungeon || node != 0 || here || leader <= 0)
				return false;
		}
		if (townSince < 0)
			townSince = now;
		return now - townSince >= 1000;
	}

	public function decide(now:Float, leader:Int, self:Int, node:Int, leaderHere:Bool, inRun:Bool, summary:Bool, transitioning:Bool, key:String):String {
		if (leader <= 0 || leader == self || node <= 0 || transitioning || leaderHere && !summary || now < nextAttempt)
			return "wait";
		if (inRun && !summary)
			return dismissed == key ? "wait" : "ask";
		return "join";
	}

	/**
	 * A fully offline leader is never followed: no join attempt and no forced return to Town while
	 * offline. Only a known friend entry that says offline counts; a join already under way finishes.
	 */
	public static function holdForOffline(known:Bool, online:Bool, joining:Bool):Bool {
		return known && !online && !joining;
	}

	/** The map node this client shares with the leader. Town never keeps the previous dungeon's node. */
	public static function sharedNodeFor(town:Bool, joining:Bool, shared:Int):Int {
		return town && !joining ? 0 : shared;
	}

	/** Show the no-weapon notice once per episode; equipping a weapon starts a new episode. */
	public static function showNoWeapon(alreadyShown:Bool, hasWeapon:Bool):Bool {
		return !hasWeapon && !alreadyShown;
	}
}
