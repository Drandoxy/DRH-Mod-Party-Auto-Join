package mods.party_time_auto_game_joiner;

import openfl.display.Sprite;
import openfl.display.Bitmap;
import openfl.text.TextField;
import brain.assetRepository.AssetLoadingComponent;
import facade.DBFacade;

/** Steam-only portrait. Never substitutes an in-game hero in town. */
class SteamPortrait extends Sprite {
	var assets:AssetLoadingComponent;
	var facade:DBFacade;
	var size:Float;
	var url = "";
	var generation = 0;
	var hint:TextField;

	public var imageReady = false;

	public function new(facade:DBFacade, size:Float) {
		super();
		this.facade = facade;
		this.size = size;
		mouseEnabled = mouseChildren = false;
		hint = Theme.text(this, "?", Std.int(size * 0.55), 0xD8CBA9);
		hint.x = size * 0.3;
		hint.y = size * 0.12;
		hint.width = size * 0.7;
		hint.height = size;
	}

	public function bindFriend(friend:account.FriendInfo):Void {
		update(0, friend == null ? "" : friend.steamAvatarUrl);
	}

	public function update(skin:Int, next:String = ""):Void {
		if (next == null)
			next = "";
		if (next == url)
			return;
		url = next;
		generation++;
		var token = generation;
		imageReady = false;
		while (numChildren > 1)
			removeChild(getChildAt(numChildren - 1));
		hint.visible = true;
		if (assets != null)
			assets.destroy();
		assets = null;
		if (url == "")
			return;
		assets = new AssetLoadingComponent(facade);
		assets.getImageAsset(url, function(image:brain.assetRepository.ImageAsset) {
			if (token != generation || image == null || image.image == null || image.image.bitmapData == null)
				return;
			var bitmap = new Bitmap(image.image.bitmapData);
			bitmap.smoothing = true;
			var factor = size / Math.max(bitmap.width, bitmap.height);
			bitmap.scaleX = bitmap.scaleY = factor;
			bitmap.x = (size - bitmap.width) / 2;
			bitmap.y = (size - bitmap.height) / 2;
			addChild(bitmap);
			hint.visible = false;
			imageReady = true;
		}, function() {});
	}

	public function destroy():Void {
		generation++;
		if (assets != null)
			assets.destroy();
		assets = null;
		facade = null;
		if (parent != null)
			parent.removeChild(this);
	}
}
