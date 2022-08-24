
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

function try_remove_filter(filter)
    local vf_table = mp.get_property_native("vf")
    local key = -1
    for k, v in pairs(vf_table) do
        if v.name == filter.name then
            key = k
            break
        end
    end
    if key ~= -1 then
        table.remove(vf_table, key)
        mp.set_property_native("vf", vf_table)
        return true
    end
    return false
end

function add_filter(filter)
    local vf_table = mp.get_property_native("vf")
    vf_table[#vf_table + 1] = filter
    mp.set_property_native("vf", vf_table)
end

function toggle_filter(filter)
    local removed = try_remove_filter(filter)
    if not removed then
        add_filter(filter)
    end
end

function remove_all()
    mp.set_property_native("vf", {})
end

function create_filter_toggle(filter)
    return (
        function ()
            toggle_filter(filter)
        end
    )
end


mp.add_key_binding(nil, "remove-all", remove_all)

mp.add_key_binding(nil, "toggle-scale-720", create_filter_toggle({
    name="scale",
    params= {
        w = "720",
        h = "720",
        force_original_aspect_ratio = "decrease",
    }
}))

mp.add_key_binding(nil, "toggle-scale-1080p", create_filter_toggle({
    name="scale",
    params= {
        w = "1920",
        h = "1080",
        force_original_aspect_ratio = "decrease",
    }
}))

function burn_text()
    local stream_index = tostring(math.floor(mp.get_property("current-tracks/sub/id") - 1))
    return toggle_filter({
            name="subtitles",
            params= {
                si = stream_index,
                filename = mp.get_property("path"),
            }
    })
end

function burn_image()
    local stream_index = tostring(math.floor(mp.get_property("current-tracks/sub/id") - 1))
    return toggle_filter({
            name="overlay",
            params= {
                si = stream_index,
                filename = mp.get_property("path"),
            }
    })
end

function table.contains(table, element)
  for _, value in pairs(table) do
    if value == element then
      return true
    end
  end
  return false
end

function burn_filter()
    local subs = mp.get_property_native("current-tracks/sub")
    if not subs then
        print("no subtitle track selected")
        return
    end
    local codec = subs["codec"]
    local image_codecs = { "hdmv_pgs_subtitle", }
    local image_based = table.contains(image_codecs, codec)
    if image_based then
        print("image based subs no yet supported")
        return false
        --return burn_image()
    else
        return burn_text()
    end
end

mp.add_key_binding(nil, "toggle-burn", (function()
    local f = burn_filter()
    if f then
        toggle_filter(f)
    end
end))

mp.add_key_binding(nil, "toggle-burn-large", (function()
    toggle_filter({
            name="subtitles",
            params= {
                si = subtitle_stream_index(),
                filename = mp.get_property("path"),
                force_style = 'ScaleX=1.5,ScaleY=1.5',
            }
    })
end))

mp.add_key_binding(nil, "toggle-burn-huge", (function()
    toggle_filter({
            name="subtitles",
            params= {
                si = subtitle_stream_index(),
                filename = mp.get_property("path"),
                force_style = 'ScaleX=2,ScaleY=2',
            }
    })
end))

