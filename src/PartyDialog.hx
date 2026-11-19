package mods.party_auto_join;

import mods.api.Context;
import openfl.display.Sprite;
import openfl.events.Event;
import openfl.events.KeyboardEvent;
import brain.event.EventComponent;
import steamInput.OnSteamInputButtonPressedEvent;
import openfl.display.DisplayObjectContainer;
import openfl.events.MouseEvent;
import openfl.filters.GlowFilter;
import openfl.text.TextField;

/** A mod-owned modal: no host popup subclass or native menu-layer mutation. */
class PartyDialog extends Sprite {
	public var left:Dynamic;
	public var right:Dynamic;
	public var message:String;

	var ctx:Context;
	var board = new Sprite();
	var yes:Sprite;
	var no:Sprite;
	var portrait:DialogPortrait;
	var nativeFrame:openfl.display.MovieClip;
	var nativeButtons:Array<brain.uI.UIButton> = [];
	var nativeArt:DialogArt;
	var notification = false;

	static inline final LAYER = "PARTY_TIME_MODAL";

	var events:EventComponent;
	var keyboardStage:DisplayObjectContainer;
	var choice = -1;
	var navigationStarted = false;
	var closed = false;

	public function new(ctx:Context, title:String, message:String, details:Dynamic, onYes:Void->Void, onNo:Void->Void) {
		super();
		this.ctx = ctx;
		this.message = message;
		left = function() {
			finish(onYes);
		};
		right = function() {
			finish(onNo);
		};
		graphics.beginFill(0, 0.68);
		graphics.drawRect(0, 0, ctx.viewWidth, ctx.viewHeight);
		graphics.endFill();
		addEventListener(MouseEvent.MOUSE_DOWN, block);
		addEventListener(MouseEvent.CLICK, block);
		addChild(board);

		notification = onYes == null;
		var h = details == null ? 250. : 420.;
		nativeArt = DialogArt.current;
		if (nativeArt != null && nativeArt.ready)
			nativeFrame = nativeArt.popup();
		var notificationText:TextField = null;
		if (notification) {
			notificationText = plainText(board, message, 17, 0xFFFFFF);
			notificationText.wordWrap = true;
			notificationText.multiline = true;
			notificationText.width = 472;
			notificationText.height = 400;
			h = Math.max(180, notificationText.textHeight + 126);
		}
		if (nativeFrame != null)
			buildNativeFrame(title, h);
		else
			drawBoard(board, 520, h);
		board.x = (ctx.viewWidth - 520) / 2;
		board.y = (ctx.viewHeight - h) / 2;
		if (nativeFrame == null) {
			var heading = plainText(board, title.toUpperCase(), 22, 0xFFD650);
			center(heading, 16, 488, 38);
		}
		var questionY = 76.;
		if (details != null) {
			var url:String = Std.string(details.url);
			if (url == "null")
				url = "";
			portrait = new DialogPortrait(ctx.core.facade, url);
			portrait.x = 216;
			portrait.y = 48;
			board.addChild(portrait);
			var name = plainText(board, Std.string(details.name), 20, 0xFFF4D2);
			center(name, 150, 472, 34);
			var location = plainText(board, Std.string(details.location), 22, 0xFFD65A);
			location.wordWrap = true;
			location.multiline = true;
			center(location, 211, 472, 68);
			questionY = 292.;
		}
		var question = notification ? notificationText : plainText(board, message, 17, 0xFFFFFF);
		question.wordWrap = true;
		question.multiline = true;
		if (notification) {
			board.setChildIndex(question, board.numChildren - 1);
			var textHeight = question.textHeight + 6;
			center(question, 44 + Math.max(0, (h - 120 - textHeight) / 2), 472, textHeight);
		} else
			center(question, questionY, 472, details == null ? 92 : 48);
		no = dialogButton(notification ? "OK" : "No", function() {
			right();
		});
		yes = dialogButton("Yes", function() {
			left();
		});
		no.x = notification ? 194 : 106;
		yes.x = 282;
		no.y = yes.y = h - 68;
		board.addChild(no);
		board.addChild(yes);
		yes.visible = !notification;
		no.addEventListener(MouseEvent.ROLL_OVER, function(_) {
			focus(0);
		});
		yes.addEventListener(MouseEvent.ROLL_OVER, function(_) {
			focus(1);
		});
		if (nativeFrame == null) {
			var close = closeButton(function() {
				right();
			});
			close.x = 476;
			close.y = 12;
			board.addChild(close);
		}
		ctx.core.overlay.addChild(this);
		// Keep the host's global input callback untouched. An empty modal layer
		// blocks underlying buttons; our short-lived listeners handle this dialog.
		ctx.core.facade.menuNavigationController.pushNewLayer(LAYER, function() {
			right();
		}, null);
		events = new EventComponent(ctx.core.facade);
		events.addListener("OnSteamInputButtonPressedEvent", controllerPressed);
		keyboardStage = ctx.core.overlay.stage;
		if (keyboardStage != null)
			keyboardStage.addEventListener(KeyboardEvent.KEY_DOWN, keyPressed, true, 1000);
	}

