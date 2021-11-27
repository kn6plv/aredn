#!/usr/bin/lua
--[[

	Part of AREDN -- Used for creating Amateur Radio Emergency Data Networks
	Copyright (C) 2021 Tim Wilkinson
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

local html = aredn.html

local cursor = uci.cursor();

local node = aredn.info.get_nvram("node")
if node == "" then
    node = "NOCALL"
end
local config = aredn.info.get_nvram("config");
local VPNVER = "1.1"

-- post_data
local parms = {}
if os.getenv("REQUEST_METHOD") == "POST" then
    require('luci.http')
    require('luci.sys')
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

local cli_err = {}
function err(msg)
    cli_err[#cli_err + 1] = msg
end

local hidden = {}
function hide(inp)
    hidden[#hidden + 1] = inp
end

function navbar()
    html.print("<tr><td>")
    html.print("<hr><table cellpadding=5 border=0 width=100%><tr>")
    html.print("<td align=center width=15%><a href='status.lua'>Node Status</a></td>")
    html.print("<td align=center width=15%><a href='setup.lua'>Basic Setup</a></td>")
    html.print("<td align=center width=15%><a href='ports'>Port Forwarding,<br>DHCP, and Services</a></td>")
    html.print("<td align=center width=15% class=navbar_select><a href='vpn.lua'>Tunnel<br>Server</a></td>")
    html.print("<td align=center width=15%><a href='vpnc.lua'>Tunnel<br>Client</a></td>")
    html.print("<td align=center width=15%><a href='admin'>Administration</a></td>")
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

function get_server_network_address()
    local server_net = cursor:get("vtun", "@network[0]", "start")
    if not server_net then
        local mac = aredn.hardware.get_interface_mac(aredn.hardware.get_iface_name("lan"))
        local a, b = mac:match("^..:..:..:..:(..):(..)$")
        server_net = "172.31." .. tonumber(b, 16) .. "." .. ((tonumber(a, 16) * 4) % 256)
        cursor:set("vtun", "@network[0]", "start", server_net)
        cursor:commit("vtun")

    end
    local a, b, c, d = server_net:match("^(%d+).(%d+).(%d+).(%d+)$")
    return { a, b, c, d }
end

function get_server_dns()
    return cursor:get("vtun", "@network[0]", "dns")
end

-- helper end

-- load client info from uci
local gci_vars = { "enabled", "name", "passwd", "netip", "contact" }
function get_client_info()
    local c = 0
    for _, myclient in pairs(cursor:get_all("vtun"))
    do
        if myclient[".type"] == "client" then
            for _, var in ipairs(gci_vars)
            do
                local key = "client" .. c .. "_" .. var
                parms[key] = myclient[var]
                if not parms[key] then
                    parms[key] = ""
                end
            end
            c = c + 1
        end
    end
    parms.client_num = c
end

if parms.button_reboot then
    luci.sys.reboot()
    os.exit()
end

if parms.button_install then
    -- fix me
end

if config == "" or nixio.fs.stat("/tmp/reboot-required") then
    http_header();
    html.header(node .. " setup", true);
    html.print("<body><center><table width=790><tr><td>")
    navbar();
    hrml.print("</td></tr><tr><td align=center><br>")
    if config == "" then
        html.print("<b>This page is not available until the configuration has been set.</b>")
    else
        html.print("<b>The configuration has been changed.<br>This page will not be available until the node is rebooted.</b>")
        html.print("<form method='post' action='/cgi-bin/vpn.lua' enctype='multipart/form-data'>")
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
    html.print("<body><center><table width=790>")
    html.print("<tr><td>")
    navbar();
    html.print("</td></tr>")
    if #cli_err > 0 then
        html.print("<tr><td align=center><b>ERROR:<br>")
        for _, e in ipairs(cli_err)
        do
            html.print(e .. "<br>")
        end
        html.print("</b></td></tr>")
    end
    html.print("<tr><td align=center><br><b>")
    html.print("Tunnel software needs to be installed.<br/>")
    html.print("<form method='post' action='/cgi-bin/vpn.lua' enctype='multipart/form-data'>")
    html.print("<input type=submit name=button_install value='Click to install' class='btn_tun_install' />")
    html.print("</form>")
    html.print("</b></td></tr>")
    html.print("</table></center></body></html>")
    http_footer()
    os.exit();
end

if parms.button_reset then
    cursor:revert("vtun")
    cursor:delete("vtun", "@network[0]", "start")
    cursor:delete("vtun", "@network[0]", "dns")
    cursor:commit("vtun")
end

-- get vtun network address
local netw = get_server_network_address()
local dns = get_server_dns()

-- if RESET or FIRST TIME load client/servers from file into parms
if parms.button_reset or not parms.reload then
    cursor:revert("vtun")
    get_client_info()
    parms.server_net1 = netw[3]
    parms.server_net2 = netw[4]
    parms.dns = dns
    -- initialzie the "add" entries to clear them
    parms.client_add_enabled = "0"
    parms.client_add_name = ""
    parms.client_add_passwd = ""
end

local list = {}
for i = 0,parms.client_num-1
do
    list[#list + 1] = i
end
list[#list + 1] = "_add"
local client_num = 0

local vars = { "enabled", "name", "passwd", "netip", "contact" }
local vars2 = { "net", "enabled", "name", "passwd", "netip", "contact" }
for _, val in ipairs(list)
do
    for _, var in ipairs(vars)
    do
        local varname = "client" .. val .. "_" .. var
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

    if val == "_add" and not ((enabled or name or passwd or contact) and (parms.client_add or parms.button_save)) then
        -- continue
    else
        if val == "_add" and parms.button_save then
            err(val .. " this client must be added or cleared out before saving changes")
            -- continue
        else
            if passwd:match("%W") then
                err("The password cannot contain non-alphanumeric characters (#" .. client_num .. ")")
            end
            if not passwd:match("%a") then
                err("The password must contain at least one alphabetic character (#" .. client_num .. ")")
            end
            if name == "" then
                err("A client name is required")
            end
            if passwd == "" then
                err("A client password is required")
            end

            if val == "_add" or #cli_err > 0 then
                -- continue
            else
                parms["client" .. client_num .. "_enabled"] = enabled
                parms["client" .. client_num .. "_name"] = name:upper()
                parms["client" .. client_num .. "_passwd"] = passwd
                parms["client" .. client_num .. "_netip"] = netip

                -- commit the data from this client
                client_num = client_num + 1

                -- clear out the ADD values
                if val == "_add" then
                    for _, var in ipairs(vars2)
                    do
                        parms["client_add_" .. var] = ""
                    end
                end
            end
        end
    end
end

parms.client_num = client_num

-- SAVE the server network numbers and dns into the UCI
netw[3] = parms.server_net1
netw[4] = parms.server_net2
dns = parms.dns
if not tonumber(parms.server_net1) or tonumber(parms.server_net1) < 0 or tonumber(parms.server_net1) > 255 then
    err("The third octet of the network MUST be from 0 to 255")
end
if not tonumber(parms.server_net2) or tonumber(parms.server_net2) < 0 or tonumber(parms.server_net2) > 255 then
    err("The last octet of the network MUST be from 0 to 255")
end
if not tonumber(parms.server_net2) or tonumber(parms.server_net2) %4 ~= 0 then
    err("The last octet of the network MUST be a multiple of 4 (ie. 0,4,8,12,16,...)")
end
if not validate_fqdn(dns) then
    err("Not a valid DNS name")
end
if #cli_err == 0 then
    local net = "172.31." .. parms.server_net1 .. "." .. parms.server_net2
    cursor:set("vtun", "@network[0]", "start", net)
    cursor.set("vtun", "@network[0]", "dns", dns)
end

-- SAVE the clients
local enabled_count = 0
for i = 0,client_num-1
do
    local clientx_ = "client" .. i .. "_"
    local client_x = "client_" .. i

    local net = parms[clientx_ .. "netip"]
    local vtun_node_name = parms[clientx_ .. "name"]:sub(1,23) .. "-" .. net:gsub("%,", "-")
    local base = ip_to_decimal(net)
    local clientip = decimal_to_ip(base + 1)
    local serverip = decimal_to_ip(base + 2)

    cursor:set("vtun", client_x, "netip", net)
    cursor:set("vtun", client_x, "enabled", parms[clientx_ .. "enabled"])
    cursor:set("vtun", client_x, "name", parms[clientx_ .. "name"])
    cursor:set("vtun", client_x, "contact", parms[clientx_ .. "contact"])
    cursor:set("vtun", client_x, "passwd", parms[clientx_ .. "passwd"])
    cursor:set("vtun", client_x, "clientip", clientip)
    cursor:set("vtun", client_x, "serverip", serverip)
    cursor:set("vtun", client_x, "node", vtun_node_name)

    if parms[clientx_ .. "enabled"] == "1" then
        enabled_count = enabled_count + 1
    end
end
if enabled_count > 100 then
    err("Number of clients enabled (" .. enabled_count .. " exceeds maxclients (100); only the first 100 will activate.")
end

-- save configuration (commit)
if parms.button_save and #cli_err == 0 then
    cursor:commit("vtun")
    write_all("/etc/config.mesh/vtun", read_all("/etc/config/vtun"))
    os.execute("/etc/init.d/olsrd restart")
    os.execute("/etc/init.d/vtundsrv restart")
end

local active_tun = get_active_tun()

-- generate the page

http_header()
html.header(node .. "setup", true)
html.print("<body><center>")
html.alert_banner()
html.print("<form id=vpn method=post action=/cgi-bin/vpn enctype='multipart/form-data'>")
html.print("<form method=post action=test>")
html.print("<table width=790>")

-- navigation bar
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
if #cli_err > 0 then
    html.print("<tr><td align=center><b>ERROR:<br>")
    for _,msg in ipairs(cli_err)
    do
        html.print(msg .. "<br>")
    end
    html.print("</b></td></tr>")
end

if parms.button_save then
    if #cli_err > 0 then
        html.print("<tr><td align=center><b>Configuration NOT saved!</b></td></tr>")
    else
        html.print("<tr><td align=center><b>Configuration saved and is now active.</b></td></tr>")
    end
    html.print("<tr><td>&nbsp;</td></tr>")
end

-- everything else
if config == "mesh" then
    html.print("<tr><td align=center valign=top>")
    -- print vpn clients
    html.print("<table cellpadding=0 cellspacing=0>")
    
    html.print("<br /><tr class=tun_network_row><td colspan=6 align=center valign=top>Tunnel Server Network: ")
    html.print(netw[1] .. "." .. netw[2] .. ".")
    html.print("<input type='text' name='server_net1' size='3' maxlen='3' value='" .. netw[3] .. "' onChange='form.submit()' title='from 0-255' >")
    html.print(".")
    html.print("<input type='text' name='server_net2' size='3' maxlen='3' value='" .. netw[4] .. "' onChange='form.submit()' title='from 0-255 in multiples of 4. (ie. 0,4,8,12,16...252)' >")

    html.print("<br /><hr>Tunnel Server DNS Name: ")
    html.print("<input type='text' name='dns' size='30' value='" .. dns .. "' onChange='form.submit()' ></td></tr>")

    html.print("</table>")
    html.print("<table cellpadding=0 cellspacing=0>")
    html.print("<tr><th colspan=6 align=center valign=top>&nbsp;</th></tr>")
    html.print("<tr class=tun_client_row>")
    html.print("<tr><th colspan=6>Allow the following clients to connect to this server:</th></tr>")
    html.print("<tr><th colspan=6><hr></th></tr>")
    html.print("<tr><th>Enabled?</th><th>Client</th><th>Pwd</th><th>Net</th><th>Active&nbsp;</td><th>Action</th></tr>")

    -- loop
    local list = {}
    for i = 0,client_num-1
    do
        list[#list+1] = i
    end
    if client_num < 100 then
        list[#list+1] = "_add"
    end

    local keys = { "enabled", "name", "passwd", "contact" }
    local cnum = 0
    for _, val in ipairs(list)
    do
        for _, var in ipairs(keys)
        do
            _G[var] = parms["client" .. val .. "_" .. var]
        end
        if val == "_add" and #list > 1 then
            html.print("<tr class=tun_client_add_row><td height=10></td></tr>")
        end
        html.print("<tr class='tun_client_list2 tun_client_row'>")
        html.print("<td class='tun_client_center_item' rowspan='2'>")
        -- required to be first, so the checkbox is cleared, a value with still POST
        if val ~= "_add" then
            html.print("<input type='hidden' name='client" .. val .. "_enabled' value='0'>")
        end
        html.print("<input type='checkbox' name='client" .. val .. "_enabled' value='1'")
        if val ~= "_add" then
            html.print(" onChange='form.submit()'")
        end
        if enabled == "1" then
            html.print(" checked='checked'")
        end
        html.print(" title='enable this client'></td>")
        html.print("<td><input type=text size=40 name=client" .. val .. "_name value='" .. name .. "'")
        if val ~= "_add" then
            html.print(" onChange='form.submit()'")
        end
        html.print(" title='client name'></td>")
        html.print("<td><input type=text size=25 name=client" .. val .. "_passwd value='" .. passwd .. "' ")
        if val ~= "_add" then
            html.print(" onChange='form.submit()'")
        end
        html.print(" title='client password'></td>")
        
        -- handle rollover of netw
        local net
        if netw[4] + cnum * 4 > 252 then
            netw[3] = netw[3] + 1
            netw[4] = 0
            net = 0
            cnum = 0
        else
            net = cnum
        end
        local lastnet = netw[4] + net * 4
        local fullnet = netw[1] .. "." .. netw[2] .. "." .. netw[3] .. "." .. lastnet
        html.print("<td rowspan='2' class='tun_client_center_item'>&nbsp;" .. fullnet)
        html.print("<input type=hidden name=client" .. val .. "_netip value='" .. fullnet .. "'/></td>")
        html.print("<td rowspan='2' class='tun_client_center_item' align=center>&nbsp;")
        if val ~= "_add" and is_tunnel_active(val, active_tun) then
            html.print("<img class='tun_client_active_img' src='/connected.png' title='Connected' />")
        else
            html.print("<img class='tun_client_inactive_img' src='/disconnected.png' title='Not connected' />")
        end
        html.print("</td>")
        if val == "_add" then
            html.print("<td rowspan='2' class='tun_client_center_item'><input type=submit name=client_add value=Add title='Add this client'></td>")
        else
            html.print("<td rowspan='2' class='tun_client_center_item tun_client_mailto'><a href='mailto:?subject=AREDN%20Tunnel%20Connection&body=Your%20connection%20details:%0D%0AName:%20" .. name .. "%0D%0APassword:%20$" .. passwd .. "%0D%0ANetwork:%20" .. fullnet .. "%0D%0AServer%20address:%20" .. dns .. "'><img class='tun_client_mailto_img' src='/email.png' title='Email details' /></a></td>")
        end
        html.print("</tr><tr class='tun_client_list1 tun_client_row tun_loading_css_comment'><td colspan='2' align='right'>Contact Info/Comment (Optional): <input type=text maxlength='50' size=40 name=client" .. val .. "_contact value='" .. contact .."'")
        if val ~= "" and val ~= "_add" then
            html.print(" onChange='form.submit()'")
        end
        html.print(" title='client contact info'></td></tr>")

        -- display any errors
        if #cli_err > 0 then
            for i, err in ipairs(cli_err)
            do
                if err:match("^" .. val .. " ") then
                    html.print("<tr class=tun_client_error_row><th colspan=4>" .. err .. "</th></tr>")
                    cli_err:remove(i)
                end
            end
        end

        html.print("<tr><td colspan=4 height=4></td></tr>")
        cnum = cnum + 1
    end

    html.print("</table>")
    -- 
    html.print("</td></tr><tr><td><hr></td></tr>")
end
html.print("</table><p style='font-size:8px'>Tunnel v" .. VPNVER .. "</p>")
hide("<input type=hidden name=client_num value=" .. parms.client_num .. ">")

-- add hidden forms fields
for _, h in ipairs(hidden)
do
    html.print(h)
end

-- close the form
html.print("</form></center>")
html.footer()
html.print("</body></html>")
http_footer()
