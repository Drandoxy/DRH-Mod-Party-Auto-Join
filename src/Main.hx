package mods.party_time_auto_game_joiner;

import account.FriendInfo;
import mods.api.Mod;
import mods.api.Context;
import mods.api._internal.Hub;
import facade.DBFacade;
import distributedObjects.DistributedDungeonSummary;
import openfl.events.Event;
import facade.Locale;
import brain.event.EventComponent;
import openfl.Lib;
import openfl.ui.Keyboard;

class Main extends Mod {
	var errorHook = new EventHook("REQUEST_ENTRY_FAILED");
	var retryPopup:PartyDialog;
	var noticePopup:PartyDialog;
	var retryPaused = false;
	var manualOnly = false;
	var pendingExitCallback = false;
	var leaderWasHere = false;
	var leaderDepartureSeen = false;
	var autoHoldUntilLeave = false;
	var startupNeedsApproval = false;
	var startupDeclined = false;
	var startupPopup:PartyDialog;
	var startupDetails:Dynamic;
	var startupPromptNode = 0;
	var leaderReturnedPrompt = false;
	var leaderOfflineAt = -1;
	var returningForOffline = false;
	var presenceEvents:EventComponent;
	var art:GameArt;
	var dialogArt:DialogArt;
	var heroSnapshots:haxe.ds.IntMap<Dynamic> = new haxe.ds.IntMap();
	var ctx:Context;
	var keySubscription:Dynamic;
	var facade:DBFacade;
	var state:PartyState;
	var panel:PartyPanel;
	var addButton:FriendButton;
	var subscriptions:Array<Dynamic> = [];
	var summary:Dynamic;
	var resultDepartures:haxe.ds.IntMap<Bool> = new haxe.ds.IntMap();
	var lock = new SummaryLock();
	var policy = new FollowPolicy();
	var nextTick = 0;
	var nextPresence = 0;
	var markerPath:String;
	var nextMarker = 0;
	var markerWas = false;
	var joining = false;
	var joinEnteredLoading = false;
	var sharedNode = 0;
	var joinDeadline = 0;
	var targetId = 0;
	var leaderNode = 0;
	var presenceEpoch = 0;
	var lastNode = 0;
	var promptKey = "";
	var lastError = "";
	var status = "";
	var startupTraceLast = "";
	var startupTraceSeen:Map<String, Bool> = new Map();
	var startupTraceUntil = 0;

	function startupTrace(stage:String):Void {
		if (ctx == null
			|| stage == startupTraceLast
			|| startupTraceSeen.exists(stage)
			|| (startupTraceUntil > 0 && Lib.getTimer() > startupTraceUntil))
			return;
		startupTraceLast = stage;
		startupTraceSeen.set(stage, true);
		try {
			sys.io.File.saveContent(ctx.data + "/startup-stage.json", haxe.Json.stringify({version: "0.1.40", stage: stage, time: Date.now().toString()}));
		} catch (_:Dynamic) {}
	}

	override public function init(context:Context):Void {
		ctx = context;
		state = new PartyState(ctx.data + "/party.json");
		markerPath = ctx.data + "/waiting.json";
		clearMarker();
		keySubscription = ctx.keys.action("toggleParty", "Toggle Party Time panel", "Show or hide the party panel.", Keyboard.P, true, true)
			.onPress(function() {
				state.shown = !state.shown;
				state.save();
				if (panel != null)
					panel.visible = state.shown;
			});
	}

	override public function ready(context:Context):Void {
		facade = ctx.core.facade;
		startupTraceUntil = Lib.getTimer() + 20000;
		startupTrace("ready");
		if (state.contains(facade.accountId))
			state.remove(facade.accountId);
		manualOnly = state.autoJoinPaused;
		retryPaused = manualOnly;
		if (manualOnly)
			lastError = "Automatic joining paused";
		startupNeedsApproval = state.leader > 0 && !manualOnly;
		addButton = new FriendButton(facade, addMember, function(message) {
			ctx.log(message);
		});
		addButton.contains = state.contains;
		addButton.remove = removeMember;
		addButton.notify = showNotification;
		if (state.members.length > 0)
			startParty();
		ctx.core.overlay.addEventListener(Event.ENTER_FRAME, frame);
	}