	static function fitNative(art:openfl.display.DisplayObject, w:Float, h:Float):Void {
		art.scaleX = art.scaleY = 1;
		art.scaleX = w / art.width;
		art.scaleY = h / art.height;
	}

	function buildNativeFrame(title:String, h:Float):Void {
		board.addChild(nativeFrame);
		for (name in ["message_label", "left_button", "center_button", "right_button", "content"]) {
			var child = nativeFrame.getChildByName(name);
			if (child != null)
				child.visible = false;
		}
		var base = nativeFrame.getChildByName("popup_base");
		fitNative(base, 520, h);
		base.x = 260;
		base.y = h / 2;
		var banner = nativeFrame.getChildByName("banner_title_label");
		fitNative(banner, 440, banner.height * 1.3);
		banner.x = 260;
		banner.y = -4;
		var label = DialogArt.field(nativeFrame, "title_label");
		var fmt = label.defaultTextFormat;
		fmt.size = 26;
		fmt.align = openfl.text.TextFormatAlign.CENTER;
		label.defaultTextFormat = fmt;
		label.width = 440;
		label.height = 42;
		label.x = 40;
		label.y = -21;
		label.text = title.toUpperCase();
		var cross:openfl.display.MovieClip = cast nativeFrame.getChildByName("close");
		cross.scaleX *= 1.2;
		cross.scaleY *= 1.2;
		cross.x = 514;
		cross.y = 8;
		var button = new brain.uI.UIButton(ctx.core.facade, cross);
		button.rolloverFilter = dBGlobals.DBGlobal.UI_ROLLOVER_FILTER;
		button.releaseCallback = function() {
			right();
		};
		nativeButtons.push(button);
	}

	function drawBoard(target:Sprite, w:Float, h:Float):Void {
		var g = target.graphics;
		g.lineStyle(3, 0x21180D);
		g.beginFill(0x66370D, .99);
		g.drawRoundRect(0, 0, w, h, 14, 14);
		g.endFill();
		g.lineStyle(2, 0xD0A34F);
		g.drawRoundRect(5, 5, w - 10, h - 10, 10, 10);
	}

	function plainText(parent:Sprite, value:String, size:Int, color:Int):TextField {
		var f = new TextField();
		f.defaultTextFormat = new openfl.text.TextFormat("_sans", size, color, true);
		if (nativeFrame != null)
			nativeArt.format(f, false, size, color);
		else
			f.embedFonts = false;
		f.selectable = false;
		f.mouseEnabled = false;
		f.text = value;
		parent.addChild(f);
		return f;
	}

	function closeButton(action:Void->Void):Sprite {
		var b = new Sprite();
		b.graphics.beginFill(0x148500);
		b.graphics.drawRoundRect(0, 0, 30, 28, 6, 6);
		b.graphics.endFill();
		new ButtonHover(b, ctx.core.facade);
		var t = plainText(b, "X", 18, 0xFFFFFF);
		t.x = 8;
		t.y = 2;
		t.width = 24;
		t.height = 25;
		b.addEventListener(MouseEvent.CLICK, function(e:MouseEvent) {
			e.stopPropagation();
			action();
		});
		return b;
	}

