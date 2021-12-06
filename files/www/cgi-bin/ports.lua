#!/usr/bin/lua
--[[

	Part of AREDN -- Used for creating Amateur Radio Emergency Data Networks
	Copyright (C) 2021 Tim Wilkinson
	Original Perl Copyright (C) 2015 Conrad Lara
	See Contributors file for additional contributors

	This program is free software: you can redistribute it and/or modify
	it under the terms of the GNU General Public License as published by
	the Free Software Foundation version 3 of the License.

	This program is distributed in the hope that it will be useful,
	but WITHOUT ANY WARRANTY; without even the implied warranty of
	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
	GNU General Public License for more details.

	You should have received a copy of the GNU General Public License
	along with this program.  If not, see <http://www.gnu.org/licenses/>.

	Additional Terms:

	Additional use restrictions exist on the AREDN(TM) trademark and logo.
		See AREDNLicense.txt for more info.

	Attributions to the AREDN Project must be retained in the source code.
	If importing this code into a new or existing project attribution
	to the AREDN project must be added to the source code.

	You must not misrepresent the origin of the material contained within.

	Modified versions must be modified to attribute to the original source
	and be marked in reasonable ways as differentiate it from the original
	version

--]]

require("nixio")
require("aredn.hardware")
require("aredn.http")
require("aredn.utils")
aredn.html = require("aredn.html")
require("uci")
aredn.info = require("aredn.info")
require("luci.sys")

local html = aredn.html

local cursor = uci.cursor()

local config = aredn.info.get_nvram("config")
local node = aredn.info.get_nvram("node")
if not node or node == "" then
    node = "NOCALL"
end
local tactical = aredn.info.get_nvram("tactical")
if not tactical then
    tactical = ""
end

-- post_data
local parms = {}
if os.getenv("REQUEST_METHOD") == "POST" then
    require('luci.http')
    local request = luci.http.Request(luci.sys.getenv(),
      function()
        local v = io.read(1024)
        if not v then
            io.close()
        end
        return v
      end
    )
    parms = request:formvalue()
end

function navbar()
    html.print("<tr><td>")
    html.print("<hr><table cellpadding=5 border=0 width=100%><tr>")
    html.print("<td align=center width=15%><a href='status.lua'>Node Status</a></td>")
    html.print("<td align=center width=15%><a href='setup.lua'>Basic Setup</a></td>")
    html.print("<td align=center width=15% class=navbar_select><a href='ports.lua'>Port Forwarding,<br>DHCP, and Services</a></td>")
    html.print("<td align=center width=15%><a href='vpn.lua'>Tunnel<br>Server</a></td>")
    html.print("<td align=center width=15%><a href='vpnc.lua'>Tunnel<br>Client</a></td>")
    html.print("<td align=center width=15%><a href='admin.lua'>Administration</a></td>")
    html.print("<td align=center width=15%><a href='advancedconfig.lua'>Advanced<br>Configuration</a></td>")
    html.print("</tr></table><hr>")
end

function validate_service_name(name)
    if not name or name == "" or name:match("[:-\"|]") then
        return false
    else
        return true
    end
end

function validate_service_protocol(proto)
    if not name or name == "" or name:match("[:-\"|]") or not name:match("^%w+") then
        return false
    else
        return true
    end
end

function validate_service_suffix(suffix)
    if not suffix or suffix:match("[:-\"|]") or not name:match("^[%w/?._=#-]*$") then
        return false
    else
        return true
    end
end

