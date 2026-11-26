# CarrotCloak

A small World of Warcraft addon that swaps travel gear for you.

- **Mounted:** equips your riding items (default: Carrot on a Stick in the bottom trinket slot).
- **Swimming:** equips your swim items (default: Cloak of Hermitic Bliss).
- **Afterwards:** puts back whatever you were wearing before. If the slot was empty, the item goes back to your bags.

The carrot only goes on while you are actually mounted. Gear can't be swapped in combat, so if you
get knocked off your mount in a fight the addon waits and fixes your gear the moment combat ends.
It re-checks a few times a second, so items can't get stuck on or off.

## Install

Copy this folder into your AddOns folder and name it `CarrotCloak`:

```
World of Warcraft\_forever_\Interface\AddOns\CarrotCloak
```

Restart the game (or log out to character select) and make sure CarrotCloak is ticked in the AddOns list.

## Commands

| Command | What it does |
| --- | --- |
| `/cc` | Show what is set up |
| `/cc on` / `/cc off` | Turn the addon on or off |
| `/cc mount [item]` | Equip this item while mounted (shift-click the item to link it) |
| `/cc swim [item]` | Equip this item while swimming |
| `/cc remove [item]` | Stop managing an item |
| `/cc trinket 1` / `/cc trinket 2` | Which trinket slot to use (1 = top, 2 = bottom) |

`/carrotcloak` works too if another addon already uses `/cc`.

### Adding more items

Anything wearable works, for example boots with Mithril Spurs or gloves with a riding enchant:

```
/cc mount [Your Spurred Boots]
/cc swim [Azure Silk Belt]
```

One item per slot per list. Weapons and off-hands are not supported.

## Notes

- Items are matched by name, so two different pairs of boots with the same name can't be told apart.
- Settings are saved per character.
