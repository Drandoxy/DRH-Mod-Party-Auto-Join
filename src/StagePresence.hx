package mods.party_auto_join;

/** Visual grace only: never changes join policy or the leader-offline timer. */
class StagePresence {
	var map = "";
	var number = 0;
	var deadline = -1;
	var gap = false;
	var lastSeen = new haxe.ds.IntMap<Int>();
	var retained = new haxe.ds.IntMap<Bool>();

	public function new() {}

	public function reset():Void {
		map = "";
		number = 0;
		deadline = -1;
		gap = false;
		lastSeen.clear();
		retained.clear();
	}

	public function observe(nextMap:String, nextNumber:Int, eligible:Bool, now:Int):Void {
		if (!eligible) {
			reset();
			return;
		}
		if (nextNumber <= 0 || nextMap == null || nextMap == "") {
			if (number > 0 && !gap) {
				begin(now);
				gap = true;
			}
			return;
		}
		if (number > 0 && (nextMap != map || nextNumber < number)) {
			reset();
		} else if (number > 0 && nextNumber > number) {
			if (!gap)
				begin(now);
		} else if (gap) {
			// The old floor returned: this was not a stage change.
			deadline = -1;
			retained.clear();
		}
		map = nextMap;
		number = nextNumber;
		gap = false;
	}

	function begin(now:Int):Void {
		deadline = now + 5000;
		retained.clear();
		for (id in lastSeen.keys())
			if (now - lastSeen.get(id) <= 1500)
				retained.set(id, true);
	}

	public function present(id:Int, now:Int):Void {
		lastSeen.set(id, now);
		retained.remove(id);
	}

	public function loading(id:Int, now:Int):Bool {
		return now < deadline && retained.exists(id);
	}
}