	function showNotification(message:String):Void {
		if (noticePopup != null)
			noticePopup.destroy();
		noticePopup = new PartyDialog(ctx, "Party Time", message, null, null, function() {
			noticePopup = null;
		});
	}

	function startParty():Void {
		if (panel != null)
			return;
		startupTrace("party-art");
		dialogArt = new DialogArt(facade);
		art = new GameArt(facade);
		startupTrace("party-panel");
		panel = new PartyPanel(ctx, state);
		panel.onManualJoin = manualJoin;
		panel.onPauseJoin = pauseAutoJoin;
		panel.onLeader = setLeader;
		panel.onRemove = removeMember;
		panel.onFollow = answer;
		startupTrace("party-rows-build");
		panel.rebuild();
		startupTrace("party-watchers");
		presenceEvents = new EventComponent(facade);
		presenceEvents.addListener("PlayerExitEvent_str", leaderExitedResults);
		presenceEvents.addListener("REFRESH_FRIENDS_EVENT", function(_) {
			refreshRows();
			if (state.leader > 0)
				poll(true);
		});
		subscriptions.push(ctx.core.onFieldReceived(function(object, id, name) {
			if (facade != null && state.leader > 0 && Std.string(name).indexOf("PresenceManager.friendState") >= 0)
				poll(true);
		}));
		subscriptions.push(ctx.core.onStateEnter(function(machine, state) {
			if (joining && state.name == "LoadingScreenState") {
				var events:EventComponent = cast Read.get(state, "mEventComponent");
				errorHook.arm(events, joinFailed);
			}
		}));
		subscriptions.push(ctx.core.onStateExit(function(machine, state) {
			if (state.name == "LoadingScreenState")
				errorHook.restore();
		}));
		subscriptions.push(ctx.core.onObjectReady(function(o) {
			if (Std.isOfType(o, DistributedDungeonSummary)) {
				resultDepartures.clear();
				summary = o;
			}
		}));
		subscriptions.push(ctx.core.onObjectGone(function(o) {
			if (o == summary) {
				lock.restore();
				summary = null;
			}
		}));
	}

	function stopParty():Void {
		if (noticePopup != null)
			noticePopup.destroy();
		noticePopup = null;
		if (dialogArt != null)
			dialogArt.destroy();
		dialogArt = null;
		if (presenceEvents != null) {
			presenceEvents.destroy();
			presenceEvents = null;
		}
		for (subscription in subscriptions)
			subscription.cancel();
		subscriptions = [];
		errorHook.restore();
		lock.restore();
		if (startupPopup != null) {
			startupPopup.destroy();
			startupPopup = null;
		}
		if (retryPopup != null) {
			retryPopup.destroy();
			retryPopup = null;
		}
		startupDetails = null;
		if (panel != null) {
			panel.destroy();
			panel = null;
		}
		if (art != null) {
			art.destroy();
			art = null;
		}
		heroSnapshots.clear();
		summary = null;
		joining = false;
		// Preserve Dungeon Manager's automatic-action hold until leaving this run.
		if (!autoHoldUntilLeave)
			clearMarker();
	}

	function friend(id:Int):FriendInfo {
		if (facade == null || facade.dbAccountInfo == null)
			return null;
		return facade.dbAccountInfo.friendInfos.itemFor(id);
	}

	function addMember(value:Dynamic):Void {
		var info:FriendInfo = cast value;
		if (info == null)
			return;
		var id = Std.int(info.id);
		if (id == facade.accountId) {
			showNotification("Your own character is already on the game's HUD.");
			return;
		}
		if (id <= 0) {
			ctx.log("Party + could not resolve selected friend ID");
			showNotification("The selected friend is not ready yet. Reopen their portrait menu and try again.");
			return;
		}
		if (!state.add(id, info.name)) {
			status = state.contains(id) ? "Already in party" : "Party is full (4 friends)";
			if (state.contains(id)) {
				state.shown = true;
				state.save();
				panel.visible = true;
			} else
				showNotification(status);
			return;
		}
		startParty();
		ctx.log("Party + added friend " + id);
		state.shown = true;
		state.save();
		panel.visible = true;
		panel.rebuild();
		refreshRows();
	}

	function followingLeader():Bool {
		return state.leader > 0 && state.leader != facade.accountId && !manualOnly && !retryPaused && !startupNeedsApproval;
	}

	function releaseAutomationHold():Void {
		autoHoldUntilLeave = false;
		lock.restore();
		clearMarker();
	}

