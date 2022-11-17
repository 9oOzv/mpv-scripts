local utils = require "mp.utils"
local msg = require "mp.msg"
local options = require "mp.options"
local overlay = mp.create_osd_overlay("ass-events")
local names = {
    'vf',
    'files',
    'current-tracks',
}
local enabled = {}
local f = {}
local update_timer = nil
local style="{\\fs12}"

function dump(o, pretty, indentation)
    indentation = indentation or 0
    pretty = pretty or false
    if pretty then
        if type(o) == 'table' then
           local s = string.rep("\\h\\h", indentation) .. "\\{ " .. "\n"
           for k,v in pairs(o) do
             s = s .. string.rep("\\h\\h", indentation + 1) .. k .. ": " .. dump(v, pretty, indentation + 1) .. ",\n"
           end
           return s .. string.rep("\\h\\h", indentation) .. "\\}"
        else
           return tostring(o)
        end
    else
        if type(o) == 'table' then
           local s = "\\{ "
           for k,v in pairs(o) do
             s = s .. k .. ": " .. dump(v, pretty) .. ", "
           end
           return s .. "\\}"
        else
           return tostring(o)
        end
    end
end

f['vf'] = function(data)
    data = data .. "# FILTERS" .. "\n"
    data = data .. "vf: "
    data = data .. mp.get_property("vf") .. "\n"
    return data
end

f['files'] = function(data)
    data = data .. "# FILES" .. "\n"
    data = data .. "current-tracks/video/external-filename: " .. (mp.get_property("current-tracks/video/external-filename") or '') .. "\n"
    data = data .. "current-tracks/audio/external-filename: " .. (mp.get_property("current-tracks/audio/external-filename") or '')  .. "\n"
    data = data .. "current-tracks/sub/external-filename: " .. (mp.get_property("current-tracks/sub/external-filename") or '')  .. "\n"
    data = data .. "current-tracks/sub2/external-filename: " .. (mp.get_property("current-tracks/sub2/external-filename") or '')  .. "\n"
    data = data .. "path: " .. (mp.get_property("path") or '')  .. "\n"
    data = data .. "stream-open-filename: " .. (mp.get_property("stream-open-filename") or '')  .. "\n"
    return data
end

f['current-tracks'] = function(data)
    data = data .. "# CURRENT TRACKS" .. "\n"
    data = data .. "video:" .. "\n"
    data = data .. dump(mp.get_property_native("current-tracks/video")) .. "\n"
    data = data .. "audio:" .. "\n"
    data = data .. dump(mp.get_property_native("current-tracks/audio")) .. "\n"
    data = data .. "sub:" .. "\n"
    data = data .. dump(mp.get_property_native("current-tracks/sub")) .. "\n"
    data = data .. "sub2:" .. "\n"
    data = data .. dump(mp.get_property_native("current-tracks/sub2")) .. "\n"
    return data
end

function string:split(delimiter)
  local result = { }
  local from  = 1
  local delim_from, delim_to = string.find( self, delimiter, from  )
  while delim_from do
    table.insert( result, string.sub( self, from , delim_from-1 ) )
    from  = delim_to + 1
    delim_from, delim_to = string.find( self, delimiter, from  )
  end
  table.insert( result, string.sub( self, from  ) )
  return result
end

function set_overlay_text(text)
    lines = string.split(text, "\n")
    styled_text = ""
    for k, l in pairs(lines) do
        styled_text = styled_text .. style .. l .. "\n"
    end
    overlay.data = styled_text
    overlay:update()
end

function kill_update_timer()
    if update_timer then
        update_timer:kill()
        update_timer = nil
    end
end

function start_update_timer()
    update_timer = mp.add_timeout(1, update)
end

function reset_update_timer()
    kill_update_timer()
    start_update_timer()
end

function update()
    reset_update_timer()
    local data = ""
    for i = 1, #names do
        local name = names[i]
        if enabled[name] then
            data = f[names[i]](data)
        end
    end
    set_overlay_text(data)
end

function toggle(name)
    print("toggle " .. name)
    enabled[name] = not enabled[name]
    update_overlay()
end

function enable(name)
    print("enable " .. name)
    enabled[name] = true
    update()
end

function disable(name)
    print("disable " .. name)
    enabled[name] = nil
end

function disable_all()
    print("disable all")
    for _, v in pairs(names) do
        disable(v)
    end
    update()
    kill_update_timer()
end

function enable_all()
    print("enable all")
    for _, v in pairs(names) do
        enable(v)
    end
end

function toggle_all()
    print("toggle all")
    if update_timer then
        disable_all()
    else
        enable_all()
    end
end

mp.add_key_binding(nil, "toggle-all", toggle_all)
