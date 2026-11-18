import mods.party_time_auto_game_joiner.FriendPopupLayout;
import openfl.display.MovieClip;
import openfl.geom.Rectangle;
class BoundsClip extends MovieClip {
 public var offset=-11.;
 override public function getBounds(target:Dynamic):Rectangle {
  return new Rectangle(x-7*scaleX,y+offset*scaleY,width*Math.abs(scaleX),height*Math.abs(scaleY));
 }
}
class PopupHeightChecks {
 static function close(a:Float,b:Float,message:String){if(Math.abs(a-b)>.251)throw message+": "+a+" != "+b;}
 static function main(){
  var popup=new MovieClip();popup.x=480;popup.y=750;popup.scaleY=.65;
  var bg=new BoundsClip();bg.width=190;bg.height=140;bg.scaleY=1.8;bg.y=-160;bg.offset=-35;
  var title=new BoundsClip();title.y=-220;title.height=48;title.scaleY=1.7;
  var remove=new BoundsClip();remove.y=-44;remove.height=31;remove.scaleY=1.42;
  var party=new BoundsClip();party.y=500;party.height=31;party.scaleY=1.42;
  for(lines in 1...4){
   title.height=24*lines;
   FriendPopupLayout.placeAfter(popup,remove,party);
   FriendPopupLayout.fit(popup,bg,title,party);
   close(party.getBounds(popup).top,remove.getBounds(popup).bottom+7,"party spacing");
   close(bg.getBounds(popup).top,title.getBounds(popup).top-12,"top padding");
   close(bg.getBounds(popup).top+bg.getBounds(popup).height*(2114./2919.),party.getBounds(popup).bottom+14,"party bottom excluded");
   var before=bg.height;var y=bg.y;
   for(i in 0...50)FriendPopupLayout.fit(popup,bg,title,party);
   close(bg.height,before,"background grew on every tick");close(bg.y,y,"background drifted");
   // Host restores only its background, with no title change or visibility edge.
   bg.height=140;bg.y=-160;bg.scaleY=1.8;
   FriendPopupLayout.fit(popup,bg,title,party);
   close(bg.getBounds(popup).top+bg.getBounds(popup).height*(2114./2919.),party.getBounds(popup).bottom+14,"same-title host reset was not repaired");
  }
  close(popup.y,750,"native animation position changed");close(popup.scaleY,.65,"native animation scale changed");
  trace("PASS: 1/2/3-line titles, native scales/offsets, full Party height and padding, host reset, no cumulative growth, untouched animation");
 }
}