	function setLeader(id:Int):Void {
		manualOnly = false;
		state.autoJoinPaused = false;
		state.save();
		leaderReturnedPrompt = false;
		leaderOfflineAt = -1;
		returningForOffline = false;
		if (id == 0 && state.leader > 0 && (summary != null || facade.mainStateMachine.currentStateName == "RunState"))
			autoHoldUntilLeave = true;
		startupNeedsApproval = false;
		startupDeclined = false;
		if (startupPopup != null) {
			startupDetails = null;
			startupPopup.destroy();
			startupPopup = null;
		}
		if (retryPopup != null) {
			retryPopup.destroy();
			retryPopup = null;
		}
		lastError = "";
		state.setLeader(id);
		policy.reset();
		retryPaused = false;
		leaderWasHere = false;
		leaderDepartureSeen = false;
		sharedNode = 0;
		lastNode = 0;
		leaderNode = 0;
		presenceEpoch++;
		promptKey = "";
		panel.ask(false);
		clearMarker();
		updateMarker(followingLeader(), Lib.getTimer());
		lock.apply(summary, followingLeader());
		if (id == 0) {
			lock.restore();
			joining = false;
			targetId = 0;
			status = "";
		}
		joining = false;
		targetId = 0;
		if (state.leader > 0) {
			// Selecting leadership is not consent to join or leave a dungeon.
			pauseAutoJoin();
		} else {
			refreshRows();
		}
	}

	function removeMember(id:Int):Void {
		if (state.leader == id)
			setLeader(0);
		state.remove(id);
		heroSnapshots.remove(id);
		if (state.members.length == 0) {
			stopParty();
			return;
		}
		panel.rebuild();
		refreshRows();
	}

	function here(id:Int):Dynamic {
		var manager = facade == null ? null : facade.gameObjectManager;
		if (manager == null || ctx.state.floor == null || summary != null)
			return null;
		for (p in ctx.state.players)
			if (p.accountId == id && p.hero != null) {
				var h = manager.getReferenceFromId(p.hero.id);
				if (h != null)
					return h;
			}
		return null;
	}

	function refreshRows():Void {
		if (panel == null)
			return;
		panel.autoJoining = state.leader > 0 && !manualOnly && !retryPaused && !startupNeedsApproval;
		var data:Array<Dynamic> = [];
		var running = facade.mainStateMachine.currentStateName == "RunState" || summary != null;
		if (!running) {
			heroSnapshots.clear();
			resultDepartures.clear();
		}
		for (m in state.members) {
			var f = friend(m.id);
			if (m.id == facade.accountId && f == null)
				f = facade.dbAccountInfo.localFriendInfo;
			var hero = here(m.id);
			if (hero != null)
				heroSnapshots.set(m.id, {
					skinType: Read.number(hero, "skinType", 151),
					hitPoints: Read.number(hero, "hitPoints"),
					maxHitPoints: Read.number(hero, "maxHitPoints", 1),
					manaPoints: Read.number(hero, "manaPoints"),
					maxManaPoints: Read.number(hero, "maxManaPoints", 1)
				});
			else if (summary != null) {
				var savedHero = heroSnapshots.get(m.id);
				if (savedHero != null)
					hero = {
						skinType: savedHero.skinType,
						hitPoints: savedHero.maxHitPoints,
						maxHitPoints: savedHero.maxHitPoints,
						manaPoints: savedHero.maxManaPoints,
						maxManaPoints: savedHero.maxManaPoints
					};
			}
			var label = hero != null ? "In your dungeon" : (running ? "Not in your dungeon" : (f != null && f.isOnline() ? "Online" : "Offline"));
			if (m.id == state.leader && status != "")
				label = status;
			var actionStatus = label;
			var online = f != null && f.isOnline();
			var departed = summary != null && resultDepartures.exists(m.id);
			if (departed)
				hero = null;
			label = MemberStatus.label(online, hero != null && !departed, f != null && f.isInDungeon(), f == null ? null : f.dungeonName, summary != null);
			data.push({
				friend: f,
				hero: online ? hero : null,
				online: online,
				status: label,
				actionStatus: actionStatus,
				manual: online && m.id == state.leader && retryPaused && retryPopup == null && lastError != ""});
		}
		panel.refresh(data, running);
	}

