# Mafia: City of Families

A top-down real-time strategy game for PC. Up to four crime families (the
Corrados, Morettis, Bellinis and Vitales) fight over a big, scrolling city of
48 blocks and about 200 businesses, grouped into twelve districts. Any family
can be run by a person, online, or by the computer, and families can team up.
Lean on bakeries, bars and casinos until they pay you protection, buy out the
best of them, run whole districts, recruit more muscle, and either rule the
whole city or burn the rival headquarters down.

This is a playable vertical slice built with **Godot 4.3** (GDScript, no paid
engine or assets; everything is drawn in code).

## Play it

1. Install [Godot 4.3 or newer](https://godotengine.org/download) (standard
   build, not .NET).
2. Open Godot, choose **Import**, and pick this folder's `project.godot`.
3. Press **F5** (Run Project) and pick a mode on the title screen.

## Setting up a match

Both **Play against the computer** and **Host a game** open the lobby, which
has four seats, one per family. Each seat is **You**, a joined player,
**Computer**, **Open for a player** (online only) or **Empty**, and each
family picks a team. Families on the same team are allies: they don't fight,
don't take each other's districts, and win together. Some setups:

* 1 vs 1 against the computer (the default)
* Free-for-all against three computer families
* 2 vs 2: you and a friend against two computer families
* Three players and one computer family, everyone for themselves

## Online multiplayer (up to 4 players)

1. One player clicks **Host a game** (default port 7777). The lobby shows
   their local address. They play the blue Corrado family.
2. The others type that address into the box next to **Join** (add `:port`
   if the host changed it) and click **Join**. Each takes the next open seat.
3. The host sets the remaining seats and teams and clicks **Start the war**.
   Open seats nobody joined are left empty.

On the same home or office network this just works. Over the internet the
host must forward **UDP port 7777** on their router to their PC and share
their public IP address. A tool like Tailscale or ZeroTier avoids port
forwarding by putting both PCs on one virtual network.

The host's game runs the match, computer families included, and sends the
other players about 20 snapshots a second; their orders go back to the host.
If a player leaves mid-match, the computer takes over their family. If the
host leaves, the match ends. Online matches can't be paused.

## How to play

| Input | Action |
| --- | --- |
| Left-click / left-drag | Select a unit / box-select (Shift adds) |
| Right-click | Move, attack the enemy under the cursor, or lean on the business under it |
| Left-click a business | Show its details (owner, takings, takeover price) |
| T | Take over the selected business |
| Tab | Territory screen: income per district |
| A, then left-click | Attack-move (fight anything on the way) |
| S | Stop |
| F | Select your whole crew |
| 1 / 2 / 3 | Recruit Thug / Enforcer / Hitman |
| Click your HQ, then right-click | Set the rally point |
| Arrows, screen edge, middle-drag | Pan |
| Mouse wheel | Zoom |
| H or Space | Jump to your HQ |
| P | Pause (single player only) |
| R | After a match: play again (single player) or back to the menu (online) |

**Rackets.** Every block is lined with businesses, from barbers ($2) to
casinos ($16+), and richer districts pay more. Send crew to a business
(right-click it) and they lean on it while they stand there: its meter fills
at 12 points per second per gangster, up to 3. A free business pays you
protection, 40% of its takings, once the meter is full. A rival's business has
to be drained to free first, and one they own outright takes twice as long.
Rival crews at the same business stall each other.

**Takeovers.** Click a business that pays you protection and press **T** (or
the button) to buy it out for 30x its takings. From then on it pays its full
takings. Takeovers are the main way to turn cash into income.

**Districts.** Hold more than half the businesses in a district and you run
it: it shows your colour and pays a district bonus ($10 to $25) every payout.
Each family starts running its home district. The **Territory** screen (Tab)
lists every district with who runs it, your protected and owned businesses,
rival holdings and what it earns you, plus a breakdown of your income.
Everything pays every 3 seconds on top of your HQ's base income.

**Units.**

| Unit | Cost | HP | Damage | Range | Notes |
| --- | --- | --- | --- | --- | --- |
| Thug | $150 | 80 | 8 | short | Cheap and fast, good for grabbing blocks |
| Enforcer | $300 | 230 | 14 | short | Slow, soaks damage |
| Hitman | $450 | 70 | 32 | long | Fragile, hits hard from range |

Headquarters have 2500 HP and a small gun that shoots units close by. Idle
crew only fight other gangsters; to hit a headquarters, order an attack on it
or attack-move past it.

**Winning.** A family whose headquarters burns is out: its crew scatters and
its businesses go free. A team wins when every rival team is out, or when
its families run all 12 districts between them. If you are knocked out while
allies fight on, you can keep watching.

**Computer families.** You are always the Corrados. Each computer family recruits continuously, defends its HQ, sends
crews of 1 to 2 to shake down the most valuable businesses near them
(preferring ones that would tip a district), spends spare cash taking over
the rackets it runs, and after six minutes launches an all-out assault on the
nearest enemy HQ once it has 22 men.

## Project layout

```
project.godot          Engine settings (Compatibility renderer for wide PC support)
scenes/menu.tscn       Title screen (entry scene): single player, host, join
scenes/main.tscn       A match
scripts/net.gd         Autoload: lobby seats, teams, and host / client session state
scripts/menu.gd        Title screen, connecting and the match lobby
scripts/game_data.gd   All balance numbers, unit stats, city layout, business types, districts
scripts/main.gd        City building, input, orders, income, victory and network sync
scripts/district.gd    One district of 2 x 2 blocks: lots, apartment houses, who runs it
scripts/business.gd    One business: extortion meter, protection, takeover, drawing
scripts/unit.gd        Movement, targeting and combat for one soldier
scripts/hq.gd          Recruitment queue, rally point, HQ defense
scripts/rival_ai.gd    Computer-run family
scripts/hud.gd         Top bar, recruit panel, business panel, territory screen, end screen
scripts/minimap.gd     Clickable city overview
scripts/overlay.gd     Selection box and order markers
```

## Exporting a build

In Godot: **Editor > Manage Export Templates > Download**, then
**Project > Export**, add a Windows Desktop, macOS or Linux preset, and click
**Export Project**.

## Testing without a screen

Running with `--autoplay` puts an AI in charge of your family too and prints
the result:

```
godot --headless --fixed-fps 60 --path . -- --autoplay
# AUTOPLAY RESULT: winner=The Moretti Family after 432s (...) districts: ..., Moretti 9 (146 businesses, 146 owned, $1297/interval)
```

`--slots=you,ai,ai,ai` sets the seats (`ai`, `open` or `closed` after the
first) and `--teams=0,0,1,1` the teams, for single player or hosting.

To test online play on one machine, start a host and one or more clients in
separate terminals. Under `--autoplay` the host starts once every open seat
is filled, the computer plays the host's family, and a simple test bot on
each client sends its orders over the network:

```
godot --headless --path . -- --host --autoplay --slots=you,open,ai,ai --teams=0,0,1,1
godot --headless --path . -- --join=127.0.0.1 --autoplay
# NET: host applied 507 orders from joined players
```
