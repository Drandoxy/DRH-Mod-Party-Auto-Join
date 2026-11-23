package brain.uI;

import openfl.display.Sprite;

/** Test stand-in for the game's button: only the fields the results lock uses. */
class UIButton {
	public var root:Sprite = new Sprite();
	public var releaseCallback:Dynamic;
	public var enabled = true;
	public var leftNavigation:Dynamic;
	public var rightNavigation:Dynamic;
	public var upNavigation:Dynamic;
	public var downNavigation:Dynamic;

	public function new() {}

	public function clearLeftNavigation()
		leftNavigation = null;

	public function clearRightNavigation()
		rightNavigation = null;

	public function clearUpNavigation()
		upNavigation = null;

	public function clearDownNavigation()
		downNavigation = null;
}
