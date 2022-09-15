
local rootPath = "/Users/yusiyuan/Desktop/SlotsProject/multical/tools/Unity/LuaJsonConvert/"
 

local json = { _version = "0.1.2" } 
-------------------------------------------------------------------------------
-- Encode
-------------------------------------------------------------------------------

local encode

local escape_char_map = {
  [ "\\" ] = "\\",
  [ "\"" ] = "\"",
  [ "\b" ] = "b",
  [ "\f" ] = "f",
  [ "\n" ] = "n",
  [ "\r" ] = "r",
  [ "\t" ] = "t",
}

local escape_char_map_inv = { [ "/" ] = "/" }
for k, v in pairs(escape_char_map) do
  escape_char_map_inv[v] = k
end


local function escape_char(c)
  return "\\" .. (escape_char_map[c] or string.format("u%04x", c:byte()))
end


local function encode_nil(val)
  return "null"
end


local function encode_table(val, stack)
  local res = {}
  stack = stack or {}

  -- Circular reference?
  if stack[val] then error("circular reference") end

  stack[val] = true

  if rawget(val, 1) ~= nil or next(val) == nil then
    -- Treat as array -- check keys are valid and it is not sparse
    local n = 0
    for k in pairs(val) do
      if type(k) ~= "number" then
        error("invalid table: mixed or invalid key types")
      end
      n = n + 1
    end
    if n ~= #val then
      error("invalid table: sparse array")
    end
    -- Encode
    for i, v in ipairs(val) do
      table.insert(res, encode(v, stack))
    end
    stack[val] = nil
    return "[" .. table.concat(res, ",") .. "]"

  else
    -- Treat as an object
    for k, v in pairs(val) do
      if type(k) ~= "string" then
        error("invalid table: mixed or invalid key types")
      end
      table.insert(res, encode(k, stack) .. ":" .. encode(v, stack))
    end
    stack[val] = nil
    return "{" .. table.concat(res, ",") .. "}"
  end
end


local function encode_string(val)
  return '"' .. val:gsub('[%z\1-\31\\"]', escape_char) .. '"'
end


local function encode_number(val)
  -- Check for NaN, -inf and inf
  if val ~= val or val <= -math.huge or val >= math.huge then
    error("unexpected number value '" .. tostring(val) .. "'")
  end
  return string.format("%.14g", val)
end


local type_func_map = {
  [ "nil"     ] = encode_nil,
  [ "table"   ] = encode_table,
  [ "string"  ] = encode_string,
  [ "number"  ] = encode_number,
  [ "boolean" ] = tostring,
}


encode = function(val, stack)
  local t = type(val)
  local f = type_func_map[t]
  if f then
    return f(val, stack)
  end
  error("unexpected type '" .. t .. "'")
end


function json.encode(val)
  return ( encode(val) )
end


-------------------------------------------------------------------------------
-- Decode
-------------------------------------------------------------------------------

local parse

local function create_set(...)
  local res = {}
  for i = 1, select("#", ...) do
    res[ select(i, ...) ] = true
  end
  return res
end

local space_chars   = create_set(" ", "\t", "\r", "\n")
local delim_chars   = create_set(" ", "\t", "\r", "\n", "]", "}", ",")
local escape_chars  = create_set("\\", "/", '"', "b", "f", "n", "r", "t", "u")
local literals      = create_set("true", "false", "null")

local literal_map = {
  [ "true"  ] = true,
  [ "false" ] = false,
  [ "null"  ] = nil,
}


local function next_char(str, idx, set, negate)
  for i = idx, #str do
    if set[str:sub(i, i)] ~= negate then
      return i
    end
  end
  return #str + 1
end


local function decode_error(str, idx, msg)
  local line_count = 1
  local col_count = 1
  for i = 1, idx - 1 do
    col_count = col_count + 1
    if str:sub(i, i) == "\n" then
      line_count = line_count + 1
      col_count = 1
    end
  end
  error( string.format("%s at line %d col %d", msg, line_count, col_count) )
