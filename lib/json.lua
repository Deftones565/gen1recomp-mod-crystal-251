-- Small JSON codec kept inside the mod so importing a ROM never depends on
-- link/network internals. Supports the object/array/scalar shapes emitted by
-- extractor.lua.
local Json={}

local function encodeValue(value,out)
  local kind=type(value)
  if value==nil then out[#out+1]="null"
  elseif kind=="boolean" then out[#out+1]=value and "true" or "false"
  elseif kind=="number" then out[#out+1]=string.format("%.17g",value)
  elseif kind=="string" then
    out[#out+1]='"'..value:gsub('[%c"\\]',function(char)
      if char=='"' then return '\\"' end
      if char=='\\' then return '\\\\' end
      if char=='\n' then return '\\n' end
      if char=='\r' then return '\\r' end
      if char=='\t' then return '\\t' end
      return string.format("\\u%04x",char:byte())
    end)..'"'
  elseif kind=="table" then
    local count=#value
    local array=count>0 or next(value)==nil
    if array then
      out[#out+1]="["
      for i=1,count do
        if i>1 then out[#out+1]="," end
        encodeValue(value[i],out)
      end
      out[#out+1]="]"
    else
      out[#out+1]="{"
      local first=true
      for key,child in pairs(value) do
        if not first then out[#out+1]="," end
        first=false
        encodeValue(tostring(key),out); out[#out+1]=":"; encodeValue(child,out)
      end
      out[#out+1]="}"
    end
  else error("cannot encode "..kind) end
end

function Json.encode(value)
  local out={}; encodeValue(value,out); return table.concat(out)
end

local function skipSpace(text,pos)
  return text:find("[^ \t\r\n]",pos) or #text+1
end

local decodeValue
local function decodeString(text,pos)
  local out={}; pos=pos+1
  while pos<=#text do
    local char=text:sub(pos,pos)
    if char=='"' then return table.concat(out),pos+1 end
    if char=='\\' then
      local escape=text:sub(pos+1,pos+1)
      if escape=="n" then out[#out+1]='\n'
      elseif escape=="r" then out[#out+1]='\r'
      elseif escape=="t" then out[#out+1]='\t'
      elseif escape=="b" then out[#out+1]=string.char(8)
      elseif escape=="f" then out[#out+1]=string.char(12)
      elseif escape=="u" then
        local code=tonumber(text:sub(pos+2,pos+5),16) or 32
        if code<128 then out[#out+1]=string.char(code)
        elseif code<0x800 then
          out[#out+1]=string.char(0xc0+math.floor(code/0x40),0x80+code%0x40)
        else
          out[#out+1]=string.char(0xe0+math.floor(code/0x1000),
            0x80+math.floor(code/0x40)%0x40,0x80+code%0x40)
        end
        pos=pos+4
      else out[#out+1]=escape end
      pos=pos+2
    else out[#out+1]=char; pos=pos+1 end
  end
  error("unterminated string")
end

decodeValue=function(text,pos)
  pos=skipSpace(text,pos)
  local char=text:sub(pos,pos)
  if char=='"' then return decodeString(text,pos)
  elseif char=='{' then
    local object={}; pos=skipSpace(text,pos+1)
    if text:sub(pos,pos)=='}' then return object,pos+1 end
    while true do
      local key; key,pos=decodeString(text,skipSpace(text,pos))
      pos=skipSpace(text,pos); assert(text:sub(pos,pos)==':',"expected :")
      local child; child,pos=decodeValue(text,pos+1); object[key]=child
      pos=skipSpace(text,pos); local delimiter=text:sub(pos,pos)
      if delimiter=='}' then return object,pos+1 end
      assert(delimiter==',',"expected , or }"); pos=pos+1
    end
  elseif char=='[' then
    local array={}; pos=skipSpace(text,pos+1)
    if text:sub(pos,pos)==']' then return array,pos+1 end
    while true do
      local child; child,pos=decodeValue(text,pos); array[#array+1]=child
      pos=skipSpace(text,pos); local delimiter=text:sub(pos,pos)
      if delimiter==']' then return array,pos+1 end
      assert(delimiter==',',"expected , or ]"); pos=pos+1
    end
  elseif char=='t' then assert(text:sub(pos,pos+3)=='true'); return true,pos+4
  elseif char=='f' then assert(text:sub(pos,pos+4)=='false'); return false,pos+5
  elseif char=='n' then assert(text:sub(pos,pos+3)=='null'); return nil,pos+4
  else
    local number=text:match("^-?%d+%.?%d*[eE]?[-+]?%d*",pos)
    assert(number and #number>0,"unexpected character "..char)
    return tonumber(number),pos+#number
  end
end

function Json.decode(text)
  local ok,value=pcall(function() return select(1,decodeValue(text,1)) end)
  if ok then return value end
  return nil,value
end

return Json
