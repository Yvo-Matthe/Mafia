class_name GameData
extends RefCounted
## Tuning constants and static data for a match. Change balance here.

# The city is a grid of blocks; every 2 x 2 blocks form one named district.
const BLOCK := Vector2(380, 320)
const STREET := 80.0
const COLS := 8  # blocks across
const ROWS := 6  # blocks down
const DISTRICT_SPAN := 2  # blocks per district side
const DISTRICT_COLS := 4  # COLS / DISTRICT_SPAN
const DISTRICT_ROWS := 3  # ROWS / DISTRICT_SPAN
const WORLD_SIZE := Vector2(COLS * BLOCK.x + (COLS + 1) * STREET, ROWS * BLOCK.y + (ROWS + 1) * STREET)

const MAX_FAMILIES := 4
const NEUTRAL := -1

const START_MONEY := 600
const INCOME_INTERVAL := 3.0  # seconds between payouts
const HQ_INCOME := 25  # paid every interval while the HQ stands
const POP_CAP := 30
const QUEUE_MAX := 5

const FAMILY_NAMES := ["The Corrado Family", "The Moretti Family", "The Bellini Family", "The Vitale Family"]
const FAMILY_SHORT := ["Corrado", "Moretti", "Bellini", "Vitale"]
const FAMILY_COLORS := [
	Color(0.30, 0.56, 0.96), Color(0.92, 0.26, 0.24),
	Color(0.30, 0.80, 0.42), Color(0.95, 0.74, 0.20),
]

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

# --- Rackets -----------------------------------------------------------------
# Crew standing at a business lean on it. A free business starts paying
# protection once its meter is full; a rival's has to be drained first.
# A business under your protection can then be taken over for cash, which
# makes it pay its full takings instead of a cut.
const EXTORT_RATE := 12.0  # meter points per second per gangster
const MAX_EXTORTERS := 3  # more crew than this doesn't lean any harder
const OWNED_DRAIN_FACTOR := 0.5  # a taken-over business resists twice as long
const EXTORT_ZONE := 34.0  # how far from the walls crew still counts
const PROTECTION_SHARE := 0.4  # cut of the takings a protected business pays
const TAKEOVER_PRICE := 30  # takeover costs this many times the takings
const DISTRICT_MAJORITY := 0.5  # hold more than this share to run a district

# Takings are paid every INCOME_INTERVAL by a business you own (protection
# pays PROTECTION_SHARE of it), before the district's wealth multiplier.
const BUSINESS_TYPES := {
	"barber": {"name": "Barber", "letter": "Br", "takings": 2, "color": Color(0.55, 0.62, 0.70)},
	"bakery": {"name": "Bakery", "letter": "Bk", "takings": 3, "color": Color(0.80, 0.66, 0.44)},
	"laundry": {"name": "Laundry", "letter": "Ld", "takings": 3, "color": Color(0.50, 0.70, 0.78)},
	"grocer": {"name": "Grocer", "letter": "Gr", "takings": 3, "color": Color(0.48, 0.70, 0.40)},
	"diner": {"name": "Diner", "letter": "Dn", "takings": 4, "color": Color(0.82, 0.44, 0.40)},
	"pawn": {"name": "Pawn Shop", "letter": "Pw", "takings": 5, "color": Color(0.70, 0.60, 0.30)},
	"pool": {"name": "Pool Hall", "letter": "Pl", "takings": 5, "color": Color(0.30, 0.60, 0.42)},
	"bar": {"name": "Bar", "letter": "Ba", "takings": 6, "color": Color(0.66, 0.40, 0.24)},
	"restaurant": {"name": "Restaurant", "letter": "Rs", "takings": 7, "color": Color(0.72, 0.30, 0.34)},
	"warehouse": {"name": "Warehouse", "letter": "Wh", "takings": 8, "color": Color(0.46, 0.44, 0.40)},
	"hotel": {"name": "Hotel", "letter": "Ht", "takings": 9, "color": Color(0.60, 0.52, 0.70)},
	"speakeasy": {"name": "Speakeasy", "letter": "Sp", "takings": 10, "color": Color(0.58, 0.34, 0.58)},
	"bookie": {"name": "Bookmaker", "letter": "Bm", "takings": 11, "color": Color(0.36, 0.52, 0.30)},
	"nightclub": {"name": "Nightclub", "letter": "Nc", "takings": 12, "color": Color(0.80, 0.30, 0.62)},
	"casino": {"name": "Casino", "letter": "Cs", "takings": 16, "color": Color(0.90, 0.72, 0.24)},
}
const BUSINESS_OWNERS := [
	"Sal's", "Vinnie's", "Rosa's", "Mickey's", "Lou's", "Frankie's", "Angelo's", "Dot's",
	"Benny's", "Carmine's", "Nell's", "Paulie's", "Gino's", "Ida's", "Max's", "Tommy's",
	"Fat Joe's", "Lucky's", "Stella's", "Murph's", "Sid's", "Nico's", "Bella's", "Duke's",
]

# Row-major, top-left to bottom-right. `wealth` scales every business's
# takings; `bonus` is paid each interval to whoever runs the district;
# `mix` is the kind of businesses it tends to have.
const DISTRICTS := [
	{"name": "Little Italy", "wealth": 0.9, "bonus": 10, "mix": ["bakery", "restaurant", "diner", "bar", "grocer", "barber"]},
	{"name": "Garment District", "wealth": 1.0, "bonus": 12, "mix": ["laundry", "warehouse", "diner", "pawn", "grocer"]},
	{"name": "Chinatown", "wealth": 1.0, "bonus": 14, "mix": ["restaurant", "laundry", "grocer", "bookie", "speakeasy"]},
	{"name": "The Docks", "wealth": 1.2, "bonus": 20, "mix": ["warehouse", "bar", "warehouse", "pawn", "speakeasy"]},
	{"name": "Bowery", "wealth": 0.8, "bonus": 12, "mix": ["bar", "pool", "pawn", "diner", "barber", "speakeasy"]},
	{"name": "Casino Row", "wealth": 1.5, "bonus": 25, "mix": ["casino", "nightclub", "hotel", "bar", "bookie"]},
	{"name": "Financial District", "wealth": 1.4, "bonus": 22, "mix": ["hotel", "restaurant", "bookie", "diner", "barber"]},
	{"name": "Meatpacking", "wealth": 0.9, "bonus": 12, "mix": ["warehouse", "diner", "bar", "nightclub", "grocer"]},
	{"name": "Waterfront", "wealth": 1.1, "bonus": 18, "mix": ["warehouse", "bar", "speakeasy", "hotel", "pool"]},
	{"name": "Old Town", "wealth": 1.0, "bonus": 14, "mix": ["bakery", "barber", "pawn", "restaurant", "pool"]},
	{"name": "Midtown", "wealth": 1.1, "bonus": 12, "mix": ["hotel", "nightclub", "restaurant", "diner", "laundry"]},
	{"name": "Harlem Heights", "wealth": 0.9, "bonus": 10, "mix": ["nightclub", "diner", "bar", "pool", "bakery", "speakeasy"]},
]
const HOME_DISTRICTS := [0, 11, 3, 8]  # HQ district per family: opposite corners first