end


local function codepoint_to_utf8(n)
  -- http://scripts.sil.org/cms/scripts/page.php?site_id=nrsi&id=iws-appendixa
  local f = math.floor
  if n <= 0x7f then
    return string.char(n)
  elseif n <= 0x7ff then
    return string.char(f(n / 64) + 192, n % 64 + 128)
  elseif n <= 0xffff then
    return string.char(f(n / 4096) + 224, f(n % 4096 / 64) + 128, n % 64 + 128)
  elseif n <= 0x10ffff then
    return string.char(f(n / 262144) + 240, f(n % 262144 / 4096) + 128,
                       f(n % 4096 / 64) + 128, n % 64 + 128)
  end
  error( string.format("invalid unicode codepoint '%x'", n) )
end


local function parse_unicode_escape(s)
  local n1 = tonumber( s:sub(1, 4),  16 )
  local n2 = tonumber( s:sub(7, 10), 16 )
   -- Surrogate pair?
  if n2 then
    return codepoint_to_utf8((n1 - 0xd800) * 0x400 + (n2 - 0xdc00) + 0x10000)
  else
    return codepoint_to_utf8(n1)
  end
end


local function parse_string(str, i)
  local res = ""
  local j = i + 1
  local k = j

  while j <= #str do
    local x = str:byte(j)

    if x < 32 then
      decode_error(str, j, "control character in string")

    elseif x == 92 then -- `\`: Escape
      res = res .. str:sub(k, j - 1)
      j = j + 1
      local c = str:sub(j, j)
      if c == "u" then
        local hex = str:match("^[dD][89aAbB]%x%x\\u%x%x%x%x", j + 1)
                 or str:match("^%x%x%x%x", j + 1)
                 or decode_error(str, j - 1, "invalid unicode escape in string")
        res = res .. parse_unicode_escape(hex)
        j = j + #hex
      else
        if not escape_chars[c] then
          decode_error(str, j - 1, "invalid escape char '" .. c .. "' in string")
        end
        res = res .. escape_char_map_inv[c]
      end
      k = j + 1

    elseif x == 34 then -- `"`: End of string
      res = res .. str:sub(k, j - 1)
      return res, j + 1
    end

    j = j + 1
  end

  decode_error(str, i, "expected closing quote for string")
end


local function parse_number(str, i)
  local x = next_char(str, i, delim_chars)
  local s = str:sub(i, x - 1)
  local n = tonumber(s)
  if not n then
    decode_error(str, i, "invalid number '" .. s .. "'")
  end
  return n, x
end


local function parse_literal(str, i)
  local x = next_char(str, i, delim_chars)
  local word = str:sub(i, x - 1)
  if not literals[word] then
    decode_error(str, i, "invalid literal '" .. word .. "'")
  end
  return literal_map[word], x
end


local function parse_array(str, i)
  local res = {}
  local n = 1
  i = i + 1
  while 1 do
    local x
    i = next_char(str, i, space_chars, true)
    -- Empty / end of array?
    if str:sub(i, i) == "]" then
      i = i + 1
      break
    end
    -- Read token
    x, i = parse(str, i)
    res[n] = x
    n = n + 1
    -- Next token
    i = next_char(str, i, space_chars, true)
    local chr = str:sub(i, i)
    i = i + 1
    if chr == "]" then break end
    if chr ~= "," then decode_error(str, i, "expected ']' or ','") end
  end
  return res, i
end


