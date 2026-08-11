# blucheck for HorizonXI

This version is adapted for **HorizonXI** and its 75-cap Blue Mage spell list.

## What was changed

- The spell database is filtered to **only the 107 BLU spells listed by the HorizonXI Wiki at level 75 or below**.
- The addon no longer assumes that every retail BLU spell in Ashita's resource files exists on HorizonXI.
- `ui.lua` now requires a spell to be present in `data/spells.json` before it can appear in the addon.
- The learned/known status still comes directly from Ashita's player spell data.
- The Zone Helper continues to use the existing monster/zone mappings for the retained spells.

## Usage

Place the `blucheck` folder in your Ashita v4 `addons` directory and load it normally.

Use:

```text
/blucheck
```

to open or close the tracker.

## Important note about learning locations

The spell whitelist is HorizonXI-specific. The monster/zone source data in this conversion is retained from the original project for the spells that survived the filter. If you want, the next step can be to replace those monster/zone entries with a **fully HorizonXI-specific learning database** as well.

## Sources

- HorizonXI Blue Magic Spell List:
  https://horizonffxi.wiki/Blue_Magic_Spell_List
- HorizonXI Blue Magic:
  https://horizonffxi.wiki/Category:Blue_Magic

Original addon by atom0s / Ashita Development Team.

## HorizonXI location filtering

The learning-location database has also been filtered to Horizon-era zones.

The conversion excludes:
- Wings of the Goddess-era `[S]` source zones.
- Abyssea and later expansion zones.
- Adoulin / Escha / modern endgame zones.
- Other post-75-cap areas present in the original retail-oriented database.

The addon also contains a Lua-side Horizon zone whitelist, so the Zone Helper
will refuse to show a source from an excluded zone even if a future edit adds
one to `data/spells.json`.

This is intentionally conservative: if a spell has both an older valid source
and a later source, the older Horizon-era source is retained.

The HorizonXI wiki is still actively marked as under construction for parts of
Blue Magic, so this version uses the current Horizon spell/monster data where
available and avoids presenting later-expansion locations as valid learning
spots.

### Spells with no verified Horizon source

Four level-75-cap spells in the retained spell list currently have no
non-[S], non-modern source in the Horizon data we could verify:

- Corrosive Ooze
- Spiral Spin
- Asuran Claws
- Sub-Zero Smash

They remain in the spell list because they are present in the current
HorizonXI Blue Magic Spell List, but the addon intentionally does **not**
invent a monster or zone for them. Their Zone Helper source list will simply
be empty until a Horizon-verified source is available.


## Zone Helper recommendation

The Zone Helper now shows a **HorizonXI Recommended Source** for each spell. The recommendation prioritizes your current zone first, then common classic/leveling zones, while pushing Dynamis, Limbus, Sea/Sky, battlefields, and obvious endgame sources lower.

Because the local spell database contains monster names and zones but not reliable monster-level data, this is an accessibility heuristic rather than a claim that the selected monster is mathematically the lowest-level source. The full source list remains available underneath the recommendation.
