package mods.party_auto_join;

import openfl.display.DisplayObject;
import openfl.display.DisplayObjectContainer;
import openfl.text.TextField;
import brain.uI.UIButton;

private typedef SavedLink = {
	var owner:Dynamic;
	var name:String;
	var target:Dynamic;
	var interaction:Dynamic;
}

/** Reversible summary controls hold. Does not intercept keyboard or chat input. */
class SummaryLock {
	var summary:Dynamic;
	var button:UIButton;
	var callback:Dynamic;
	var enabled = false;
	var visibleBefore = true;
	var buttonParent:DisplayObjectContainer;
	var buttonIndex = 0;
	var label:TextField;
	var extra:DisplayObject;
	var extraParent:DisplayObjectContainer;
	var extraIndex = 0;
	var extraVisible = false;
	var links:Array<SavedLink> = [];
	var previousFocus:Dynamic;
	var navigationHeld = false;
	var replacement:Dynamic;
	var layerSeen = false;

	public function new() {}

	function saveLink(owner:Dynamic, name:String, target:Dynamic):Void {
		links.push({
			owner: owner,
			name: name,
			target: target,
			interaction: Read.get(owner, name + "AdditionalInteraction")
		});
		var direction = name.substr(0, name.length - "Navigation".length);
		Read.call(owner, "clear" + direction.charAt(0).toUpperCase() + direction.substr(1) + "Navigation", []);
	}

	function detachNavigation():Void {
		var facade = Read.get(summary, "mDBFacade");
		var navigation = Read.get(facade, "menuNavigationController");
		if (Read.call(navigation, "getTopUILayer", []) != "DISTRIBUTED_DUNGEON_SUMMARY")
			return;
		var chat = Read.get(summary, "mUIChatLog");
		var safe = Read.get(chat, "mChatInputText");
		if (safe == null)
			return;
		var objects:Array<Dynamic> = cast Read.call(navigation, "collectCurrentLayerObjects", []);
		if (objects == null)
			objects = [];
		var firstHold = !navigationHeld;
		if (firstHold) {
			previousFocus = Read.get(navigation, "focusedUiObject");
			navigationHeld = true;
			replacement = safe;
		}
		for (object in objects)
			for (name in ["leftNavigation", "rightNavigation", "upNavigation", "downNavigation"]) {
				var target = Read.get(object, name);
				if (target == button) {
					saveLink(object, name, target);
				}
			}
		// Disconnect outgoing links as well; native button references stay alive
		// so restoration does not recreate the host's UI objects.
		for (name in ["leftNavigation", "rightNavigation", "upNavigation", "downNavigation"]) {
			var target = Read.get(button, name);
			if (target != null) {
				saveLink(button, name, target);
			}
		}
		var focus = Read.get(navigation, "focusedUiObject");
		var close = Read.get(Read.get(summary, "mTownHeader"), "closeButton");
		var selectInput = firstHold || focus == button || focus == close || focus == null;
		Read.call(navigation, "replaceLayerUIObjects", ["DISTRIBUTED_DUNGEON_SUMMARY", safe, selectInput ? safe : focus]);
		// Native menu selection invokes UIInputText.onSelected, which focuses
		// its TextField. Do not force stage focus or intercept keyboard events.
	}

