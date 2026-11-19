package mods.party_auto_join;

import brain.assetRepository.AssetLoadingComponent;
import brain.assetRepository.ImageAsset;
import facade.DBFacade;
import openfl.display.Sprite;
import openfl.display.Bitmap;

/** Dialog-owned image only: no HUD font or shared-art callbacks. */
class DialogPortrait extends Sprite {
	var loader:AssetLoadingComponent;
	var closed = false;
	var imageMask = new Sprite();

	public function new(facade:DBFacade, url:String) {
		super();
		mouseEnabled = mouseChildren = false;
		graphics.lineStyle(3, 0x25180C);
		graphics.beginFill(0x3A240E);
		graphics.drawRoundRect(-4, -4, 96, 96, 14, 14);
		graphics.endFill();
		graphics.lineStyle(2, 0xE6BC62);
		graphics.drawRoundRect(-1, -1, 90, 90, 10, 10);
		if (url == null || url == "")
			return;
		loader = new AssetLoadingComponent(facade);
		loader.getImageAsset(url, function(asset:ImageAsset) {
			if (closed || asset == null || asset.image == null || asset.image.bitmapData == null)
				return;
			var image = new Bitmap(asset.image.bitmapData);
			image.smoothing = true;
			var scale = 88 / Math.max(1, Math.min(image.width, image.height));
			image.scaleX = image.scaleY = scale;
			image.x = (88 - image.width) / 2;
			image.y = (88 - image.height) / 2;
			addChild(image);
			imageMask.graphics.beginFill(0);
			imageMask.graphics.drawRoundRect(0, 0, 88, 88, 8, 8);
			imageMask.graphics.endFill();
			addChild(imageMask);
			image.mask = imageMask;
		}, function() {});
	}

	public function destroy():Void {
		closed = true;
		if (loader != null)
			loader.destroy();
		loader = null;
		if (parent != null)
			parent.removeChild(this);
	}
}