	function frame(event:Event):Void {
		// Empty roster: only discover native friend buttons; no presence polling,
		// game-object watchers, portraits, panel animations or asset bundles.
		startupTrace("friend-button-tick");
		addButton.tick();
		if (state.members.length == 0) {
			if (autoHoldUntilLeave) {
				var scene = facade.mainStateMachine.currentStateName;
				if (scene == "TownState")
					autoHoldUntilLeave = false;
				updateMarker(false, Lib.getTimer());
			}
			return;
		}
		var scene = facade.mainStateMachine.currentStateName;
		if (scene == "TownState")
			autoHoldUntilLeave = false;
		panel.visible = state.shown
			&& (scene == "TownState" || scene == "RunState")
			&& (summary == null || Read.number(summary, "mRevealState") >= 12);
		if (!panel.visible)
			panel.closeMenu();
		var now = Lib.getTimer();
		if (now < nextTick)
			return;
		nextTick = now + 100;
		if (joining && now > joinDeadline) {
			showJoinError("The join request timed out before entry was confirmed.");
		}
		if (joining
			&& joinEnteredLoading
			&& facade.mainStateMachine.currentStateName == "RunState"
			&& summary == null
			&& here(state.leader) != null) {
			joining = false;
			targetId = 0;
			policy.failures = 0;
			leaderDepartureSeen = false;
			status = "In your dungeon";
		}
		if (summary == null && here(state.leader) != null)
			leaderWasHere = true;
		var waiting = followingLeader();
		if (!waiting && state.leader > 0)
			autoHoldUntilLeave = false;
		updateMarker(waiting, now);
		lock.apply(summary, waiting);
		if (now >= nextPresence) {
			nextPresence = now + 1000;
			startupTrace("presence-poll");
			poll(false);
		}
		startupTrace("rows-refresh");
		refreshRows();
		startupTrace("frame-complete");
	}

	function leaderExitedResults(event:Dynamic):Void {
		if (summary == null)
			return;
		var id = Std.int(Read.number(event, "id"));
		if (id <= 0)
			return;
		resultDepartures.set(id, true);
		if (state.leader <= 0 || id != state.leader)
			return;
		leaderDepartureSeen = true;
		policy.nextAttempt = Math.max(policy.nextAttempt, Lib.getTimer() + 1500);
		ctx.log("Leader left the results session; following their next joinable game, including the same dungeon.");
	}

