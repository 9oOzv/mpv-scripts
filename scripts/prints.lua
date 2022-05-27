local utils = require "mp.utils"
local msg = require "mp.msg"
local options = require "mp.options"
local overlay = mp.create_osd_overlay("ass-events")
local names = {
    'vf',
}
local enabled = {}
local f = {}
local update_timer = nil

f['vf'] = function(data)
    data = data .. "\n"
    data = data .. mp.get_property("vf")
    return data
end

function set_overlay_text(text)
    overlay.data = text
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
    enabled[name] = not enabled[name]
    update_overlay()
end

function enable(name)
    enabled[name] = true
    update()
end

function disable(name)
    enabled[name] = nil
end

function disable_all()
    enabled = {}
    kill_update_timer()
end

function enable_all()
    for _, v in pairs(names) do
        enable(v)
    end
end

function toggle_all()
    if update_timer then
        disable_all()
    else
        enable_all()
    end
end

mp.add_key_binding(nil, "toggle-all", toggle_all)
