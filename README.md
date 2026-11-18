# AnyReagent

*Version française : [README.fr.md](README.fr.md)*

An "at least one reagent" filter for the profession window of World of Warcraft
"Forever" 1.60.1 (`## Interface: 16001`).

Blizzard's filter ("Have Materials") only keeps a recipe when **all** of its reagents are in
your bags. AnyReagent adds another one: it keeps the recipes you have **at least one** required
reagent for, so the recipes you can start farming for.

The addon shows English on every client except French ones, which get French.

## What it does

- A checkbox **"At least one reagent in the bags"** in the profession window's **Filter** menu,
  under an `AnyReagent` title, set apart by a divider.
- When checked, the recipe list only shows the recipes with at least **one required reagent**
  in your bags. Categories the filter empties lose their header, padding rows that are no longer
  needed are removed, and the "unlearned" divider goes away when no unlearned recipe is left.
- Only the bags and the reagent bag count: **the bank is not counted**.
- A recipe's **optional** reagents are not enough to show it, and slots of any other type than
  basic reagents (quality reagents) are ignored.
- A recipe whose reagents the client cannot describe, or that has none, stays visible: the addon
  never hides a recipe on uncertain information.
- The list refreshes by itself when your bags change while the profession window is open,
  without rebuilding it.
- The choice is saved (`AnyReagentDB.enabled`) and applies the next time you open the window.

## Difference from Blizzard's filter

| Filter | Keeps the recipe if |
| --- | --- |
| Blizzard, "Have Materials" | all required reagents are in the bags |
| AnyReagent | at least one required reagent is in the bags |

Both can be checked at once: Blizzard filters first, AnyReagent only removes more rows.

## Working with other addons

AnyReagent changes no other addon and replaces no Blizzard function: it adds a checkbox to the
Filter menu and removes rows from the list Blizzard built. It only puts back the rows **it removed
itself**, so another addon filtering the same list (CraftProfit, for example, with its
"profitable" filter) keeps its own hidden rows: unchecking AnyReagent does not bring them back.

## Installation

1. Download the addon. If you use GitHub's **Code → Download ZIP**, the folder inside is named
   `AnyReagent-main`: rename it to `AnyReagent`.
2. Copy the `AnyReagent` folder into `World of Warcraft\_forever_\Interface\AddOns\`.
3. Restart the game (a new addon folder needs a full restart).
4. Open a profession: the checkbox is in the **Filter** menu, above the recipe list.

## Commands

- `/anyreagent`: turns the filter on or off, and says so in the chat window
  (`[AnyReagent] Filter on.` / `[AnyReagent] Filter off.`).
- Addon compartment entry: a click toggles the same setting, hovering shows the state and what
  the click does.

There is no minimap button and no settings window: the only interface added is the Filter menu
checkbox.

## Not verified in game

Written from the API and from what CraftProfit does on this client, but **not** tested in game:

- **Profession window names**: `ProfessionsFrame.CraftingPage.RecipeList.ScrollBox` and
  `Menu.ModifyMenu("MENU_PROFESSIONS_FILTER", ...)`. If Blizzard renames either, the checkbox
  does not appear and the addon does nothing (no error shown in game).
- **Removing rows**: `parent:Remove(node, true)` (the `true` avoids one invalidation per row; the
  addon invalidates once at the end) and `parent.sortComparator` to put restored rows back in
  place. If the comparator does not exist, rows go back to their original index.
- **Recipe schematic**: `C_TradeSkillUI.GetRecipeSchematic(recipeID, false).reagentSlotSchematics`,
  with `reagentType` (`Enum.CraftingReagentType.Basic`, or 0) and `required` per slot, and
  `reagents[j].itemID` per reagent.
- **Counting**: `C_Item.GetItemCount(itemID, false, false, true)` (bags + reagent bag), with
  `GetItemCount(itemID)` as a fallback when `C_Item` does not exist. If `includeReagentBank` is
  not honored on this client, the reagent bag will be missing from the count.
- **"No results" line**: `RecipeList.NoResultsText` is driven from `dataProvider:IsEmpty()`; if
  Blizzard also manages it, the last pass wins.
- **Filter order**: AnyReagent and Blizzard's "Have Materials" filter each apply their rules to
  the current list; no combination has been checked in game.

## Tests

`%LOCALAPPDATA%\Temp\opencode\lua-check\test-anyreagent.js` loads the real `AnyReagent.lua` into
fengari with a fake client API (a `TreeNodeMixin`-style recipe tree, `ScrollBox`, Filter menu,
schematics, bags, bank, events) and checks the rows actually left in the list, on a French and
an English client. Run it with `bun test-anyreagent.js` from that folder.
