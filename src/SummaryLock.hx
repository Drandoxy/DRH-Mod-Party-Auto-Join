package mods.party_time_auto_game_joiner;

import openfl.display.Sprite;
import openfl.display.DisplayObject;
import openfl.display.DisplayObjectContainer;
import openfl.text.TextField;
import brain.uI.UIButton;
import openfl.events.KeyboardEvent;

class SummaryLock {
	var summary:Dynamic;
	var button:UIButton;
	var callback:Dynamic;
	var enabled = false;
	var visibleBefore = true;
	var label:TextField;
	var extra:DisplayObject;
	var extraVisible = false;
	var blocker:Dynamic;
	var keyStage:DisplayObjectContainer;

	public function new() {}

	function key(event:KeyboardEvent):Void {
		if (summary == null || event.keyCode != 13 || SummaryRules.dialogsOpen(summary))
			return;
		var facade = Read.get(summary, "mDBFacade");
		var navigation = Read.get(facade, "menuNavigationController");
		var layer = Read.call(navigation, "getTopUILayer", []);
		if (layer != null && layer != "DISTRIBUTED_DUNGEON_SUMMARY")
			return;
		event.preventDefault();
		event.stopImmediatePropagation();
	}

	function watchKeys():Void {
		if (keyStage != null || button == null || button.root.stage == null)
			return;
		keyStage = button.root.stage;
		for (type in [KeyboardEvent.KEY_DOWN, KeyboardEvent.KEY_UP]) {
			keyStage.addEventListener(type, key, true, 10000);
			keyStage.addEventListener(type, key, false, 10000);
		}
	}

	public function apply(value:Dynamic, waiting:Bool):Void {
		if (summary != value || !waiting) {
			restore();
			if (!waiting)
				return;
			summary = value;
		}
		if (value == null)
			return;
		var section = Read.get(value, "mNextFloorSection");
		var found:UIButton = cast Read.get(section, "mBattleButton");
		if (button == null && found != null) {
			button = found;
			callback = button.releaseCallback;
			enabled = button.enabled;
			visibleBefore = button.root.visible;
			blocker = function() {};
			var parent = button.root.parent;
			if (parent != null) {
				label = Theme.text(cast parent, "Waiting for Leader", 18, 0xFFE05A);
				var rect = button.root.getBounds(parent);
				label.width = 260;
				label.height = 40;
				label.x = rect.x + rect.width / 2 - 130;
				label.y = rect.y + rect.height / 2 - 32;
				var fmt = label.defaultTextFormat;
				fmt.align = openfl.text.TextFormatAlign.CENTER;
				label.setTextFormat(fmt);
			}
		}
		watchKeys();
		if (button != null) {
			if (button.releaseCallback != blocker)
				callback = button.releaseCallback;
			if (button.enabled)
				button.enabled = false;
			button.releaseCallback = blocker;
			button.root.visible = false;
			if (label != null)
				label.visible = true;
			var parent = button.root.parent;
			if (parent != null && extra == null) {
				extra = parent.getChildByName("auto_dungeon_loot_manager_secondary");
				if (extra != null)
					extraVisible = extra.visible;
			}
			if (extra != null)
				extra.visible = false;
		}
	}

	public function restore():Void {
		if (keyStage != null) {
			for (type in [KeyboardEvent.KEY_DOWN, KeyboardEvent.KEY_UP]) {
				keyStage.removeEventListener(type, key, true);
				keyStage.removeEventListener(type, key, false);
			}
			keyStage = null;
		}

		if (button != null && button.root != null) {
			if (button.releaseCallback == blocker)
				button.releaseCallback = callback;
			button.enabled = enabled;
			button.root.visible = visibleBefore;
			var section = Read.get(summary, "mNextFloorSection");
			if (Read.number(summary, "mRevealState") >= 12)
				Read.call(section, "setButtonEnabled", []);
		}
		if (extra != null)
			extra.visible = extraVisible;
		if (label != null && label.parent != null)
			label.parent.removeChild(label);
		summary = null;
		button = null;
		label = null;
		extra = null;
		callback = null;
		blocker = null;
	}
}
