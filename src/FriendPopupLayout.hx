package mods.party_time_auto_game_joiner;

import openfl.display.DisplayObject;
import openfl.display.MovieClip;

/** Fit authored artwork in popup coordinates; never move the animated popup. */
class FriendPopupLayout {
	// db_UI_leaderboard background symbol 2 -> shape 1, twip coordinates:
	// body top -1459, body bottom 655, pointer tip 1460. The pointer is not
	// usable content space. Native scaling preserves this authored proportion.
	public static inline final BODY_FRACTION = 2114. / 2919.;

	public static function placeAfter(popup:MovieClip, previous:DisplayObject, button:DisplayObject):Void {
		var expected = previous.getBounds(popup).bottom + 7;
		var actual = button.getBounds(popup).top;
		if (Math.abs(expected - actual) > 0.25)
			button.y += expected - actual;
	}

	public static function fit(popup:MovieClip, background:DisplayObject, title:DisplayObject, last:DisplayObject):Void {
		if (background == null || title == null || last == null)
			return;
		var top = title.getBounds(popup).top - 12;
		var bottom = last.getBounds(popup).bottom + 14;
		var desired = (bottom - top) / BODY_FRACTION;
		if (desired <= 0 || !Math.isFinite(desired))
			return;
		var bounds = background.getBounds(popup);
		if (bounds.height <= 0)
			return;
		// Use measured parent-space bounds, including authored offsets and scale9.
		// Do not assume getBounds(background) is an immutable unscaled template.
		if (Math.abs(bounds.height - desired) > 0.25) {
			background.height *= desired / bounds.height;
			bounds = background.getBounds(popup);
		}
		if (Math.abs(bounds.top - top) > 0.25)
			background.y += top - bounds.top;
	}
}
