# Party Errand

A very unserious third-person exploration game, built in Godot 4, about walking
around with your friends over LAN, picking things up, throwing them, opening
doors, and bothering an NPC. Graphics are all primitive shapes (capsules and
boxes) on purpose — the point is the interaction, not the art.

## Installing Godot

1. Download **Godot 4.3 or later** (the "Standard" build, not .NET) from
   https://godotengine.org/download — it's a single executable, no installer needed.
2. Open Godot, click **Import**, and select the `project.godot` file in this repo.

## Running it

- Press **F5** (or the Play button, top-right) to run the game. It starts on the
  main menu.
- **To host:** type a name (optional) and click **Host Game (LAN)**. This starts
  a server on UDP port `7777` and drops you straight into the world.
- **To join from another computer on the same network:** run the game there too,
  type the host's LAN IP address (e.g. `192.168.1.23` — find it on the host's
  machine with `ipconfig` on Windows or `ifconfig`/`ip addr` on Mac/Linux) into
  the IP field, and click **Join**.
- To test multiplayer solo on one machine, run the game twice (e.g. export a
  debug build and run two instances, or use Godot's "Run Multiple Instances"
  editor feature under Debug menu), host on one and join `127.0.0.1` on the other.
- If joining fails, it's almost always the host's firewall blocking UDP 7777 —
  allow it, or temporarily disable the firewall to test on a trusted home network.

## Controls

| Action | Key |
| --- | --- |
| Move | WASD |
| Sprint | Hold Shift |
| Look around | Mouse |
| Zoom camera in/out | Mouse wheel |
| Jump | Space |
| Interact / talk / pick up | E |
| Throw held item / snowball, or swing sword | Left mouse click |
| Free the mouse cursor | Esc |
| Leave to main menu | HUD button, top-right (after pressing Esc) |
| Options (sensitivity, jump, camera...) | HUD button, top-right (after pressing Esc) |

Options apply live mid-game and persist to `user://settings.cfg`. Mouse
sensitivity, invert-Y, and camera distance are local to you; movement
snappiness and jump strength are sent to the host, which clamps them to the
same ranges the sliders allow.

## What's in this vertical slice

- **LAN multiplayer** — one player hosts, others join by IP. The host's machine
  is authoritative (it runs all the "physics"); everyone else just displays what
  the host tells them, which keeps things simple and consistent. If the host
  leaves or crashes, joined clients automatically drop back to the main menu
  instead of getting stuck.
- **A player character** you can walk and look around with in third person,
  with a landing squash animation and a "Players Online" list in the corner.
- **An interaction system** — look at something interactable and a prompt
  appears telling you what pressing E will do.
- **Pickup props** (the red boxes) — walk up, press E to grab, click to throw them.
- **A door with a lever** — press E on the lever to swing it open or shut.
- **Three NPCs** who wander around and say a random one-liner each (with their
  own personality/lines) when you talk to them. One of them is lost.
- **A snowman in the snowy hills** who'll grant you a snowball hat if you talk
  to him — while you're wearing it, click to lob snowballs instead of your
  hands staying empty. Talk to him again to take it off.
- **A sword in a stone** in the forest clearing — pull it to don a knight
  helmet and a sword; while you have it, click to swing, which knocks nearby
  props (and snowballs) flying. Interact again to put it back. You can hold
  the sword *or* the snowball hat, not both — each one replaces the other.
- **A goblin cave** in the forest's NE corner: a rocky mouth with skull
  stakes that burrows due north in one straight line of rooms, descending
  as it goes — entry tunnel and low goblin warren at the surface, a long
  torch-lit snaking hall ramping down to the campfire-lit main chamber
  (~4.5m down, tall enough for a troll), then another long hall down to the
  treasure room at ~8.5m below the surface (chest and gold — set dressing
  for now, not lootable). The line runs out past the map's north edge
  through a gap in the perimeter wall (sealed by the cave itself), into
  space a future map expansion will fill in. **Six goblins** live along the
  line (plus a lookout outside) — small, pointy-eared, in assorted greens
  from yellowish to dark moss. They wander their own rooms and mouth off if
  you bother them. A troll is still planned.
- **Ragdoll combat** — nobody has health and nobody dies: getting hit just
  cuts your controls and launches you tumbling end over end until you land,
  skid out, and get back up. The sword ragdolls goblins, villagers, and
  other players alike (and knocks whatever they were carrying loose), with
  a short immunity window so one victim can't be juggled forever. Knockback
  strength is per-weapon, so future weapons and abilities can hit softer or
  harder.
- **A 120x120 fixed map** (hand-placed, identical every game) with a small
  town in the center — houses, a shop, a well, lampposts, signposts — and a
  distinct biome in each quadrant: a forest (NE), a farm with a barn and
  silo (NW), a hand-designed canyon maze with a prize at its dead end (SE),
  and snowy hills with a snowman (SW). All layout lives in
  `scripts/map_decorations.gd` as literal coordinates — tweak numbers there
  to move things around.
- **An underground tunnel network**, two levels deep, under the whole map.
  Each quadrant has a circular entrance you drop into (walk over the dark
  disc and gravity does the rest) and climb back out of via straight
  switchback ramps — the top landing stops just short of the rim, one easy
  jump from ground level in either direction. Three vertical shafts connect
  the upper and lower levels the same way. The maze layout is baked as a
  literal grid (no runtime randomness) generated once offline to guarantee
  every room has at least two connections — no dead ends, always another way
  through — and lit with scattered torches so it's never pitch black. The
  third-person camera sweeps a small sphere so it pulls in against walls
  instead of clipping through them, and the thin shaft/ceiling meshes are
  single-sided so the camera never gets blinded by one filling the screen
  underground.

## Project layout

```
project.godot           Engine + input map configuration
scenes/                 All .tscn scene files (main_menu, world, player, npc, door, pickup_item)
scripts/                All .gd scripts
scripts/autoload/       Global singletons: NetworkManager (hosting/joining), GameState (mouse capture)
```

## Where to go from here

This is intentionally a small, working slice rather than a finished game.
Natural next additions, roughly in order of "easy win":
- More/varied interactable props (switches, crates you can stack, a ball you
  can kick).
- A simple inventory instead of a one-item hold point.
- More NPCs with quest-ish requests instead of just one-liners.
- A lobby/ready-up screen before dropping players into the world.
- Persisting a save (e.g. which doors are open) if you want sessions to matter.

## A note on testing

This project was developed with a real Godot 4.3 editor binary available for
automated headless testing (`godot --headless`), including running two actual
separate host+client processes with simulated input to verify the networking
end to end. If you're picking this up somewhere that binary isn't available,
you're back to playtesting by hand — everything here has been verified to
work, but any *new* changes to movement, networking, or interaction logic are
easy to get subtly wrong (see the git history for the kinds of bugs that
turned up: silent RPC failures, sign errors in facing/aim math, and a couple
of scene-file syntax mistakes that Godot doesn't even warn about).
