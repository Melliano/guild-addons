-- Small, dependency-free serializer that produces strings safe to send as
-- addon messages (no NUL bytes, no pipes, no control characters).
local _, GJ = ...

local Serializer = {}
GJ.Serializer = Serializer

local byte, char, sub, find, format = string.byte, string.char, string.sub, string.find, string.format
local tostring, tonumber, type, pairs = tostring, tonumber, type, pairs
local tconcat = table.concat

-- Characters that must be escaped inside strings.
local function escapeChar(c)
    return format("~%02x", byte(c))
end

local function escape(s)
    return (s:gsub("[%z\1-\31~'|\127]", escapeChar))
end

local function unescape(s)
    return (s:gsub("~(%x%x)", function(h) return char(tonumber(h, 16)) end))
end

local function write(v, out)
    local t = type(v)
    if t == "string" then
        out[#out + 1] = "'" .. escape(v) .. "'"
    elseif t == "number" then
        if v == math.floor(v) and v > -1e15 and v < 1e15 then
            out[#out + 1] = format("#%d;", v)
        else
            out[#out + 1] = "#" .. format("%.6g", v) .. ";"
        end
    elseif t == "boolean" then
        out[#out + 1] = v and "T" or "F"
    elseif t == "table" then
        out[#out + 1] = "{"
        -- Array part first, compactly, then the hash part.
        local n = #v
        for i = 1, n do
            write(v[i], out)
        end
        out[#out + 1] = "^"
        for k, val in pairs(v) do
            local isArray = type(k) == "number" and k >= 1 and k <= n and k == math.floor(k)
            if not isArray then
                write(k, out)
                write(val, out)
            end
        end
        out[#out + 1] = "}"
    else
        out[#out + 1] = "n"
    end
end

function Serializer.Serialize(v)
    local out = {}
    write(v, out)
    return tconcat(out)
end

local read

read = function(s, pos)
    local c = sub(s, pos, pos)
    if c == "'" then
        local e = find(s, "'", pos + 1, true)
        if not e then error("unterminated string") end
        return unescape(sub(s, pos + 1, e - 1)), e + 1
    elseif c == "#" then
        local e = find(s, ";", pos + 1, true)
        if not e then error("unterminated number") end
        return tonumber(sub(s, pos + 1, e - 1)), e + 1
    elseif c == "T" then
        return true, pos + 1
    elseif c == "F" then
        return false, pos + 1
    elseif c == "n" then
        return nil, pos + 1
    elseif c == "{" then
        local t = {}
        pos = pos + 1
        local i = 1
        while sub(s, pos, pos) ~= "^" do
            if pos > #s then error("unterminated table") end
            t[i], pos = read(s, pos)
            i = i + 1
        end
        pos = pos + 1
        while sub(s, pos, pos) ~= "}" do
            if pos > #s then error("unterminated table") end
            local k, v
            k, pos = read(s, pos)
            v, pos = read(s, pos)
            if k ~= nil then t[k] = v end
        end
        return t, pos + 1
    end
    error("bad token '" .. c .. "' at " .. pos)
end

-- Returns ok, value
function Serializer.Deserialize(s)
    if type(s) ~= "string" or s == "" then return false end
    local ok, v = pcall(read, s, 1)
    if not ok then return false, v end
    return true, v
end
