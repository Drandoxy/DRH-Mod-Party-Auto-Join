package mods.party_auto_join;

import facade.DBFacade;
import brain.assetRepository.AssetLoadingComponent;
import brain.assetRepository.SwfAsset;
import openfl.display.Sprite;
import openfl.display.MovieClip;
import openfl.display.DisplayObject;
import openfl.display.DisplayObjectContainer;
import openfl.text.TextField;
import openfl.text.TextFormat;
import openfl.geom.Rectangle;

/** Loads native artwork once. Every live UIButton is explicitly released with its owner. */
class GameArt {
	public static var current:GameArt;

	public var facade(default, null):DBFacade;

	var assets:AssetLoadingComponent;
	var hud:SwfAsset;
	var report:SwfAsset;
	var template:TextField;
	var pending:Array<Void->Void> = [];
	var pendingFonts:Array<Void->Void> = [];
	var dead = false;
	var boards:haxe.ds.ObjectMap<Sprite, Dynamic> = new haxe.ds.ObjectMap();

	public function new(facade:DBFacade) {
		this.facade = facade;
		current = this;
		assets = new AssetLoadingComponent(facade);
		assets.getSwfAsset(DBFacade.buildFullDownloadPath("Resources/Art2D/UI/db_UI_HUD.swf"), function(a) {
			if (dead)
				return;
			hud = a;
			var p = profile();
			if (p != null)
				template = cast p.getChildByName("HP_text");
			var jobs = pendingFonts;
			pendingFonts = [];
			for (job in jobs)
				job();
		});
		assets.getSwfAsset(DBFacade.buildFullDownloadPath("Resources/Art2D/UI/db_UI_score_report.swf"), function(a) {
			if (dead)
				return;
			report = a;
			drain();
		});
	}

	function drain():Void {
		if (report == null)
			return;
		var jobs = pending;
		pending = [];
		for (job in jobs)
			job();
	}

	public function font(field:TextField, size:Int, color:Int, center:Bool = false, ?ready:Void->Void):Void {
		var apply = function() {
			if (dead)
				return;
			var fmt = template == null ? new TextFormat("Futura Bold", size, color, true) : template.getTextFormat();
			if (center)
				fmt.font = "Fat Rhino PB";
			fmt.size = size;
			fmt.color = color;
			fmt.align = center ? openfl.text.TextFormatAlign.CENTER : openfl.text.TextFormatAlign.LEFT;
			field.defaultTextFormat = fmt;
			field.setTextFormat(fmt);
			if (template != null) {
				field.embedFonts = template.embedFonts;
				field.filters = [];
			}
			if (ready != null)
				ready();
		};
		if (template == null && hud == null)
			pendingFonts.push(apply);
		else
			apply();
	}

	public function profile():MovieClip {
		if (hud == null)
			return null;
		var fresh:MovieClip = cast hud.instantiateRuntimeSymbol("ui_hud_old", []);
		if (fresh == null)
			return null;
		NativeButton.stop(fresh);
		var p:MovieClip = cast fresh.getChildByName("UI_profile");
		if (p == null)
			return null;
		p.parent.removeChild(p);
		p.x = 0;
		p.y = 0;
		p.scaleX = p.scaleY = 1;
		p.mouseEnabled = false;
		p.mouseChildren = false;
		// In the authored old HUD the unnamed red pennant is immediately before the avatar slot.
		var avatar = p.getChildByName("avatar");
		if (avatar != null) {
			var index = p.getChildIndex(avatar);
			if (index > 0)
				p.removeChild(p.getChildAt(index - 1));
		}
		for (n in [
			"HP_bar_delta",
			"mana_bar_delta",
			"HP_bar_invincible",
			"HP_full_text",
			"mana_full_text"
		]) {
			var child = p.getChildByName(n);
			if (child != null)
				p.removeChild(child);
		}
		return p;
	}

	/** Heart and potion are one authored vector layer in the original HUD.
		Mask each original drawing instead of replacing it with a custom icon. */
	public function vitalIcon(mana:Bool, size:Float):Sprite {
		if (hud == null)
			return null;
		var fresh:MovieClip = cast hud.instantiateRuntimeSymbol("ui_hud_old", []);
		if (fresh == null)
			return null;
		NativeButton.stop(fresh);
		var profile:MovieClip = cast fresh.getChildByName("UI_profile");
		if (profile == null || profile.numChildren < 7)
			return null;
		var art = profile.getChildAt(6);
		profile.removeChild(art);
		var holder = new Sprite();
		var content = new Sprite();
		var mask = new Sprite();
		holder.mouseEnabled = holder.mouseChildren = false;
		content.addChild(art);
		holder.addChild(content);
		holder.addChild(mask);
		var left = 118.;
		var top = mana ? 66. : 34.;
		var side = 38.;
		content.x = -left;
		content.y = -top;
		mask.graphics.beginFill(0xFFFFFF);
		mask.graphics.drawRect(0, 0, side, side);
		mask.graphics.endFill();
		content.mask = mask;
		holder.scaleX = holder.scaleY = size / side;
		return holder;
	}

	public function board(holder:Sprite, w:Float, h:Float):Void {
		holder.graphics.clear();
		var record = boards.get(holder);
		if (record != null) {
			record.w = w;
			record.h = h;
			if (record.skin != null) {
				var existing:DisplayObject = cast record.skin;
				existing.width = w;
				existing.height = h;
			}
			return;
		}
		record = {
			w: w,
			h: h,
			skin: null,
			released: false
		};
		boards.set(holder, record);
		var build = function() {
			if (dead || record.released)
				return;
			var fresh:MovieClip = cast report.instantiateRuntimeSymbol("DRfriends_UI_score_report", []);
			if (fresh == null)
				return;
			NativeButton.stop(fresh);
			var popup:MovieClip = cast fresh.getChildByName("dungeon_popup");
			if (popup == null || popup.numChildren == 0)
				return;
			var skin = popup.getChildAt(0);
			popup.removeChild(skin);
			skin.name = "party_native_board";
			holder.addChildAt(skin, 0);
			var sprite = Std.downcast(skin, Sprite);
			if (sprite != null) {
				var own = sprite.getBounds(sprite);
				var inset = Math.min(14, Math.min(own.width, own.height) / 4);
				sprite.scale9Grid = new Rectangle(own.x + inset, own.y + inset, own.width - inset * 2, own.height - inset * 2);
			}
			skin.width = record.w;
			skin.height = record.h;
			var bounds = skin.getBounds(holder);
			skin.x -= bounds.x;
			skin.y -= bounds.y;
			skin.mouseEnabled = false;
			record.skin = skin;
		};
		if (report == null)
			pending.push(build);
		else
			build();
	}

	public function release(owner:DisplayObject):Void {
		var old:Array<Sprite> = [];
		for (holder in boards.keys()) {
			var node:DisplayObject = holder;
			while (node != null && node != owner)
				node = node.parent;
			if (node == owner)
				old.push(holder);
		}
		for (holder in old) {
			boards.get(holder).released = true;
			boards.remove(holder);
		}
	}

	public function destroy():Void {
		dead = true;
		pending = [];
		pendingFonts = [];
		boards = new haxe.ds.ObjectMap();
		assets.destroy();
		template = null;
		hud = null;
		report = null;
		if (current == this)
			current = null;
	}
}
