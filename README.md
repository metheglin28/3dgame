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
| Look around | Mouse |
| Jump | Space |
| Interact / talk / pick up | E |
| Throw held item | Left mouse click |
| Free the mouse cursor | Esc |

## What's in this vertical slice

- **LAN multiplayer** — one player hosts, others join by IP. The host's machine
  is authoritative (it runs all the "physics"); everyone else just displays what
  the host tells them, which keeps things simple and consistent.
- **A player character** you can walk and look around with in third person.
- **An interaction system** — look at something interactable and a prompt
  appears telling you what pressing E will do.
- **Pickup props** (the red boxes) — walk up, press E to grab, click to throw them.
- **A door with a lever** — press E on the lever to swing it open or shut; it
  physically blocks the way when closed.
- **An NPC** who wanders around aimlessly and says a random one-liner when you
  talk to it.

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
- More NPCs with different personalities, maybe a quest-ish request.
- Simple animations (even just squash-and-stretch on the capsule) instead of
  a static mesh.
- A lobby/ready-up screen before dropping players into the world.
- Persisting a save (e.g. which doors are open) if you want sessions to matter.
