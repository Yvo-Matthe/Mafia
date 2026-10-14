# Mafia: City of Families

A top-down real-time strategy game for PC. Two crime families, the Corrados
and the Morettis, fight over a city of twelve districts. Play against the
computer or against another person online. Take blocks by standing your crew in them, collect
their income, recruit more muscle, and either own the whole city or burn the
rival headquarters down.

This is a playable vertical slice built with **Godot 4.3** (GDScript, no paid
engine or assets; everything is drawn in code).

## Play it

1. Install [Godot 4.3 or newer](https://godotengine.org/download) (standard
   build, not .NET).
2. Open Godot, choose **Import**, and pick this folder's `project.godot`.
3. Press **F5** (Run Project) and pick a mode on the title screen.

## Online multiplayer (2 players)

1. One player clicks **Host a game** (default port 7777). The title screen
   shows their local address. They play the blue Corrado family.
2. The other player types that address into the box next to **Join** (add
   `:port` if the host changed it) and clicks **Join**. They play the red
   Morettis.
3. The match starts as soon as both are connected.

On the same home or office network this just works. Over the internet the
host must forward **UDP port 7777** on their router to their PC and share
their public IP address. A tool like Tailscale or ZeroTier avoids port
forwarding by putting both PCs on one virtual network.

The host's game runs the match and sends the joining player about 20
snapshots a second; the joining player's orders go back to the host. If
either player leaves, the other wins. Online matches can't be paused.

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

**Winning.** Control all 12 districts, or destroy the other family's
headquarters. You lose if they do either to you.

**The computer opponent.** In single player you are the Corrados. The Moretti AI recruits continuously, defends its HQ, sends
crews of 2 to 3 toward the most valuable districts near them, and launches an
all-out assault on your HQ once it has 18 men.

## Project layout

```
project.godot          Engine settings (Compatibility renderer for wide PC support)
scenes/menu.tscn       Title screen (entry scene): single player, host, join
scenes/main.tscn       A match
scripts/net.gd         Autoload: single player / host / client session state
scripts/menu.gd        Title screen and connecting
scripts/game_data.gd   All balance numbers, unit stats, district names and income
scripts/main.gd        Match setup, input, orders, income, victory and network sync
scripts/district.gd    Capture logic and drawing for one city block
scripts/unit.gd        Movement, targeting and combat for one soldier
scripts/hq.gd          Recruitment queue, rally point, HQ defense
scripts/rival_ai.gd    Computer opponent
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

To test online play on one machine, start a host and a client in two
terminals. The host's AI plays the Corrados and a simple test bot on the
client sends Moretti orders over the network:

```
godot --headless --path . -- --host --autoplay
godot --headless --path . -- --join=127.0.0.1 --autoplay
# NET: host applied 456 orders from the joined player
```
