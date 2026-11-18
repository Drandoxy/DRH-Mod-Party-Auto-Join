package mods.party_time_auto_game_joiner;

class Read {
	public static function get(o:Dynamic, n:String):Dynamic {
		if (o == null)
			return null;
		try {
			var f = Reflect.field(o, "get_" + n);
			if (f != null && Reflect.isFunction(f))
				return Reflect.callMethod(o, f, []);
			return Reflect.getProperty(o, n);
		} catch (_:Dynamic) {
			return null;
		}
	}

	public static function call(o:Dynamic, n:String, args:Array<Dynamic>):Dynamic {
		if (o == null)
			return null;
		var f = Reflect.field(o, n);
		return f == null ? null : Reflect.callMethod(o, f, args);
	}

	public static function number(o:Dynamic, n:String, fallback:Float = 0):Float {
		var v = get(o, n);
		return v == null ? fallback : Std.parseFloat(Std.string(v));
	}

	public static function set(o:Dynamic, n:String, v:Dynamic):Void {
		if (o == null)
			return;
		var f = Reflect.field(o, "set_" + n);
		if (f != null && Reflect.isFunction(f))
			Reflect.callMethod(o, f, [v]);
		else
			Reflect.setProperty(o, n, v);
	}
}
