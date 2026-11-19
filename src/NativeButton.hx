package mods.party_auto_join;

import brain.utils.TextUtil;
import openfl.display.DisplayObject;
import openfl.display.DisplayObjectContainer;
import openfl.display.MovieClip;
import openfl.text.TextField;

/** Reuse the authored artwork, embedded font, outline and label alignment. */
class NativeButton {
	static var originals:haxe.ds.ObjectMap<TextField, Dynamic> = new haxe.ds.ObjectMap();

	public static function forget(root:DisplayObject):Void {
		if (Std.isOfType(root, TextField))
			originals.remove(cast root);
		if (Std.isOfType(root, DisplayObjectContainer)) {
			var container:DisplayObjectContainer = cast root;
			for (i in 0...container.numChildren)
				forget(container.getChildAt(i));
		}
	}

	public static function child(root:DisplayObject, name:String):DisplayObject {
		return Std.isOfType(root, DisplayObjectContainer) ? (cast root : DisplayObjectContainer).getChildByName(name) : null;
	}

	public static function label(root:DisplayObject, text:String, fit:Bool = false):Void {
		if (Std.isOfType(root, TextField)) {
			var field:TextField = cast root;
			var original:Dynamic = originals.get(field);
			if (original == null) {
				original = {format: field.getTextFormat(), y: field.y, height: field.height};
				originals.set(field, original);
			}
			field.defaultTextFormat = original.format;
			field.setTextFormat(original.format);
			field.y = original.y;
			field.height = original.height;
			field.selectable = false;
			field.mouseEnabled = false;
			TextUtil.setText(field, text);
			if (fit && field.width > 6 && field.textWidth > field.width - 6) {
				var height = field.textHeight;
				var format = field.getTextFormat();
				var size:Float = cast format.size;
				format.size = size * (field.width - 6) / field.textWidth;
				field.defaultTextFormat = format;
				field.setTextFormat(format);
			}
			if (fit)
				field.y = original.y + (original.height - field.textHeight) * 0.5 - 2;
		}
		if (Std.isOfType(root, DisplayObjectContainer)) {
			var container:DisplayObjectContainer = cast root;
			for (i in 0...container.numChildren)
				label(container.getChildAt(i), text, fit);
		}
	}

	public static function stop(root:DisplayObject):Void {
		if (Std.isOfType(root, MovieClip))
			(cast root : MovieClip).stop();
		if (Std.isOfType(root, DisplayObjectContainer)) {
			var container:DisplayObjectContainer = cast root;
			for (i in 0...container.numChildren)
				stop(container.getChildAt(i));
		}
	}
}