	function poll(force:Bool):Void {
		if (manualOnly)
			return;
		if (state.leader <= 0 || state.leader == facade.accountId) {
			leaderNode = 0;
			panel.ask(false);
			return;
		}
		var presence = facade.mDistributedObjectManager == null ? null : facade.mDistributedObjectManager.mPresenceManager;
		var node = presence == null ? 0 : Std.int(presence.InDungeonId(state.leader));
		if (node != lastNode) {
			if (leaderWasHere && (lastNode > 0 || node == 0))
				leaderDepartureSeen = true;
			presenceEpoch++;
			lastNode = node;
			promptKey = "";
			panel.ask(false);
		}
		leaderNode = node;
		var key = state.leader + ":" + node + ":" + presenceEpoch;
		var current = facade.mainStateMachine.currentStateName;
		var transition = current != "TownState" && current != "RunState";
		var inRun = current == "RunState";
		var promptFriend:FriendInfo = friend(state.leader);
		var leaderJoinable = promptFriend != null && promptFriend.isOnline() && promptFriend.isInDungeon() && node > 0;
		if (startupPopup != null && (!leaderJoinable || current != "TownState" || node != startupPromptNode)) {
			startupPopup.destroy();
			startupPopup = null;
			startupDetails = null;
			startupPromptNode = 0;
			// Presence invalidation is not a Yes/No response. Keep consent pending.
			startupNeedsApproval = true;
			startupDeclined = false;
		}
		if (startupNeedsApproval) {
			if (!startupDeclined && startupPopup == null && leaderJoinable && current == "TownState") {
				var layer:String = facade.menuNavigationController.getTopUILayer();
				if (layer != null && (layer != null && (layer.indexOf("POPUP") >= 0 || layer == "SETTINGS_MENU")))
					return;
				if (dialogArt == null || !dialogArt.ready)
					return;
				var name = "your friend";
				for (member in state.members)
					if (member.id == state.leader)
						name = member.name;
				var respond = function(yes:Bool) {
					startupDetails = null;
					startupPopup = null;
					startupPromptNode = 0;
					if (!yes) {
						pauseAutoJoin();
						return;
					}
					startupNeedsApproval = false;
					startupDeclined = false;
					retryPaused = false;
					lastError = "";
					status = "Waiting for Leader";
					policy.reset();
					var latest:FriendInfo = friend(state.leader);
					if (latest == null || !latest.isOnline() || !latest.isInDungeon())
						leaderUnavailableNotice();
					else
						poll(true);
					refreshRows();
				};
				var leaderInfo = friend(state.leader);
				if (leaderInfo == null)
					return;
				var place = leaderInfo.dungeonName;
				if (place == null || place == "")
					return;
				var url = leaderInfo.steamAvatarUrl;
				startupDetails = {
					facade: facade,
					friend: leaderInfo,
					name: name,
					location: place == null ? "In a dungeon" : Std.string(place),
					question: leaderReturnedPrompt ? "Your leader is online again. Join them?" : "Start automatically joining your leader?",
					skin: Std.int(Read.number(leaderInfo, "skinId", 151)),
					url: url == null ? "" : Std.string(url),
					portrait: null
				};
				startupTrace("startup-dialog");
				startupPromptNode = node;
				var startupQuestion:String = leaderReturnedPrompt ? "Your leader is online again. Join them?" : "Start automatically joining your leader?";
				startupPopup = new PartyDialog(ctx, "Party Time", startupQuestion, startupDetails, function() {
					respond(true);
				}, function() {
					respond(false);
				});
				startupTrace("startup-dialog-ready");
			}
			return;
		}
		var leaderInfo = friend(state.leader);
		var leaderOffline = leaderInfo != null && !leaderInfo.isOnline();
		if (leaderOffline && (inRun || summary != null) && !joining) {
			if (leaderOfflineAt < 0)
				leaderOfflineAt = Lib.getTimer();
			if (Lib.getTimer() - leaderOfflineAt >= 5000 && !returningForOffline)
				returnAfterLeaderOffline();
			return;
		} else
			leaderOfflineAt = -1;
		if (returningForOffline || retryPaused || retryPopup != null)
			return;
		if (here(state.leader) != null) {
			sharedNode = node;
			leaderWasHere = true;
			leaderDepartureSeen = false;
		}
		if (leaderWasHere && sharedNode > 0 && node == sharedNode && !leaderDepartureSeen) {
			panel.ask(false);
			status = "Waiting for Leader";
			return;
		}
		if (leaderWasHere && !leaderDepartureSeen) {
			status = "Waiting for Leader";
			return;
		}
		var action = policy.decide(Lib.getTimer(), state.leader, facade.accountId, node, here(state.leader) != null, inRun, summary != null, transition
			|| joining, key);
		if (action == "ask") {
			promptKey = key;
			panel.ask(true);
			status = "Leader is in another dungeon";
		} else if (action == "join") {
			if (summary != null && SummaryRules.blocked(summary) != null) {
				status = "Finish collecting your rewards";
				return;
			}
			var layer:String = facade.menuNavigationController.getTopUILayer();
			if (current == "TownState" && (layer != null && (layer.indexOf("POPUP") >= 0 || layer == "SETTINGS_MENU")))
				return;
			status = "Joining leader...";
			requestJoin(false);
		} else if (node == 0)
			status = "Waiting for Leader";
	}

	function returnAfterLeaderOffline():Void {
		returningForOffline = true;
		startupNeedsApproval = true;
		startupDeclined = false;
		leaderReturnedPrompt = true;
		autoHoldUntilLeave = true;
		panel.ask(false);
		var name = "Your leader";
		for (member in state.members)
			if (member.id == state.leader)
				name = member.name;
		var machine = facade.mainStateMachine;
		pendingExitCallback = true;
		machine.setOneShotReloadTownCallback(function() {
			pendingExitCallback = false;
			returningForOffline = false;
			leaderOfflineAt = -1;
			machine.enterTownState();
			if (ctx.core.alive)
				showNotification(name + " has left the game. You have returned to town.");
		});
		try {
			if (summary != null) {
				var section = Read.get(summary, "mNextFloorSection");
				var callback = Read.get(section, "mCallback");
				if (!Reflect.isFunction(callback))
					throw "Summary exit is not ready";
				Reflect.callMethod(summary, callback, []);
			} else {
				facade.dbAccountInfo.dbAccountParams.flushParams();
				facade.mDistributedObjectManager.mMatchMaker.RequestExit();
			}
		} catch (error:Dynamic) {
			pendingExitCallback = false;
			returningForOffline = false;
			machine.setOneShotReloadTownCallback(machine.enterTownState);
			leaderOfflineAt = Lib.getTimer();
			ctx.log("Leader offline: could not return to town: " + Std.string(error));
		}
	}

