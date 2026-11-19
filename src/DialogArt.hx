package mods.party_auto_join;

import brain.assetRepository.AssetLoadingComponent;
import brain.assetRepository.SwfAsset;
import facade.DBFacade;
import openfl.display.MovieClip;
import openfl.text.TextField;
import openfl.text.TextFormat;

/** Exact town popup/prompt symbols and font extraction used by Ultimate Records. */
class DialogArt {
	public static var current:DialogArt;

	public var ready(default, null) = false;

	var loader:AssetLoadingComponent;
	var town:SwfAsset;
	var dead = false;
	var titleFont = "_sans";
	var bodyFont = "_sans";
	var embedded = false;

	public function new(facade:DBFacade) {
		current = this;
		loader = new AssetLoadingComponent(facade);
		loader.getSwfAsset(DBFacade.buildFullDownloadPath("Resources/Art2D/UI/db_UI_town.swf"), function(asset:SwfAsset) {
			if (dead)
				return;
			var sample = create(asset, "popup");
			if (sample == null)
				return;
			var title = field(sample, "title_label");
			var body = field(sample, "message_label");
			if (title == null || body == null)
				return;
			titleFont = title.defaultTextFormat.font;
			bodyFont = body.defaultTextFormat.font;
			embedded = title.embedFonts;
			town = asset;
			ready = true;
		});
	}

	static function create(asset:SwfAsset, name:String):MovieClip {
		var type:Dynamic = asset.getClass(name);
		return type == null ? null : cast ASCompat.createInstance(type, []);
	}

	public function popup():MovieClip {
		return ready ? create(town, "popup") : null;
	}

	public function button():MovieClip {
		return ready ? create(town, "UI_prompt_button_extended") : null;
	}

	public static function field(clip:MovieClip, name:String):TextField {
		var child = clip.getChildByName(name);
		return Std.isOfType(child, TextField) ? cast child : null;
	}

	public function format(field:TextField, title:Bool, size:Int, color:Int):Void {
		var fmt = new TextFormat(title ? titleFont : bodyFont, size, color);
		fmt.align = openfl.text.TextFormatAlign.CENTER;
		field.defaultTextFormat = fmt;
		field.setTextFormat(fmt);
		field.embedFonts = embedded;
		field.filters = [new openfl.filters.GlowFilter(0x330000, 1, 4, 4, 4)];
	}

	public function destroy():Void {
		dead = true;
		loader.destroy();
		town = null;
		ready = false;
		if (current == this)
			current = null;
	}
}