	function dialogButton(value:String, action:Void->Void):Sprite {
		if (nativeFrame != null) {
			var holder = new Sprite();
			var clip = nativeArt.button();
			fitNative(clip, 132, 44);
			var bounds = clip.getBounds(clip);
			clip.x = -bounds.x * clip.scaleX;
			clip.y = -bounds.y * clip.scaleY;
			var label = DialogArt.field(clip, "label");
			if (label != null)
				label.visible = false;
			holder.addChild(clip);
			var caption = new TextField();
			nativeArt.format(caption, true, 20, 0xFFFFFF);
			caption.text = value.toUpperCase();
			caption.width = 124;
			caption.height = 40;
			caption.x = 4;
			caption.y = (44 - caption.textHeight) / 2 - 2;
			caption.mouseEnabled = false;
			caption.selectable = false;
			holder.addChild(caption);
			var button = new brain.uI.UIButton(ctx.core.facade, clip);
			button.rolloverFilter = dBGlobals.DBGlobal.UI_ROLLOVER_FILTER;
			button.selectedFilter = dBGlobals.DBGlobal.UI_SELECTED_FILTER;
			button.releaseCallback = action;
			nativeButtons.push(button);
			return holder;
		}
		var b = new Sprite();
		new ButtonHover(b, ctx.core.facade);
		b.mouseChildren = false;
		var g = b.graphics;
		g.lineStyle(2, 0x201807);
		g.beginFill(0x148500);
		g.drawRoundRect(0, 0, 132, 44, 9, 9);
		g.endFill();
		g.lineStyle(1, 0x8CD36C);
		g.drawRoundRect(3, 3, 126, 38, 6, 6);
		var f = plainText(b, value.toUpperCase(), 20, 0xFFFFFF);
		var format = f.defaultTextFormat;
		format.align = openfl.text.TextFormatAlign.CENTER;
		f.defaultTextFormat = format;
		f.width = 124;
		f.height = 40;
		f.x = 4;
		f.y = (44 - f.textHeight) / 2 - 2;
		b.addEventListener(MouseEvent.CLICK, function(e:MouseEvent) {
			e.stopPropagation();
			action();
		});
		return b;
	}

	function keyPressed(event:KeyboardEvent):Void {
		if (ctx.core.facade.menuNavigationController.getTopUILayer() != LAYER)
			return;
		event.preventDefault();
		event.stopImmediatePropagation();
		handleCode(event.keyCode);
	}

	function controllerPressed(event:OnSteamInputButtonPressedEvent):Void {
		if (ctx.core.facade.menuNavigationController.getTopUILayer() != LAYER)
			return;
		switch (event.actionName) {
			case "menu_left":
				handleCode(37);
			case "menu_right":
				handleCode(39);
			case "menu_up":
				handleCode(38);
			case "menu_down":
				handleCode(40);
			case "menu_select":
				if (navigationStarted)
					handleCode(13);
			case "menu_cancel", "menu_return":
				handleCode(27);
			default:
		}
	}

	function handleCode(code:Int):Void {
		if (closed)
			return;
		if (code >= 37 && code <= 40) {
			if (!navigationStarted) {
				navigationStarted = true;
				focus(0);
			} else
				focus(!notification && code == 39 ? 1 : 0);
		} else if (code == 13 && choice >= 0) {
			if (choice == 0)
				right();
			else
				left();
		} else if (code == 27)
			right();
	}

	function center(field:TextField, y:Float, width:Float, height:Float):Void {
		field.x = (520 - width) / 2;
		field.y = y;
		field.width = width;
		field.height = height;
		var format = field.getTextFormat();
		format.align = openfl.text.TextFormatAlign.CENTER;
		field.defaultTextFormat = format;
		field.setTextFormat(format);
	}

	function focus(value:Int):Void {
		choice = value;
		no.filters = value == 0 ? [new GlowFilter(0xFFD34A, 0.9, 4, 4, 2)] : [];
		yes.filters = value == 1 ? [new GlowFilter(0xFFD34A, 0.9, 4, 4, 2)] : [];
	}

	function block(e:MouseEvent):Void {
		e.stopPropagation();
	}

	function finish(callback:Void->Void):Void {
		if (closed)
			return;
		destroy();
		if (callback != null)
			callback();
	}

	public function destroy():Void {
		if (closed)
			return;
		closed = true;
		for (button in nativeButtons)
			button.destroy();
		nativeButtons = [];
		if (keyboardStage != null)
			keyboardStage.removeEventListener(KeyboardEvent.KEY_DOWN, keyPressed, true);
		keyboardStage = null;
		if (events != null) {
			events.destroy();
			events = null;
		}
		ctx.core.facade.menuNavigationController.removeLayer(LAYER);

		if (portrait != null) {
			portrait.destroy();
			portrait = null;
		}

		removeEventListener(MouseEvent.MOUSE_DOWN, block);
		removeEventListener(MouseEvent.CLICK, block);
		if (parent != null)
			parent.removeChild(this);
	}
}
