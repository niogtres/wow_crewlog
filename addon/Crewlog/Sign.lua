-- HMAC-SHA256 in plain Lua 5.1, for signing live snapshots that a crewmate may relay to the website (Live.lua,
-- DESIGN §5.4 "Party relay"). The game has a `bit` library; plain Lua 5.1 (the tests) doesn't, so the bit operations
-- fall back to arithmetic. Every result is brought into 0 .. 2^32-1, whichever library computed it.
local _, ns = ...
local Sign = {}
ns.Sign = Sign

local M = 4294967296
local floor = math.floor
local byte, char = string.byte, string.char

local band, bor, bxor, rshift, lshift
local lib = rawget(_G, "bit")
if lib and lib.band and lib.bxor and lib.rshift and lib.lshift and lib.bor then
  band = function(a, b) return lib.band(a, b) % M end
  bor = function(a, b) return lib.bor(a, b) % M end
  bxor = function(a, b) return lib.bxor(a, b) % M end
  rshift = function(a, n) return lib.rshift(a, n) % M end
  lshift = function(a, n) return lib.lshift(a, n) % M end
else
  -- Bitwise operations a nibble at a time through lookup tables.
  local AND, XOR = {}, {}
  for a = 0, 15 do
    AND[a], XOR[a] = {}, {}
    for b = 0, 15 do
      local r_and, r_xor, bit = 0, 0, 1
      local x, y = a, b
      for _ = 1, 4 do
        local xa, yb = x % 2, y % 2
        if xa == 1 and yb == 1 then r_and = r_and + bit end
        if xa ~= yb then r_xor = r_xor + bit end
        x, y, bit = floor(x / 2), floor(y / 2), bit * 2
      end
      AND[a][b], XOR[a][b] = r_and, r_xor
    end
  end
  local function op(t, a, b)
    a, b = a % M, b % M
    local r, m = 0, 1
    for _ = 1, 8 do
      r = r + t[a % 16][b % 16] * m
      a, b, m = floor(a / 16), floor(b / 16), m * 16
    end
    return r
  end
  band = function(a, b) return op(AND, a, b) end
  bxor = function(a, b) return op(XOR, a, b) end
  bor = function(a, b) a, b = a % M, b % M; return a + b - op(AND, a, b) end
  rshift = function(a, n) return floor((a % M) / 2 ^ n) end
  lshift = function(a, n) return ((a % M) * 2 ^ n) % M end
end

local function rrot(x, n) return bor(rshift(x, n), lshift(x, 32 - n)) end
local function bnot(x) return M - 1 - (x % M) end

local K = {
  0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
  0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
  0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
  0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
  0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
  0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
  0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
  0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
}

-- SHA-256 of a byte string, as 32 raw bytes.
function Sign.sha256(msg)
  local len = #msg
  local bits = len * 8
  msg = msg .. "\128" .. string.rep("\0", (55 - len) % 64)
  local tail = {}
  for i = 8, 1, -1 do tail[i] = char(bits % 256); bits = floor(bits / 256) end
  msg = msg .. table.concat(tail)

  local h0, h1, h2, h3 = 0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a
  local h4, h5, h6, h7 = 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19
  local w = {}
  for chunk = 1, #msg, 64 do
    for i = 0, 15 do
      local a, b, c, d = byte(msg, chunk + i * 4, chunk + i * 4 + 3)
      w[i] = ((a * 256 + b) * 256 + c) * 256 + d
    end
    for i = 16, 63 do
      local x, y = w[i - 15], w[i - 2]
      local s0 = bxor(bxor(rrot(x, 7), rrot(x, 18)), rshift(x, 3))
      local s1 = bxor(bxor(rrot(y, 17), rrot(y, 19)), rshift(y, 10))
      w[i] = (w[i - 16] + s0 + w[i - 7] + s1) % M
    end
    local a, b, c, d, e, f, g, h = h0, h1, h2, h3, h4, h5, h6, h7
    for i = 0, 63 do
      local S1 = bxor(bxor(rrot(e, 6), rrot(e, 11)), rrot(e, 25))
      local ch = bxor(band(e, f), band(bnot(e), g))
      local t1 = (h + S1 + ch + K[i + 1] + w[i]) % M
      local S0 = bxor(bxor(rrot(a, 2), rrot(a, 13)), rrot(a, 22))
      local maj = bxor(bxor(band(a, b), band(a, c)), band(b, c))
      local t2 = (S0 + maj) % M
      h, g, f, e, d, c, b, a = g, f, e, (d + t1) % M, c, b, a, (t1 + t2) % M
    end
    h0, h1, h2, h3 = (h0 + a) % M, (h1 + b) % M, (h2 + c) % M, (h3 + d) % M
    h4, h5, h6, h7 = (h4 + e) % M, (h5 + f) % M, (h6 + g) % M, (h7 + h) % M
  end
  local out = {}
  for i, v in ipairs({ h0, h1, h2, h3, h4, h5, h6, h7 }) do
    out[i] = char(floor(v / 16777216) % 256, floor(v / 65536) % 256, floor(v / 256) % 256, v % 256)
  end
  return table.concat(out)
end

function Sign.hex(s) return (s:gsub(".", function(c) return string.format("%02x", byte(c)) end)) end

function Sign.unhex(h)
  if type(h) ~= "string" or #h % 2 ~= 0 or h:find("[^%x]") then return nil end
  return (h:gsub("%x%x", function(x) return char(tonumber(x, 16)) end))
end

local function pad(key, v)
  local t = {}
  for i = 1, 64 do t[i] = char(bxor(byte(key, i) or 0, v)) end
  return table.concat(t)
end

-- HMAC-SHA256(key, msg) as lowercase hex; key given as hex (the Inbox's relay key).
function Sign.hmac(keyHex, msg)
  local key = Sign.unhex(keyHex)
  if not key then return nil end
  if #key > 64 then key = Sign.sha256(key) end
  return Sign.hex(Sign.sha256(pad(key, 0x5c) .. Sign.sha256(pad(key, 0x36) .. msg)))
end

-- What goes out with a snapshot: the first 128 bits, plenty against forgery and short enough for one message.
Sign.LENGTH = 32
function Sign.sign(keyHex, msg)
  local h = Sign.hmac(keyHex, msg)
  return h and h:sub(1, Sign.LENGTH)
end