local serv_err = {}
function serverr(msg)
    serv_err[#serv_err + 1] = msg
end
local port_err = {}
function porterr(msg)
    port_err[#port_err + 1] = msg
end

local dmz_err = {}
function dmzerr(msg)
    dmz_err[#dmz_err + 1] = msg
end
local dhcp_err = {}
function dhcperr(msg)
    dhcp_err[#dhcp_err + 1] = msg
end
local alias_err = {}
function aliaserr(msg)
    alias_err[#alias_err + 1] = msg
end
local errors = {}
function err(msg)
    errors[#errors + 1] = msg
end
local hidden = {}
function hide(m)
    hidden[#hidden + 1] = m
end

local hosts = {}
local addrs = {}
local macs = {}

if config ~= "mesh" or nixio.fs.stat("/tmp/reboot-required") then
    http_header()
    html.header(node .. " setup", true)
    html.print("<body><center><table width=790><tr><td>")
    html.alert_banner()
    navbar()
    html.print("</td></tr><tr><td align=center><br><b>")
    if config == "" then
        html.print("This page is not available until the configuration has been set.")
    else
        html.print("The specified configuration is invalid, try flushing your browser cache or reboot the mesh node.")
    end
    html.print("</b></td></tr>")
    html.print("</table></center>")
    html.footer();
    html.print("</body></html>")
    http_footer()
    os.exit()
end

-- check for dmz mode
local dmz_mode = tonumber(cursor:get("aredn", "@dmz[0]", "mode"))
if not dmz_mode then
    dmz_mode = 2
end

local lanip, lanbcast, lanmask = aredn.hardware.get_interface_ip4(aredn.hardware.get_iface_name("lan"))
local lannet_d = nixio.bit.band(ip_to_decimal(lanip), ip_to_decimal(lanmask))

local tmpdir = "/tmp/web/ports"
if not parms.reload then
    remove_all(tmpdir)
end
nixio.fs.mkdir(tmpdir)

local fsuffix = dmz_mode == 0 and ".nat" or ".dmz"
local portfile = "/etc/config.mesh/_setup.ports" .. fsuffix
local dhcpfile = "/etc/config.mesh/_setup.dhcp" .. fsuffix
local servfile = "/etc/config.mesh/_setup.services" .. fsuffix
local aliasfile = "/etc/config.mesh/aliases" .. fsuffix

-- if a reset or a first time page load
-- read the data from the config files
if parms.button_reset or not parms.reload then
    local i = 0
    for line in io.lines(portfile)
    do
        if not (line:match("^%s*#") or line:match("^%s*$")) then
            local k, v = line:match("(%S+)%s+=%s+(%S+)")
            if v then
                parms[k] = v
            else
                local inf, type, out, ip, _in, enable = line:match("(.*):(.*):(.*):(.*):(.*):(.*)")
                if inf then
                    i = i + 1
                    local prefix = "port" .. i .. "_"
                    parms[prefix .. "inf"] = inf
                    parms[prefix .. "type"] = type
                    parms[prefix .. "out"] = out
                    parms[prefix .. "ip"] = ip
                    parms[prefix .. "in"] = _in
                    parms[prefix .. "enable"] = enable
                end
            end
        end
    end
    parms.port_num = i

    -- set dhcp reservations
    -- ip addresses are stored as offsets from the lan network address
    i = 0
    for line in io.lines(dhcpfile)
    do
        if not (line:match("^%s*#") or line:match("^%s*$")) then
            local a, b, x = line:match("(%S*)%s+(%S*)%s+(.*)")
            if x then
                local c, d = x:match("(%S*)%s+(%S*)")
                if not c then
                    c = x
                    d = ""
                end
                i = i + 1
                local prefix = "dhcp" .. i .. "_"
                parms[prefix .. "mac"] = a
                parms[prefix .. "ip"] = decimal_to_ip(lannet_d + tonumber(b))
                parms[prefix .. "host"] = c
                parms[prefix .. "noprop"] = d
            end
        end
    end
    parms.dhcp_num = i

    -- services
    i = 0
    for line in io.lines(servfile)
    do
        if not (line:match("^%s*#") or line:match("^%s*$")) then
            local a, b, c, d, x = line:match("(.*)|(.*)|(.*)|(.*)|(.*)")
            if x then
                local e, f = x:match("(.*)|(.*)")
                if not e then
                    e = x
                    f = ""
                end
                i = i + 1
                local prefix = "serv" .. i .. "_"
                parms[prefix .. "name"] = a
                parms[prefix .. "link"] = b
                parms[prefix .. "proto"] = c
                parms[prefix .. "host"] = d
                parms[prefix .. "port"] = e
                parms[prefix .. "suffix"] = f
            end
        end
    end
    parms.serv_num = i

    -- aliases
    i = 0
    for line in io.lines(aliasfile)
    do
        if not (line:match("^%s*#") or line:match("^%s*$")) then
            local a, b = line:match("(.*)%s+(.*)")
            if b then
                i = i + 1
                parms["alias" .. i .. "_ip"] = a
                parms["alias" .. i .. "_host"] = b
            end
        end
    end
    parms.alias_num = i

    -- sanatize the 'add' values
    parms.port_add_intf = dmz_mode ~= 0 and "wan" or "wifi"
    parms.port_add_type = "tcp"
    if not parms.dmz_ip then
        parms.dmz_ip = ""
    end
    parms.port_add_out = ""
    parms.port_add_ip = ""
    parms.port_add_in = ""
    parms.dhcp_add_host = ""
    parms.dhcp_add_ip = ""
    parms.dhcp_add_mac = ""
    parms.dhcp_add_noprop = ""
    parms.serv_add_name = ""
    parms.serv_add_proto = ""
    parms.serv_add_host = ""
    parms.serv_add_port = ""
    parms.serv_add_suffix = ""
    parms.alias_add_host = ""
    parms.alias_add_ip = ""
end

local dhcp_start = tonumber(cursor:get("dhcp", "@dhcp[0]", "start"))
local dhcp_limit = tonumber(cursor:get("dhcp", "@dhcp[0]", "limit"))
local dhcp_end = dhcp_start + dhcp_limit - 1

-- load and validate the ports

local list = {}
for i = 1,parms.port_num
do
    list[#list + 1] = i
end
list[#list + 1] = "_add"
local port_num = 0
local usedports = {}

local f = io.open(tmpdir .. "/ports", "w")
if f then
    local vars = { "_intf", "_type", "_out", "_ip", "_in" }
    for _, val in ipairs(list)
    do
        for _ = 1,1 -- a non-loop so we can break out to continue the parent loop
        do
            for _, var in ipairs(vars)
            do
                local varname = "port" .. val .. var
                local v = parms[varname]
                if v then
                    v = v:gsub("^%s+", ""):gsub("%s+$", "")
                else
                    v = ""
                end
                parms[varname] = v
                _G[var] = v
            end
            local varname = "port" .. val .. "_enable"
            if not parms[varname] then
                parms[varname] = 0
            end
            _enable = parms[varname]

            if val == "_add" then
                _enable = 1
            end

            local continue = false
            if val == "_add" then
                if not ((_out ~= "" or _ip ~= "" or _in ~= "") and (parms.port_add or parms.button_save)) then
                    break
                end
            else
                if parms["port" .. val .. "_del"] then
                    break
                end
            end
            
            if val == "_add" and parms.button_save then
                porterr(val .. " this rule must be added or cleared out before saving changes")
                break
            end

            if _out:match("-") then
                if validate_port_range(_out) then
                    _in = _out:match("^(%d+)")
                else
                    porterr(val .. "'" .. _out .. "' is not a valid port range")
                end
            else
                if _out == "" then
                    porterr(val .. " an outside port is required")
                elseif not validate_port(_out) then
                    porterr(val .. "'" .. _out .. "' is not a valid port")
                end
            end
            if _ip == "" then
                porterr(val .. " an address must be selected")
            elseif not validate_ip(_ip) then
                porterr(val .. "'" .. _ip .. "' is not a valid address")
            end
            if _in == "" then
                porterr(val .. "a LAN port is required")
            elseif not validate_port(_in) then
                porterr(val .. "'" .. _in .. "' is not a valid port")
            end
            if val == "_add" and #port_err > 0 then
                break
            end

            -- commit the data for this rule
            port_num = port_num + 1
            usedports[_out] = true
            if _type ~= "tcp" and _type ~= "udp" then
                _type = "both"
            end

            f:write(_intf .. ":" .. _type .. ":" .. _out .. ":" .. _ip .. ":" .. _in .. ":" .. enable .. "\n")
            
            for _, var in ipairs(vars)
            do
                parms["port" .. port_num .. "_" .. var] = _G[var]
            end

            if val == "_add" then
                parms.port_add_intf = "wifi"
                parms.port_add_out = ""
                parms.port_add_ip = ""
                parms.port_add_in = ""
            end
        end
    end

    if parms.dmz_ip then
        f:write("dmz_ip = " .. parms.dmz_ip .. "\n")
        if not validate_ip(parms.dmz_ip) then
            dmzerr(parms.dmz_ip .. " is not a valid address")
        end
    end

    f:close()
end
parms.port_num = port_num

-- load and validate the dhcp reservations

local list = {}
for i = 1,parms.dhcp_num
do
    list[#list + 1] = i
end
list[#list + 1] = "_add"
local dhcp_num = 0

for _, val in ipairs(list)
do
    for _ = 1,1
    do
        local host = parms["dhcp" .. val .. "_host"]
        local ip = parms["dhcp" .. val .. "_ip"]
        local mac = parms["dhcp" .. val .. "_mac"]
        local noprop = parms["dhcp" .. val .. "_noprop"]

        local foundhost = false
        if val == "_add" then
            if host ~= "" then
                local pattern = "%s" .. host .. "%s"
                for line in io.lines("/var/run/hosts_olsr")
                do
                    if line:lower():match(pattern) then
                        foundhost = true
                        dhcperr(val .. [[ <font color='red'>Warning!</font> ']] .. host .. [[ is already in use!<br>
                            Please choose another hostname.<br>
                            Prefixing the hostname with your callsign will help prevent duplicates on the network.
                        ]])
                        break
                    end
                end
            end
            if not ((host ~= "" or ip ~= "" or mac ~= "" or foundhost) and (parms.dhcp_add or parms.button_save)) then
                break
            end
        elseif parms["dhcp" .. val .. "_del"] then
            break
        end

        if val == "_add" and parms.button_save then
            dhcperr(val .. " this reservation must be added or cleared before saving changes")
            break
        end

        if validate_hostname(host) then
            if not foundhost then
                local lhost = host:lower()
                if lhost == node:lower() or lhost == tactical:lower() then
                    dhcperr(val .. " hostname '" .. host .. "' is already in use")
                end
                for key, _ in pairs(hosts)
                do
                    if key:lower() == lhost then
                        dhcperr(val .. " hostname '" .. host .. "' is already in use")
                        break
                    end
                end
            end
        else
            if host then
                dhcperr(val .. " '" .. host .. "' is not a valid hostname")
            else
                dhcperr(val .. " a hostname is required")
            end
        end

        if validate_ip(ip) then
            if addrs[ip] then
                dhcperr(val .. " '" .. ip .. "' is already in use")
            elseif ip == lanip or not validate_same_subnet(ip, lanip, lanmask) or not validate_ip_netmask(ip, lanmask) then
                dhcperr(val .. " '" .. ip .. "' is not a valid LAN address")
            end
        else
            if ip then
                dhcperr(val .. " '" .. ip .. "' is not a valid address")
            else
                dhcperr(val .. " an IP Address must be selected")
            end
        end

        if mac:match("[a-fA-F0-9][a-fA-F0-9]:[a-fA-F0-9][a-fA-F0-9]:[a-fA-F0-9][a-fA-F0-9]:[a-fA-F0-9][a-fA-F0-9]:[a-fA-F0-9][a-fA-F0-9]:[a-fA-F0-9][a-fA-F0-9]") then
            if macs[mac] then
                dhcperr(val .. " MAC " .. mac .. " is already in use")
            end
        else
            if mac then
                dhcperr(val .. " '" .. mac .. "' is not a valid mac address")
            else
                dhcperr(val .. " a MAC address is required")
            end
        end

        if val == "_add" and #dhcp_err > 0 then
            break
        end

        dhcp_num = dhcp_num + 1
        local prefix = "dhcp" .. dhcp_num .. "_"
        parms[prefix .. "host"] = host
        parms[prefix .. "ip"] = ip
        parms[prefix .. "mac"] = mac
        parms[prefix .. "noprop"] = noprop

        hosts[host] = true
        addrs[ip] = true
        macs[mac] = true

        if val == "_add" then
            parms.dhcp_add_host = ""
            parms.dhcp_add_ip = ""
            parms.dhcp_add_mac = ""
            parms.dhcp_add_noprop = ""
        end
    end
end

-- add existing leases
for lease, lval in pairs(parms)
do
    local n = lease:match("^lease(%d+)_add$")
    if n and lval ~= "" then
        local found = false
        for k, v in pairs(parms)
        do
            if not k:match("dhcp%d+_mac") then
                if v == parms["leases" .. n .. "_mac"] then
                    found = true
                    break
                end
            end
        end
        if not found then
            dhcp_num = dhcp_num + 1
            local prefix1 = "leases" .. n .. "_"
            local prefix2 = "dhcp" .. dhcp_num .. "_"
            local host = parms[prefix1 .. "host"]
            local ip = parms[prefix1 .. "ip"]
            local mac = parms[prefix1 .. "mac"]
            local noprop = parms[prefix1 .. "noprop"]

            parms[prefix2 .. "host"] = host
            parms[prefix2 .. "ip"] = ip
            parms[prefix2 .. "mac"] = mac
            parms[prefix2 .. "noprop"] = noprop
            local lhost = host:lower()
            if lhost == node:lower() or lhost == tactical:lower() then
                dhcperr(dhcp_num .. " hostname '" .. host .. "' is already in use")
            end
            for key, _ in pairs(hosts)
            do
                if key:lower() == lhost then
                    dhcperr(dhcp_num .. " hostname '" .. host .. "' is already in use")
                    break
                end
            end
            if addrs[ip] then
                dhcperr(dhcp_num .. " is already in use")
            end
            if macs[mac] then
                dhcperr(dhcp_num .. " MAC " .. mac .. " is already in use")
            end
        end
    end
end

parms.dhcp_num = dhcp_num
dhcphosts = {}
dhcphosts[lanip] = "localhost"

-- replace "blank" dhcp hostname and save the dhcp info into the tmpdir

local f = io.open(tmpdir .. "/dhcp", "w")
if f then
    local nn = 1
    for i = 1,parms.dhcp_num
    do
        if parms["dhcp" .. i .. "_host"] == "*" then
            while hosts["noname" .. nn]
            do
                nn = nn + 1
            end
            parms["dhcp" .. i .. "_host"] = "noname" .. nn
            hosts["noname" .. nn] = true
        end
        f:write(parms["dhcp" .. i .. "_mac"] .. " " .. (ip_to_decimal(parms["dhcp" .. i .. "_ip"]) - lannet_d) .. " " .. parms["dhcp" .. i .. "_host"] .. " " .. parms["dhcp" .. i .. "_noprop"] .. "\n")
        if not (dhcphosts[parms["dhcp" .. i .. "_ip"]]) then
            dhcphosts[parms["dhcp" .. i .. "_ip"]] = parms["dhcp" .. i .. "_host"]
        end
    end
    f:close()
end

-- aliases
local list = {}
for i = 1,parms.alias_num
do
    list[#list + 1] = i
end
list[#list + 1] = "_add"
local alias_num = 0

for _, val in ipairs(list)
do
    for _ = 1,1
    do
        local foundhost = false
        local host = parms["alias" .. val .. "_host"]
        local ip = parms["alias" .. val .. "_ip"]
        -- if adding aliases check the name is not already in use,
        -- also check that it dos not contain anything that will be weird on the mesh
        -- for instance: supercoolservice.kg6wxc-host.local.mesh is certainly a valid host name, but it won't work for the mesh.
        if val == "_add" then
            if host ~= "" then
                local pattern = "%s" .. host .. "%s"
                for line in io.lines("/var/run/hosts_olsr")
                do
                    if line:lower():match(pattern) then
                        foundhost = true
                        aliaserr(val .. [[ <font color='red'>Warning!</font> ']] .. host .. [[ is already in use!<br>
                            Please choose another hostname.<br>
                            Prefixing the hostname with your callsign will help prevent duplicates on the network.
                        ]])
                        break
                    end
                end
                if not validate_hostname(host) then
                    aliaserr(val .. " <font color='red'>Warning!</font> The alias name: '" .. host .."' is invalid")
                end
                if host:match("%.") then
                    aliaserr(val .. " '" .. host .. "' cannot contain the dot '.' character")
                end
            end
            if not ((host ~= "" or ip ~= "" or foundhost) and (parms.alias_add or parms.button_save)) then
                break
            end
        elseif parms["alias" .. val .. "_del"] then
            break
        end
        if val == "_add" and parms.button_save then
            aliaserr(val .. " this alias must be added or cleared out before saving changes")
            break
        end
        if val == "_add" and #alias_err > 0 and alias_err[#alias_err]:match("^" .. val .. " ") then
            break
        end

        alias_num = alias_num + 1
        parms["alias" .. alias_num .. "_host"] = host
        parms["alias" .. alias_num .. "_ip"] = ip
        hosts[host] = true
        if val == "_add" then
            parms.alias_add_host = ""
            parms.alias_add_ip = ""
        end
    end
end

-- write to temp file
local f = io.open(tmpdir .. "/aliases", "w")
if f then
    for i = 1,alias_num
    do
        f:write(parms["alias" .. i .. "_ip"] .. " " .. parms["alias" .. i .. "_host"] .. "\n")
    end
    f:close()
end
parms.alias_num = alias_num

-- load and validate services
local list = {}
for i = 1,parms.serv_num
do
    list[#list + 1] = i
end
list[#list + 1] = "_add"
local serv_num = 0
hosts[""] = true
hosts[node] = true
usedports[""] = true
local servicenames = {}

local vars = { "name", "proto", "host", "port", "suffix" }
local vars2 = { "name", "link", "proto", "host", "port", "suffix" }
local f = io.open(tmpdir .. "/services", "w")
if f then
    for _, val in ipairs(list)
    do
        for _ = 1,1
        do
            for _, var in ipairs(vars)
            do
                local varname = "serv" .. val .. "_" .. var
                local v = parms[varname]
                if v then
                    v = v:gsub("^%s+", ""):gsub("%s+$", "")
                else
                    v = ""
                end
                parms[varname] = v
                _G[var] = v
            end

            if dmz_mode == 0 then
                host = node
            end

            -- remove services that have had their host or port deleted
            if val ~= "_add" and not (dmz_mode == 0 and true or hosts[host]) then
                break
            end

            local link = parms["serv" .. val .. "_link"]
            if not link then
                link = "0"
            end

            if val == "_add" then
                if not ((name ~= "" or proto ~= "" or port ~= "" or suffix ~= "") and (parms.serv_add or parms.button_save)) then
                    break
                end
            else
                if parms["serv" .. val .. "_del"] or not (name ~= "" or proto ~= "" or port ~= "" or suffix ~= "") then
                    break
                end
            end

            if val == "_add" and parms.button_save then
                serverr(val .. " this service must be added or cleared out before saving changes")
                break
            end

            if name == "" then
                serverr(val .. " a name is required")
            elseif not validate_service_name(name) then
                serverr(val .. " '" .. name .. "' is not a valid service name")
            elseif servicenames[name] then
                serverr(val .. " the name '" .. name .. "' is already in use")
            end

            if link then
                parms["serv" .. val .. "_proto"] = (proto and proto or "http")
                if not validate_service_protocol(proto) then
                    serverr(val .. " '" .. proto .. "' is not a valid protocol")
                elseif proto == "" then
                    serverr(val .. " a port number is required")
                elseif not validate_port(port) then
                    serverr(val .. " '" .. port .. "' is not a valid port")
                elseif not validate_service_suffix(suffix) then
                    serverr(val .. " '" .. suffix .. "' is not a valid service suffix")
                end
            elseif val == "_add" then
                proto = ""
                port = ""
                suffix = ""
            end

            if val == "_add" and #serv_err > 0 then
                break
            end

            -- commit the data for this service
            serv_num = serv_num + 1
            servicenames[name] = true

            f:write(name .. "|" .. link .. "|" .. proto .. "|" .. host .. "|" .. port .. "|" .. suffix .. "\n")

            for _, var in ipairs(vars2)
            do
                parms["serv" .. serv_num .. "_" .. var] = _G[var]
            end

            if val == "_add" then
                parms.serv_add_name = ""
                parms.serv_add_link = ""
                parms.serv_add_proto = ""
                parms.serv_add_host = ""
                parms.serv_add_port = ""
                parms.serv_add_suffix = ""
            end
        end
    end
    f:close()
end
parms.serv_num = serv_num

-- save configuration
if parms.button_save and not (#port_err > 0 or #dhcp_err > 0 or #dmz_err > 0 or #serv_err > 0 or #alias_err > 0) then
    filecopy(tmpdir .. "/ports", portfile)
    filecopy(tmpdir .. "/dhcp", dhcpfile)
    filecopy(tmpdir .. "/services", servfile)
    filecopy(tmpdir .. "/aliases", aliasfile)
    
    if os.execute("/usr/local/bin/node-setup.lua -a -p mesh") ~= 0 then
        err("problem with configuration")
    end
    if not luci.sys.init.reload("dnsmasq") then
        err("problem with dnsmasq")
    end
    if not luci.sys.init.reload("firewall") then
        err("problem with port setup")
    end
    -- This "luci.sys.init.restart("olsrd")" doesnt do the same thing so we have to call restart directly
    if os.execute("/etc/init.d/olsrd restart") ~= 0 then
        err("problem with olsr setup")
    end
end

-- generate the page

http_header()
html.header(node .. " setup", true)
html.print("<body><center>")
html.alert_banner()
html.print("<form method=post action=/cgi-bin/ports.lua enctype='multipart/form-data'>")
html.print("<table width=790>")
html.print("<tr><td>")
navbar();
html.print("</td></tr>")

-- control buttons
html.print([[<tr><td align=center>
<a href='/help.html#ports' target='_blank'>Help</a>
&nbsp;&nbsp;&nbsp;
<input type=submit name=button_save value='Save Changes' title='Save and use these settings now (takes about 20 seconds)'>&nbsp;
<input type=submit name=button_reset value='Reset Values' title='Revert to the last saved settings'>&nbsp;
<input type=submit name=button_refresh value='Refresh' title='Refresh this page'>&nbsp;
<tr><td>&nbsp;</td></tr>]])
hide("<input type=hidden name=reload value=1></td></tr>")

-- messages

if parms.button_save then
    if #port_err > 0 or #dhcp_err > 0 or #dmz_err > 0 or #serv_err > 0 then
        html.print("<tr><td align=center><b>Configuration NOT saved!</b></td></tr>")
    elseif #errors > 0 then
        html.print("<tr><td align=center><b>Configuration saved, however:<br>")
        for _, err in ipairs(errors)
        do
            html.print(err .. "<br>")
        end
	    html.print("</b></td></tr>")
    else
        html.print("<tr><td align=center><b>Configuration saved and is now active.</b></td></tr>")
    end
    html.print("<tr><td>&nbsp;</td></tr>")
end

-- everything else

function print_reservations()
    html.print("<table cellpadding=0 cellspacing=0><tr><th colspan=4>DHCP Address Reservations</th></tr>")
    html.print("<tr><td colspan=4 height=5></td></tr>")
    html.print("<tr><td align=center>Hostname</td><td align=center>IP Address</td><td align=center>MAC Address</td>")
    
    if dmz_mode ~= 0 then
        html.print("<td align=center style='font-size:10px;'>Do Not<br>Propagate</td><td></td></tr>")
    else
        html.print("<td></td><td></td></tr>")
    end
    html.print("<tr><td colspan=4 height=5></td></tr>")

    local list = {}
    for i = 1,parms.dhcp_num
    do
        list[#list + 1] = i
    end
    list[#list + 1] = "_add"

    for _, val in ipairs(list)
    do
        local host = parms["dhcp" .. val .. "_host"]
        local ip = parms["dhcp" .. val .. "_ip"]
        local mac = parms["dhcp" .. val .. "_mac"]:lower()
        local noprop = parms["dhcp" .. val .. "_noprop"]

        if val == "_add" and #list > 1 then
            html.print("<tr><td colspan=4 height=10></td></tr>")
        end
	    html.print("<tr><td><input type=text name=dhcp" .. val .. "_host value='" .. host .. "' size=10></td>")
        html.print("<td align=center><select name=dhcp" .. val .. "_ip>")
        if val == "_add" then
	        html.print("<option value=''>- IP Address -</option>\n")
        end
        for i = dhcp_start,dhcp_end
        do
            local selip = decimal_to_ip(lannet_d + i - lannet_d % 256)
            if selip ~= lanip then
                local ipname = dhcphosts[selip]
                if not ipname or selip == ip then
                    ipname = selip
                end
                html.print("<option " .. (ip == selip and "selected" or "") .. " value='" .. selip .. "'>" .. ipname .. "</option>")
            end
        end
        html.print("</select></td>")
        html.print("<td><input type=text name=dhcp" .. val .. "_mac value='" .. mac .. "' size=16></td>")
        if dmz_mode ~= 0 then
            if noprop == "#NOPROP" then
                html.print("<td align=center><input type=checkbox id=dhcp" .. val .. "_noprop name=dhcp" .. val .. "_noprop value='#NOPROP' checked></td>")
            else
                html.print("<td align=center><input type=checkbox id=dhcp" .. val .. "_noprop name=dhcp" .. val .. "_noprop value='#NOPROP'></td>")
            end
        else
            html.print("<td></td>")
        end

        html.print("<td><nobr>&nbsp;<input type=submit name=")

        if val == "_add" then
            html.print("dhcp_add       value=Add title='Add this as a DHCP reservation'")
        else
            html.print("dhcp" .. val .. "_del value=Del title='Remove this reservation'")
        end
        html.print("></nobr></td></tr>")

        while #dhcp_err > 0 and dhcp_err[1]:match("^" .. val .. " ")
        do
            html.print("<tr><th colspan=4>" .. dhcp_err[1]:gsub("^%S+ ", "") .. "</th></tr>")
            table.remove(dhcp_err, 1)
        end

        html.print("<tr><td height=5></td></tr>")
    end

    html.print("<tr><td>&nbsp;</td></tr>")
    html.print("<tr><th colspan=4>Current DHCP Leases</th></tr>\n<tr>")

    local i = 0
    for line in io.lines("/tmp/dhcp.leases")
    do
        i = i + 1
        local _, mac, ip, host = line:match("(%S+)%s+(%S+)%s+(%S+)%s+(%S+)")
        html.print("<tr><td height=5></td></tr>")
        html.print("<tr><td align=center>" .. host .. "</td><td align=center><small>" .. ip .. "</small></td>")
        html.print("<td align=center><small>" .. mac .. "</small></td><td></td><td><nobr>&nbsp;")
        html.print("<input type=submit name=lease" .. i .. "_add  value=Add ")
        html.print("title='Use these values as an address reservation'></nobr></td></tr>")
        hide("<input type=hidden name=lease" .. i .. "_host value=" .. host .. ">")
        hide("<input type=hidden name=lease" .. i .. "_ip   value=" .. ip .. ">")
        hide("<input type=hidden name=lease" .. i .. "_mac  value=" .. mac .. ">")
    end

    if i == 0 then
        html.print("<tr><td align=center colspan=4>there are no active leases</td></tr>")
    end
    html.print("</table>")
end

function print_forwarding()
    html.print("<table cellpadding=0 cellspacing=0><tr><th colspan=7>Port Forwarding</th></tr>")
    html.print("<tr><td>&nbsp;</td><td align=center>Interface</td><td align=center>Type</td>")
    html.print("<td align=center>Outside<br>Port</td><td align=center>LAN IP</td>")
    html.print("<td align=center width=1>LAN<br>Port</td><td>&nbsp;</td></tr>")

    local list = {}
    for i = 1,parms.port_num
    do
        list[#list + 1] = i
    end
    list[#list + 1] = "_add"
    local vars = { "_intf", "_type", "_out", "_ip", "_in", "_enable", "_adv", "_link", "_proto", "_suffix", "_name" }
    for _, val in ipairs(list)
    do
        for _, var in ipairs(vars)
        do
            _G[var] = parms["port" .. val .. var]
        end

        if val == "_add" and #list > 1 then
            html.print("<tr><td colspan=7 height=10></td></tr>")
        end

        html.print("<tr><td>&nbsp;</td>")
	    hide("<input type=hidden name=port" .. val .. "_enable value=1>")

        -- port forwarding settings
        html.print("<td align=center valign=top><select name=port" .. val .. "_intf title='forward inbound packets from this interface'>")
        if dmz_mode == 0 then
            html.print("<option " .. (_inntf == "wifi" and "selected" or "") .. " value='wifi'>WiFi</option>")
            html.print("<option " .. (_inntf == "wab" and "selected" or "") .. " value='wan'>WAN</option>")
            html.print("<option " .. (_inntf == "both" and "selected" or "") .. " value='both'>Both</option>")
        else
            html.print("<option " .. (_inntf == "wan" and "selected" or "") .. " value='wan'>WAN</option>")
        end
        html.print("</select></td>")

        html.print("<td align=center valign=top><select name=port" .. val .. "_type>")
        html.print("<option " .. (_type == "tcp" and "selected" or "") .. " value='tcp'>TCP</option>")
        html.print("<option " .. (_type == "udp" and "selected" or "") .. " value='udp'>UDP</option>")
        html.print("<option " .. (_type == "both" and "selected" or "") .. " value='both'>Both</option>")
        html.print("</select></td>")

        html.print("<td align=center valign=top><input type=text name=port" .. val .. "_out value='" .. _out .. "' size=8></td>")
        html.print("<td align=center valign=top><select name=port" .. val .. "_ip>")
        if val == "_add" then
            html.print("<option value=''>- IP Address -</option>")
        end
        local lanlimit = nixio.bit.lshift(1, 32 - netmask_to_cidr(lanmask)) - 2
        for i = 1,lanlimit
        do
            local selip = decimal_to_ip(lannet_d + i)
            local ipname = dhcphosts[selip]
            if not ipname then
                ipname = selip
            end
            html.print("<option " .. (_ip == selip and "selected" or "") .. " value='" .. selip .. "'>" .. ipname .. "</option>")
        end
        html.print("</select></td>")

        html.print("<td align=left valign=top><input type=text name=port" .. val .. "_in value='" .. _in .. "' size=4></td>")
	    html.print("<td><nobr>&nbsp;<input type=submit name=")

        if val == "_add" then
            html.print("port_add value=Add title='Add this as a port forwarding rule'")
        else
            html.print("port" .. val .. "_del value=Del title='Remove this rule'")
        end
        html.print("></nobr></td></tr>")

        -- display any errors
        while #port_err > 0 and port_err[1]:match("^" .. val .. " ")
        do
            local err = port_err[1]:gsub("^%S+ ", "")
            html.print("<tr><th colspan=7>" .. err .. "</th></tr>")
            table.remove(port_err, 1)
        end

        html.print("<tr><td colspan=7 height=5></td></tr>")
    end

    -- dmz server for nat mode
    if dmz_mode == 0 then
        html.print("<tr><td colspan=7 height=10></td></tr>")
        html.print("<tr><td colspan=4 align=right>DMZ Server &nbsp; </td>")
        html.print("<td colspan=3><select name=dmz_ip onChange='form.submit()' ")
        html.print("title='Send all other inbound traffic to this host'>")
        html.print("<option value=''>None</option>")
        for i = 1,lanlimit
        do
            local selip = decimal_to_ip(lannet_d + i)
                if selip ~= lanip then
                local ipname = dhcphosts[selip]
                if not ipname then
                    ipname = selip
                end
                html.print("<option " .. (parms.dmz_ip == selip and "selected" or "") .. " value='" .. selip .. "'>" .. ipname .. "</option>")
            end
        end
        html.print("</select></td>")

        for _, e in ipairs(dmz_err)
        do
            html.print("<tr><th colspan=8>" .. e .. "</th></tr>")
        end
    end
    html.print("</table>")
end

function print_services()
    html.print("<table cellpadding=0 cellspacing=0><tr><th colspan=4>Advertised Services</th></tr>")
    if not (dmz_mode ~= 0 or parms.port_num ~= 0 or parms.dmz_ip) then
        if dmz_mode ~= 0 then
            html.print("<tr><td>&nbsp;</td></tr><tr><td height=10></td></tr>")
        else
            html.print("<tr><td>&nbsp;<br><br></td></tr>")
        end
        html.print("<tr><td colspan=4 align=center>none</td></tr>")
        html.print("</table>")
        return;
    end

    if dmz_mode ~= 0 then
        html.print("<tr><td height=5></td></tr>")
        html.print("<tr><td>Name</td><td>Link</td><td>URL</td><td></td></tr>")
        html.print("<tr><td height=5></td></tr>")
    else
        html.print("<tr><td>Name</td><td>Link</td><td>URL</td><td><br><br></td></tr>")
    end

    local list = {}
    for i = 1,parms.serv_num
    do
        list[#list + 1] = i
    end
    list[#list + 1] = "_add"

    local vars = { "_name", "_link", "_proto", "_host", "_port", "_suffix" }
    for _, val in ipairs(list)
    do
        for _, var in ipairs(vars)
        do
            _G[var] = parms["serv" .. val .. var]
        end
        if dmz_mode == 0 then
            _host = node
            parms["serv" .. val .. "_host"] = node
        end

        if val == "_add" and #list > 1 then
            html.print("<tr><td colspan=4 height=10></td></tr>")
        end
        html.print("<tr>")
        html.print("<td><input type=text size=6 name=serv" .. val .. "_name value='" .. _name .. "' title='what to call this service'></td>")

        html.print("<td><nobr><input type=checkbox name=serv" .. val .. "_link value=1")
        if val ~= "_add" then
            html.print(" onChange='form.submit()'")
        end
        if _link ~= "0" then
            html.print(" checked")
        end
        html.print(" title='create a clickable link for this service'>")
        html.print("<input type=text size=2 name=serv" .. val .. "_proto value='" .. _proto .. "' title='URL Protocol'")
        if val ~= "_add" and _link ~= "1" then
            html.print(" disabled")
        end
        html.print("></nobr></td>")

        if dmz_mode ~= 0 then
            html.print("<td><nobr><b>:</b>//<select name=serv" .. val .. "_host")
            if val ~= "_add" and _link ~= "1" then
                html.print(" disabled")
            end
            html.print(">")
            html.print("<option " .. (node == _host and "selected" or "") .. " value='" .. node .. "'>" .. node .. "</option>")
            for i = 1,parms.alias_num
            do
                html.print("<option " .. (parms["alias" .. i .. "_host"] == _host and "selected" or "") .. " value='" .. parms["alias" .. i .. "_host"] .. "'>" .. parms["alias" .. i .. "_host"] .. "</option>")
            end
            for i = 1,parms.dhcp_num
            do
                html.print("<option " .. (parms["dhcp" .. i .. "_host"] == _host and "selected" or "") .. " value='" .. parms["dhcp" .. i .. "_host"] .. "'>" .. parms["dhcp" .. i .. "_host"] .. "</option>")
            end
            html.print("</select>")
        else
	        html.print("<td><nobr><b>:</b>//<small>" .. _host .. "</small>")
        end

        html.print("<b>:</b><input type=text size=2 name=serv" .. val .. "_port value='" .. _port .. "' title='port number'")
        if val ~= "_add" and _link ~= "1" then
            html.print(" disabled")
        end
        html.print("> / <input type=text size=6 name=serv" .. val .. "_suffix value='" .. _suffix .. "' ")
        html.print("title='leave blank unless the URL needs a more specific path'")
        if val ~= "_add" and _link ~= "1" then
            html.print(" disabled")
        end
        html.print("></nobr></td>")

        html.print("<td><nobr>&nbsp;<input type=submit name=")
        if val == "_add" then
            html.print("serv_add       value=Add title='Add this as a service'")
        else
            html.print("serv" .. val .. "_del value=Del title='Remove this service'")
        end
        html.print("></nobr></td></tr>")

        -- display any errors
        while #serv_err > 0 and serv_err[1]:match("^" .. val .. " ")
        do
            html.print("<tr><th colspan=4>" .. serv_err[1]:gsub("^%S+ ", "") .. "</th></tr>")
            table.remove(serv_err, 1)
        end

        if _link ~= "1" and val ~= "_add" then
            hide("<input type=hidden name=serv" .. val .. "_proto  value='" .. _proto .. "'>")
            hide("<input type=hidden name=serv" .. val .. "_host   value='" .. _host .. "'>")
            hide("<input type=hidden name=serv" .. val .. "_port   value='" .. _port .. "'>")
            hide("<input type=hidden name=serv" .. val .. "_suffix value='" .. _suffix .. "'>")
        end

        html.print("<tr><td colspan=4 height=4></td></tr>")
    end
    html.print("</table>")
end

function print_aliases()
    html.print("<table cellpadding=0 cellspacing=0><tr><th colspan=4>DNS Aliases</th></tr>")
    html.print("<tr><td colspan=3 height=5></td></tr>")
    html.print("<tr><td align=center>Alias Name</td><td></td><td align=center>IP Address</td></tr>")
    html.print("<tr><td colspan=3 height=5></td></tr>")

    local list = {}
    for i = 1,parms.alias_num
    do
        list[#list + 1] = i
    end
    list[#list + 1] = "_add"

    for _, val in ipairs(list)
    do
        local host = parms["alias" .. val .. "_host"]
        local ip = parms["alias" .. val .. "_ip"]
        if val == "_add" and #list > 1 then
            html.print("<tr><td colspan=3 height=10></td></tr>\n")
        end
        html.print("<tr><td align=center><input type=text name=alias" .. val .. "_host value='" .. host .. "' size=20></td>")
        html.print("<td>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</td>")
        html.print("<td align=center><select name=alias" .. val .. "_ip>")
        if val == "_add" then
            html.print("<option value=''>- IP Address -</option>")
        end
        for i = dhcp_start,dhcp_end
        do
            local selip = decimal_to_ip(lannet_d + i - lannet_d % 256)
            if selip ~= lanip then
                local ipname = dhcphosts[selip]
                if not ipname then
                    ipname = selip
                end
                html.print("<option " .. (_ip == selip and "selected" or "") .. " value='" .. selip .. "'>" .. ipname .. "</option>")
            end
        end
        html.print("</select></td>")
        html.print("<td><nobr>&nbsp;<input type=submit name=")
        if val == "_add" then
            html.print("alias_add       value=Add title='Add Alias'")
        else
            html.print("alias" .. val .. "_del value=Del title='Remove Alias'")
        end
        html.print("></nobr></td></tr>")
    end
    for _, e in ipairs(alias_err)
    do
        html.print("<tr><th colspan=4>" .. e:gsub("^%S+ ", "") .. "</th></tr>")
    end
    html.print("</table>")
end

html.print("<tr><td align=center><table width=100%>")
html.print("<tr><td width=1 align=center valign=top>")
if dmz_mode ~= 0 then
    print_reservations()
else
    print_forwarding()
end
html.print("</td>")
html.print("<td>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</td><td align=center valign=top>")
print_services()
html.print("</td>")
html.print("</tr></table></td></tr>")
html.print("<tr><td>&nbsp;</td></tr>")
html.print("<tr><td><hr></td></tr>")  
html.print("</table><table width=790>")
html.print("<tr><td align=center valign=top>")
if dmz_mode ~= 0 then
    print_forwarding()
else
    print_reservations()
end
html.print("</td>")
html.print("<td>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</td>")
html.print("<td>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</td>")
html.print("<td align=center valign=top>")
print_aliases()
html.print("</td></tr></table>")

hide("<input type=hidden name=port_num value=" .. parms.port_num .. ">")
hide("<input type=hidden name=dhcp_num value=" .. parms.dhcp_num .. ">")
hide("<input type=hidden name=serv_num value=" .. parms.serv_num .. ">")
hide("<input type=hidden name=alias_num value=" .. parms.alias_num .. ">")

for _, h in ipairs(hidden)
do
    html.print(h)
end

html.print("</form></center>")
html.footer()
html.print("</body></html>")
http_footer()