	function pauseAutoJoin():Void {
		releaseAutomationHold();
		manualOnly = true;
		joining = false;
		targetId = 0;
		state.autoJoinPaused = true;
		state.save();
		retryPaused = true;
		startupNeedsApproval = false;
		startupDeclined = true;
		if (startupPopup != null)
			startupPopup.destroy();
		startupPopup = null;
		startupDetails = null;
		if (retryPopup != null)
			retryPopup.destroy();
		retryPopup = null;
		panel.ask(false);
		lastError = "Automatic joining paused";
		status = "Auto join paused - click Join";
		refreshRows();
	}

	function manualJoin():Void {
		manualOnly = false;
		state.autoJoinPaused = false;
		state.save();
		startupNeedsApproval = false;
		startupDeclined = false;
		if (startupPopup != null) {
			startupDetails = null;
			startupPopup.destroy();
			startupPopup = null;
		}
		retryPaused = false;
		lastError = "";
		policy.reset();
		leaderDepartureSeen = true;
		var presence = facade.mDistributedObjectManager.mPresenceManager;
		leaderNode = presence == null ? 0 : Std.int(presence.InDungeonId(state.leader));
		if (leaderNode <= 0) {
			retryPaused = false;
			lastError = "";
			status = "Following leader - waiting for a game";
			refreshRows();
			return;
		}
		if (facade.mainStateMachine.currentStateName == "RunState" && summary == null) {
			promptKey = "manual";
			panel.ask(true);
		} else
			requestJoin(false);
	}

	function answer(yes:Bool):Void {
		var key = promptKey;
		promptKey = "";
		panel.ask(false);
		if (!yes) {
			policy.dismissed = key;
			if (key == "manual") {
				pauseAutoJoin();
				return;
			}
			status = "Follow declined";
			return;
		}
		requestJoin(true);
	}

	function requestJoin(confirmed:Bool):Void {
		if (manualOnly
			|| startupNeedsApproval
			|| joining
			|| state.leader <= 0
			|| state.leader == facade.accountId
			|| leaderNode <= 0)
			return;
		var current = facade.mainStateMachine.currentStateName;
		if (current == "RunState" && summary == null && !confirmed)
			return;
		if (current != "RunState" && current != "TownState")
			return;
		var avatar = facade.dbAccountInfo.activeAvatarInfo;
		if (avatar == null || facade.dbAccountInfo.inventoryInfo.getEquipedItemsOnAvatar(avatar.id).length == 0) {
			status = "Equip a weapon to join";
			policy.delay(Lib.getTimer());
			return;
		}
		if (summary != null) {
			var reason = SummaryRules.blocked(summary);
			if (reason != null) {
				status = reason;
				lastError = reason;
				retryPaused = true;
				refreshRows();
				return;
			}
		}
		ctx.log("Following leader: requesting join from " + current + " to dungeon node " + leaderNode);
		joining = true;
		joinEnteredLoading = false;
		targetId = state.leader;
		joinDeadline = Lib.getTimer() + 60000;
		policy.delay(Lib.getTimer());
		panel.ask(false);
		try {
			if (current == "TownState") {
				joinNow();
				return;
			}
			var machine = facade.mainStateMachine;
			var requested = targetId;
			pendingExitCallback = true;
			machine.setOneShotReloadTownCallback(function() {
				pendingExitCallback = false;
				if (!ctx.core.alive || state.leader != requested || !joining) {
					machine.enterTownState();
					return;
				}
				joinNow();
			});
			if (summary != null) {
				var section = Read.get(summary, "mNextFloorSection");
				var callback = Read.get(section, "mCallback");
				if (!Reflect.isFunction(callback))
					throw "summary exit not ready";
				Reflect.callMethod(summary, callback, []);
			} else {
				facade.dbAccountInfo.dbAccountParams.flushParams();
				facade.mDistributedObjectManager.mMatchMaker.RequestExit();
			}
		} catch (error:Dynamic) {
			showJoinError(Std.string(error));
		}
	}

