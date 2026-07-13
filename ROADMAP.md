# Party Errand — Party-Game Roadmap

## North star

A **coherent hangout sandbox for friends over LAN.** Silly, drop-in/drop-out,
"play for 15–30 min while the pizza arrives" energy. Both **cooperative** and
**competitive**. The structure that makes this work:

> **Hub + Rounds.** The existing map is the **hub** — free play, mess with
> powers, shove each other in the pond. From the hub anyone can start a
> **round** (a short shared mode). It pulls everyone in, plays 2–4 min, scores,
> declares a winner (or a shared win/loss), and dumps everyone back in the hub.

Everything below builds that. The three **foundational primitives** (Phase 0)
are the skeleton — nothing else is a "game" without them. Phase 1 (Sumo) is the
proof-of-concept round. After that, modes are cheap.

Keep the house rules: **server-authoritative** (server simulates, clients render
from snapshots), **deterministic map** (no runtime randomness for layout),
**headless-verified** (single- and two-process tests, cleaned up before commit).

---

## Open decisions (resolve before/while building Phase 0–1)

- [ ] **Round-start UX:** a physical thing in the hub (a podium/bell you
      interact with, maybe with a mode picker) vs. a host menu button.
      *Leaning: physical, to match the diegetic-interaction style.*
- [ ] **Elimination feel:** respawn-after-short-delay (stay in the round) vs.
      out-until-next-round (spectate). *Leaning: short respawn for most modes;
      ring-out modes may want elimination for tension. Could be per-mode.*
- [ ] **Sumo arena location:** repurpose the empty tower interior, a new
      platform over the pond, or a dedicated built arena. *Leaning: dedicated
      raised ring so ring-out is unambiguous.*
- [ ] **Powers during rounds:** disabled, everyone gets the same one, or picked
      up in the arena? *Leaning: per-mode; Sumo = no powers first, tune later.*
- [ ] **Respawn behavior:** on respawn, drop carried item + remove power? keep?
      *Leaning: reset to a clean state (no power, nothing carried).*
- [ ] **Scoreboard scope:** points per round only, or a running "best of the
      night" total? *Leaning: both — round tally + session total.*

---

## Phase 0 — Foundational primitives (the skeleton)

### 0.1 Respawn / reset
- [ ] Kill-plane: below a Y threshold (or outside map bounds) → respawn.
      *Also fixes the uncapped bunny-jump "launched off-map, stuck" hole.*
- [ ] Manual "I'm stuck" respawn (hold a key for ~1s).
- [ ] Server-authoritative respawn: teleport to a spawn point, zero velocity,
      clear ragdoll/tumble state. *Spawn markers already exist (`player_spawn`
      group, `SpawnPoint*` in world.tscn).*
- [ ] Clean-state on respawn per the decision above (drop carried item, clear
      power flags).
- [ ] Networking: respawn is a big position jump — confirm the existing
      `NET_SNAP_DISTANCE` teleport handling hides the zip (it should).
- [ ] Context-aware spawn: hub respawns in the hub; in-round respawns use the
      active mode's spawn set (wired in Phase 0.3).
- [ ] **Test:** walk off a ledge / bunny-launch off-map → respawn at hub;
      two-process (host + client) confirms both see the teleport cleanly.

### 0.2 Session scoreboard
- [ ] Server-authoritative score store keyed by peer_id (new `GameDirector`
      autoload, or alongside `NetworkManager.player_names`).
- [ ] `add_score(peer, n)` / `reset_scores()` API.
- [ ] Sync scores to all clients (reliable RPC, or fold into the snapshot).
- [ ] HUD scoreboard panel (toggle on a key, e.g., Tab; plus a compact
      always-on corner tally). Lives in the player HUD `CanvasLayer`.
- [ ] Round tally view (points earned this round) + session running total.
- [ ] Handle join/leave (add/remove rows; late joiner sees current totals).
- [ ] **Test:** award points on the host; all peers show identical totals;
      a late-joining client receives the current scores.

### 0.3 Round controller (`GameDirector` state machine)
- [ ] New server-owned director: states `HUB → COUNTDOWN → PLAYING →
      ROUND_END → HUB`.
- [ ] Server owns state; broadcast `{state, mode, timer, ...}` to clients
      (reliable for transitions, snapshot/interval for the timer).
- [ ] Round-start trigger (per Open Decisions).
- [ ] Countdown: freeze input, teleport players to the mode's arena spawns,
      3-2-1 banner.
- [ ] Per-mode hooks: `on_start()`, `check_win() -> winner/none`,
      `on_end(winner)`. Modes are data/subclasses plugged into the director.
- [ ] Win detection → award scores → `ROUND_END` (show result) → return to hub
      (teleport back, restore free play).
