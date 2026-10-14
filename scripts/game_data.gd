class_name GameData
extends RefCounted
## Tuning constants and static data for a match. Change balance here.

const WORLD_SIZE := Vector2(2400, 1800)
const STREET := 80.0
const COLS := 4
const ROWS := 3

const PLAYER := 0
const RIVAL := 1
const NEUTRAL := -1

const START_MONEY := 600
const INCOME_INTERVAL := 3.0  # seconds between payouts
const HQ_INCOME := 25  # paid every interval while the HQ stands
const POP_CAP := 30
const QUEUE_MAX := 5

const FAMILY_NAMES := ["The Corrado Family", "The Moretti Family"]
const FAMILY_SHORT := ["Corrado", "Moretti"]
const FAMILY_COLORS := [Color(0.30, 0.56, 0.96), Color(0.92, 0.26, 0.24)]

const UNIT_ORDER := ["thug", "enforcer", "hitman"]
const UNIT_TYPES := {
	"thug": {
		"name": "Thug", "letter": "T", "cost": 150, "build_time": 3.0,
		"hp": 80.0, "damage": 8.0, "range": 40.0, "cooldown": 0.8,
		"speed": 115.0, "radius": 10.0,
	},
	"enforcer": {
		"name": "Enforcer", "letter": "E", "cost": 300, "build_time": 5.0,
		"hp": 230.0, "damage": 14.0, "range": 45.0, "cooldown": 1.0,
		"speed": 82.0, "radius": 13.0,
	},
	"hitman": {
		"name": "Hitman", "letter": "H", "cost": 450, "build_time": 6.0,
		"hp": 70.0, "damage": 32.0, "range": 170.0, "cooldown": 1.6,
		"speed": 95.0, "radius": 9.0,
	},
}

# Row-major, top-left to bottom-right. Income is paid every INCOME_INTERVAL.
const DISTRICTS := [
	{"name": "Little Italy", "income": 25},
	{"name": "Garment District", "income": 30},
	{"name": "Chinatown", "income": 35},
	{"name": "The Docks", "income": 50},
	{"name": "Bowery", "income": 30},
	{"name": "Casino Row", "income": 60},
	{"name": "Financial District", "income": 55},
	{"name": "Meatpacking", "income": 30},
	{"name": "Waterfront", "income": 45},
	{"name": "Old Town", "income": 35},
	{"name": "Midtown", "income": 30},
	{"name": "Harlem Heights", "income": 25},
]
const HOME_DISTRICTS := [0, 11]  # HQ location per family