	function leaderUnavailableNotice():Void {
		joining = false;
		targetId = 0;
		startupNeedsApproval = false;
		startupDeclined = false;
		retryPaused = false;
		lastError = "";
		status = "Waiting for Leader";
		var latest:FriendInfo = friend(state.leader);
		var online = latest != null && latest.isOnline();
		var message = online ? "Sorry, your leader is in town now, so their game could not be joined. Once they start a game, you will join automatically." : "Your leader is no longer online, so their game could not be joined. Following remains enabled; you will be asked again when they return and start a game.";
		showNotification(message);
	}

	function joinNow():Void {
		if (manualOnly)
			return;
		if (state.leader != targetId || targetId <= 0) {
			joining = false;
			return;
		}
		var presence = facade.mDistributedObjectManager.mPresenceManager;
		if (presence == null || !presence.isInDungeon(targetId)) {
			if (facade.mainStateMachine.currentStateName != "TownState")
				facade.mainStateMachine.enterTownState();
			leaderUnavailableNotice();
			return;
		}
		joinEnteredLoading = true;
		facade.mainStateMachine.enterLoadingScreenState(0, "", targetId, 0, false);
	}

	function joinFailed(event:Dynamic):Void {
		if (manualOnly)
			return;
		var code = Std.int(Read.number(event, "errorCode"));
		var message = Locale.getError(code);
		showJoinError(message + " (" + code + ")");
	}

	function showJoinError(message:String):Void {
		errorHook.restore();
		joining = false;
		joinEnteredLoading = false;
		targetId = 0;
		retryPaused = true;
		releaseAutomationHold();
		status = "Join failed";
		lastError = message;
		if (retryPopup != null)
			return;
		var respond = function(yes:Bool) {
			retryPopup = null;
			if (!yes)
				pauseAutoJoin();
			else {
				retryPaused = false;
				status = "Retrying join...";
				lastError = "";
				policy.nextAttempt = Lib.getTimer() + 1500;
				policy.dismissed = "";
			}
			if (facade.mainStateMachine.currentStateName == "LoadingScreenState")
				facade.mainStateMachine.enterReloadTownState(true);
			else if (yes)
				requestJoin(true);
		};
		retryPopup = new PartyDialog(ctx, "Retry joining?", message, null, function() {
			respond(true);
		}, function() {
			respond(false);
		});
	}

	function updateMarker(waiting:Bool, now:Int):Void {
		if ((waiting || autoHoldUntilLeave) && now >= nextMarker) {
			nextMarker = now + 1000;
			sys.io.File.saveContent(markerPath, haxe.Json.stringify({waiting: waiting, autoHold: autoHoldUntilLeave, time: Date.now().getTime()}));
			markerWas = true;
		} else if (!waiting && !autoHoldUntilLeave && markerWas)
			clearMarker();
	}

	function clearMarker():Void {
		if (markerPath != null && sys.FileSystem.exists(markerPath))
			sys.FileSystem.deleteFile(markerPath);
		markerWas = false;
		nextMarker = 0;
	}

	override public function dispose():Void {
		if (keySubscription != null) {
			keySubscription.cancel();
			keySubscription = null;
		}
		if (presenceEvents != null) {
			presenceEvents.destroy();
			presenceEvents = null;
		}
		if (startupPopup != null) {
			startupDetails = null;
			startupPopup.destroy();
			startupPopup = null;
		}
		heroSnapshots.clear();
		joining = false;
		errorHook.restore();
		if (retryPopup != null) {
			retryPopup.destroy();
			retryPopup = null;
		}
		clearMarker();
		lock.restore();
		if (pendingExitCallback && facade != null && facade.mainStateMachine != null)
			facade.mainStateMachine.setOneShotReloadTownCallback(facade.mainStateMachine.enterTownState);
		if (panel != null)
			panel.destroy();
		if (addButton != null)
			addButton.destroy();
		if (art != null)
			art.destroy();
		ctx.core.overlay.removeEventListener(Event.ENTER_FRAME, frame);
		for (s in subscriptions)
			s.cancel();
		subscriptions = [];
		summary = null;
		facade = null;
	}
}
