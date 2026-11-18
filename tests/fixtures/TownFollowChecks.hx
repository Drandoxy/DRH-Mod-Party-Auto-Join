import mods.party_time_auto_game_joiner.FollowPolicy;
class TownFollowChecks {
    static function main() {
        if (FollowPolicy.waitForDeparture(false, true, false)) throw "Town blocked by stale session";
        if (!FollowPolicy.waitForDeparture(true, true, false)) throw "Active shared session must wait";
        if (FollowPolicy.waitForDeparture(true, true, true)) throw "Leader departure must release wait";
        var policy = new FollowPolicy();
        if (policy.decide(10000, 2, 1, 5, false, false, false, false, "2:5") != "join") throw "Town must join";
        trace("Town follow regressions passed");
    }
}
