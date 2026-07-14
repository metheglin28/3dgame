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
- **King of the Hill (party round)** — the hub doubles as an arena. Interact
  with the crown on the table inside the town's south house to start a ~2.5 min
  round: a glowing ring appears at one of a rotating set of spots (plaza, farm,
  forest, snowy hills), and while you're its *sole* occupant you bank control
  time (contested or empty = frozen). Most time held when the clock runs out
  wins the round; a running scoreboard tracks wins for the session. You keep and
  grab powers as normal during a round, so shoving the King off with a sword,
  snowballs, or the revolver is the whole game. Built on a reusable
  server-authoritative round controller (`GameDirector`) so more modes can slot
  in later.
- **A player character** you can walk and look around with in third person,
  with a landing squash animation and a "Players Online" list in the corner.
- **An interaction system** — look at something interactable and a prompt
  appears telling you what pressing E will do.
- **Pickup props** (the red boxes) — walk up, press E to grab, click to throw them.
- **A door with a lever** — press E on the lever to swing it open or shut.
- **Three NPCs** who wander around and say a random one-liner each (with their
  own personality/lines) when you talk to them. One of them is lost. Name
  tags and speech bubbles (on NPCs and other players alike) fade in only when
  you're close by, so you're not reading every name across the whole map. The
  same goes for signpost text.
- **A snowman in the snowy hills** who'll grant you a snowball hat if you talk
  to him — while you're wearing it, click to lob snowballs instead of your
  hands staying empty. Talk to him again to take it off.
- **A sword in a stone** in the forest clearing — pull it to don a knight
  helmet and a sword; while you have it, click to swing, which knocks nearby
  props (and snowballs) flying. Interact again to put it back.
- **A coat rack** deep in the canyon maze (next to Dave, who denies
  everything) with a cowboy hat on it — take it to don the hat and a
  revolver; click to fire a small, very fast bullet that ragdolls whatever
  it hits with the hardest knockback in the game.
- **The goblin cave's treasure chest** (at the end of the descending line,
  past the goblins) — open it to don a bunny-ear headband. While worn your
  base jump is 1.5x higher, and every consecutive bounce (re-jump the
  instant you land) stacks higher and higher with no cap; miss the rhythm
  and you drop back to the 1.5x base. You can hold only one power at a
  time — snowball hat, sword, revolver, or bunny ears; each replaces the
  others.
- **A goblin cave** in the forest's NE corner: a rocky mouth with skull
  stakes that burrows due north in one straight line of rooms, descending
  as it goes — entry tunnel and goblin warren at the surface, a long
  torch-lit snaking hall ramping down to the campfire-lit main chamber
  (~4.5m down, tall enough for a troll), then another long hall down to the
  treasure room at ~8.5m below the surface (chest and gold — set dressing
  for now, not lootable). The line runs out past the map's north edge
  through a gap in the perimeter wall (sealed by the cave itself), into
  space a future map expansion will fill in. **Six goblins** live along the
  line — small, pointy-eared, in assorted greens from yellowish to dark
  moss, each carrying a little dagger. Enter the cave and the nearby ones
  hunt you down and stab, knocking you flying (a dagger hits softer than
  your sword); leave the cave and they give up and slink back to their
  rooms — they never chase outside. A troll is still planned.
- **A duck pond** on the farm — a shallow, shin-deep basin with gently
  sloped shores (wade in, wade out; never deep enough to swim). Wading slows
  you to ~65% speed, expanding ripple rings follow anyone moving through the
  water, and two ducks supervise. The water surface renders single-sided so
  a camera dunked under it sees clear air, not a blue screen.
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
- **An underground tunnel network** under the whole map. Each quadrant has
  an entrance: an open trench where you drop a short, jumpable ~1.1m onto a
  flat landing, then follow a single straight ramp down to the tunnel floor
  (and back up + a hop to get out). The maze layout is baked as a
  literal grid (no runtime randomness) generated once offline to guarantee
  every room has at least two connections — no dead ends, always another way
  through. It's warm brown rock lit by torches. (A second, deeper level —
  the **gem caverns** — is built but sealed off for now; its connector
  shafts were removed while the entrances get reworked.) The
  third-person camera sweeps a small sphere so it pulls in against walls
  instead of clipping through them, and the thin shaft/ceiling meshes are
  single-sided so the camera never gets blinded by one filling the screen
  underground.
- **A stone tower** standing in the void west of the farm, past the map edge
  — a tall cylindrical shell of stone blocks with a cone roof, classic
  fantasy tower. Its only way in is a corridor off the first underground
  level (a gap punched through the tunnel's west wall). The interior is one
  big empty room for now, deliberately left undesigned — plenty of elbow
  room to build into later.
- **A boss dungeon** buried in the void *east* of the map — the tower's
  mirror image, and the future arena for a co-op mode. One massive
  cylindrical room, ~48m across and nearly 40m tall, reached only by a
  corridor off the first underground level under the forest quadrant (drop
  into the forest entrance shaft, head a few steps east). You enter at floor
  level, stepping across a short bridge onto a raised central arena disc;
  between the disc and the outer wall is a wide ring of open air with a long
  drop into a pit, so players and enemies can be knocked clean *off* the
  arena, sumo-style. The whole structure sits below ground with its roof
  just under grade, so surface players never see it. Right now it's
  **geometry only** — the "fell out of bounds" behavior (elimination /
  respawn) and the mode rules come later; for now the pit just has a floor
  at the bottom.

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
