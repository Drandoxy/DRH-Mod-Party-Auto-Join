package mods.party_auto_join;

import openfl.display.Sprite;
import openfl.text.TextField;
import openfl.text.TextFormat;

/** Test stand-in for Theme: only the text label the results lock adds. */
class Theme {
	public static function text(parent:Sprite, value:String, size:Int = 14, color:Int = 0xFFF3CF):TextField {
		var field = new TextField();
		field.text = value;
		field.defaultTextFormat = new TextFormat(null, size, color, false);
		parent.addChild(field);
		return field;
	}
}
