SurfNTurf
=========

A small World of Warcraft addon that swaps travel gear for you.

  Mounted:     equips your riding items
               (default: Carrot on a Stick in the bottom trinket slot)
  Swimming:    equips your swim items
               (default: Cloak of Hermitic Bliss)
  Afterwards:  puts back whatever you were wearing before. If the slot was
               empty, the item goes back to your bags.

The carrot only goes on while you are actually mounted, and it stays off on
flight paths, where it would do nothing. Gear can't be swapped
in combat, so if you get knocked off your mount in a fight the addon waits and
fixes your gear the moment combat ends. It re-checks a few times a second, so
items can't get stuck on or off.


INSTALL
-------

1. Download SurfNTurf.zip:

    https://github.com/matthew-hakes/SurfNTurf/releases/latest/download/SurfNTurf.zip

   (The green "Code" button, then "Download ZIP", works too.)
2. Unzip it. Inside you will find this README and a folder named SurfNTurf.
3. Drag the SurfNTurf folder into your AddOns folder:

       World of Warcraft\_forever_\Interface\AddOns

   Do not rename it, and leave this README out. If you have an older copy
   named SurfNTurf-main in AddOns, delete it first.
4. Restart the game (or log out to character select) and make sure SurfNTurf
   is ticked in the AddOns list.


USING IT
--------

Click the carrot button on the minimap to open the settings window.
Typing /surf or /surfnturf opens it too. Everything is done in that window:

  Enabled          Turn the addon on or off.
  Minimap button   Show or hide the carrot button.
  Trinket slot     Click to switch between the top and bottom trinket slot.
  While mounted    Pick up an item from your bags and click the box to add it.
  While swimming   Same, for swim gear.
  Remove           Click Remove next to an item to stop managing it.

Anything wearable works, for example boots with Mithril Spurs or gloves with a
riding enchant. One item per slot per list. Weapons and off-hands are not
supported.


NOTES
-----

- Items are matched by name, so two different pairs of boots with the same
  name can't be told apart.
- Settings are saved per character.
