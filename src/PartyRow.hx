package mods.party_auto_join;

import openfl.display.Sprite;
import openfl.text.TextField;
import openfl.events.MouseEvent;
import openfl.filters.ColorMatrixFilter;
import uI.portrait.PlayerPortraitView;
import facade.DBFacade;

class PartyRow extends Sprite {
	public var id:Int;
	public var rowHeight = 52.;
	public var targetHeight = 52.;
	public var live = false;

	var profile:SteamPortrait;
	var heroPic:PlayerPortraitView;
	var profileMask:Sprite;
	var heroMask:Sprite;
	var crown = new Sprite();
	var nameLabel:TextField;
	var info:TextField;
	var bars = new Sprite();
	var hpLabel:TextField;
	var mpLabel:TextField;
	var menuButton:Sprite;
	var hpIcon:Sprite;
	var mpIcon:Sprite;
	var joinButton:Sprite;
	var joinVisible = false;

	public var onJoin:Void->Void;

	var lastValues = "";
	var member:PartyMember;
	var mode = "";
	var lastSkin = -1;
	var friendUrl = "";
	var leader = false;
	var inRun = false;

	public var online(default, null) = true;

	var hp = 0.;
	var hpMax = 1.;
	var mp = 0.;
	var mpMax = 1.;
	var widthValue = 290.;
	var needsPaint = true;
	var readyToGrow = false;

	public var onMenu:Int->Float->Float->Void;

	public function new(facade:DBFacade, member:PartyMember, onMenu:Int->Float->Float->Void) {
		super();
		this.member = member;
		id = member.id;
		this.onMenu = onMenu;
		profile = new SteamPortrait(facade, 44);
		heroPic = new PlayerPortraitView(facade, 62, true);
		addChild(heroPic);
		addChild(profile);
		profileMask = new Sprite();
		heroMask = new Sprite();
		addChild(profileMask);
		addChild(heroMask);
		profile.mask = profileMask;
		heroPic.mask = heroMask;
		nameLabel = Theme.text(this, member.name, 13);
		info = Theme.text(this, "In town", 11, 0xD2C0A2);
		addChild(bars);
		hpLabel = Theme.text(this, "", 11, 0xFFFFFF);
		mpLabel = Theme.text(this, "", 10, 0xFFFFFF);
		Theme.crown(crown);
		crown.mouseEnabled = crown.mouseChildren = false;
		joinButton = Theme.button("Join", 48, 27, function() {
			if (onJoin != null)
				onJoin();
		});
		joinButton.visible = false;
		addChild(joinButton);
		menuButton = Theme.button("", 30, 28, function() {
			if (this.onMenu != null)
				this.onMenu(id, 0, 0);
		});
		menuButton.name = "party_time_options";
		var dots = new Sprite();
		for (i in 0...3) {
			dots.graphics.beginFill(0xFFFFFF);
			dots.graphics.drawRoundRect(7 + i * 7, 12, 4, 4, 4, 4);
			dots.graphics.endFill();
		}
		dots.mouseEnabled = false;
		menuButton.addChild(dots);
		addChild(menuButton);
		addChild(crown);
		addEventListener(MouseEvent.RIGHT_CLICK, right);
	}

	public function menuBounds(target:openfl.display.DisplayObject):openfl.geom.Rectangle {
		return menuButton.getBounds(target);
	}

	function right(e:MouseEvent):Void {
		e.stopPropagation();
		onMenu(id, e.stageX, e.stageY);
	}

