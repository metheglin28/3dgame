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
  forest, snowy hills) and **relocates every 50 seconds** — three hills per
  round, with a HUD countdown to each move. While you're the ring's *sole*
  occupant you bank control time (contested or empty = frozen), and your
  total carries across hill moves. Most time held when the clock runs out
  wins the round; a running scoreboard tracks wins for the session. You keep and
  grab powers as normal during a round, so shoving the King off with a sword,
  snowballs, or the revolver is the whole game. Built on a reusable
  server-authoritative round controller (`GameDirector`) so more modes can slot
  in later.
- **Goblin Siege (co-op boss round)** — a skull on a stake just past the boss
  dungeon's entrance starts it. Seven enemies spawn frozen on the arena disc —
  the six cave goblins and a **troll**: a ~6m brown giant with a wooden club
  and the hardest knockback in the game. After a 3-2-1 countdown they go live
  and hunt everyone on the disc. Nobody has health, so you "kill" enemies the
  same way they kill you: **knock them off the disc into the pit**. The troll
  is the puzzle — he doesn't ragdoll and has no immunity, he just gets shoved,
  so gang up and heave him over the edge. Clear all seven before the ~2.5 min
  timer to win; if every fighter gets knocked out (or time runs out with the
  horde alive) you lose. Fall out mid-fight and you drop into a **spectator
  chase-cam** following a living teammate (click to switch who you watch) until
  the round ends and everyone's returned to town. Reward's still TBD.
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
  to him — while you're wearing it, click to lob snowballs (talk to him again
  to take it off). Snowballs are proper projectiles: they arc, pop in a puff
  of flecks on the first thing they touch, and hit as hard as the wizard's
  lightning — but as a shove (no ragdoll, troll-style) plus a **chill**: the
  target moves 45% slower for 2.5 s and turns frost-blue so everyone can see
  it. Works on players, goblins, and — usefully — the troll.
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
  time — snowball hat, sword, revolver, bunny ears, wizard hat, or golden
  ears; each replaces the others.
- **A wizard hat** (blue cone with white stars) sitting on the ground in the
  forest clearing near the sword in the stone — it has no permanent home yet.
  Take it to don the hat, then click to cast a **blue lightning bolt**: it
  flies flat and fast with moderate knockback, but leaves whatever it zaps
  ragdolling and tumbling roughly three times longer than a normal hit.
- **Golden ears** — the bunny-ears variation, borrowed from the Bunny Man on
  the secret moon. Same look but gold, and the same jump kit (1.5x plus the
  consecutive-bounce stacking). Their trick is a **ground pound**: while
  airborne, hit and hold the attack button to dive straight down; on landing,
  everyone near the impact is knocked back — harder the farther you fell
  (capped). Release mid-dive to cancel. A little hop-slam is weaker than a
  sword; a dive from a big bounce-stack (or off the moon) hits like a truck.
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
  silo (NW — the barn is enterable: three hay stalls inside, one home to a
  family of bunnies; the mama is where you borrow the bunny-ear headband), a hand-designed canyon maze with a prize at its dead end (SE),
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
  just under grade, so surface players never see it. There's a **kill plane**
  near the bottom of the pit: fall in and, if you're a player, you're
  teleported back to a town spawn; enemies that fall in are despawned. The
  actual co-op *mode* rules (win/lose, scoring, who spawns here) come later —
  for now this is the arena plus its out-of-bounds safety net.

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
