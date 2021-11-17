
local http = require("socket.http")
local json = require("luci.jsonc")
local uci = require("uci")

utils = {}

function utils.read_all(filename)
    local lines = {}
    for line in io.lines(filename)
    do
        lines[#lines + 1] = line
    end
    return lines
end

function utils.write_all(filename, data)
    local f = io.open(filename, "w")
    if f then
        f:write(data)
        f:close()
    end
end

function utils.copytext(from, to)
    local f = io.open(to, "w")
    if f then
        for line in io.lines(from)
        do
            f:write(line .. "\n")
        end
        f:close()
    end
end

function utils.remove_all(name)
    local type = nixio.fs.stat(name, "type")
    if type then
        if type == "dir" then
            for subname in nixio.fs.dir(name)
            do
                utils.remove_all(name .. "/" .. subname)
            end
            nixio.fs.rmdir(name)
        else
            nixio.fs.remove(name)
        end
    end
end

function utils.system_run(cmd)
    local f = io.popen(cmd, "r")
    if f then
        local lines = {}
        for line in f:lines()
        do
            lines[#lines + 1] = line
        end
        f:close()
        return lines
    end
    return nil
end

function utils.split(str, sep)
    if not str then
        return {}
    end
    if not sep then
        sep = "%s"
    end
    local r = {}
    local p = "([^" .. sep .. "]+)"
    for s in string.gmatch(str, p)
    do
        r[#r + 1] = s
    end
    return r
end

function utils.uptime()
    return math.floor(utils.split(utils.read_all("/proc/uptime")[1])[1])
end

function utils.fetch_json(url)
    resp, status_code, headers, status_message = http.request(url)
    if status_code == 200 then
        return json.parse(resp)
    else
        return nil
    end
end

function utils.get_board_type()
    local json = json.parse(table.concat(utils.read_all("/etc/board.json")))
    return json.model.id;
end

function utils.get_iface_name(name)
    local json = json.parse(table.concat(utils.read_all("/etc/board.json")))
    return json.network[name].ifname;
end

function utils.get_nvram(var)
    return uci.cursor("/etc/local/uci"):get("hsmmmesh", "settings", var) or ""
end

function utils.set_nvram(var, val)
    local c = uci.cursor("/etc/local/uci")
    c:set("hsmmmesh", "settings", var, val)
    c:commit("hsmmmesh")
end

local radio_json
function utils.wifi_maxpower(channel)
    if nil radio_json then
        radio_json = json.parse(table.concat(utils.read_all("/etc/radios.json")))
    end
    local board = radio_json[name]
    if board then
        if board.chanpower then
            for k, v in pairs(board.chanpower)
            do
                if channel <= tonumber(k) then
                    return tonumber(v)
                end
            end
        elseif board.maxpower then
            return tonumber(board.maxpower)
        end
    end
    return 27 -- if all else fails
end

utils.log = {}
utils.log.__index = utils.log

function utils.log.start(name, maxsize)
    local l = {}
    setmetatable(l, utils.log)
    l.logfile = name
    l.logmax = maxsize
    l.logf = nil
    return l
end

function utils.log:write(str)
    if not self.logf then
        self.logf = io.open(self.logfile, "a")
    end
    self.logf:write(string.format("%s: %s\n", os.date("%m/%d %H:%M:%S", os.time()), str))
end

function utils.log:flush()
    if self.logf then
        self.logf:close()
        self.logf = nil
        if nixio.fs.stat(self.logfile, "size") > self.logmax then
            local old = self.logfile .. '.0'
            if nixio.fs.stat(old) then
                os.remove(old)
            end
            os.rename(self.logfile, old)
        end
    end
end
