
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


function subtitle_stream_index()
    return tostring(math.floor(mp.get_property("current-tracks/sub/id")))
end

mp.add_key_binding(nil, "toggle-burn", (function()
    toggle_filter({
            name="subtitles",
            params= {
                si = subtitle_stream_index(),
                filename = mp.get_property("path"),
            }
    })
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