	public function refresh(friend:Dynamic, hero:Dynamic, running:Bool, isLeader:Bool, width:Float, status:String, isOnline:Bool = true):Void {
		widthValue = width;
		inRun = running;
		online = isOnline;
		leader = isLeader;
		var next = hero != null;
		var newMode = next ? "live" : (running ? "away" : "town");
		var url = friend == null ? "" : Std.string(Read.get(friend, "steamAvatarUrl"));
		if (url == "null")
			url = "";
		var skin = hero == null ? Std.int(Read.number(friend, "skinId", 151)) : Std.int(Read.number(hero, "skinType", 151));
		if (mode != newMode || url != friendUrl) {
			friendUrl = url;
			profile.update(friend == null ? 151 : Std.int(Read.number(friend, "skinId", 151)), url);
			mode = newMode;
			needsPaint = true;
		}
		if (next && skin != lastSkin) {
			lastSkin = skin;
			heroPic.update(skin);
			readyToGrow = false;
		}
		if (next != live) {
			live = next;
			readyToGrow = false;
			needsPaint = true;
		}
		if (next) {
			hp = Read.number(hero, "hitPoints");
			hpMax = Math.max(1, Read.number(hero, "maxHitPoints", 1));
			mp = Read.number(hero, "manaPoints");
			mpMax = Math.max(1, Read.number(hero, "maxManaPoints", 1));
		}
		if (nameLabel.text != member.name)
			nameLabel.text = member.name;
		if (info.text != status)
			info.text = status;
		if (!live)
			targetHeight = running || !online ? 42 : 52;
		var signature = hp + ":" + hpMax + ":" + mp + ":" + mpMax + ":" + leader + ":" + width + ":" + status + ":" + newMode + ":" + online;
		if (signature != lastValues) {
			lastValues = signature;
			needsPaint = true;
		}
	}

	public function setJoinVisible(value:Bool):Void {
		if (joinVisible != value) {
			joinVisible = value;
			joinButton.visible = value;
			needsPaint = true;
		}
	}

	public function animate(dt:Float):Bool {
		if (GameArt.current != null && hpIcon == null) {
			hpIcon = GameArt.current.vitalIcon(false, 26);
			mpIcon = GameArt.current.vitalIcon(true, 28);
			if (hpIcon != null) {
				addChild(hpIcon);
				addChild(mpIcon);
				needsPaint = true;
			}
		}

		if (live && !readyToGrow && heroPic.numChildren > 0) {
			readyToGrow = true;
			targetHeight = 84;
			needsPaint = true;
		}
		var moving = Math.abs(targetHeight - rowHeight) > 0.2;
		if (moving) {
			rowHeight += (targetHeight - rowHeight) * Math.min(1, dt / 0.16);
			needsPaint = true;
		} else
			rowHeight = targetHeight;
		if (needsPaint) {
			paint();
			needsPaint = false;
		}
		return moving;
	}

