import brain.uI.UIButton;
import mods.party_auto_join.SummaryLock;
import openfl.display.Sprite;

class FakeNavigation {
	public var layers = "DISTRIBUTED_DUNGEON_SUMMARY, ";
	public var replaced = 0;
	public var focusedUiObject:Dynamic;

	public function new() {}

	public function getAllCurrentLayers():String
		return layers;

	public function getTopUILayer():String
		return layers == "" ? null : "DISTRIBUTED_DUNGEON_SUMMARY";

	public function collectCurrentLayerObjects():Array<Dynamic>
		return [];

	public function replaceLayerUIObjects(layer:String, safe:Dynamic, focus:Dynamic)
		replaced++;
}

class FakeSection {
	public var mBattleButton:UIButton;
	public var enabledCalls = 0;

	public function new(button:UIButton)
		mBattleButton = button;

	public function setButtonEnabled()
		enabledCalls++;
}

/** The results lock must leave a closed (destroyed) results screen alone. */
class SummaryLockChecks {
	static function scene() {
		var navigation = new FakeNavigation();
		var button = new UIButton();
		var parent = new Sprite();
		parent.addChild(button.root);
		var section = new FakeSection(button);
		var summary = {
			mDBFacade: {menuNavigationController: navigation},
			mNextFloorSection: section,
			mUIChatLog: {mChatInputText: {}},
			mTownHeader: {closeButton: null},
			mRevealState: 12
		};
		return {navigation: navigation, button: button, parent: parent, section: section, summary: summary};
	}

	static function check(ok:Bool, label:String) {
		if (!ok)
			throw "FAILED: " + label;
	}

	static function main() {
		check(SummaryLock.layerOpen("DISTRIBUTED_DUNGEON_SUMMARY, "), "layer listed");
		check(!SummaryLock.layerOpen("TOWN, "), "other layer");
		check(!SummaryLock.layerOpen(null), "no layers");

		// Open screen: lock hides the button, restore gives it back.
		var s = scene();
		var lock = new SummaryLock();
		lock.apply(s.summary, true);
		check(s.button.root.parent == null, "button hidden while waiting");
		lock.restore();
		check(s.button.root.parent == s.parent, "button back on an open screen");
		check(s.navigation.replaced == 2, "navigation held and restored");

		// The game closes the results screen (leader followed): nothing is re-added or re-linked.
		var s = scene();
		var lock = new SummaryLock();
		lock.apply(s.summary, true);
		var replacedBefore = s.navigation.replaced;
		s.navigation.layers = "";
		lock.restore(true);
		check(s.button.root.parent == null, "destroyed button not re-added");
		check(s.navigation.replaced == replacedBefore, "no layer replace after close");
		check(s.section.enabledCalls == 0, "no native calls after close");
		check(s.parent.numChildren == 0, "own label removed");

		// Layer already gone without the gone flag (mod disabled during the exit).
		var s = scene();
		var lock = new SummaryLock();
		lock.apply(s.summary, true);
		s.navigation.layers = "";
		lock.restore();
		check(s.button.root.parent == null && s.section.enabledCalls == 0, "closed layer detected");

		// Apply after the layer closed does not touch the screen.
		var s = scene();
		s.navigation.layers = "";
		new SummaryLock().apply(s.summary, true);
		check(s.button.root.parent == s.parent, "no hold on a closed screen");
		trace("SummaryLockChecks ok");
	}
}