local function parse_object(str, i)
  local res = {}
  i = i + 1
  while 1 do
    local key, val
    i = next_char(str, i, space_chars, true)
    -- Empty / end of object?
    if str:sub(i, i) == "}" then
      i = i + 1
      break
    end
    -- Read key
    if str:sub(i, i) ~= '"' then
      decode_error(str, i, "expected string for key")
    end
    key, i = parse(str, i)
    -- Read ':' delimiter
    i = next_char(str, i, space_chars, true)
    if str:sub(i, i) ~= ":" then
      decode_error(str, i, "expected ':' after key")
    end
    i = next_char(str, i + 1, space_chars, true)
    -- Read value
    val, i = parse(str, i)
    -- Set
    res[key] = val
    -- Next token
    i = next_char(str, i, space_chars, true)
    local chr = str:sub(i, i)
    i = i + 1
    if chr == "}" then break end
    if chr ~= "," then decode_error(str, i, "expected '}' or ','") end
  end
  return res, i
end


local char_func_map = {
  [ '"' ] = parse_string,
  [ "0" ] = parse_number,
  [ "1" ] = parse_number,
  [ "2" ] = parse_number,
  [ "3" ] = parse_number,
  [ "4" ] = parse_number,
  [ "5" ] = parse_number,
  [ "6" ] = parse_number,
  [ "7" ] = parse_number,
  [ "8" ] = parse_number,
  [ "9" ] = parse_number,
  [ "-" ] = parse_number,
  [ "t" ] = parse_literal,
  [ "f" ] = parse_literal,
  [ "n" ] = parse_literal,
  [ "[" ] = parse_array,
  [ "{" ] = parse_object,
}


parse = function(str, idx)
  local chr = str:sub(idx, idx)
  local f = char_func_map[chr]
  if f then
    return f(str, idx)
  end
  decode_error(str, idx, "unexpected character '" .. chr .. "'")
end


function json.decode(str)
  if type(str) ~= "string" then
    error("expected argument of type string, got " .. type(str))
  end
  local res, idx = parse(str, next_char(str, 1, space_chars, true))
  idx = next_char(str, idx, space_chars, true)
  if idx <= #str then
    decode_error(str, idx, "trailing garbage")
  end
  return res
end
 
 


local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local math = _tl_compat and _tl_compat.math or math; local string = _tl_compat and _tl_compat.string or string; local table = _tl_compat and _tl_compat.table or table
local inspect = {Options = {}, }

















inspect._VERSION = 'inspect.lua 3.1.0'
inspect._URL = 'http://github.com/kikito/inspect.lua'
inspect._DESCRIPTION = 'human-readable representations of tables'
inspect._LICENSE = [[
  MIT LICENSE

  Copyright (c) 2022 Enrique García Cota

  Permission is hereby granted, free of charge, to any person obtaining a
  copy of this software and associated documentation files (the
  "Software"), to deal in the Software without restriction, including
  without limitation the rights to use, copy, modify, merge, publish,
  distribute, sublicense, and/or sell copies of the Software, and to
  permit persons to whom the Software is furnished to do so, subject to
  the following conditions:

  The above copyright notice and this permission notice shall be included
  in all copies or substantial portions of the Software.

  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
  OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
  MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
  IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
  CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
  TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
  SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
]]
inspect.KEY = setmetatable({}, { __tostring = function() return 'inspect.KEY' end })
inspect.METATABLE = setmetatable({}, { __tostring = function() return 'inspect.METATABLE' end })

local tostring = tostring

local function rawpairs(t)
   return next, t, nil
end



local function smartQuote(str)
   if str:match('"') and not str:match("'") then
      return "'" .. str .. "'"
   end
   return '"' .. str:gsub('"', '\\"') .. '"'
end


local shortControlCharEscapes = {
   ["\a"] = "\\a", ["\b"] = "\\b", ["\f"] = "\\f", ["\n"] = "\\n",
   ["\r"] = "\\r", ["\t"] = "\\t", ["\v"] = "\\v", ["\127"] = "\\127",
}
local longControlCharEscapes = { ["\127"] = "\127" }
for i = 0, 31 do
   local ch = string.char(i)
   if not shortControlCharEscapes[ch] then
      shortControlCharEscapes[ch] = "\\" .. i
      longControlCharEscapes[ch] = string.format("\\%03d", i)
   end
end