	public function apply(value:Dynamic, waiting:Bool):Void {
		if (summary != value || !waiting) {
			restore();
			if (!waiting)
				return;
			summary = value;
		}
		if (value == null || screenClosed())
			return;
		var section = Read.get(value, "mNextFloorSection");
		var found:UIButton = cast Read.get(section, "mBattleButton");
		if (button == null && found != null) {
			button = found;
			callback = button.releaseCallback;
			enabled = button.enabled;
			visibleBefore = button.root.visible;
			buttonParent = button.root.parent;
			if (buttonParent != null) {
				buttonIndex = buttonParent.getChildIndex(button.root);
				var rect = button.root.getBounds(buttonParent);
				label = Theme.text(cast buttonParent, "Waiting for Leader", 18, 0xFFE05A);
				label.width = 260;
				label.height = 40;
				label.x = rect.x + rect.width / 2 - 130;
				label.y = rect.y + rect.height / 2 - 32;
				var format = label.defaultTextFormat;
				format.align = openfl.text.TextFormatAlign.CENTER;
				label.setTextFormat(format);
			}
		}
		if (button == null)
			return;
		detachNavigation();
		// Remove the display objects, not just their visibility. Callback removal
		// protects direct native selection until the navigation graph is detached.
		if (button.releaseCallback != null)
			callback = button.releaseCallback;
		button.releaseCallback = null;
		button.enabled = false;
		button.root.visible = false;
		if (button.root.parent != null)
			button.root.parent.removeChild(button.root);
		if (extra == null && buttonParent != null) {
			extra = buttonParent.getChildByName("auto_dungeon_loot_manager_secondary");
			if (extra != null) {
				extraParent = extra.parent;
				extraIndex = extraParent.getChildIndex(extra);
				extraVisible = extra.visible;
			}
		}
		if (extra != null) {
			extra.visible = false;
			if (extra.parent != null)
				extra.parent.removeChild(extra);
		}
	}

	/** True when the navigation layer list contains the results screen layer. */
	public static function layerOpen(layers:String):Bool {
		return layers != null && layers.indexOf("DISTRIBUTED_DUNGEON_SUMMARY,") >= 0;
	}

	/**
	 * True once the game is closing the results screen. The game adds the results layer only after the reveal
	 * and removes it only when leaving (Battle, Close or destroy), so a layer seen earlier and now missing, or the
	 * screen's own leaving flag, means its UI objects are being destroyed. Before the reveal the screen is open.
	 */
	function screenClosed():Bool {
		if (summary == null)
			return true;
		if (Read.get(summary, "mLeaving") == true)
			return true;
		var navigation = Read.get(Read.get(summary, "mDBFacade"), "menuNavigationController");
		if (navigation == null)
			return layerSeen;
		var open = layerOpen(Std.string(Read.call(navigation, "getAllCurrentLayers", [])));
		if (open)
			layerSeen = true;
		return layerSeen && !open;
	}

	/**
	 * Gives the results screen back its controls. `gone` is true once the game has closed the screen: its
	 * UI objects are then destroyed, so only the references are dropped and nothing is re-added or re-linked.
	 */
	public function restore(gone:Bool = false):Void {
		if (gone || screenClosed()) {
			release();
			return;
		}
		for (link in links)
			if (Read.get(link.owner, link.name) == null) {
				Read.set(link.owner, link.name, link.target);
				if (link.interaction != null)
					Read.set(link.owner, link.name + "AdditionalInteraction", link.interaction);
			}
		links = [];
		if (navigationHeld) {
			var facade = Read.get(summary, "mDBFacade");
			var navigation = Read.get(facade, "menuNavigationController");
			var header = Read.get(summary, "mTownHeader");
			var focus = Read.get(navigation, "focusedUiObject");
			Read.call(navigation, "replaceLayerUIObjects", [
				"DISTRIBUTED_DUNGEON_SUMMARY",
				Read.get(header, "closeButton"),
				focus == replacement ? previousFocus : focus
			]);
		}
		if (button != null && button.root != null) {
			if (button.root.parent == null && buttonParent != null)
				buttonParent.addChildAt(button.root, Std.int(Math.min(buttonIndex, buttonParent.numChildren)));
			if (button.releaseCallback == null)
				button.releaseCallback = callback;
			button.enabled = enabled;
			button.root.visible = visibleBefore;
			if (Read.number(summary, "mRevealState") >= 12)
				Read.call(Read.get(summary, "mNextFloorSection"), "setButtonEnabled", []);
		}
		if (extra != null) {
			if (extra.parent == null && extraParent != null)
				extraParent.addChildAt(extra, Std.int(Math.min(extraIndex, extraParent.numChildren)));
			extra.visible = extraVisible;
		}
		release();
	}

	function release():Void {
		if (label != null && label.parent != null)
			label.parent.removeChild(label);
		links = [];
		summary = null;
		button = null;
		callback = null;
		buttonParent = null;
		label = null;
		extra = null;
		extraParent = null;
		previousFocus = null;
		replacement = null;
		navigationHeld = false;
		layerSeen = false;
	}
}
