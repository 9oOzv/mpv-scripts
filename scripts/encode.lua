local utils = require "mp.utils"
local msg = require "mp.msg"
local options = require "mp.options"

local ON_WINDOWS = (package.config:sub(1,1) ~= "/")

local start_timestamp = nil
local end_timestamp = nil
local overlay = mp.create_osd_overlay("ass-events")
local overlay_status = mp.create_osd_overlay("ass-events")
local command = nil
local default_settings = {
    append_batch_file = '',
    detached = true,
    container = "",
    only_active_tracks = false,
    preserve_filters = true,
    append_filter = "",
    codec = "-an -sn -c:v libvpx -crf 10 -b:v 1000k",
    output_format = "$f_$n.webm",
    output_directory = "",
    ffmpeg_command = "ffmpeg",
    print = true,
}
local settings = default_settings
local current_profile = nil
local cooldown_timer = nil

function append_table(lhs, rhs)
    for i = 1,#rhs do
        lhs[#lhs+1] = rhs[i]
    end
    return lhs
end

function file_exists(name)
    local f = io.open(name, "r")
    if f ~= nil then
        io.close(f)
        return true
    else
        return false
    end
end

function get_extension(path)
    local candidate = string.match(path, "%.([^.]+)$")
    if candidate then
        for _, ext in ipairs({ "mkv", "webm", "mp4", "avi" }) do
            if candidate == ext then
                return candidate
            end
        end
    end
    return "mkv"
end

function get_output_string(dir, format, input, extension, title, from, to, profile)
    local res = utils.readdir(dir)
    if not res then
        return nil
    end
    local files = {}
    for _, f in ipairs(res) do
        files[f] = true
    end
    local output = format
    output = string.gsub(output, "$f", input)
    output = string.gsub(output, "$t", title)
    output = string.gsub(output, "$s", seconds_to_time_string(from, true))
    output = string.gsub(output, "$e", seconds_to_time_string(to, true))
    output = string.gsub(output, "$d", seconds_to_time_string(to-from, true))
    output = string.gsub(output, "$x", extension)
    output = string.gsub(output, "$p", profile)
    if ON_WINDOWS then
        output = string.gsub(output, "[/\\|<>?:\"*]", "_")
    end
    if not string.find(output, "$n") then
        return files[output] and nil or output
    end
    local i = 1
    while true do
        local potential_name = string.gsub(output, "$n", tostring(i))
        if not files[potential_name] then
            return potential_name
        end
        i = i + 1
    end
end

--function get_video_filters()
--    local filters = {}
--    for _, vf in ipairs(mp.get_property_native("vf")) do
--        local name = vf["name"]
--        local filter
--        if name == "crop" then
--            local p = vf["params"]
--            filter = string.format("crop=%d:%d:%d:%d", p.w, p.h, p.x, p.y)
--        elseif name == "mirror" then
--            filter = "hflip"
--        elseif name == "flip" then
--            filter = "vflip"
--        elseif name == "rotate" then
--            local rotation = vf["params"]["angle"]
--            -- rotate is NOT the filter we want here
--            if rotation == "90" then
--                filter = "transpose=clock"
--            elseif rotation == "180" then
--                filter = "transpose=clock,transpose=clock"
--            elseif rotation == "270" then
--                filter = "transpose=cclock"
--            end
--        end
--        filters[#filters + 1] = filter
--    end
--    return filters
--end

function append_filter_param(params_str, name, value)
    local escaped = value
    escaped = escaped:gsub("\\", "\\\\")
    escaped = escaped:gsub(":", "\\:")
    if #params_str > 0 then
        params_str = params_str .. ":"
    end
    params_str = params_str .. name .. "=" .. escaped
    return params_str
end


function filter_setpts_start()
    local filter = {
        name = "setpts",
        params = {
            expr = "PTS+" .. start_timestamp .. "/TB",
        },
    }
    return filter
end

function filter_setpts_end()
    local filter = {
        name = "setpts",
        params = {
            expr = "PTS-STARTPTS",
        },
    }
    return filter
end

function append_filter(vf_string, filter)
    local params_str = ""
    local name = filter["name"]
    local params = filter["params"]
    if name == "subtitles" then
        vf_string = append_filter(vf_string, filter_setpts_start())
    end
    if params then
        for k, v in pairs(params) do
            params_str = append_filter_param(params_str, k, v)
        end
    end
    local filter_string = name .. "=" .. params_str
    escaped = filter_string
    escaped = escaped:gsub("\\", "\\\\")
    escaped = escaped:gsub("%[", "\\[")
    escaped = escaped:gsub("]", "\\]")
    escaped = escaped:gsub(",", "\\,")
    escaped = escaped:gsub(";", "\\;")
    msg.info("filter: " .. escaped )
    if #vf_string > 0 then
        vf_string = vf_string .. ","
    end
    vf_string = vf_string .. escaped
    if name == "subtitles" then
        vf_string = append_filter(vf_string, filter_setpts_end())
    end
    return vf_string
end

function get_vf_string()
    local vf_string = ""
    for _, filter in ipairs(mp.get_property_native("vf")) do
        vf_string = append_filter(vf_string, filter)
    end
    return vf_string
end

function edl_next(str)
    url_start = str:find("http")
    if not url_start then
        return nil
    end
    str = str:sub(url_start)
    local url_length = (str:find(";") or #str + 1) - 1
    url = str:sub(1, url_length)
    str = str:sub(url_length + 1)
    return url, str
end

function tracks_from_edl(edl)
    local ret = {}
    while true do
        local track
        track, edl = edl_next(edl)
        if not track then
            return ret
        end
        msg.info("parsed edl track: " .. track)
        ret[#ret + 1] = track
    end
end

function get_input_info(default_path, only_active)
    local accepted = {
        video = true,
        audio = not mp.get_property_bool("mute"),
        sub=false,
        --sub = mp.get_property_bool("sub-visibility")
    }
    local ret = {}
    print(mp.get_property("track-list"))
    for _, track in ipairs(mp.get_property_native("track-list")) do
        local filename = track["external-filename"] or default_path
        if string.find(filename, "edl://") then
            msg.info("Getting tracks from EDL. This feature may not work and it assumes a youtube source. EDL: " .. filename)
            local edl_tracks = tracks_from_edl(filename)
            track_index = track["ff-index"] + 1
            if #edl_tracks < track_index then
                msg.warn("Something went wrong. EDL track index is " .. track_index .. " but we only have " .. #edl_tracks .. " tracks ")
            end
            local track_path = edl_tracks[track_index]
            ret[track_path] = { 0 }
            goto continue
        end
        if not only_active or (track["selected"] and accepted[track["type"]]) then
            local tracks = ret[filename]
            if not tracks then
                ret[filename] = { track["ff-index"] }
            else
                tracks[#tracks + 1] = track["ff-index"]
            end
            goto continue
        end
        ::continue::
    end
    return ret
end

function seconds_to_time_string(seconds, full)
    local ret = string.format("%02d:%02d.%03d"
        , math.floor(seconds / 60) % 60
        , math.floor(seconds) % 60
        , seconds * 1000 % 1000
    )
    if full or seconds > 3600 then
        ret = string.format("%d:%s", math.floor(seconds / 3600), ret)
    end
    return ret
end

function set_overlay_text(text)
    overlay.data = text
    overlay:update()
end

function start_encoding()
    if not settings.append_batch_file or settings.append_batch_file ~='' then
        f = io.open (settings.append_batch_file, 'a')
        command_string = "'" .. command[1] .. "' "
        for i = 2, #command do
            command_string = command_string .. " '" .. command[i] .. "'"
        end
        f:write(command_string .. '\n')
        f:close()
        return
    end
    if settings.detached then
        utils.subprocess_detached({ args = command })
        return
    end
    set_overlay_text("encoding...")
    local res = utils.subprocess({ args = command, max_size = 0, cancellable = false })
    if res.status == 0 then
        set_overlay_text("Finished encoding succesfully")
    else
        set_overlay_text("Failed to encode, check the log")
    end
end

function set_command()
    local profile = current_profile
    local from = start_timestamp
    local to = end_timestamp
    settings = default_settings
    options.read_options(settings)
    if profile then
        options.read_options(settings, profile)
        if settings.container ~= "" then
            msg.warn("The 'container' setting is deprecated, use 'output_format' now")
            settings.output_format = settings.output_format .. "." .. settings.container
        end
        settings.profile = profile
    else
        settings.profile = "default"
    end
    local args = {
        settings.ffmpeg_command,
        "-loglevel", "error", "-hide_banner",
    }
    local append_args = function(table) args = append_table(args, table) end

    local path = mp.get_property("path")
    local is_stream = not file_exists(path)
    if is_stream then
        path = mp.get_property("stream-path")
    end

    local track_args = {}
    local start = seconds_to_time_string(from, false)
    local input_index = 0
    for input_path, tracks in pairs(get_input_info(path, settings.only_active_tracks)) do
       append_args({
            "-ss", start,
            "-i", input_path,
        })
        if settings.only_active_tracks then
            for _, track_index in ipairs(tracks) do
                track_args = append_table(track_args, { "-map", string.format("%d:%d", input_index, track_index)})
            end
        else
            track_args = append_table(track_args, { "-map", tostring(input_index)})
        end
        input_index = input_index + 1
    end

    append_args({"-to", tostring(to-from)})
    append_args(track_args)

    -- apply some of the video filters currently in the chain
    --local filters = {}
    local vf_string = ""
    if settings.preserve_filters then
        vf_string = get_vf_string()
    end
    --if settings.append_filter ~= "" then
    --    filters[#filters + 1] = settings.append_filter
    --end
    --if #filters > 0 then
    --    append_args({ "-filter:v", table.concat(filters, ",") })
    --end

    if #vf_string > 0 then
        append_args({ "-vf", vf_string})
    end
    
    --local filters = ""
    --if settings.preserve_filters then
    --    filters = mp.get_property("vf")
    --end
    --if #filters > 0 then
    --    local escaped_filters = filters
    --    local escaped_filters = filters:gsub('')
    --    append_args({ "-vf", filters })
    --end


    -- split the user-passed settings on whitespace
    for token in string.gmatch(settings.codec, "[^%s]+") do
        args[#args + 1] = token
    end

    -- path of the output
    local output_directory = settings.output_directory
    if output_directory == "" then
        if is_stream then
            output_directory = "."
        else
            output_directory, _ = utils.split_path(path)
        end
    else
        output_directory = string.gsub(output_directory, "^~", os.getenv("HOME") or "~")
    end
    local input_name = mp.get_property("filename/no-ext") or "encode"
    local title = mp.get_property("media-title")
    local extension = get_extension(path)
    local output_name = get_output_string(output_directory, settings.output_format, input_name, extension, title, from, to, settings.profile)
    if not output_name then
        mp.osd_message("Invalid path " .. output_directory)
        return
    end
    args[#args + 1] = utils.join_path(output_directory, output_name)

    if settings.print then
        local o = ""
        -- fuck this is ugly
        for i = 1, #args do
            local fmt = ""
            if i == 1 then
                fmt = "%s%s"
            elseif i >= 2 and i <= 4 then
                fmt = "%s"
            elseif args[i-1] == "-i" or i == #args or args[i-1] == "-filter:v" then
                fmt = "%s '%s'"
            else
                fmt = "%s %s"
            end
            o = string.format(fmt, o, args[i])
        end
        print(o)
    end
    command = args
    set_overlay_text(table.concat(command, "\n"))
end

function reset()
    start_timestamp = nil
    end_timestamp = nil
    mp.remove_key_binding("encode-ESC")
    mp.remove_key_binding("encode-ENTER")
    mp.osd_message("", 0)
    overlay.data = ""
    overlay:remove()
    ffmpeg_command = nil
    current_profile = nil
    if cooldown_timer then
        cooldown_timer:kill()
        cooldown_timer = nil
    end
end

function set_start_timestamp()
    start_timestamp = math.max(mp.get_property_number("time-pos"), 0)
    set_overlay_text("[" .. current_profile .. "] waiting for end timestamp...")
    mp.add_forced_key_binding("ESC", "encode-ESC", reset)
    mp.add_forced_key_binding("ENTER", "encode-ENTER", function() encode() end)
end

function set_end_timestamp()
    local from = start_timestamp
    local to = mp.get_property_number("time-pos")
    if to <= from then
        mp.osd_message("Second timestamp cannot be before the first", timer_duration)
        reset()
        return false
    end
    start_timestamp = from
    end_timestamp = to
    -- include the current frame into the extract
    local fps = mp.get_property_number("container-fps") or 30
    to = to + 1 / fps / 2
end

function is_valid_media()
    if not mp.get_property("path") then
        mp.osd_message("No file currently playing")
        return false
    elseif not mp.get_property_bool("seekable") then
        mp.osd_message("Cannot encode non-seekable media")
        return false
    else
        return true
    end
end

function select_profile()
    bindings_repeat[opts.left_coarse]  = movement_func(-opts.coarse_movement, 0)
end

function cooldown()
    cooldown_timer = mp.add_timeout(2, reset)
end

function encode(profile)
    current_profile = profile
    if not is_valid_media() then
        reset()
        return false
    end
    if (not start_timestamp) then
        set_start_timestamp()
    elseif (not end_timestamp) then
        set_end_timestamp()
        set_command()
    elseif (not profile) then
        select_profile()
    elseif cooldown_timer then
        reset()
    else
        start_encoding() 
        cooldown()
    end
end

mp.add_key_binding(nil, "trigger", encode)
