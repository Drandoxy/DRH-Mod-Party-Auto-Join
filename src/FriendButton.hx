package mods.party_time_auto_game_joiner;

import facade.DBFacade;
import brain.assetRepository.AssetLoadingComponent;
import brain.assetRepository.SwfAsset;
import brain.uI.UIButton;
import uI.leaderboard.UILeaderboard;
import account.FriendInfo;
import openfl.display.MovieClip;
import openfl.display.Sprite;
import openfl.events.MouseEvent;
import openfl.Lib;
import openfl.display.DisplayObject;
import openfl.text.TextField;

private typedef PopupEntry = {
	var popup:MovieClip;
	var root:MovieClip;
	var background:DisplayObject;
	var baseScale:Float;
	var baseY:Float;
	var button:UIButton;
	var original:UIButton;
	var previousDown:Dynamic;
	var shifted:Array<{child:DisplayObject, y:Float}>;
	var title:TextField;
	var friend:FriendInfo;
	var label:String;
	var lastClick:Int;
	var lastTitle:String;
	var lastVisible:Bool;
	var lastTitleY:Float;
	var press:MouseEvent->Void;
	var click:MouseEvent->Void;
}

class FriendButton {
	var facade:DBFacade;
	var assets:AssetLoadingComponent;
	var art:SwfAsset;
	var buttons:Array<PopupEntry> = [];
	var dead = false;
	var add:Dynamic->Void;
	var log:String->Void;

	public var contains:Int->Bool;
	public var notify:String->Void;
	public var remove:Int->Void;

	public function new(facade:DBFacade, add:Dynamic->Void, log:String->Void = null) {
		this.facade = facade;
		this.add = add;
		this.log = log;
		assets = new AssetLoadingComponent(facade);
		assets.getSwfAsset(DBFacade.buildFullDownloadPath("Resources/Art2D/UI/db_UI_leaderboard.swf"), function(s:SwfAsset) {
			if (!dead)
				art = s;
		});
	}

	function selected(leaderboard:UILeaderboard):FriendInfo {
		var slots:Dynamic = Read.get(leaderboard, "mFriendSlots");
		var index = leaderboard.currentPopupIndex;
		if (slots != null)
			try {
				var slot:Dynamic = slots[index];
				var info:FriendInfo = cast Read.get(slot, "mFriendInfo");
				if (info != null)
					return info;
			} catch (_:Dynamic) {}
		var absolute = index + Std.int(Read.number(leaderboard, "mScrollIndex"));
		var online = leaderboard.onlineFriends;
		var offline = leaderboard.offlineFriends;
		if (absolute >= 0 && absolute < online.length)
			return online[absolute];
		absolute -= online.length;
		return absolute >= 0 && absolute < offline.length ? offline[absolute] : null;
	}

	function cleanup(entry:PopupEntry):Void {
		if (Read.get(entry.original, "downNavigation") == entry.button) {
			Read.call(entry.original, "clearDownNavigation", []);
			if (entry.previousDown != null)
				Read.set(entry.original, "downNavigation", entry.previousDown);
		}
		entry.root.removeEventListener(MouseEvent.MOUSE_DOWN, entry.press, true);
		entry.root.removeEventListener(MouseEvent.CLICK, entry.click);

		for (item in entry.shifted) {
			var child:openfl.display.DisplayObject = cast item.child;
			child.y = item.y;
		}
		entry.button.destroy();
		if (entry.root.parent != null)
			entry.root.parent.removeChild(entry.root);
		if (entry.background != null) {
			entry.background.scaleY = entry.baseScale;
			entry.background.y = entry.baseY;
		}
		NativeButton.forget(entry.root);
	}