- [ ] Round timer + HUD (state banner, time left).
- [ ] Drop-in/drop-out mid-round: joiners spectate until next round (or
      late-join if the mode allows); leavers don't stall the round.
- [ ] Abort/cancel (host request, or auto-abort if too few players remain).
- [ ] **Test:** full cycle host+client — start → countdown → play → win →
      scores → back to hub, with a forced win condition.

**Phase 0 "done" =** you can start a trivial round (e.g., "first to press a
button wins"), it scores, declares a winner, and returns everyone to the hub.

---

## Phase 1 — First real mode: Sumo (proof of concept)

*Smallest thing that makes someone say "oh, this is a game now." Exercises all
three primitives and turns the ragdoll system into an actual contest.*

- [ ] Build/choose the arena (per Open Decisions) with clear ring-out edges.
- [ ] Arena spawn points (ring of markers) registered with the director.
- [ ] Ring-out detection: leave arena bounds / fall below its plane →
      eliminated (server-side).
- [ ] Rules: last player not ringed out wins; timer fallback (sudden-death
      shrink or highest-ground wins if time expires).
- [ ] Elimination handling per the decision (respawn-to-sidelines vs. out).
- [ ] Round-scoped powers per the decision (start with none).
- [ ] Win → award points → `ROUND_END` banner ("X wins!") → hub.
- [ ] Minimal feedback: KO pop + winner banner (fuller juice in Phase 2).
- [ ] **Test:** multi-process Sumo round — players ragdoll each other out, last
      one standing wins, score awarded, back to hub.

---

## Phase 2 — Feel & readability (party juice)

*Party games live or die on legibility and spectacle. Currently there's zero
audio and minimal feedback.*

- [ ] **Player identity/colors** — distinct color per player (capsule tint +
      scoreboard swatch). Prerequisite for legible competition; consider
      pulling this earlier, into Phase 0.2.
- [ ] SFX: jump, land, KO/ragdoll hit, shoot, swing, snowball, round-start,
      win. (First audio in the project.)
- [ ] Hit/KO visual feedback (flash, small particle burst, light screen shake).
- [ ] Countdown + round-start presentation (banner, arena reveal).
- [ ] Winner celebration moment (pose, confetti, sting).
- [ ] Scoreboard polish (colors, sorting, leader highlight).

---

## Phase 3 — More competitive modes

*Mostly rules layered over existing geography + combat.*

- [ ] **King of the Hill** — hold a spot (tower top / a snowy hill) while others
      snowball/shoot/swing you off. Reuses powers + knockback.
- [ ] **Power Brawl / Deathmatch** — timed, most knockouts wins; powers as arena
      pickups.
- [ ] **Race** — checkpoint course across the map; bunny-ears + tunnels are the
      racing lines. Finally makes the map's size an asset.

---

## Phase 4 — Cooperative modes

- [ ] **Goblin Siege / Horde Defense** — goblins (and the promised **troll** as
      a raid boss) attack a point; players defend together. Reuses goblin AI;
      closes the "troll planned" and combat threads.
- [ ] **The Errand Run** — lean back into the title: a shared checklist under a
      timer (fetch the maze prize, dunk snowballs in the well, clear the cave).
      Turns the map into a coop scavenger hunt.

---

## Phase 5 — Lobby & session polish

- [ ] Mode picker / vote from the hub.
- [ ] Ready-up before a round.
- [ ] Drop-in/drop-out robustness pass (spectate, late-join, mid-round leaves).
- [ ] Name entry / persistent-per-session identity.
- [ ] "Best of the night" end-of-session summary screen.

---

## Loose threads to fold in (don't let these rot)

- [ ] **Gem caverns (Level B)** — built but sealed; give it a purpose (a mode
      arena? a coop objective?) or cut it.
- [ ] **Stone tower interior** — empty; candidate Sumo arena or KotH spot.
- [ ] **Troll** — promised; lands naturally as the Goblin Siege boss (Phase 4).
- [ ] **Powers** — currently mutually exclusive novelties; decide their role in
      rounds (pickups? disabled? mode-granted?) vs. hub free-play.

---

## Suggested build order (MVP path)

1. **0.1 Respawn** → **0.2 Scoreboard** → **0.3 Round controller** (the
   skeleton; also fixes the off-map bug).
2. **Phase 1 Sumo** (first real round; proves the skeleton).
3. **Phase 2 juice** — at least KO sound + winner banner + player colors, so
   Sumo actually *feels* like a party game.
4. Then breadth: one more competitive (KotH) and one coop (Goblin Siege) to
   have a rotation, and a simple mode picker (Phase 5).

**MVP definition of done:** friends can host, mess around in the hub, start a
Sumo round from within the world, ragdoll each other out, see a winner and a
running scoreboard, and drop back into the hub — on repeat, with sound.
