# CarrotCloak

A small World of Warcraft addon that swaps travel gear for you.

- **Mounted:** equips your riding items (default: Carrot on a Stick in the bottom trinket slot).
- **Swimming:** equips your swim items (default: Cloak of Hermitic Bliss).
- **Afterwards:** puts back whatever you were wearing before. If the slot was empty, the item goes back to your bags.

The carrot only goes on while you are actually mounted. Gear can't be swapped in combat, so if you
get knocked off your mount in a fight the addon waits and fixes your gear the moment combat ends.
It re-checks a few times a second, so items can't get stuck on or off.

## Install

1. Download **[CarrotCloak.zip](https://github.com/matthew-hakes/CarrotCloak/releases/latest/download/CarrotCloak.zip)**
   (always the latest version).
2. Unzip it into your AddOns folder. The zip already contains a folder with the right name, so you end up with:

```
World of Warcraft\_forever_\Interface\AddOns\CarrotCloak
```

Don't use GitHub's green "Code > Download ZIP" button: that one names the folder `CarrotCloak-main`,
which the game won't load. If you did use it, copy the `CarrotCloak` folder from inside it instead.

Restart the game (or log out to character select) and make sure CarrotCloak is ticked in the AddOns list.

## Using it

Click the carrot button on the minimap to open the settings window. (Typing `/cc` or
`/carrotcloak` opens it too.) Everything is done in that window:

- **Enabled:** turn the addon on or off.
- **Minimap button:** show or hide the carrot button.
- **Trinket slot:** click to switch between the top and bottom trinket slot.
- **While mounted / While swimming:** pick up an item from your bags and click the box to add it.
  Click **Remove** next to an item to stop managing it.

Anything wearable works, for example boots with Mithril Spurs or gloves with a riding enchant.
One item per slot per list. Weapons and off-hands are not supported.

## Notes

- Items are matched by name, so two different pairs of boots with the same name can't be told apart.
- Settings are saved per character.
