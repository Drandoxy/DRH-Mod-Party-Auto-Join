package mods.party_auto_join;

import account.FriendInfo;
import mods.api.Mod;
import mods.api.Context;
import facade.DBFacade;
import distributedObjects.DistributedDungeonSummary;
import openfl.events.Event;
import facade.Locale;
import brain.event.EventComponent;
import openfl.Lib;
import openfl.ui.Keyboard;

class Main extends Mod {
	public static var integrationWaiting = false;
	public static var integrationHeld = false;

	var errorHook = new EventHook("REQUEST_ENTRY_FAILED");
	var retryPopup:PartyDialog;
	var noticePopup:PartyDialog;
	var retryPaused = false;
	var manualOnly = false;
	var leaveWithLeader:mods.api.settings.Flag;
	var waitInDungeon:mods.api.settings.Flag;
	var returningWithLeader = false;
	var rewardsReadySince = -1;
	var rewardHoldStarted = -1;
	var rewardHoldDone = false;
	var integrationMarker:openfl.display.Sprite;
	var lastScene = "";
	var leaderMissingSince = -1;
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
	var stagePresence = new StagePresence();
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
	var joining = false;
	var joinEnteredLoading = false;
	/** When this client arrived in RunState after a join, or -1. */
	var joinArrivedAt = -1.;
	/** The leader's presence changed while this client was loading into their game. */
	var movedDuringJoin = false;
	/** False while the floor arrival guard waits for the floor's data. */
	var floorSettled = true;
	var sharedNode = 0;
	/** The no-weapon notice was shown; shown again only after a weapon was equipped in between. */
	var noWeaponShown = false;
	var joinDeadline = 0;
	var targetId = 0;
	var leaderNode = 0;
	var presenceEpoch = 0;
	var lastNode = 0;
	/** Presence changed while the leader was not in this dungeon: they started another game. */
	var leaderMovedSinceHere = false;
	var arrivalFloor = -1;
	var arrivalAt = -1.;
	var leaderSeenOnFloor = false;
	var endingSince = -1.;
	var attemptEpoch = -1;
	var promptKey = "";
	var lastError = "";
	var status = "";

	override public function init(context:Context):Void {
		ctx = context;
		waitInDungeon = ctx.settings.flag("waitInDungeon", "Wait in current dungeon",
			"Stay in your dungeon while a party member is away.", false);
		leaveWithLeader = ctx.settings.flag("leaveWithLeader", "Auto follow everywhere", "Automatically follow your leader between dungeons and Town.", false);
		// Read old preferences once without changing the previous installation's data.
		var statePath = ctx.data + "/party.json";
		var legacyPath = ctx.data + "/../party_time_auto_game_joiner/party.json";
		if (!sys.FileSystem.exists(statePath) && sys.FileSystem.exists(legacyPath))
			sys.io.File.copy(legacyPath, statePath);
		state = new PartyState(statePath);
		if (state.loadError != null)
			note("Saved party could not be read, starting empty: " + state.loadError);
		clearMarker();
		keySubscription = ctx.keys.action("toggleParty", "Toggle Party Auto Join", "Pause and hide, or show in manual mode.", Keyboard.P, true, true)
			.onPress(toggleParty);
	}

	override public function ready(context:Context):Void {
		facade = ctx.core.facade;

		if (state.contains(facade.accountId))
			state.remove(facade.accountId);
		manualOnly = state.autoJoinPaused;
		retryPaused = manualOnly;
		if (manualOnly)
			lastError = "Automatic joining paused";
		startupNeedsApproval = state.leader > 0 && !manualOnly;
		if (state.shown) {
			createFriendButtons();
			if (state.members.length > 0)
				startParty();
		} else {
			pauseAutoJoin();
		}
		ctx.core.overlay.addEventListener(Event.ENTER_FRAME, frame);
	}

