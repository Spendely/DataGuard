-- DataGuard schema. Bump Version whenever Renames or Removed change.
-- Keys not in Template and not in Removed are kept as-is.
return {
	Version = 1,

	Template = {
		Coins = 0,
		Level = 1,
		Inventory = {},
	},

	-- { from = "OldName", to = "NewName", since = <Version this rename was added> }
	Renames = {},

	-- { key = "KeyName", since = <Version this removal was added> }  -- the only way data is deleted
	Removed = {},
}
