package mods.party_time_auto_game_joiner;

class PartyState {
	public var members:Array<PartyMember> = [];
	public var leader = 0;
	public var autoJoinPaused = false;
	public var x = 35.;
	public var y = 100.;
	public var width = 310.;
	public var height = 290.;
	public var shown = false;
	public var townX = 35.;
	public var townY = 100.;
	public var runX = 35.;
	public var runY = 100.;

	var path:String;

	public function new(path:String) {
		this.path = path;
		try {
			var d = haxe.Json.parse(sys.io.File.getContent(path));
			if (Std.isOfType(d.members, Array))
				for (m in (cast d.members : Array<Dynamic>))
					if (members.length < 4 && m.id != null && Std.parseInt(Std.string(m.id)) > 0 && !contains(Std.int(m.id)))
						members.push(new PartyMember(Std.int(m.id), Std.string(m.name)));
			if (d.leader != null && contains(Std.int(d.leader)))
				leader = Std.int(d.leader);
			for (n in ["x", "y", "width", "height"]) {
				var v = Reflect.field(d, n);
				if (v != null && !Math.isNaN(Std.parseFloat(Std.string(v))))
					Reflect.setField(this, n, Std.parseFloat(Std.string(v)));
			}
			townX = runX = x;
			townY = runY = y;
			for (n in ["townX", "townY", "runX", "runY"]) {
				var v = Reflect.field(d, n);
				if (v != null && !Math.isNaN(Std.parseFloat(Std.string(v))))
					Reflect.setField(this, n, Std.parseFloat(Std.string(v)));
			}
			autoJoinPaused = d.autoJoinPaused == true;
			if (d.shown != null)
				shown = d.shown;
		} catch (_:Dynamic) {}
		width = Math.max(240, Math.min(700, width));
		height = Math.max(130, Math.min(700, height));
	}

	public function contains(id:Int):Bool {
		for (m in members)
			if (m.id == id)
				return true;
		return false;
	}

	public function add(id:Int, name:String):Bool {
		if (id <= 0 || contains(id) || members.length >= 4)
			return false;
		members.push(new PartyMember(id, name));
		save();
		return true;
	}

	public function remove(id:Int):Void {
		members = members.filter(function(m) {
			return m.id != id;
		});
		if (leader == id)
			leader = 0;
		save();
	}

	public function setLeader(id:Int):Void {
		leader = contains(id) ? id : 0;
		save();
	}

	public function savePosition(running:Bool, px:Float, py:Float):Void {
		x = px;
		y = py;
		if (running) {
			runX = px;
			runY = py;
		} else {
			townX = px;
			townY = py;
		}
		save();
	}

	public function save():Void {
		sys.io.File.saveContent(path, haxe.Json.stringify({
			members: members,
			leader: leader,
			autoJoinPaused: autoJoinPaused,
			x: x,
			y: y,
			townX: townX,
			townY: townY,
			runX: runX,
			runY: runY,
			width: width,
			height: height,
			shown: shown
		}, null, "  "));
	}
}