local function escape(str)
   return (str:gsub("\\", "\\\\"):
   gsub("(%c)%f[0-9]", longControlCharEscapes):
   gsub("%c", shortControlCharEscapes))
end

local function isIdentifier(str)
   return type(str) == "string" and not not str:match("^[_%a][_%a%d]*$")
end

local flr = math.floor
local function isSequenceKey(k, sequenceLength)
   return type(k) == "number" and
   flr(k) == k and
   1 <= (k) and
   k <= sequenceLength
end

local defaultTypeOrders = {
   ['number'] = 1, ['boolean'] = 2, ['string'] = 3, ['table'] = 4,
   ['function'] = 5, ['userdata'] = 6, ['thread'] = 7,
}

local function sortKeys(a, b)
   local ta, tb = type(a), type(b)


   if ta == tb and (ta == 'string' or ta == 'number') then
      return (a) < (b)
   end

   local dta, dtb = defaultTypeOrders[ta], defaultTypeOrders[tb]

   if dta and dtb then return defaultTypeOrders[ta] < defaultTypeOrders[tb]
   elseif dta then return true
   elseif dtb then return false
   end


   return ta < tb
end



local function getSequenceLength(t)
   local len = 1
   local v = rawget(t, len)
   while v ~= nil do
      len = len + 1
      v = rawget(t, len)
   end
   return len - 1
end

local function getNonSequentialKeys(t)
   local keys, keysLength = {}, 0
   local sequenceLength = getSequenceLength(t)
   for k, _ in rawpairs(t) do
      if not isSequenceKey(k, sequenceLength) then
         keysLength = keysLength + 1
         keys[keysLength] = k
      end
   end
   table.sort(keys, sortKeys)
   return keys, keysLength, sequenceLength
end

local function countTableAppearances(t, tableAppearances)
   tableAppearances = tableAppearances or {}

   if type(t) == "table" then
      if not tableAppearances[t] then
         tableAppearances[t] = 1
         for k, v in rawpairs(t) do
            countTableAppearances(k, tableAppearances)
            countTableAppearances(v, tableAppearances)
         end
         countTableAppearances(getmetatable(t), tableAppearances)
      else
         tableAppearances[t] = tableAppearances[t] + 1
      end
   end

   return tableAppearances
end

local function makePath(path, a, b)
   local newPath = {}
   local len = #path
   for i = 1, len do newPath[i] = path[i] end

   newPath[len + 1] = a
   newPath[len + 2] = b

   return newPath
end


local function processRecursive(process,
   item,
   path,
   visited)
   if item == nil then return nil end
   if visited[item] then return visited[item] end

   local processed = process(item, path)
   if type(processed) == "table" then
      local processedCopy = {}
      visited[item] = processedCopy
      local processedKey

      for k, v in rawpairs(processed) do
         processedKey = processRecursive(process, k, makePath(path, k, inspect.KEY), visited)
         if processedKey ~= nil then
            processedCopy[processedKey] = processRecursive(process, v, makePath(path, processedKey), visited)
         end
      end

      local mt = processRecursive(process, getmetatable(processed), makePath(path, inspect.METATABLE), visited)
      if type(mt) ~= 'table' then mt = nil end
      setmetatable(processedCopy, mt)
      processed = processedCopy
   end
   return processed
end





local Inspector = {}










local Inspector_mt = { __index = Inspector }

function Inspector:puts(a, b, c, d, e)
   local buffer = self.buffer
   local len = #buffer
   buffer[len + 1] = a
   buffer[len + 2] = b
   buffer[len + 3] = c
   buffer[len + 4] = d
   buffer[len + 5] = e
end

function Inspector:down(f)
   self.level = self.level + 1
   f()
   self.level = self.level - 1
end

function Inspector:tabify()
   self:puts(self.newline,
   string.rep(self.indent, self.level))
end

function Inspector:alreadyVisited(v)
   return self.ids[v] ~= nil
end

