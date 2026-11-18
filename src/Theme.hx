package mods.party_time_auto_game_joiner;

import openfl.display.Sprite;
import openfl.text.TextField;
import openfl.text.TextFormat;
import openfl.text.TextFormatAlign;
import openfl.display.GradientType;
import openfl.geom.Matrix;

class Theme {
	public static function text(parent:Sprite, value:String, size:Int = 14, color:Int = 0xFFF3CF):TextField {
		var f = new TextField();
		f.defaultTextFormat = new TextFormat("Futura Bold", size, color, true);
		f.selectable = false;
		f.mouseEnabled = false;
		f.text = value;
		f.width = 250;
		f.height = size + 10;
		parent.addChild(f);
		if (GameArt.current != null)
			GameArt.current.font(f, size, color);
		return f;
	}

	public static function board(s:Sprite, w:Float, h:Float):Void {
		var g = s.graphics;
		g.clear();
		g.lineStyle(3, 0x17150F);
		g.beginFill(0x302E26, 0.98);
		g.drawRoundRect(0, 0, w, h, 12, 12);
		g.endFill();
		g.lineStyle(1, 0x927345);
		g.drawRoundRect(4, 4, w - 8, h - 8, 8, 8);
	}

	public static function card(s:Sprite, w:Float, h:Float, muted:Bool, leader:Bool):Void {
		var g = s.graphics;
		g.clear();
		g.lineStyle(3, 0x25180C);
		g.beginFill(muted ? 0x403E36 : 0x61360D, 0.97);
		g.drawRoundRect(0, 0, w, h, 14, 14);
		g.endFill();
		g.lineStyle(2, leader ? 0xFFE482 : (muted ? 0x81796A : 0xCA963F));
		g.drawRoundRect(3, 3, w - 6, h - 6, 10, 10);
	}

	public static function button(label:String, w:Float, h:Float, action:Void->Void):Sprite {
		var s = new Sprite();
		new ButtonHover(s, GameArt.current == null ? null : GameArt.current.facade);
		s.mouseChildren = false;
		var g = s.graphics;
		g.lineStyle(2, 0x201807);
		var matrix = new Matrix();
		matrix.createGradientBox(w, h, Math.PI / 2);
		g.beginGradientFill(GradientType.LINEAR, [0x29BF18, 0x087000], [1, 1], [0, 255], matrix);
		g.drawRoundRect(0, 0, w, h, 9, 9);
		g.endFill();
		g.lineStyle(1, 0xA9D270, 0.75);
		g.drawRoundRect(3, 3, w - 6, h - 6, 6, 6);
		var f = text(s, label.toUpperCase(), 12, 0xFFFFFF);
		f.x = 4;
		f.width = w - 8;
		f.height = h;
		var fmt = f.defaultTextFormat;
		fmt.align = TextFormatAlign.CENTER;
		f.defaultTextFormat = fmt;
		f.setTextFormat(fmt);
		f.y = (h - f.textHeight) / 2 - 2;
		if (GameArt.current != null)
			GameArt.current.font(f, 12, 0xFFFFFF, true, function() {
				f.y = (h - f.textHeight) / 2 - 2;
			});
		s.addEventListener(openfl.events.MouseEvent.CLICK, function(e) {
			e.stopPropagation();
			action();
		});
		return s;
	}

	// Lucide crown silhouette, with its detached bottom stroke omitted.
	public static function crown(s:Sprite):Void {
		var g = s.graphics;
		g.clear();
		g.lineStyle(1.6, 0xFFD84D);
		g.beginFill(0xFFD84D, 0.18);
		g.moveTo(9, 0);
		g.lineTo(12, 5.3);
		g.lineTo(16.8, 2.4);
		g.lineTo(14.5, 11.2);
		g.lineTo(3.5, 11.2);
		g.lineTo(1.2, 2.4);
		g.lineTo(6, 5.3);
		g.lineTo(9, 0);
		g.endFill();
	}
}
