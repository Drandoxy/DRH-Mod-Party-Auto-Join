package mods.party_time_auto_game_joiner;

import openfl.display.Sprite;
import openfl.text.TextField;
import openfl.events.MouseEvent;
import openfl.events.Event;
import openfl.geom.Point;
import mods.api.Context;

class PartyPanel extends Sprite {
	var ctx:Context;
	var state:PartyState;
	var header = new Sprite();
	var body = new Sprite();
	var title:TextField;
	var empty:TextField;
	var rows:Array<PartyRow> = [];
	var menu:Sprite;
	var menuMember = 0;
	var prompt:Sprite;
	var promptText:TextField;
	var sceneRun = false;
	var mode = 0;
	var downAt = 0;
	var startX = 0.;
	var startY = 0.;
	var originX = 0.;
	var originY = 0.;
	var lastTime = 0;
	var moving = false;

	public var onManualJoin:Void->Void;
	public var onPauseJoin:Void->Void;
	public var autoJoining(default, set) = false;

	function set_autoJoining(value:Bool):Bool {
		if (autoJoining != value)
			closeMenu();
		autoJoining = value;
		return value;
	}

	public var onLeader:Int->Void;
	public var onRemove:Int->Void;
	public var onFollow:Bool->Void;

	public function new(ctx:Context, state:PartyState) {
		super();
		this.ctx = ctx;
		this.state = state;
		state.width = 310;
		state.height = 430;
		addChild(body);
		addChild(header);
		addEventListener(MouseEvent.MOUSE_DOWN, beginDrag);
		addEventListener(Event.ENTER_FRAME, frame);
		ctx.core.overlay.addChild(this);
		x = state.townX;
		y = state.townY;
		visible = state.shown;
		layout();
	}

	public function rebuild():Void {
		var previous = rows;
		var next:Array<PartyRow> = [];
		for (member in state.members) {
			var row:PartyRow = null;
			for (existing in previous)
				if (existing.id == member.id) {
					row = existing;
					break;
				}
			if (row == null) {
				row = new PartyRow(ctx.core.facade, member, showMenu);
				row.onJoin = function() {
					if (onManualJoin != null)
						onManualJoin();
				};
				body.addChild(row);
			}
			next.push(row);
		}
		for (row in previous)
			if (next.indexOf(row) < 0)
				row.destroy();
		rows = next;
		layout();
	}

	public function refresh(data:Array<Dynamic>, running:Bool):Void {
		if (sceneRun != running) {
			state.savePosition(sceneRun, x, y);
			sceneRun = running;
			x = running ? state.runX : state.townX;
			y = running ? state.runY : state.townY;
			clamp();
		}
		for (i in 0...rows.length) {
			var d = data[i];
			var online = d.online != false;
			rows[i].visible = !running || online;
			if (!rows[i].visible && menuMember == rows[i].id)
				closeMenu();
			rows[i].setJoinVisible(d.manual == true && online);
			rows[i].refresh(d.friend, d.hero, running, state.leader == rows[i].id, state.width - 20, d.status, online);
		}
		layoutRows();
	}

	function point(e:MouseEvent):Point {
		return ctx.core.overlay.globalToLocal(new Point(e.stageX, e.stageY));
	}

	function beginDrag(e:MouseEvent):Void {
		var target:Dynamic = Read.get(e, "target");
		while (target != null && target != this) {
			if (Read.get(target, "buttonMode") == true)
				return;
			target = Read.get(target, "parent");
		}
		begin(e, 1);
	}

	function begin(e:MouseEvent, m:Int):Void {
		e.stopPropagation();
		closeMenu();
		if (stage == null)
			return;
		mode = m;
		downAt = openfl.Lib.getTimer();
		var p = point(e);
		startX = p.x;
		startY = p.y;
		originX = x;
		originY = y;
		stage.addEventListener(MouseEvent.MOUSE_MOVE, drag);
		stage.addEventListener(MouseEvent.MOUSE_UP, endDrag);
	}

	function drag(e:MouseEvent):Void {
		if (mode == 0 || openfl.Lib.getTimer() - downAt < 500)
			return;
		var p = point(e);
		moving = true;
		x = originX + p.x - startX;
		y = originY + p.y - startY;
		clamp();
		e.stopPropagation();
	}

	function endDrag(e:MouseEvent):Void {
		if (stage != null) {
			stage.removeEventListener(MouseEvent.MOUSE_MOVE, drag);
			stage.removeEventListener(MouseEvent.MOUSE_UP, endDrag);
		}
		if (mode != 0) {
			state.savePosition(sceneRun, x, y);
		}
		mode = 0;
		moving = false;
	}

	function clamp():Void {
		x = Math.max(0, Math.min(x, Math.max(0, ctx.viewWidth - state.width)));
		y = Math.max(0, Math.min(y, Math.max(0, ctx.viewHeight - state.height)));
	}

	function frame(e:Event):Void {
		if (!visible)
			return;
		var now = openfl.Lib.getTimer();
		var dt = lastTime == 0 ? 0.016 : Math.min(0.05, (now - lastTime) / 1000);
		lastTime = now;
		var changed = false;
		for (row in rows)
			if (row.animate(dt))
				changed = true;
		if (changed)
			layoutRows();
		positionMenu();
		clamp();
	}

