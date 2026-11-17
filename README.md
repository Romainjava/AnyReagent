# AnyReagent

Filtre « au moins un composant » pour la fenêtre de métier de World of Warcraft
« Forever » 1.60.1 (`## Interface: 16001`).

Le filtre de Blizzard (« Avez les composants ») ne garde une recette que si **tous** ses
composants sont dans les sacs. AnyReagent en ajoute un autre : il ne garde que les recettes
dont vous avez **au moins un** composant requis, donc les recettes que vous pouvez commencer
à farmer.

## Ce que fait l'addon

- Une case à cocher **« Au moins un composant dans les sacs »** dans le menu **Filtre** de la
  fenêtre de métier, sous un titre `AnyReagent`, séparée par un trait.
- Cochée, la liste des recettes ne montre que les recettes pour lesquelles au moins **un
  composant requis** est dans les sacs. Les catégories que le filtre vide perdent leur en-tête,
  les lignes d'espacement qui ne servent plus sont retirées et le séparateur « non appris »
  disparaît quand il ne reste plus de recette non apprise.
- Seuls les sacs et la sacoche de composants comptent : **la banque n'est pas comptée**.
- Les composants **facultatifs** d'une recette ne suffisent pas à la faire apparaître, et les
  emplacements d'un autre type que les composants de base (reagents de qualité) sont ignorés.
- Une recette dont le client ne sait pas décrire les composants, ou qui n'en a aucun, reste
  visible : l'addon ne cache jamais une recette sur une information incertaine.
- La liste se rafraîchit toute seule quand les sacs changent pendant que la fenêtre de métier
  est ouverte, sans la reconstruire.
- Le choix est enregistré (`AnyReagentDB.enabled`) et s'applique dès l'ouverture suivante.

## Différence avec le filtre de Blizzard

| Filtre | Garde la recette si |
| --- | --- |
| Blizzard, « Avez les composants » | tous les composants requis sont dans les sacs |
| AnyReagent | au moins un composant requis est dans les sacs |

Les deux peuvent être cochés en même temps : c'est Blizzard qui filtre en premier, AnyReagent
ne fait que retirer des lignes en plus.

## Coexistence avec les autres addons

AnyReagent ne modifie aucun autre addon et ne remplace aucune fonction de Blizzard : il ajoute
une case au menu Filtre et retire des lignes de la liste que Blizzard a construite.
Il ne remet en place que les lignes **qu'il a lui-même retirées**, donc un autre addon qui
filtre la même liste (CraftProfit, par exemple, avec son filtre « rentable ») garde ses propres
lignes masquées : décocher AnyReagent ne les fait pas revenir.

## Installation

1. Copier le dossier `AnyReagent` dans `World of Warcraft\_forever_\Interface\AddOns\`.
2. Redémarrer le jeu ou `/reload`.
3. Ouvrir un métier : la case est dans le menu **Filtre**, en haut de la liste des recettes.

## Commandes

- `/anyreagent` : active ou désactive le filtre, et l'annonce dans la fenêtre de discussion
  (`[AnyReagent] Filtre activé.` / `[AnyReagent] Filtre désactivé.`).
- Entrée dans le compartiment d'addons : un clic bascule le même réglage, le survol affiche
  l'état et le fonctionnement du clic.

Il n'y a ni bouton minimap ni fenêtre de réglages : la seule interface ajoutée est la case du
menu Filtre.

## Points non vérifiés en jeu

Écrits à partir de l'API et de ce que fait CraftProfit sur ce client, mais **pas** testés en
jeu :

- **Noms de la fenêtre de métier** : `ProfessionsFrame.CraftingPage.RecipeList.ScrollBox` et
  `Menu.ModifyMenu("MENU_PROFESSIONS_FILTER", ...)`. Si Blizzard renomme l'un des deux, la case
  n'apparaît pas et l'addon ne fait rien (aucune erreur affichée en jeu).
- **Retrait des lignes** : `parent:Remove(node, true)` (le `true` évite une invalidation par
  ligne, l'addon invalide une seule fois à la fin) et `parent.sortComparator` pour replacer les
  lignes remises. Si le comparateur n'existe pas, les lignes reviennent à leur index d'origine.
- **Schéma des recettes** : `C_TradeSkillUI.GetRecipeSchematic(recipeID, false).reagentSlotSchematics`,
  avec `reagentType` (`Enum.CraftingReagentType.Basic`, ou 0) et `required` par emplacement, et
  `reagents[j].itemID` par composant.
- **Comptage** : `C_Item.GetItemCount(itemID, false, false, true)` (sacs + sacoche), avec
  `GetItemCount(itemID)` en secours si `C_Item` n'existe pas. Si `includeReagentBank` n'est pas
  pris en compte sur ce client, la sacoche de composants manquera au comptage.
- **Ligne « aucun résultat »** : `RecipeList.NoResultsText` est pilotée à partir de
  `dataProvider:IsEmpty()` ; si Blizzard la gère aussi de son côté, c'est le dernier passage qui
  gagne.
- **Ordre des filtres** : AnyReagent et le filtre « Avez les composants » de Blizzard appliquent
  leurs règles chacun sur la liste courante ; aucune combinaison n'a été vérifiée en jeu.

## Tests

`%LOCALAPPDATA%\Temp\opencode\lua-check\test-anyreagent.js` charge le vrai `AnyReagent.lua` dans
fengari avec une fausse API du client (arbre de recettes type `TreeNodeMixin`, `ScrollBox`, menu
Filtre, schémas, sacs, banque, événements) et vérifie les lignes réellement laissées dans la
liste. Il se lance avec `bun test-anyreagent.js` depuis ce dossier.
