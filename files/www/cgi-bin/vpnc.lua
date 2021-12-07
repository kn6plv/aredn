#!/usr/bin/lua
--[[

	Part of AREDN -- Used for creating Amateur Radio Emergency Data Networks
	Copyright (C) 2021 Tim Wilkinson
	Original Perl Copyright (c) 2015 Darryl Quinn
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
require("aredn.http")
require("aredn.utils")
require("aredn.html")
require("aredn.hardware")
aredn.info = require("aredn.info")
require("uci")
require("luci.sys")

local html = aredn.html

local cursor = uci.cursor();

local node = aredn.info.get_nvram("node")
if node == "" then
    node = "NOCALL"
end
-- truncate node name down to 23 chars (max) to avoid vtun issues
-- this becomes the vtun "username"
node = node:sub(1, 23)

local config = aredn.info.get_nvram("config");
local VPNVER = "1.0"

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

-- helpers start

local hidden = {}
function hide(inp)
    hidden[#hidden + 1] = inp
end

local conn_err = {}
function err(msg)
    conn_err[#conn_err + 1] = msg
end

function navbar()
    html.print("<tr><td>")
    html.print("<hr><table cellpadding=5 border=0 width=100%><tr>")
    html.print("<td align=center width=15%><a href='status.lua'>Node Status</a></td>")
    html.print("<td align=center width=15%><a href='setup.lua'>Basic Setup</a></td>")
    html.print("<td align=center width=15%><a href='ports.lua'>Port Forwarding,<br>DHCP, and Services</a></td>")
    html.print("<td align=center width=15%><a href='vpn.lua'>Tunnel<br>Server</a></td>")
    html.print("<td align=center width=15% class=navbar_select><a href='vpnc.lua'>Tunnel<br>Client</a></td>")
    html.print("<td align=center width=15%><a href='admin.lua'>Administration</a></td>")
    html.print("<td align=center width=15%><a href='advancedconfig.lua'>Advanced<br>Configuration</a></td>")
    html.print("</tr></table><hr>")
end

function get_active_tun()
    local tuns = {}
    local f = io.popen("ps -w | grep vtun | grep ' tun '")
    if f then
        for line in f:lines()
        do
            local m = line:match(".*:.*-(172-31-.*)%stun%stun.*")
            if m then
                tuns[#tuns + 1] = m:gsub("-", ".")
            end
        end
        f:close()
    end
    return tuns
end

function is_tunnel_active(ip, tunnels)
    for _, aip in ipairs(tunnels)
    do
        if ip == aip then
            return true
        end
    end
    return false
end

function install_vtun()
    local vfs = nixio.fs.statvfs("/overlay")
    local fspace = vfs.bfree * vfs.bsize / 1024
    if fspace < 600 then
        err("Insufficient free disk space")
        return
    end
    if not os.execute("opkg update") then
        err("Package update failed!")
        return
    end
    if not os.execute("opkg install kmod-tun zlib liblzo vtun") then
        err("Package installation failed!")
        return
    end
    cursor:set("aredn", "@tunnel[0]", "maxclients", "10")
    cursor:set("aredn", "@tunnel[0]", "maxservers", "10")
    cursor:commit("aredn")
    write_all("/etc/config.mesh/aredn", read_all("/etc/config/aredn"))
    for tunnum = 50,69
    do
        cursor:set("network_tun", "tun" .. tunnum, "interface")
        cursor:set("network_tun", "tun" .. tunnum, "ifname", "tun" .. tunnum)
        cursor:set("network_tun", "tun" .. tunnum, "proto", "none")
    end
    cursor:commit("network_tun")
    write_all("/etc/config.mesh/network_tun", read_all("/etc/config/network_tun"))
    os.execute("cat /etc/config.mesh/network_tun >> /etc/config.mesh/network")
    os.execute("cat /etc/config.mesh/network_tun >> /etc/config/network")

    io.open("/etc/config/vtun", "w"):close()
    cursor:add("vtun", "options")
    cursor:commit("vtun")

    http_header()
    html.header("TUNNEL INSTALLATION IN PROGRESS", true)
    html.print("<body><center>")
    html.print("<h2>Installing tunnel software...</h2>")
    html.print("<h1>DO NOT REMOVE POWER UNTIL THE INSTALLATION IS FINISHED</h1>")
    html.print("</center><br>")
    html.print([[
        <center><h2>The node is rebooting</h2>
        <h3>When the node has fully rebooted you can reconnect with<br>
        <a href='http://]] .. node .. [[.local.mesh:8080/'>http://]] .. node .. [[.local.mesh:8080/</a><br>
        </h3>
        </center>
    ]])
    html.footer()
    html.print("</body></html>")
    http_footer()
    luci.sys.reboot()
    os.exit()
end

-- helpers end

local gci_vars = { "enabled", "host", "passwd", "netip", "contact" }
function get_connection_info()
    local c = 0
    local conns = cursor:get_all("vtun", "server")
    if conns then
        for _, myconn in pairs(conns)
        do
            for _, var in ipairs(gci_vars)
            do
                local key = "conn" .. c .. "_" .. var
                parms[key] = myconn[var]
                if not parms[key] then
                    parms[key] = ""
                end
            end
            c = c + 1
        end
    end
    parms.conn_num = c
end

if parms.button_reboot then
    luci.sys.reboot()
    os.exit()
end

if parms.button_install then
    install_vtun()
end

if config == "" or nixio.fs.stat("/tmp/reboot-required") then
    http_header();
    html.header(node .. " setup", true);
    html.print("<body><center>")
    html.alert_banner()
    html.print("<table width=790>")
    navbar();
    hrml.print("</td></tr><tr><td align=center><br>")
    if config == "" then
        html.print("<b>This page is not available until the configuration has been set.</b>")
    else
        html.print("<b>The configuration has been changed.<br>This page will not be available until the node is rebooted.</b>")
        html.print("<form method='post' action='/cgi-bin/vpnc.lua' enctype='multipart/form-data'>")
        html.print("<input type=submit name=button_reboot value='Click to REBOOT' />")
        html.print("</form>")
    end
    html.print("</td></tr>")
    html.print("</table></center></body></html>")
    http_footer()
    os.exit();
end

if not nixio.fs.stat("/usr/sbin/vtund") then
    http_header();
    html.header(node .. " setup", true);
    html.print("<body><center>")
    html.alert_banner()
    html.print("<table width=790>")
    html.print("<tr><td>")
    navbar();
    html.print("</td></tr>")
    if #conn_err > 0 then
        html.print("<tr><td align=center><b>ERROR:<br>")
        for _, e in ipairs(conn_err)
        do
            html.print(e .. "<br>")
        end
        html.print("</b></td></tr>")
    end
    html.print("<tr><td align=center><br><b>")
    html.print("Tunnel software needs to be installed.<br/>")
    html.print("<form method='post' action='/cgi-bin/vpnc.lua' enctype='multipart/form-data'>")
    html.print("<input type=submit name=button_install value='Click to install' class='btn_tun_install' />")
    html.print("</form>")
    html.print("</b></td></tr>")
    html.print("</table></center></body></html>")
    http_footer()
    os.exit();
end

if parms.button_reset then
    cursor:revert("vtun")
    cursor:commit("vtun")
end

-- handle connection deletes
for i = 0,9
do
    local varname = "conn" .. i .. "_del"
    if parms[varname] then
        cursor:delete("vtun", "server_" .. i)
        for x=i+1,9
        do
            cursor:rename("vtun", "server_" .. x, "server_" .. (x - 1))
        end
    end
end

-- if RESET or FIRST TIME, load servers into parms
if parms.button_reset or not parms.reload then
    cursor:revert("vtun")
    get_connection_info()
    -- initialzie the "add" entries to clear them
    parms.conn_add_enabled = "0"
    parms.conn_add_host = ""
    parms.conn_add_passwd = ""
    parms.conn_add_netip = ""
    parms.conn_add_contact = ""
end

-- load connetions from FORM and validate
local list = {}
for i = 0,parms.conn_num-1
do
    list[#list + 1] = i
end
list[#list + 1] = "_add"
local conn_num = 0

local vars = { "enabled", "host", "passwd", "netip", "contact" }
for _, val in ipairs(list)
do
    for _, var in ipairs(vars)
    do
        local varname = "conn" .. val .. "_" .. var
        if val == "enabled" and parms[varname] == "" then
            parms[varname] = "0"
        elseif not parms[varname] then
            parms[varname] = ""
        else
            parms[varname] = parms[varname]:gsub("^%s+", ""):gsub("%s+$", "")
        end
        if val ~= "_add" and parms[varname] == "" and var == "enabled" then
            parms[varname] = "0"
        end
        _G[var] = parms[varname]
    end

    if val == "_add" and not ((enabled or host or passwd or netip or contact) and (parms.conn_add or parms.button_save)) then
        -- continue
    elseif val ~= "_add" and parms["conn" .. val .. "_del"] then
        --continue
    else
        if val == "_add" and parms.button_save then
            err(val .. " this connection must be added or cleared out before saving changes")
            -- continue
        else
            if passwd:match("%W") then
                err("The password cannot contain non-alphanumeric characters (#" .. conn_num .. ")")
            end
            if host == "" then
                err("A connection server is required")
            end
            if passwd == "" then
                err("A connection password is required")
            end
            if netip == "" then
                err("A connection network IP is required")
            end

            if val == "_add" or #conn_err > 0 then
                -- continue
            else
                parms["conn" .. conn_num .. "_enabled"] = enabled
                parms["conn" .. conn_num .. "_host"] = host
                parms["conn" .. conn_num .. "_passwd"] = passwd
                parms["conn" .. conn_num .. "_netip"] = netip
                parms["conn" .. conn_num .. "_contact"] = contact

                conn_num = conn_num + 1

                -- clear out the ADD values
                if val == "_add" then
                    for _, var in ipairs(vars)
                    do
                        parms["conn_add_" .. var] = ""
                    end
                end
            end
        end
    end
end

parms.conn_num = conn_num

-- save the connections
local enabled_count = 0
for i = 0,parms.conn_num-1
do
    local connx_ = "conn" .. i .. "_"
    local conn_x = "server_" .. i

    local net = parms[connx_ .. "netip"]
    local vtun_node_name = (node .. "-" .. net):upper()
    local base = ip_to_decimal(net)
    local clientip = decimal_to_ip(base + 2)
    local serverip = decimal_to_ip(base + 1)

    cursor:add("vtun", conn_x)

    cursor:set("vtun", conn_x, "clientip", clientip)
    cursor:set("vtun", conn_x, "serverip", serverip)
    cursor:set("vtun", conn_x, "node", vtun_node_name)

    cursor:set("vtun", conn_x, "enabled", parms[connx_ .. "enabled"])
    cursor:set("vtun", conn_x, "host", parms[connx_ .. "host"])
    cursor:set("vtun", conn_x, "passwd", parms[connx_ .. "passwd"])
    cursor:set("vtun", conn_x, "netip", parms[connx_ .. "netip"])
    cursor:set("vtun", conn_x, "contact", parms[connx_ .. "contact"])

    if parms[connx_ .. "enabled"] == "1" then
        enabled_count = enabled_count + 1
    end
end
if enabled_count > 10 then
    err("Number of servers enabled (" .. enabled_count .. " exceeds maxservers (10); only the first 10 will activate.")
end

-- save the connections the uci vtun file
if parms.button_save and #conn_err == 0 then
    cursor:commit("vtun")
    write_all("/etc/config.mesh/vtun", read_all("/etc/config/vtun"))
    os.execute("/etc/init.d/olsrd restart")
    os.execute("/etc/init.d/vtund restart")
end

local active_tun = get_active_tun()

-- generate page
http_header()
html.header(node .. " setup", true)

html.print("<body><center>")
html.alert_banner()

html.print("<form method=post action=/cgi-bin/vpnc.lua enctype='multipart/form-data'><table width=790>")

-- nav bar
html.print("<tr><td>")
navbar()
html.print("</td></tr>")

-- control buttons
html.print("<tr><td align=center>")
html.print("<a href='/help.html#vpn' target='_blank'>Help</a>")
html.print("&nbsp;&nbsp;&nbsp;")
html.print("<input type=submit name=button_save value='Save Changes' title='Save and use these settings now (takes about 20 seconds)'>&nbsp;")
html.print("<input type=submit name=button_reset value='Reset Values' title='Revert to the last saved settings'>&nbsp;")
html.print("<input type=submit name=button_refresh value='Refresh' title='Refresh this page'>&nbsp;")
html.print("<tr><td>&nbsp;</td></tr>")
hide("<input type=hidden name=reload value=1></td></tr>")

-- messages
if #conn_err > 0 then
    html.print("<tr><td align=center><b>ERROR:<br>")
    for _,msg in ipairs(conn_err)
    do
        html.print(msg .. "<br>")
    end
    html.print("</b></td></tr>")
end

if parms.button_save then
    if #conn_err > 0 then
        html.print("<tr><td align=center><b>Configuration NOT saved!</b></td></tr>")
    else
        html.print("<tr><td align=center><b>Configuration saved and is now active.</b></td></tr>")
    end
    html.print("<tr><td>&nbsp;</td></tr>")
end

-- everything else
if config == "mesh" then
    html.print("<tr><td align=center valign=top>")
    --
    html.print("<table id=connection_section cellpadding=0 cellspacing=0>")
    html.print("<tr><th colspan=6>Connect this node to the following servers:</th></tr>")
    html.print("<tr><th colspan=6><hr></th></tr>")
    html.print("<tr><th>Enabled?</th><th>Server</th><th>Pwd</th><th>Network</th><th>Active&nbsp;</th><th>Action</th></tr>")
    
    local list = {}
    for i = 0,parms.conn_num-1
    do
        list[#list+1] = i
    end
    if parms.conn_num < 10 then
        list[#list+1] = "_add"
    end

    local keys = { "enabled", "host", "passwd", "netip", "contact" }
    local cnum = 0
    for _, val in ipairs(list)
    do
        for _, var in ipairs(keys)
        do
            _G[var] = parms["conn" .. val .. "_" .. var]
        end

        if val == "_add" and #list > 1 then
            html.print("<tr><td height=10></td></tr>")
        end
        html.print("<tr class='tun_client_list2 tun_client_row'>")
        html.print("<td class='tun_client_center_item' rowspan='2'>")

        -- Required to be first, so, if the checkbox is cleared, a value will still POST
        if val ~= "_add" then
            html.print("<input type='hidden' name='conn" .. val .. "_enabled' value='0'>")
        end
        html.print("<input type='checkbox' name='conn" .. val .. "_enabled' value='1'")
        if val ~= "_add" then
            html.print(" onChange='form.submit()'")
        end
        if enabled == "1" then
            html.print(" checked='checked'")
        end
        html.print(" title='enable this connection'></td>")

        html.print("<td><input type=text size=25 name=conn" .. val .. "_host value='" .. host .. "'")
        if val ~= "_add" then
            html.print(" onChange='form.submit()'")
        end
        html.print(" title='connection name'></td>")

        html.print("<td><input type=text size=20 name=conn" .. val .. "_passwd value='" .. passwd .. "' ")
        if val ~= "_add" then
            html.print(" onChange='form.submit()'")
        end
        html.print(" title='connection password'")
        html.print("></td>")

        html.print("<td><input type=text size=14 name=conn" .. val .. "_netip value='" .. netip .. "'")
        if val ~= "_add" then
            html.print(" onChange='form.submit()'")
        end
        html.print(" title='connection network'></td>")

        html.print("</td>")
        html.print("<td class='tun_client_center_item' rowspan='2'>&nbsp;")

        if val ~= "_add" then
            if is_tunnel_active(netip, active_tun) then
                html.print("<img class='tun_client_active_img' src='/connected.png' title='Connected' />")
            else
                html.print("<img class='tun_client_inactive_img' src='/disconnected.png' title='Not connected' />")
            end
        end
        html.print("</td>")
        html.print("<td class='tun_client_center_item' rowspan='2'>&nbsp;")

        html.print("<input type=submit name=")
        if val ~= "_add" then
            html.print("conn" .. val .. "_del value=Del title='Delete this connection'")
        else
            html.print("conn_add value=Add title='Add this connection'")
        end
        html.print("></td>")
        -- contact info for this tunnel
        html.print("</tr>")
        html.print("<tr class='tun_client_list1 tun_client_row tun_loading_css_comment'><td colspan='3' align='right'>Contact Info/Comment (Optional): <input type=text maxlength='50' size=40 name=conn" .. val .. "_contact value='" .. contact .. "'")
        if val == "_add" or val == "" then
            html.print(" onChange='form.submit()'")
        end
        html.print(" title='client contact info'></td>")

        html.print("</tr>")

        -- display any errors
        if #conn_err > 0 then
            for i, err in ipairs(conn_err)
            do
                if err:match("^" .. val .. " ") then
                    html.print("<tr><th colspan=4>" .. err .. "</th></tr>")
                    conn_err:remove(i)
                end
            end
        end

        html.print("<tr><td colspan=6 height=4></td></tr>")
        cnum = cnum + 1
    end
    html.print("</table>")
    --
    html.print("</td></tr><tr><td><hr></td></tr>")
end
html.print("</table>")
html.print("<p style='font-size:8px'>VPN v" .. VPNVER .. "</p>")
hide("<input type=hidden name=conn_num value=" .. parms.conn_num .. ">")

-- add hidden forms fields
for _, h in ipairs(hidden)
do
    html.print(h)
end

html.print("</form></center>")
html.footer()
html.print("</body></html>")
http_footer()
