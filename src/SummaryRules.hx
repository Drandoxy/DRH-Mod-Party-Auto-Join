package mods.party_auto_join;

/** Only leave a summary after its normal reward and inventory work has settled. */
class SummaryRules {
	public static function blocked(summary:Dynamic):String {
		if (summary == null)
			return "Dungeon summary is unavailable.";
		if (Reflect.field(summary, "mLeaving") == true)
			return "Already leaving this dungeon.";
		if (Reflect.field(summary, "mRevealState") != 12 || Reflect.field(summary, "mTownHeader") == null)
			return "Wait for the dungeon summary to finish.";
		var items:Dynamic = Reflect.field(summary, "mItemCount");
		if (items == null)
			return "Waiting for dungeon rewards.";
		if (items > 0)
			return "Keep, open or abandon your remaining crates before repeating.";
		if (dialogsOpen(summary))
			return "Finish the open summary dialog before restarting.";
		return null;
	}

	public static function dialogsOpen(summary:Dynamic):Bool {
		for (name in [
			"mUIInventory",
			"mBoosterPopup",
			"mInfoPopup",
			"mTreasureFoundPopup",
			"mChestRevealPopUp",
			"mChestBuyKeysPopUp",
			"mStorageFullPopUp",
			"mChestTransactionFailedPopup",
			"mAbandonChestPopUp",
			"mDRFriendBlockPopup",
			"mDRReportPlayerPopup"
		])
			if (Reflect.field(summary, name) != null)
				return true;
		return false;
	}
}