function Inspector:getId(v)
   local id = self.ids[v]
   if not id then
      local tv = type(v)
      id = (self.maxIds[tv] or 0) + 1
      self.maxIds[tv] = id
      self.ids[v] = id
   end
   return tostring(id)
end


function Inspector:putValue(_)
end

function Inspector:putKey(k)
   if isIdentifier(k) then
      self:puts(k)
      return
   end
   self:puts("[")
   self:putValue(k)
   self:puts("]")
end

function Inspector:putTable(t)
   if t == inspect.KEY or t == inspect.METATABLE then
      self:puts(tostring(t))
   elseif self:alreadyVisited(t) then
      self:puts('<table ', self:getId(t), '>')
   elseif self.level >= self.depth then
      self:puts('{...}')
   else
      if self.tableAppearances[t] > 1 then self:puts('<', self:getId(t), '>') end

      local nonSequentialKeys, nonSequentialKeysLength, sequenceLength = getNonSequentialKeys(t)
      local mt = getmetatable(t)

      self:puts('{')
      self:down(function()
         local count = 0
         for i = 1, sequenceLength do
            if count > 0 then self:puts(',') end
            self:puts(' ')
            self:putValue(t[i])
            count = count + 1
         end

         for i = 1, nonSequentialKeysLength do
            local k = nonSequentialKeys[i]
            if count > 0 then self:puts(',') end
            self:tabify()
            self:putKey(k)
            self:puts(' = ')
            self:putValue(t[k])
            count = count + 1
         end

         if type(mt) == 'table' then
            if count > 0 then self:puts(',') end
            self:tabify()
            self:puts('<metatable> = ')
            self:putValue(mt)
         end
      end)

      if nonSequentialKeysLength > 0 or type(mt) == 'table' then
         self:tabify()
      elseif sequenceLength > 0 then
         self:puts(' ')
      end

      self:puts('}')
   end
end

function Inspector:putValue(v)
   local tv = type(v)
   if tv == 'string' then
      self:puts(smartQuote(escape(v)))
   elseif tv == 'number' or tv == 'boolean' or tv == 'nil' or
      tv == 'cdata' or tv == 'ctype' then
      self:puts(tostring(v))
   elseif tv == 'table' then
      self:putTable(v)
   else
      self:puts('<', tv, ' ', self:getId(v), '>')
   end
end




function inspect.inspect(root, options)
   options = options or {}

   local depth = options.depth or (math.huge)
   local newline = options.newline or '\n'
   local indent = options.indent or '  '
   local process = options.process

   if process then
      root = processRecursive(process, root, {}, {})
   end

   local inspector = setmetatable({
      depth = depth,
      level = 0,
      buffer = {},
      ids = {},
      maxIds = {},
      newline = newline,
      indent = indent,
      tableAppearances = countTableAppearances(root),
   }, Inspector_mt)

   inspector:putValue(root)

   return table.concat(inspector.buffer)
end
local FT={};
FT.Object ={};
function FT.Object.eval(str)
  if type(str) ~= "string" then
      return
  end
  local s = string.format("return %s", str)
  return FT.Object.exec(s)
end
function FT.Object.exec(str)
  if type(str) ~= "string" then
      return
  end
  return load(str)()
end

setmetatable(inspect, {
   __call = function(_, root, options)
      return inspect.inspect(root, options)
   end,
})  


--lua转json
local f = io.open(rootPath.."LuaToJson/old_lua.txt", "r+")
local txt = f:read("*a")
f:close()
local encodeJSON = json.encode(  FT.Object.eval(txt));
local f = assert(io.open(rootPath.."LuaToJson/result.txt", "w"))
f:write(encodeJSON)
f:close()
 --json转lua
local f = io.open(rootPath.."JsonToLua/old_json.txt", "r+")
local txt = f:read("*a")
f:close()
local lua = json.decode(txt);
local f = assert(io.open(rootPath.."JsonToLua/result.txt", "w"))
f:write(inspect(lua))
f:close()