	function attach(leaderboard:UILeaderboard, popup:MovieClip, original:UIButton, online:Bool):PopupEntry {
		var fresh:MovieClip = cast art.instantiateRuntimeSymbol("DR_leaderboard_online_tooltip", []);
		if (fresh == null)
			return null;
		NativeButton.stop(fresh);
		var root:MovieClip = cast fresh.getChildByName("remove_friend");
		if (root == null)
			return null;
		root.parent.removeChild(root);
		root.transform.matrix = original.root.transform.matrix.clone();
		NativeButton.label(root, "PARTY +", true);
		var bounds = original.root.getBounds(popup);
		var own = root.getBounds(root);
		root.y = bounds.bottom + 7 - own.y * root.scaleY;
		root.name = "party_time_add";
		root.visible = true;
		// In both exported tooltip symbols, depth 1 / child zero is the shared
		// background. Generated names vary in the runtime; do not rely on instance*.
		var background:DisplayObject = online ? cast Read.get(leaderboard, "mOnlinePopupBg") : null;
		if (background == null)
			background = popup.numChildren > 0 ? popup.getChildAt(0) : null;
		popup.addChild(root);
		// Reserve one full native button plus spacing above the existing bottom.
		// Use typed DisplayObjects: Dynamic writes can bypass native property setters.
		var extra = bounds.height + 14;
		var shifted:Array<{child:DisplayObject, y:Float}> = [];
		for (i in 0...popup.numChildren) {
			var child:openfl.display.DisplayObject = popup.getChildAt(i);
			if (child != background) {
				shifted.push({child: child, y: child.y});
				child.y -= extra;
			}
		}
		var title:TextField = cast popup.getChildByName("title_label");
		var button = new UIButton(facade, root);
		var entry:PopupEntry = {
			popup: popup,
			root: root,
			background: background,
			baseScale: background == null ? 1 : background.scaleY,
			baseY: background == null ? 0 : background.y,
			button: button,
			original: original,
			previousDown: Read.get(original, "downNavigation"),
			shifted: shifted,
			title: title,
			friend: null,
			label: "PARTY +",
			lastClick: -1000,
			lastTitle: "",
			lastVisible: false,
			lastTitleY: Math.NaN,
			press: null,
			click: null
		};
		var keep = function() {
			leaderboard.callStopOnPopupTimeToLiveTask();
		};
		entry.press = function(event:MouseEvent) {
			entry.friend = selected(leaderboard);
			keep();
		};
		var activate = function() {
			if (Lib.getTimer() - entry.lastClick < 250)
				return;
			entry.lastClick = Lib.getTimer();
			keep();
			var info:FriendInfo = cast entry.friend;
			if (info == null)
				info = selected(leaderboard);
			entry.friend = null;
			if (info == null) {
				if (log != null)
					log("Party + selection unavailable");
				if (notify != null)
					notify("Please reopen the friend's portrait menu and try Party + again.");
				return;
			}
			if (log != null)
				log("Party + clicked for friend " + info.id);
			try {
				if (contains != null && contains(info.id) && remove != null)
					remove(info.id);
				else
					add(info);
				entry.label = "";
			} catch (error:Dynamic) {
				if (log != null)
					log("Party + failed: " + Std.string(error));
				if (notify != null)
					notify("Could not add friend: " + Std.string(error));
			}
		};
		button.releaseCallback = activate;
		entry.click = function(event:MouseEvent) {
			activate();
		};
		root.addEventListener(MouseEvent.MOUSE_DOWN, entry.press, true);
		root.addEventListener(MouseEvent.CLICK, entry.click);
		if (log != null)
			log("Native Party + attached to " + (online ? "online" : "offline") + " friend popup");
		return entry;
	}

	public function tick():Void {
		if (dead || facade.mainStateMachine.currentStateName != "TownState" || art == null)
			return;
		var stale = buttons.copy();
		for (b in stale)
			if (b.popup.stage == null) {
				cleanup(b);
				buttons.remove(b);
			}
		var leaderboard:UILeaderboard = facade.mainStateMachine.leaderboard;
		if (leaderboard == null)
			return;
		for (i in 0...2) {
			var online = i == 0;
			var popup:MovieClip = online ? leaderboard.onlinePopup : leaderboard.offlinePopup;
			if (popup == null)
				continue;
			var entry:PopupEntry = null;
			for (b in buttons)
				if (b.popup == popup)
					entry = b;
			if (entry == null && !popup.visible)
				continue;
			if (entry == null) {
				var original = online ? leaderboard.removeOnlineFriend : leaderboard.removeOfflineFriend;
				if (original == null || original.root == null)
					continue;
				entry = attach(leaderboard, popup, original, online);
				if (entry == null)
					continue;
				buttons.push(entry);
			}
			if (!popup.visible) {
				entry.lastVisible = false;
				continue;
			}
			// The native popup rebuilds its navigation links on every opening.
			// Link Party into that graph so pointer focus leaves Remove normally.
			if (Read.get(entry.original, "downNavigation") != entry.button) {
				Read.call(entry.original, "clearDownNavigation", []);
				Read.set(entry.original, "downNavigation", entry.button);
			}
			if (Read.get(entry.button, "upNavigation") != entry.original) {
				Read.call(entry.button, "clearUpNavigation", []);
				Read.set(entry.button, "upNavigation", entry.original);
			}
			var partyRoot:MovieClip = cast entry.root;
			if (partyRoot.parent != popup)
				popup.addChild(partyRoot);
			partyRoot.visible = true;
			FriendPopupLayout.placeAfter(popup, entry.original.root, partyRoot);
			if (entry.title != null && (!entry.lastVisible || entry.lastTitle != entry.title.text || entry.lastTitleY != entry.title.y)) {
				entry.lastTitle = entry.title.text;
				var title:openfl.text.TextField = cast entry.title;
				var gift = popup.getChildByName("join_friend");
				var original:UIButton = cast entry.original;
				var first:openfl.display.DisplayObject = gift == null ? original.root : gift;
				// Native title formatting runs when opening the popup. Measure the final
				// wrapped text, then place it above Gift without changing the popup tween.
				var h = Math.max(title.textHeight + 8, 24);
				title.height = h;
				var firstBounds = first.getBounds(popup);
				title.y += firstBounds.top - 10 - title.getBounds(popup).bottom;
				entry.lastTitleY = title.y;
				// Keep the host's original baseline immutable. It recalculates title height
				// on every opening; writing the expanded values back accumulates offsets.
			}
			// The host may restore only the background while the same title
			// remains. Check actual bounds independently of the title guard.
			FriendPopupLayout.fit(popup, entry.background, entry.title, partyRoot);
			entry.lastVisible = true;
			if (popup.visible) {
				var info = selected(leaderboard);
				var label = info != null && contains != null && contains(info.id) ? "PARTY -" : "PARTY +";
				if (label != entry.label) {
					NativeButton.label(entry.root, label, true);
					entry.label = label;
				}
			}
		}
	}

	public function destroy():Void {
		dead = true;
		for (b in buttons)
			cleanup(b);
		buttons = [];
		assets.destroy();
		art = null;
		add = null;
		log = null;
		contains = null;
		notify = null;
		remove = null;
	}
}