	function createFriendButtons():Void {
		if (addButton != null)
			return;
		addButton = new FriendButton(facade, addMember, function(message) {
			note(message);
		});
		addButton.contains = state.contains;
		addButton.remove = removeMember;
		addButton.notify = showNotification;
	}

	function toggleParty():Void {
		// Both transitions resume in manual mode; hiding releases all party
		// watchers and assets. Only the shortcut and dormant frame guard remain.
		pauseAutoJoin();
		state.shown = !state.shown;
		state.save();
		if (!state.shown) {
			stopParty();
			if (addButton != null)
				addButton.destroy();
			addButton = null;
		} else if (facade != null) {
			createFriendButtons();
			if (state.members.length > 0)
				startParty();
		}
	}

	function showNotification(message:String):Void {
		if (!state.shown)
			return;
		if (noticePopup != null)
			noticePopup.destroy();
		noticePopup = new PartyDialog(ctx, "Party Time", message, null, null, function() {
			noticePopup = null;
		});
	}

	function startParty():Void {
		if (panel != null)
			return;

		dialogArt = new DialogArt(facade);
		art = new GameArt(facade);

		panel = new PartyPanel(ctx, state);
		panel.onManualJoin = manualJoin;
		panel.onPauseJoin = pauseAutoJoin;
		panel.onLeader = setLeader;
		panel.onRemove = removeMember;
		panel.onFollow = answer;

		panel.rebuild();

		presenceEvents = new EventComponent(facade);
		presenceEvents.addListener("PlayerExitEvent_str", leaderExitedResults);
		presenceEvents.addListener("REFRESH_FRIENDS_EVENT", function(_) {
			refreshRows();
			if (state.leader > 0)
				poll(true);
		});
		// Presence is polled once per second. Avoid reentrant joins from field dispatch.

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
				rewardHoldDone = false;
				beginRewardHold();
			}
		}));
		subscriptions.push(ctx.core.onObjectGone(function(o) {
			if (o == summary) {
				// The game has already destroyed the results UI: drop references only.
				lock.restore(true);
				summary = null;
			}
		}));
	}

	/** Writes to the game log. */
	/**
	 * Two moments look like the leader leaving but are not: the leader has not appeared yet on a
	 * floor we just loaded (their game loads slower), and the last floor finishing, which removes
	 * every hero and clears their dungeon presence before the results appear. Hold both, briefly,
	 * unless their presence names another dungeon.
	 */
	function holdForLeaderArrivalOrResults(inRun:Bool, node:Int):Bool {
		var now = Lib.getTimer();
		var floorId = ctx.state.floor == null ? -1 : Std.int(ctx.state.floor.id);
		if (floorId != arrivalFloor) {
			arrivalFloor = floorId;
			arrivalAt = now;
			leaderSeenOnFloor = false;
			endingSince = -1;
		}
		var leaderHere = here(state.leader) != null;
		if (leaderHere)
			leaderSeenOnFloor = true;
		if (!inRun || summary != null || leaderHere || floorId < 0) {
			endingSince = -1;
			return false;
		}
		var nativeFloor = facade.gameObjectManager.getReferenceFromId(ctx.state.floor.id);
		var nodeData = Read.get(nativeFloor, "gmMapNode");
		var floorNode = Std.int(Read.number(nodeData, "Id"));
		// Presence naming a different dungeon is a real move: follow it.
		var elsewhere = node > 0 && floorNode > 0 && node != floorNode;
		if (elsewhere)
			return false;
		if (!leaderSeenOnFloor && now - arrivalAt < 10000) {
			status = "Waiting for Leader";
			return true;
		}
		if (leaderSeenOnFloor && isFinalFloor(nodeData, ctx.state.floor.number)) {
			if (endingSince < 0)
				endingSince = now;
			if (now - endingSince < 20000) {
				status = "Waiting for results";
				return true;
			}
		}
		return false;
	}

	/** The last floor of a normal dungeon, read from the map node's tier floor count. */
	function isFinalFloor(nodeData:Dynamic, number:Int):Bool {
		if (nodeData == null)
			return false;
		try {
			var tier:Dynamic = facade.gameMaster.coliseumTierByConstant.itemFor(Read.get(nodeData, "TierRank"));
			var total = Read.number(tier, "TotalFloors");
			return total > 0 && number >= total;
		} catch (error:Dynamic) {
			return false;
		}
	}

	function note(message:String):Void {
		ctx.log(message);
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
		stagePresence.reset();
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
			note("Party + could not resolve selected friend ID");
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
		note("Party + added friend " + id);
		state.shown = true;
		state.save();
		panel.visible = true;
		panel.rebuild();
		refreshRows();
	}

	function followingLeader():Bool {
		return state.leader > 0
			&& state.leader != facade.accountId
			&& state.shown
			&& !manualOnly
			&& !retryPaused
			&& !startupNeedsApproval;
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
		leaderMovedSinceHere = false;
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
		// The player list may lag a floor transition; live hero records are independent evidence.
		for (entry in ctx.state.heroes)
			if (!entry.local && entry.player != null && entry.player.accountId == id) {
				var h = manager.getReferenceFromId(entry.id);
				if (h != null && Read.get(h, "isDestroyed") != true)
					return h;
			}
		return null;
	}

	function refreshRows():Void {
		if (panel == null)
			return;
		panel.autoJoining = state.leader > 0 && state.shown && !manualOnly && !retryPaused && !startupNeedsApproval;
		var data:Array<Dynamic> = [];
		var running = facade.mainStateMachine.currentStateName == "RunState" || summary != null;
		var now = Lib.getTimer();
		var floor = ctx.state.floor;
		stagePresence.observe(floor == null ? "" : floor.map, floor == null ? 0 : floor.number, running && summary == null && !joining, now);
		if (!running) {
			heroSnapshots.clear();
			resultDepartures.clear();
		}
		for (m in state.members) {
			var f = friend(m.id);
			if (m.id == facade.accountId && f == null)
				f = facade.dbAccountInfo.localFriendInfo;
			var hero = here(m.id);
			if (hero != null) {
				stagePresence.present(m.id, now);
				heroSnapshots.set(m.id, {
					skinType: Read.number(hero, "skinType", 151),
					hitPoints: Read.number(hero, "hitPoints"),
					maxHitPoints: Read.number(hero, "maxHitPoints", 1),
					manaPoints: Read.number(hero, "manaPoints"),
					maxManaPoints: Read.number(hero, "maxManaPoints", 1)
				});
			} else if (summary != null) {
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
			var online = MemberStatus.online(f != null && f.isOnline(), hero != null && summary == null);
			var departed = summary != null && resultDepartures.exists(m.id);
			if (departed)
				hero = null;
			var loading = hero == null && !departed && stagePresence.loading(m.id, now);
			if (loading)
				hero = heroSnapshots.get(m.id);
			label = MemberStatus.label(online || loading, hero != null && !departed, f != null && f.isInDungeon(), f == null ? null : f.dungeonName,
				summary != null);
			if (loading)
				label = "Loading next stage...";
			data.push({
				friend: f,
				hero: online || loading ? hero : null,
				online: online || loading,
				status: label,
				actionStatus: actionStatus,
				manual: online && m.id == state.leader && retryPaused && retryPopup == null && lastError != ""});
		}
		panel.refresh(data, running);
	}

	function frame(event:Event):Void {
		if (!state.shown || addButton == null)
			return;
		// Empty roster: only discover native friend buttons; no presence polling,
		// game-object watchers, portraits, panel animations or asset bundles.

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
		if (scene == "TownState" && lastScene != "TownState") {
			returningWithLeader = false;
			returningForOffline = false;
			pendingExitCallback = false;
			joining = false;
			joinEnteredLoading = false;
			targetId = 0;
			leaderWasHere = false;
			leaderMovedSinceHere = false;
			leaderDepartureSeen = true;
			sharedNode = 0;
			policy.reset();
			nextPresence = 0;
		}
		lastScene = scene;
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
		if (joining && FollowPolicy.joinTimedOut(now, joinDeadline, !manualOnly)) {
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
			joinArrivedAt = -1;
			movedDuringJoin = false;
		}
		// Arrived, but the leader is not in this instance: they restarted or moved while this
		// client was loading. End the join so following can act on it, at once if their
		// presence changed meanwhile, otherwise after the normal arrival grace.
		if (joining
			&& joinEnteredLoading
			&& facade.mainStateMachine.currentStateName == "RunState"
			&& summary == null
			&& here(state.leader) == null) {
			if (joinArrivedAt < 0)
				joinArrivedAt = now;
			if (movedDuringJoin || floorSettled && now - joinArrivedAt >= 1000 || now - joinArrivedAt >= 6000) {
				note(["Auto follow: arrived without the leader", "movedDuringJoin " + movedDuringJoin, "after " + Std.int(now - joinArrivedAt) + " ms"].join(" "));
				joining = false;
				targetId = 0;
				joinArrivedAt = -1;
				policy.nextAttempt = 0;
			}
		} else if (!joining)
			joinArrivedAt = -1;
		if (summary == null && here(state.leader) != null)
			leaderWasHere = true;
		var waiting = followingLeader();
		if (!waiting && state.leader > 0)
			autoHoldUntilLeave = false;
		updateMarker(waiting, now);
		lock.apply(summary, waiting);
		if (now >= nextPresence) {
			// Presence is a local cache; check it often while auto following so a move is acted on at once.
			nextPresence = now + (leaveWithLeader != null && leaveWithLeader.value ? 250 : 1000);

			poll(false);
		}

		refreshRows();
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
		note("Leader left the results session; following their next joinable game, including the same dungeon.");
	}

	function beginRewardHold():Void {
		if (rewardHoldStarted < 0 && !rewardHoldDone) {
			rewardHoldStarted = Lib.getTimer();
			rewardsReadySince = -1;
		}
	}

	function holdForRewards():Bool {
		var scene = facade.mainStateMachine.currentStateName;
		if (scene == "TownState") {
			rewardHoldStarted = -1;
			rewardHoldDone = false;
			rewardsReadySince = -1;
			return false;
		}
		if (summary != null)
			beginRewardHold();
		if (ctx != null && ctx.state.floor != null && facade.gameObjectManager != null) {
			var floor = facade.gameObjectManager.getReferenceFromId(ctx.state.floor.id);
			var gui = Read.get(floor, "mFloorEndingGui");
			var renderer = Read.get(gui, "mVictoryRenderer");
			if (Read.get(Read.get(renderer, "clip"), "visible") == true)
				beginRewardHold();
		}
		if (rewardHoldStarted < 0)
			return false;

		if (summary != null && SummaryRules.blocked(summary) == null) {
			if (rewardsReadySince < 0)
				rewardsReadySince = Lib.getTimer();
			if (Lib.getTimer() - rewardsReadySince >= 1000) {
				rewardHoldDone = true;
				rewardHoldStarted = -1;
				return false;
			}
		} else
			rewardsReadySince = -1;
		status = "Waiting for rewards";
		return true;
	}

	function poll(force:Bool):Void {
		var waitHere = waitInDungeon != null && waitInDungeon.value;
		var followingEverywhere = leaveWithLeader != null && leaveWithLeader.value && state.leader > 0 && state.leader != facade.accountId;
		if (FollowPolicy.waitingCurrent(facade.mainStateMachine.currentStateName == "RunState", waitHere, summary != null, followingEverywhere)) {
			leaderOfflineAt = leaderMissingSince = -1;
			policy.reset();
			status = "Waiting for friend - no time limit";
			return;
		}
		if (manualOnly) {
			return;
		}
		if (holdForRewards()) {
			return;
		}
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
			if (leaderWasHere && here(state.leader) == null)
				leaderMovedSinceHere = true;
			if (joining && node > 0)
				movedDuringJoin = true;
			presenceEpoch++;
			lastNode = node;
			promptKey = "";
			panel.ask(false);
		}
		leaderNode = node;
		var key = state.leader + ":" + node + ":" + presenceEpoch;
		var current = facade.mainStateMachine.currentStateName;
		var preserveRun = policy.preserveRestrictedRun(ctx.state.floor == null ? null : ctx.state.floor.map, current == "TownState", summary != null);
		if (preserveRun && followingLeader()) {
			policy.confirmedTown(Lib.getTimer(), state.leader, false, false, true, node, false);
			policy.confirmedAway(Lib.getTimer(), false, false, node, node, false, true);
			leaderOfflineAt = -1;
			leaderMissingSince = -1;
			panel.ask(false);
			status = "Staying in Ultimate Rampage";
			return;
		}
		var nativeStage = ctx.state.floor == null ? null : facade.gameObjectManager.getReferenceFromId(ctx.state.floor.id);
		var endingGui = Read.get(nativeStage, "mFloorEndingGui");
		// Floor data is complete once its interest closure arrived and the local hero exists.
		var localHeroReady = false;
		for (entry in ctx.state.heroes)
			if (entry.local)
				localHeroReady = true;
		var floorDataReady = localHeroReady && Read.get(nativeStage, "pastInitialLoad") == true;
		var stageChanging = policy.stageGuard(Lib.getTimer(), ctx.state.floor == null ? 0 : Std.int(ctx.state.floor.id),
			Read.get(endingGui, "mUpdateCountdownTask") != null, current == "RunState" && summary == null, floorDataReady);
		var transition = (current != "TownState" && current != "RunState") || stageChanging;
		floorSettled = current == "RunState" && !stageChanging;
		var inRun = current == "RunState";
		sharedNode = FollowPolicy.sharedNodeFor(current == "TownState", joining, sharedNode);
		var promptFriend:FriendInfo = friend(state.leader);
		var leaderJoinable = promptFriend != null && promptFriend.isOnline() && promptFriend.isInDungeon() && node > 0;
		if (current != "RunState" && current != "TownState") {
			policy.confirmedTown(Lib.getTimer(), state.leader, false, false, true, node, false);
			policy.confirmedAway(Lib.getTimer(), false, false, node, node, false, true);
			leaderOfflineAt = -1;
			leaderMissingSince = -1;
			return;
		}
		if (startupPopup != null && (!leaderJoinable || current != "TownState" || node != startupPromptNode)) {
			startupPopup.destroy();
			startupPopup = null;
			startupDetails = null;
			startupPromptNode = 0;
			// Presence invalidation is not a Yes/No response. Keep consent pending.
			startupNeedsApproval = true;
			startupDeclined = false;
		}
		if (startupNeedsApproval
			&& FollowPolicy.acceptsStartup(leaveWithLeader != null && leaveWithLeader.value, manualOnly, state.leader, facade.accountId)) {
			if (startupPopup != null)
				startupPopup.destroy();
			startupPopup = null;
			startupDetails = null;
			startupPromptNode = 0;
			startupNeedsApproval = false;
			startupDeclined = false;
			leaderReturnedPrompt = false;
			retryPaused = false;
			lastError = "";
			status = "Waiting for Leader";
			policy.reset();
			note("Auto follow everywhere accepted leader following.");
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

				startupPromptNode = node;
				var startupQuestion:String = leaderReturnedPrompt ? "Your leader is online again. Join them?" : "Start automatically joining your leader?";
				startupPopup = new PartyDialog(ctx, "Party Time", startupQuestion, startupDetails, function() {
					respond(true);
				}, function() {
					respond(false);
				});
			}
			return;
		}
		if (holdForRewards())
			return;
		var leaderInfo = friend(state.leader);
		// A fully offline leader is not followed anywhere: this client stays where it is (its own run
		// included) and simply waits. Following resumes by itself once the leader is online again.
		if (FollowPolicy.holdForOffline(leaderInfo != null, leaderInfo != null && leaderInfo.isOnline(), joining)) {
			leaderOfflineAt = -1;
			panel.ask(false);
			status = "Leader is offline";
			return;
		}
		leaderOfflineAt = -1;

		if (holdForLeaderArrivalOrResults(inRun, node))
			return;
		if (here(state.leader) != null)
			leaderMissingSince = -1;
		else if (leaderMissingSince < 0)
			leaderMissingSince = Lib.getTimer();
		// After the floor's data arrived, a missing leader is final; town still needs one second
		// of town presence because a restart passes through town for a fraction of a second.
		var townEvidenceReady = !transition && leaderMissingSince >= 0;
		var townConfirmed = policy.confirmedTown(Lib.getTimer(),
			state.leader, leaveWithLeader != null && leaveWithLeader.value && followingLeader() && !joining && !stageChanging && townEvidenceReady, leaderInfo != null
			&& leaderInfo.isOnline(), leaderInfo == null || leaderInfo.isInDungeon(), node, here(state.leader) != null);
		if (returningWithLeader)
			return;
		if (townConfirmed && (inRun || summary != null)) {
			returnWithLeader();
			return;
		}
		if (returningForOffline || retryPaused || retryPopup != null)
			return;

		var currentNode:Float = sharedNode > 0 ? sharedNode : node;
		var finalFloor = false;
		// Use the public floor map's GM map node ID when available, never its displayed name.
		if (ctx.state.floor != null) {
			var nativeFloor = facade.gameObjectManager.getReferenceFromId(ctx.state.floor.id);
			var nodeData = Read.get(nativeFloor, "gmMapNode");
			var knownNode = Read.number(nodeData, "Id");
			if (knownNode > 0)
				currentNode = knownNode;
			finalFloor = isFinalFloor(nodeData, ctx.state.floor.number);
		}
		// Proof the leader started another game: their presence changed after they left this
		// dungeon (another dungeon, or town and back into the same one: a new instance).
		var skipGrace = inRun && movedDuringJoin && !joining;
		var leaderMoved = inRun && (leaderMovedSinceHere || skipGrace);
		// Finishing the last floor removes every hero at once before the results appear,
		// so absence alone is not a departure there; require a real presence change.
		var absenceTrusted = !finalFloor || leaderMoved;
		if (policy.confirmedAway(Lib.getTimer(), leaveWithLeader != null && leaveWithLeader.value && followingLeader() && !joining
			&& (!stageChanging || skipGrace) && absenceTrusted, leaderInfo != null
			&& leaderInfo.isOnline(), node, Std.int(currentNode), here(state.leader) != null, skipGrace ? false : transition, leaderMoved)) {
			movedDuringJoin = false;
			leaderDepartureSeen = true;
			// A new leader move is never held back by the retry backoff of an earlier attempt.
			if (Lib.getTimer() >= policy.nextAttempt || attemptEpoch != presenceEpoch) {
				note(inRun ? ["Auto follow: leader left this dungeon, node " + node, "here node " + Std.int(currentNode), "moved " + leaderMovedSinceHere].join(" ")
					: "Auto follow: leader is in dungeon node " + node);
				status = "Following leader...";
				requestJoin(true);
			}
			return;
		}
		if (inRun && here(state.leader) != null) {
			sharedNode = node;
			leaderWasHere = true;
			leaderDepartureSeen = false;
			leaderMovedSinceHere = false;
		}
		if (FollowPolicy.waitForDeparture(inRun, leaderWasHere, leaderDepartureSeen) && sharedNode > 0 && node == sharedNode) {
			panel.ask(false);
			status = "Waiting for Leader";
			return;
		}
		if (FollowPolicy.waitForDeparture(inRun, leaderWasHere, leaderDepartureSeen)) {
			status = "Waiting for Leader";
			return;
		}
		var action = policy.decide(Lib.getTimer(), state.leader, facade.accountId, node, inRun && here(state.leader) != null, inRun, summary != null, transition
			|| joining, key);
		if (action == "ask") {
			promptKey = key;
			if (leaveWithLeader != null && leaveWithLeader.value) {
				// Auto follow everywhere decides on its own; never show the follow prompt.
				panel.ask(false);
				status = "Following leader...";
				return;
			}
			panel.ask(true);
			status = "Leader is in another dungeon";
		} else if (action == "join") {
			if (summary != null && !rewardHoldDone && SummaryRules.blocked(summary) != null) {
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

	function returnWithLeader():Void {
		if (holdForRewards())
			return;
		returningWithLeader = true;
		panel.ask(false);
		status = "Following leader to Town";
		var machine = facade.mainStateMachine;
		pendingExitCallback = true;
		machine.setOneShotReloadTownCallback(function() {
			pendingExitCallback = false;
			returningWithLeader = false;
			machine.enterTownState();
			policy.reset();
			leaderWasHere = false;
			leaderMovedSinceHere = false;
			leaderDepartureSeen = true;
			nextPresence = 0;
			if (ctx.core.alive && followingLeader())
				poll(true);
		});
		try {
			facade.dbAccountInfo.dbAccountParams.flushParams();
			facade.mDistributedObjectManager.mMatchMaker.RequestExit();
		} catch (error:Dynamic) {
			pendingExitCallback = false;
			returningWithLeader = false;
			machine.setOneShotReloadTownCallback(machine.enterTownState);
			policy.reset();
			note("Could not follow leader to town: " + Std.string(error));
		}
	}

	function returnAfterLeaderOffline():Void {
		if (holdForRewards())
			return;
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
				showNotification(name + " has left the game. You have returned to Town.");
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
			note("Leader offline: could not return to town: " + Std.string(error));
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
		if (panel != null)
			panel.ask(false);
		lastError = "Automatic joining paused";
		status = "Auto join paused - click Join";
		if (panel != null)
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
		if (holdForRewards())
			return;
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
			attemptEpoch = presenceEpoch;
			if (FollowPolicy.showNoWeapon(noWeaponShown, false)) {
				noWeaponShown = true;
				note("Cannot follow leader: no weapons equipped");
				showNotification("Cannot follow your leader: you cannot enter a dungeon with no weapons equipped. Equip a weapon and following continues by itself.");
			}
			return;
		}
		noWeaponShown = false;
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
		note("Following leader: requesting join from " + current + " to dungeon node " + leaderNode);
		joining = true;
		leaderMovedSinceHere = false;
		movedDuringJoin = false;
		joinArrivedAt = -1;
		joinEnteredLoading = false;
		targetId = state.leader;
		joinDeadline = Lib.getTimer() + 60000;
		attemptEpoch = presenceEpoch;
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
			if (summary != null && !(confirmed && leaveWithLeader != null && leaveWithLeader.value)) {
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
		// No popup: the party panel already shows where the leader is (In Town or offline).
		status = "Waiting for Leader";
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
		integrationWaiting = waiting;
		integrationHeld = autoHoldUntilLeave;
		if (integrationMarker == null && ctx != null && ctx.core.overlay != null) {
			integrationMarker = new openfl.display.Sprite();
			integrationMarker.visible = false;
			integrationMarker.mouseEnabled = false;
			integrationMarker.mouseChildren = false;
			integrationMarker.name = "party_auto_join_progression_hold";
			ctx.core.overlay.addChild(integrationMarker);
		}
		if (integrationMarker != null)
			integrationMarker.alpha = waiting ? 1 : (autoHoldUntilLeave ? 0.5 : 0);
	}

	function clearMarker():Void {
		integrationWaiting = false;
		integrationHeld = false;
		if (integrationMarker != null && integrationMarker.parent != null)
			integrationMarker.parent.removeChild(integrationMarker);
		integrationMarker = null;
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
