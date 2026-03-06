# AutoSellEverything

AutoSellEverything is a quality-filtering vendor automation addon for **World of Warcraft – Wrath of the Lich King (patch 3.3.5)**.

When you open a vendor window, the addon automatically sells items in your bags that meet the configured rarity rules and have a vendor sell value. The system also continues monitoring your bags while the vendor window remains open, allowing items created through crafting, looting, or movement within your bags to be sold automatically as soon as they appear.

Items placed on the addon’s **ignore lists** will never be sold regardless of rarity or vendor value.

The addon supports both **global** and **character-specific ignore lists**, allowing players to protect items across all characters or only for the current character.

Ignored items can also display a note on their tooltip indicating whether the item is ignored globally or for the current character.

---

# Slash Commands

/asgui — Opens or closes the config window.

/astoggle — Toggles the automatic selling system on or off.

/asstatus — Displays whether the automatic selling system is currently enabled or disabled.

/asignore add <scope> <itemID | itemLink> — Adds the specified item to the ignore list. Scope may be **global** or **character**.

/asignore remove <scope> <itemID | itemLink> — Removes the specified item from the ignore list.

/asignore list — Displays ignored items.

/asignore clear <scope> — Clears either the global or character ignore list.

/asquality set <qualities> — Defines exactly which rarity levels will be sold (accepts numbers or names such as 3, Rare, Blue etc.).

Item Rarity Reference (WoW 3.3.5)

| Number | Rarity    | Accepted Names         |
| ------ | --------- | ---------------------- |
| 0      | Poor      | poor, gray, grey, junk |
| 1      | Common    | common, white          |
| 2      | Uncommon  | uncommon, green        |
| 3      | Rare      | rare, blue             |
| 4      | Epic      | epic, purple           |
| 5      | Legendary | legendary, orange      |
| 6      | Artifact  | artifact               |
| 7      | Heirloom  | heirloom               |

/asquality remove <quality> — Removes a rarity level from the list of sellable item qualities.
/asquality list — Displays the currently enabled item rarity levels that will be automatically sold.
/asquality all — Enables selling for all rarity levels.
/asquality none — Disables selling for all rarity levels.
/asquality add <quality> — Adds a rarity level to the list of sellable item qualities.

---

# Supported Client

This addon is tested on Warmane: Wrath of the Lich King
