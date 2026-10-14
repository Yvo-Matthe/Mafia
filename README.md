# Mafia: City of Families

A top-down real-time strategy game for PC. Up to four crime families (the
Corrados, Morettis, Bellinis and Vitales) fight over a city of twelve
districts. Any family can be run by a person, online, or by the computer, and
families can team up. Take blocks by standing your crew in them, collect
their income, recruit more muscle, and either own the whole city or burn the
rival headquarters down.

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
| Right-click | Move, or attack the enemy under the cursor |
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

**Districts.** A district's ring fills toward whichever family has units
inside it and nobody else's. Neutral blocks take 100 points to claim; an enemy
block must be drained to neutral first (200 points). Each unit adds 10
points per second, up to 4 units. Owned districts pay their income every 3
seconds on top of your HQ's base income.

**Units.**

| Unit | Cost | HP | Damage | Range | Notes |
| --- | --- | --- | --- | --- | --- |
| Thug | $150 | 80 | 8 | short | Cheap and fast, good for grabbing blocks |
| Enforcer | $300 | 230 | 14 | short | Slow, soaks damage |
| Hitman | $450 | 70 | 32 | long | Fragile, hits hard from range |

Headquarters have 1500 HP and a small gun that shoots units close by.

**Winning.** A family whose headquarters burns is out: its crew scatters and
its districts go neutral. A team wins when every rival team is out, or when
its families own all 12 districts between them. If you are knocked out while
allies fight on, you can keep watching.

**Computer families.** You are always the Corrados. Each computer family recruits continuously, defends its HQ, sends
crews of 2 to 3 toward the most valuable districts near them, and launches an
all-out assault on the nearest enemy HQ once it has 18 men.

## Project layout

```
project.godot          Engine settings (Compatibility renderer for wide PC support)
scenes/menu.tscn       Title screen (entry scene): single player, host, join
scenes/main.tscn       A match
scripts/net.gd         Autoload: lobby seats, teams, and host / client session state
scripts/menu.gd        Title screen, connecting and the match lobby
scripts/game_data.gd   All balance numbers, unit stats, district names and income
scripts/main.gd        Match setup, input, orders, income, victory and network sync
scripts/district.gd    Capture logic and drawing for one city block
scripts/unit.gd        Movement, targeting and combat for one soldier
scripts/hq.gd          Recruitment queue, rally point, HQ defense
scripts/rival_ai.gd    Computer-run family
scripts/hud.gd         Top bar, recruit panel, notifications, end screen
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
# AUTOPLAY RESULT: winner=The Corrado Family after 225s (...) districts 12-0
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