	function layout():Void {
		graphics.clear();
		header.graphics.clear();
		body.x = 10;
		body.y = 0;
		layoutRows();
	}

	function layoutRows():Void {
		body.scaleX = body.scaleY = 1;
		body.x = 10;
		var top = 0.;
		// Keep roster identity stable; change placement only as presence changes.
		for (group in 0...4)
			for (row in rows) {
				var priority = (row.online ? 0 : 2) + (row.id == state.leader ? 0 : 1);
				if (row.visible && priority == group) {
					row.y = top;
					top += row.rowHeight + 8;
				}
			}
		state.height = Math.max(64, top);
		if (prompt != null) {
			prompt.x = 12;
			var anchor = 0.;
			for (row in rows)
				if (row.id == state.leader)
					anchor = row.y + row.rowHeight;
			prompt.y = anchor + 8;
		}
	}

	function positionMenu():Void {
		if (menu == null)
			return;
		for (row in rows)
			if (row.visible && row.id == menuMember) {
				var b = row.getBounds(ctx.core.overlay);
				var w = 190.;
				menu.x = b.right + 14;
				if (menu.x + w > ctx.viewWidth)
					menu.x = Math.max(0, b.x - w - 14);
				var anchor = row.menuBounds(ctx.core.overlay);
				menu.y = Math.max(0, Math.min(anchor.y + anchor.height / 2 - 28, ctx.viewHeight - (state.leader == menuMember && autoJoining ? 130 : 90)));
				return;
			}
	}

	function showMenu(id:Int, sx:Float, sy:Float):Void {
		if (menu != null && menuMember == id) {
			closeMenu();
			return;
		}
		closeMenu();
		menuMember = id;
		menu = new Sprite();
		Theme.board(menu, 190, state.leader == id && autoJoining ? 130 : 90);
		ctx.core.overlay.addChild(menu);
		var a = Theme.button(state.leader == id ? "Remove as Leader" : "Set as Leader", 166, 30, function() {
			closeMenu();
			onLeader(state.leader == id ? 0 : id);
		});
		a.x = 12;
		a.y = 10;
		menu.addChild(a);
		if (state.leader == id && autoJoining) {
			var pause = Theme.button("Pause Auto Join", 166, 30, function() {
				closeMenu();
				if (onPauseJoin != null)
					onPauseJoin();
			});
			pause.x = 12;
			pause.y = 50;
			menu.addChild(pause);
		}
		var b = Theme.button("Remove from Party", 166, 30, function() {
			closeMenu();
			onRemove(id);
		});
		b.x = 12;
		b.y = state.leader == id && autoJoining ? 90 : 50;
		menu.addChild(b);
		positionMenu();
		ctx.core.overlay.stage.addEventListener(MouseEvent.MOUSE_DOWN, outside, true);
	}

	function outside(e:MouseEvent):Void {
		var target:Dynamic = Read.get(e, "target");
		while (target != null) {
			if (Read.get(target, "name") == "party_time_options")
				return;
			target = Read.get(target, "parent");
		}
		if (menu != null && !menu.hitTestPoint(e.stageX, e.stageY, true))
			closeMenu();
	}

	public function closeMenu():Void {
		if (ctx.core.overlay.stage != null)
			ctx.core.overlay.stage.removeEventListener(MouseEvent.MOUSE_DOWN, outside, true);
		if (menu != null) {
			if (GameArt.current != null)
				GameArt.current.release(menu);
			if (menu.parent != null)
				menu.parent.removeChild(menu);
		}
		menu = null;
		menuMember = 0;
	}

	public function ask(value:Bool):Void {
		if (!value) {
			if (prompt != null) {
				if (GameArt.current != null)
					GameArt.current.release(prompt);
				if (prompt.parent != null)
					prompt.parent.removeChild(prompt);
			}
			prompt = null;
			return;
		}
		if (prompt != null)
			return;
		prompt = new Sprite();
		Theme.board(prompt, state.width - 24, 80);
		promptText = Theme.text(prompt, "Leader joined another dungeon. Follow them?", 12);
		promptText.wordWrap = true;
		promptText.width = state.width - 44;
		promptText.height = 34;
		promptText.x = 10;
		promptText.y = 6;
		var yes = Theme.button("Yes", 75, 27, function() {
			onFollow(true);
		});
		yes.x = 12;
		yes.y = 45;
		prompt.addChild(yes);
		var no = Theme.button("No", 75, 27, function() {
			onFollow(false);
		});
		no.x = 98;
		no.y = 45;
		prompt.addChild(no);
		addChild(prompt);
		layoutRows();
	}

	public function destroy():Void {
		endDrag(null);
		closeMenu();
		ask(false);
		removeEventListener(Event.ENTER_FRAME, frame);
		removeEventListener(MouseEvent.MOUSE_DOWN, beginDrag);
		for (row in rows)
			row.destroy();
		rows = [];
		if (parent != null)
			parent.removeChild(this);
	}
}
