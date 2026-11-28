-- Party relay (Live.lua + Sign.lua): HMAC-SHA256, signed snapshots with position and turn-ins, and what a crewmate
-- with "Upload my party's progress" on keeps for their app.
-- Run from the repo root: lua5.1 addon/tests/relay_test.lua
local H = dofile("addon/tests/harness.lua")
local st = H.state

local passed, failed = 0, 0
local function check(cond, msg)
  if cond then passed = passed + 1 else failed = failed + 1; print("FAIL: " .. msg) end
end

-- 1. SHA-256 and HMAC against the standard test vectors, with plain arithmetic (no bit library) ...
local function loadSign()
  local ns = {}
  assert(loadfile("addon/Crewlog/Sign.lua"))("Crewlog", ns)
  return ns.Sign
end
local function vectors(Sign, how)
  check(Sign.hex(Sign.sha256("abc")) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", how .. ": sha256(abc)")
  check(Sign.hex(Sign.sha256("")) == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", how .. ": sha256 of nothing")
  check(Sign.hex(Sign.sha256(string.rep("a", 1000))) == "41edece42d63e8d9bf515a9ba6932e1c20cbc9f5a5d134645adb5db1b9737ea3", how .. ": sha256, several blocks")
  -- RFC 4231 test case 2 (key "Jefe")
  check(Sign.hmac("4a656665", "what do ya want for nothing?") == "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843", how .. ": hmac")
  check(Sign.hmac("zz", "x") == nil and Sign.hmac("abc", "x") == nil, how .. ": a key that isn't hex is refused")
end
vectors(loadSign(), "arithmetic")

-- ... and with a bit library that, like the game's, answers with signed 32-bit numbers.
local M = 4294967296
local function bits(a, b, f)
  a, b = a % M, b % M
  local r, m = 0, 1
  for _ = 1, 32 do
    r = r + f(a % 2, b % 2) * m
    a, b, m = math.floor(a / 2), math.floor(b / 2), m * 2
  end
  return r >= 2147483648 and r - M or r
end
local function signed(x) x = x % M; return x >= 2147483648 and x - M or x end
bit = {
  band = function(a, b) return bits(a, b, function(x, y) return (x == 1 and y == 1) and 1 or 0 end) end,
  bor = function(a, b) return bits(a, b, function(x, y) return (x == 1 or y == 1) and 1 or 0 end) end,
  bxor = function(a, b) return bits(a, b, function(x, y) return x ~= y and 1 or 0 end) end,
  rshift = function(a, n) return signed(math.floor((a % M) / 2 ^ n)) end,
  lshift = function(a, n) return signed((a % M) * 2 ^ n) end,
}
vectors(loadSign(), "game bit library")
bit = nil

-- The addon, in a group with Bob.
local BOB = "Player-6949-0B0B0B0B"
local KEY = "00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff"
st.log = { { header = "Durotar" } }
H.addQuest(789, "Sting of the Scorpid", 3, { { 4, 10, false, "item", "Scorpid Worker Tail" } })
H.addQuest(4641, "Your Place In The World", 1, {})
CrewlogDB = nil
local ns = H.load("Crewlog", { "Util.lua", "Sign.lua", "Store.lua", "Harvest.lua", "Collector.lua", "Live.lua", "Crew.lua", "Next.lua", "Tooltips.lua", "Way.lua", "Route.lua", "UI.lua", "Core.lua" })
local Live, Sign = ns.Live, ns.Sign
H.fire("ADDON_LOADED", "Crewlog")
H.fire("PLAYER_LOGIN")
H.advance(2)
local db = CrewlogDB

local function kinds(list)
  local out = {}
  for _, m in ipairs(list) do out[#out + 1] = m.msg:sub(1, 1) end
  return table.concat(out)
end
local function find(list, kind)
  for _, m in ipairs(list) do if m.msg:sub(1, 1) == kind then return m.msg end end
end
-- Our messages as Bob's client would send them.
local function deliverAsBob(list)
  for _, m in ipairs(list) do
    H.fire("CHAT_MSG_ADDON", m.prefix, (m.msg:gsub(st.guid:gsub("%-", "%%-"), BOB)), m.channel, "Brogg")
  end
end

H.group.members = { { BOB, "Brogg" } }
H.fire("GROUP_ROSTER_UPDATE")
H.advance(3)

-- 2. Without a key (the owner hasn't allowed relaying): position, no signature.
check(kinds(H.sent) == "HBLPE", "no key: no S message, got " .. kinds(H.sent))
check(find(H.sent, "P") == "P|" .. st.guid .. "|1|1411|432|689", "position in tenths of a percent: " .. tostring(find(H.sent, "P")))

-- 3. Bob receives it; with party upload off nothing is kept, even when signed.
H.sent = {}
Crewlog_Inbox = { relayKeys = { [st.guid] = KEY } }
Live.sync()
H.advance(3)
check(kinds(H.sent) == "BLPSE", "with a key the snapshot is signed, got " .. kinds(H.sent))
local signedSnap = H.sent
H.sent = {}
deliverAsBob(signedSnap)
check(Live.peers[BOB] and Live.peers[BOB].pos and Live.peers[BOB].pos.map == 1411, "a peer's position is decoded")
check(db.relay == nil, "party upload off: nothing kept for relaying")

-- 4. Party upload on: the signed snapshot is kept, and its text verifies with the owner's key.
SlashCmdList.CREWLOG("relay")
check(Live.relayOn(), "/cl relay turns party upload on")
deliverAsBob(signedSnap)
local r = db.relay and db.relay[BOB]
check(r and r.s and r.sig and #r.sig == 32, "the signed snapshot is kept")
local sent = r and r.s:gsub(BOB:gsub("%-", "%%-"), st.guid)  -- what we signed, before the test renamed us to Bob
check(r and Sign.sign(KEY, sent) == r.sig, "the kept text is exactly what was signed")
check(r and r.s:match("^1|" .. BOB:gsub("%-", "%%-") .. "|%d+|1|1411|432|689|789,0,4/10;4641,1,|$"),
  "canonical text: version, toon, time, level, position, quests, turn-ins: " .. tostring(r and r.s))
check(r and Sign.sign("ff" .. KEY:sub(3), sent) ~= r.sig, "another key gives another signature")

-- 5. A turn-in goes out in T and inside the signature.
st.completed = { 4641 }
H.removeQuest(4641)
H.fire("QUEST_TURNED_IN", 4641, 100, 0)
H.fire("QUEST_REMOVED", 4641)
H.advance(1)
H.sent = {}
Live.sync()
H.advance(3)
check((find(H.sent, "T") or ""):match("^T|" .. st.guid:gsub("%-", "%%-") .. "|%d+|4641$"), "T carries the turn-in: " .. tostring(find(H.sent, "T")))
deliverAsBob(H.sent)
r = db.relay[BOB]
check(r.s:match("|789,0,4/10|4641$"), "the turn-in is signed, the quest gone from the log: " .. r.s)
check(Sign.sign(KEY, (r.s:gsub(BOB:gsub("%-", "%%-"), st.guid))) == r.sig, "still verifies")

-- 6. A snapshot changed on the way doesn't verify; one without S (an older addon) isn't kept.
local tampered = {}
for _, m in ipairs(H.sent) do tampered[#tampered + 1] = { prefix = m.prefix, channel = m.channel, msg = (m.msg:gsub("4/10", "10/10")) } end
db.relay = nil
deliverAsBob(tampered)
r = db.relay and db.relay[BOB]
check(r and Sign.sign(KEY, (r.s:gsub(BOB:gsub("%-", "%%-"), st.guid))) ~= r.sig, "a changed snapshot no longer matches its signature")
db.relay = nil
local unsigned = {}
for _, m in ipairs(H.sent) do if m.msg:sub(1, 1) ~= "S" then unsigned[#unsigned + 1] = m end end
deliverAsBob(unsigned)
check(db.relay == nil or db.relay[BOB] == nil, "an unsigned snapshot isn't kept")

-- 7. From someone outside the group: ignored entirely.
db.relay = nil
for _, m in ipairs(H.sent) do H.fire("CHAT_MSG_ADDON", m.prefix, (m.msg:gsub(st.guid:gsub("%-", "%%-"), "Player-6949-0C0C0C0C")), "WHISPER", "Stranger") end
check(db.relay == nil or db.relay["Player-6949-0C0C0C0C"] == nil, "a whispered snapshot is ignored")

-- 8. Turning party upload off forgets what was kept.
deliverAsBob(H.sent)
check(db.relay and db.relay[BOB], "kept again")
SlashCmdList.CREWLOG("relay")
check(not Live.relayOn() and db.relay == nil, "/cl relay off drops what was waiting")

print(string.format("%d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
