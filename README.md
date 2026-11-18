# Party Time Auto Game Joiner

<!-- drh:show -->
A local party panel for up to four friends, excluding your own character. In town, open a friend's portrait popup and choose **Party +**. Right-click a party row to **Set as Leader**, **Remove as Leader**, or remove the member.

The panel starts near the upper-left town area. It has no outer background, border, or title. Hold a member row for 0.5 seconds, then drag. Cards have a fixed 310-pixel width and grow vertically in a dungeon. Position, roster, and leader are saved automatically when changed. Ctrl+Shift+P toggles the panel. Hiding the panel does not stop leader following; remove the leader to stop following.

In a dungeon, present players have hero portraits, small profile portraits, compact HP/mana bars, and names above the bars. Absent players shrink and grey out. Portraits load before the short expansion animation. The leader has a gold crown. This is a local roster, not a server party invitation system.

When a leader has a joinable dungeon, the mod uses the game's normal friend-join flow. While already playing, it asks **Leader joined another dungeon. Follow them?** Yes exits the current dungeon without a second loot-loss confirmation, then follows the leader. No stays in the current game. Normal server admission rules still apply.

At the end screen, Next/Retry and the local Auto Dungeon restart option are blocked while another player is the leader. **Waiting for Leader** replaces them. Return to town is still available. Remove the leader to restore navigation. Remaining reward/crate decisions must finish before automatic departure from a summary.

A failed join shows the game's error in a game-styled Yes/No dialog asking **Retry joining?** No stops automatic attempts until a leader is selected again or the manual **Join** button beside the leader is pressed. A leader changing dungeons does not resume attempts after No. The presence protocol exposes a dungeon node, not a server session ID, so repeated runs of the same dungeon require normal server-validated attempts rather than exact instance detection.

Profile and hero portraits use game assets. Player rows and buttons use a custom brown/gold and green style, with embedded game fonts. The compact custom menu matches the game’s dark popup style. Each row has an ellipsis button to open its menu; right-click also works. Party + is added inside the native friend popup without changing its origin or native animation and becomes Party - for existing members. The crown is a small vector. No external image assets are bundled and no messages or invitations are sent to friends.

Your own account is excluded. The panel has no resize handle; its fixed card width keeps labels and controls readable. Saved positions are retained. Full visual validation in the running game is still required.

With an empty roster, only the native Party +/- integration runs. Presence and game-object watchers, roster graphics and their assets are created on the first addition and released on the last removal. If the last leader was removed during a run, a small Dungeon Manager hold heartbeat remains until returning to town, preserving the requested automatic-next/restart pause.

<!-- /drh:show -->

Dialog asset loading follows the approach used by [Ultimate Records](https://github.com/Drandoxy/DRH-Mod-Records). Game artwork is loaded from the installed game and is not redistributed.
