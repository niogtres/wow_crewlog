
CrewlogDB = {
	["addonVersion"] = "0.1.0-test",
	["chars"] = {
		["Player-6949-0A1B2C3D"] = {
			["class"] = "ROGUE",
			["classId"] = 4,
			["completed"] = {
				788, -- [1]
				3911, -- [2]
				4641, -- [3]
			},
			["completedHash"] = "0010a867",
			["faction"] = "Horde",
			["lastSeen"] = 1795450008,
			["level"] = 2,
			["log"] = {
			},
			["map"] = 1412,
			["name"] = "Zarnokk",
			["pos"] = {
				["map"] = 1411,
				["x"] = 43.2,
				["y"] = 68.7,
			},
			["race"] = "Troll",
			["raceId"] = 8,
			["realmId"] = 6949,
			["seq"] = 11,
			["sex"] = 3,
		},
	},
	["events"] = {
		{
			["c"] = "Player-6949-0A1B2C3D",
			["k"] = "ACCEPT",
			["q"] = 788,
			["s"] = 3,
			["t"] = 3,
		}, -- [1]
		{
			["c"] = "Player-6949-0A1B2C3D",
			["k"] = "ACCEPT",
			["q"] = 97279,
			["s"] = 4,
			["t"] = 1795450000,
		}, -- [2]
		{
			["c"] = "Player-6949-0A1B2C3D",
			["h"] = 6,
			["k"] = "PROGRESS",
			["n"] = 10,
			["o"] = 1,
			["q"] = 788,
			["s"] = 5,
			["t"] = 1795450000,
		}, -- [3]
		{
			["c"] = "Player-6949-0A1B2C3D",
			["h"] = 7,
			["k"] = "PROGRESS",
			["n"] = 10,
			["o"] = 1,
			["q"] = 788,
			["s"] = 6,
			["t"] = 1795450000.55,
		}, -- [4]
		{
			["c"] = "Player-6949-0A1B2C3D",
			["f"] = true,
			["h"] = 10,
			["k"] = "PROGRESS",
			["n"] = 10,
			["o"] = 1,
			["q"] = 788,
			["s"] = 7,
			["t"] = 1795450001,
		}, -- [5]
		{
			["c"] = "Player-6949-0A1B2C3D",
			["k"] = "TURNIN",
			["q"] = 788,
			["s"] = 8,
			["t"] = 1795450001,
			["x"] = 450,
		}, -- [6]
		{
			["c"] = "Player-6949-0A1B2C3D",
			["k"] = "ABANDON",
			["q"] = 97279,
			["s"] = 9,
			["t"] = 1795450007.35,
		}, -- [7]
		{
			["c"] = "Player-6949-0A1B2C3D",
			["k"] = "LEVEL",
			["l"] = 2,
			["s"] = 10,
			["t"] = 1795450008,
		}, -- [8]
		{
			["c"] = "Player-6949-0A1B2C3D",
			["k"] = "ZONE",
			["m"] = 1412,
			["s"] = 11,
			["t"] = 1795450008,
		}, -- [9]
	},
	["harvest"] = {
		["quests"] = {
			[788] = {
				["ender"] = {
					["map"] = 1411,
					["npc"] = 3143,
					["x"] = 0.4323,
					["y"] = 0.6885,
				},
				["t"] = 1795450001,
				["title"] = "kept",
			},
			[790] = {
				["after"] = 788,
				["giver"] = {
					["map"] = 1411,
					["npc"] = 3143,
					["x"] = 0.4323,
					["y"] = 0.6885,
				},
				["obj"] = "Collect 6 Abandoned Training Weapons.",
				["t"] = 1795450007,
				["title"] = "Sarkoth",
			},
			[97279] = {
				["giver"] = {
					["map"] = 1411,
					["npc"] = 3143,
					["x"] = 0.4323,
					["y"] = 0.6885,
				},
				["lvl"] = 2,
				["obj"] = "Collect 6 Abandoned Training Weapons.",
				["scaling"] = true,
				["t"] = 1795450000,
				["title"] = "Wayward Weapons",
			},
		},
	},
	["installId"] = "abc",
	["lastInbox"] = 1795449400,
	["lastPrune"] = {
		["events"] = 2,
		["harvest"] = 1,
		["t"] = 1795450000,
	},
	["schema"] = 1,
	["ui"] = {
		["hideMinimap"] = false,
	},
}