	function paint():Void {
		var expanded = live && readyToGrow;
		var grey = !online || inRun && !live;
		Theme.card(this, widthValue, rowHeight, grey, leader);
		var g = graphics;
		heroPic.visible = heroMask.visible = expanded;
		profile.visible = true;
		heroPic.x = 11;
		heroPic.scaleX = heroPic.scaleY = Math.min(1, Math.max(0.3, (rowHeight - 22) / 62));
		heroPic.y = (rowHeight - heroPic.height) / 2;
		if (expanded) {
			g.lineStyle(2, 0xBBA271);
			g.drawRoundRect(heroPic.x - 1, heroPic.y - 1, heroPic.width + 2, heroPic.height + 2, 10, 10);
		}
		heroMask.graphics.clear();
		heroMask.graphics.beginFill(0xFFFFFF);
		heroMask.graphics.drawRoundRect(heroPic.x, heroPic.y, heroPic.width, heroPic.height, 10, 10);
		heroMask.graphics.endFill();
		var size = expanded ? 22 : Math.min(44, rowHeight - 22);
		profile.scaleX = profile.scaleY = size / 44;
		profile.x = expanded ? heroPic.x + heroPic.width - size + 2 : 11;
		profile.y = expanded ? heroPic.y + heroPic.height - size + 2 : (rowHeight - size) / 2;
		profileMask.graphics.clear();
		profileMask.graphics.beginFill(0xFFFFFF);
		profileMask.graphics.drawRoundRect(profile.x, profile.y, size, size, 8, 8);
		profileMask.graphics.endFill();
		g.lineStyle(2, 0xBBA271);
		g.drawRoundRect(profile.x - 1, profile.y - 1, size + 2, size + 2, 9, 9);
		menuButton.x = widthValue - 41;
		menuButton.y = (rowHeight - 28) / 2;
		joinButton.x = widthValue - 98;
		joinButton.y = menuButton.y;
		crown.visible = leader;
		crown.x = menuButton.x + 6;
		crown.y = menuButton.y - 8;
		nameLabel.x = expanded ? 77 : 51;
		nameLabel.y = expanded ? 8 : (rowHeight - 34) / 2;
		nameLabel.width = widthValue - nameLabel.x - 51 - (joinVisible ? 57 : 0);
		nameLabel.textColor = grey ? 0xC1C1C1 : 0xFFF4CE;
		info.x = nameLabel.x;
		info.y = nameLabel.y + 18;
		info.width = nameLabel.width;
		info.visible = !expanded;
		info.textColor = grey ? 0xAAAAAA : 0xD2C0A2;
		bars.visible = hpLabel.visible = mpLabel.visible = expanded;
		if (hpIcon != null) {
			hpIcon.visible = mpIcon.visible = expanded;
			hpIcon.x = 76;
			mpIcon.x = 75;
			hpIcon.y = 28;
			mpIcon.y = 50.5;
		}
		if (expanded) {
			var bw = widthValue - 134;
			var bg = bars.graphics;
			bg.clear();
			bar(bg, 85, 31, bw, 20, hp / hpMax, 0xC83429);
			bar(bg, 85, 56, bw, 17, mp / mpMax, 0x8548BC);
			hpLabel.text = Std.int(hp) + " / " + Std.int(hpMax);
			mpLabel.text = Std.int(mp) + " / " + Std.int(mpMax);
			hpLabel.x = mpLabel.x = 108;
			hpLabel.width = mpLabel.width = bw - 26;
			for (label in [hpLabel, mpLabel]) {
				var fmt = label.getTextFormat();
				fmt.align = openfl.text.TextFormatAlign.CENTER;
				label.defaultTextFormat = fmt;
				label.setTextFormat(fmt);
			}
			hpLabel.y = 31 + (20 - hpLabel.textHeight) / 2 - 2;
			mpLabel.y = 56 + (17 - mpLabel.textHeight) / 2 - 2;
		}
		if (grey && (profile.filters == null || profile.filters.length == 0))
			profile.filters = [
				new ColorMatrixFilter([
					0.3, 0.59, 0.11, 0, 0, 0.3, 0.59, 0.11, 0, 0, 0.3, 0.59, 0.11, 0, 0, 0, 0, 0, 1, 0
				])
			];
		if (!grey && profile.filters != null && profile.filters.length > 0)
			profile.filters = [];
	}

	function bar(g:openfl.display.Graphics, x:Float, y:Float, w:Float, h:Float, ratio:Float, color:Int):Void {
		g.lineStyle(1, 0x221608);
		g.beginFill(0x251A15);
		g.drawRoundRect(x, y, w, h, 4, 4);
		g.endFill();
		var fill = (w - 4) * Math.max(0, Math.min(1, ratio));
		if (fill > 0) {
			g.lineStyle();
			g.beginFill(color);
			g.drawRoundRect(x + 2, y + 2, fill, h - 4, 3, 3);
			g.endFill();
			g.lineStyle(1, 0xFFFFFF, 0.22);
			g.moveTo(x + 4, y + 3);
			g.lineTo(x + 2 + fill, y + 3);
		}
	}

	public function destroy():Void {
		removeEventListener(MouseEvent.RIGHT_CLICK, right);
		profile.mask = null;
		heroPic.mask = null;
		profile.destroy();
		heroPic.destroy();
		if (GameArt.current != null)
			GameArt.current.release(this);
		if (parent != null)
			parent.removeChild(this);
		onMenu = null;
	}
}
