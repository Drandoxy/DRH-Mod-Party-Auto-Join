# Friend-popup geometry regression

Run `python tests/run_popup.py --haxe /absolute/path/to/haxe`.

This checks the actual artwork body's height, separate from its pointer, for one-, two- and three-line headings, non-unit scales and offsets, repeated layout and native background resets. The popup animation's own position/scale remain untouched. OpenFL doubles test geometry contracts, not native rendering.

The installed `db_UI_leaderboard` export has online/offline tooltip background symbol2, containing shape1. Its grey body spans y=-1459 to655 twips and its pointer reaches y=1460: usable body fraction2114/2919. Do not include the game artwork in mod packages.
