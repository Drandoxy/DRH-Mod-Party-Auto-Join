package mods.party_time_auto_game_joiner;

import facade.DBFacade;
import brain.mouseCursor.MouseCursorManager;
import dBGlobals.DBGlobal;
import openfl.display.Sprite;
import openfl.events.Event;
import openfl.events.MouseEvent;
import openfl.geom.ColorTransform;

/** Native rollover filter and cursor, with ownership limited to one button. */
class ButtonHover {
	var target:Sprite;
	var cursor:MouseCursorManager;
	var key:UInt = 0;
	var hovered = false;
	var beforeFilters:Array<openfl.filters.BitmapFilter>;
	var beforeColor:ColorTransform;

	public function new(target:Sprite, facade:DBFacade) {
		this.target = target;
		cursor = facade == null ? null : facade.mouseCursorManager;
		target.buttonMode = true;
		target.mouseChildren = false;
		target.addEventListener(MouseEvent.ROLL_OVER, enter);
		target.addEventListener(MouseEvent.ROLL_OUT, leave);
		target.addEventListener("removedFromStage", leave);
	}

	function enter(event:MouseEvent):Void {
		if (hovered)
			return;
		hovered = true;
		beforeFilters = target.filters;
		beforeColor = target.transform.colorTransform;
		target.filters = beforeFilters.concat([DBGlobal.UI_ROLLOVER_FILTER]);
		target.transform.colorTransform = new ColorTransform(.75, .75, .75, 1, 64, 64, 64);
		if (cursor != null)
			key = cursor.pushMouseCursor("POINT", true);
	}

	function leave(event:Event):Void {
		if (!hovered)
			return;
		hovered = false;
		target.filters = beforeFilters;
		target.transform.colorTransform = beforeColor;
		if (key > 0 && cursor != null)
			cursor.popMouseCursor(key);
		key = 0;
	}

	public function destroy():Void {
		leave(null);
		target.removeEventListener(MouseEvent.ROLL_OVER, enter);
		target.removeEventListener(MouseEvent.ROLL_OUT, leave);
		target.removeEventListener("removedFromStage", leave);
	}
}
