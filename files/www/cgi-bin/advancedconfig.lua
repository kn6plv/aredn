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
require("aredn.hardware")
require("aredn.http")
require("aredn.utils")
aredn.html = require("aredn.html")
require("uci")
aredn.info = require("aredn.info")

local html = aredn.html

local urlprefix
local target = "unknown"
function defaultPackageRepos(repo)
    if not urlprefix then
        urlprefix = "http://downloads.arednmesh.org"
        local release = "unknown"
        for line in io.lines("/etc/openwrt_release")
        do
            local m = line:match("DISTRIB_RELEASE='(.*)'")
            if m then
                release = m
            end
            m = line:match("DISTRIB_TARGET='(.*)'")
            if m then
                target = m
            end
        end
        if release:match("%.") then
            local a, b = release:match("^(%d+)%.(%d+)%.")
            urlprefix = urlprefix .. "/releases/" .. a .. "/" .. b .. "/" .. release
        else
            -- nightly
            urlprefix = urlprefix .. "/snapshots/trunk"
        end
    end
    if repo:match("aredn_core") then
        return urlprefix .. "/targets/" .. target .. "/packages"
    else
        return urlprefix .. "/packages/mips_24kc/" .. repo
    end
end

local settings = {
    {
        key = "aredn.@map[0].maptiles",
        type = "string",
        desc = "Specifies the URL of the location to access map tiles",
        default = "http://stamen-tiles-{s}.a.ssl.fastly.net/terrain/{z}/{x}/{y}.jpg"
    },
    {
        key = "aredn.@map[0].leafletcss",
        type = "string",
        desc = "Specifies the URL of the leaflet.css file",
        default = "http://cdn.leafletjs.com/leaflet/v0.7.7/leaflet.css"
    },
    {
        key = "aredn.@map[0].leafletjs",
        type = "string",
        desc = "Specifies the URL of the leaflet.js file",
        default = "http://cdn.leafletjs.com/leaflet/v0.7.7/leaflet.js"
    },
    {
        key = "aredn.@downloads[0].firmwarepath",
        type = "string",
        desc = "Specifies the URL of the location from which firmware files will be downloaded.",
        default = "http://downloads.arednmesh.org/firmware"
    },
    {
        key = "aredn.@downloads[0].pkgs_core",
        type = "string",
        desc = "Specifies the URL for the 'core' packages: kernel modules and the like",
        default = defaultPackageRepos('aredn_core'),
        postcallback = "writePackageRepo('core')"
    },
    {
        key = "aredn.@downloads[0].pkgs_base",
        type = "string",
        desc = "Specifies the URL for the 'base' packages: libraries, shells, etc.",
        default = defaultPackageRepos('base'),
        postcallback = "writePackageRepo('base')"
    },
    {
        key = "aredn.@downloads[0].pkgs_arednpackages",
        type = "string",
        desc = "Specifies the URL for the 'arednpackages' packages: vtun, etc.",
        default = defaultPackageRepos('arednpackages'),
        postcallback = "writePackageRepo('arednpackages')"
    },
    {
        key = "aredn.@downloads[0].pkgs_luci",
        type = "string",
        desc = "Specifies the URL for the 'luci' packages: luci and things needed for luci.",
        default = defaultPackageRepos('luci'),
        postcallback = "writePackageRepo('luci')"
    },
    {
        key = "aredn.@downloads[0].pkgs_packages",
        type = "string",
        desc = "Specifies the URL for the 'packages' packages: everything not included in the other dirs.",
        default = defaultPackageRepos('packages'),
        postcallback = "writePackageRepo('packages')"
    },
    {
        key = "aredn.@downloads[0].pkgs_routing",
        type = "string",
        desc = "Specifies the URL for the 'routing' packages: olsr, etc.",
        default = defaultPackageRepos('routing'),
        postcallback = "writePackageRepo('routing')"
    },
    {
        key = "aredn.@downloads[0].pkgs_telephony",
        type = "string",
        desc = "Specifies the URL for the 'telephony' packages.",
        default = defaultPackageRepos('telephony'),
        postcallback = "writePackageRepo('telephony')"
    },
    {
        key = "aredn.@downloads[0].pkgs_freifunk",
        type = "string",
        desc = "Specifies the URL for the 'freifunk' packages.",
        default = defaultPackageRepos('freifunk'),
        postcallback = "writePackageRepo('freifunk')"
    },
        
    {
        key = "aredn.@poe[0].passthrough",
        type = "boolean",
        desc = "Specifies whether a PoE passthrough port should be on or off.  (Not all devices have PoE passthrough ports.",
        default = "0",
        condition = "hasPOE()",
        postcallback = "setPOEOutput()"
    },
    {
        key = "aredn.@usb[0].passthrough",
        type = "boolean",
        desc = "Specifies whether the USB port should be on or off.  (Not all devices have USB powered ports.",
        default = "1",
        postcallback = "setUSBOutput()",
        condition = "hasUSB()"
    },
    {
        key = "aredn.@tunnel[0].maxclients", 
        type = "string", 
        desc = "Specifies the maximum number of tunnel clients this node can serve; must be an integer in the range [0,100].  (Only applies if tunnel software is installed)", 
        default = "10", 
        condition = "hasTunnelSoftware()",
        precallback = "restrictTunnelLimitToValidRange()",
        postcallback = "adjustTunnelInterfaceCount()"
    },
    {
        key = "aredn.@tunnel[0].maxservers", 
        type = "string", 
        desc = "Specifies the maximum number of tunnel servers to which this node can connect; must be an integer in the range [0,100].  (Only applies if tunnel software is installed)", 
        default = "10", 
        condition = "hasTunnelSoftware()",
        precallback = "restrictTunnelLimitToValidRange()",
        postcallback = "adjustTunnelInterfaceCount()"
    },
    {
        key = "aredn.@meshstatus[0].lowmem",
        type = "string",
        desc = "Specifies the low memory threshold (in KB) when we will truncate the mesh status page",
        default = "10000"
    },
    {
        key = "aredn.@meshstatus[0].lowroutes",
        type = "string",
        desc = "When low memory is detected, limit the number of routes shown on the mesh status page",
        default = "1000"
    },
    {
        key = "aredn.olsr.restart",
        type = "none",
        desc = "Will restart OLSR when saving setting -- wait up to 2 or 3 minutes to receive response.",
        default = "0",
        postcallback = "olsr_restart()"
    },
    {
        key = "aredn.aam.refresh",
        type = "none",
        desc = "Attempt to pull any AREDN Alert messages.",
        default = "0",
        postcallback = "aam_refresh()"
    },
    {
        key = "aredn.@alerts[0].localpath",
        type = "string",
        desc = "Specifies the URL of the location from which local AREDN Alerts can be downloaded.",
        default = ""
    },
    {
        key = "aredn.aam.purge",
        type = "none",
        desc = "Immediately purge/delete all AREDN (and local) Alerts from this node.",
        default = "",
        postcallback = "alert_purge()"
    }
}

local msgs = {}

--
-- helpers
--
function msg(m)
    msgs[#msgs + 1] = m
end

function reboot()
    local node = aredn.info.get_nvram("node")
    if node == "" then
        node = "Node"
    end
    local lanip, _, lanmask = aredn.hardware.get_interface_ip4(aredn.hardware.get_iface_name("lan"))
    local browser = os.getenv("REMOTE_ADDR"):match("::ffff:([%d%.]+)")
    local fromlan = false
    local subnet_change = false
    if lanip then
        fromlan = validate_same_subnet(browser, lanip, lanmask)
        if fromlan then
            lanmask = ip_to_decimal(lanmask)
            local cfgip = cursor_get("network", "lan", "ipaddr")
            local cfgmask = ip_to_decimal(cursor_get("network", "lan", "netmask"))
            if lanmask ~= cfgmask or decimal_to_ip(nixio.bit.band(ip_to_decimal(ip), lanmask)) ~= nixio.bit.band(ip_to_decimal(cfgip), cfgmask) then
                subnet_change = true
            end
        end
    end
    http_header()
    if fromlan and subnet_change then
        html.header(node .. " rebooting", true);
        html.print("<body><center>")
        html.print("<h1>" .. node .. " is rebooting</h1><br>")
        html.print("<h3>The LAN subnet has changed. You will need to acquire a new DHCP lease<br>")
        html.print("and reset any name service caches you may be using.</h3><br>")
        html.print("<h3>When the node reboots you get your new DHCP lease and reconnect with<br>")
        html.print("<a href='http://localnode.local.mesh:8080/'>http://localnode.local.mesh:8080/</a><br>or<br>")
        html.print("<a href='http://" .. node .. ".local.mesh:8080/'>http://" .. node .. ".local.mesh:8080/</a></h3>")
    else
        html.header(node .. " rebooting", false)
        html.print("<meta http-equiv='refresh' content='60;url=/cgi-bin/status.lua'>")
        html.print("</head><body><center>")
        html.print("<h1>" .. node .. " is rebooting</h1><br>")
        html.print("<h3>Your browser should return to this node in 60 seconds.</br><br>")
        html.print("If something goes astray you can try to connect with<br><br>")
        html.print("<a href='http://localnode.local.mesh:8080/'>http://localnode.local.mesh:8080/</a><br>")
        if node ~= "Node" then
            html.print("or<br><a href='http://" .. node .. ".local.mesh:8080/'>http://" .. node .. ".local.mesh:8080/</a></h3>")
        end
    end
    html.print("</center></body></html>")
    http_footer()
    luci.sys.reboot()
    os.exit()
end

-- uci cursor
local cursora = uci:cursor()
local cursorb = uci:cursor("/etc/config.mesh")
function cursor_set(a, b, c, d)
    cursora:set(a, b, c, d)
    cursorb:set(a, b, c, d)
    cursora:commit(a)
    cursorb:commit(a)
end

function cursor_add(a, b, c)
    cursora:set(a, b, c)
    cursorb:set(a, b, c)
    cursora:commit(a)
    cursorb:commit(a)
end

function cursor_delete(a, b)
    cursora:delete(a, b)
    cursorb:delete(a, b)
    cursora:commit(a)
    cursorb:commit(a)
end

function cursor_get(a, b, c)
    return cursora:get(a, b, c)
end

-- conditionals

function hasPOE()
    return aredn.hardware.has_poe()
end

function hasUSB()
    return aredn.hardware.has_usb()
end

function hasTunnelSoftware()
    if nixio.fs.stat("/usr/sbin/vtund") then
        return true
    else
        return false
    end
end

-- callbacks

local newval
local key

function setPOEOutput()
    if not newval then
        newval = 0
    end
    os.execute("/usr/local/bin/poe_passthrough " .. newval)
end

function setUSBOutput()
    if not newval then
        newval = 0
    end
    os.execute("/usr/local/bin/usb_passthrough " .. newval)
end

function olsr_restart()
    os.execute("/etc/init.d/olsrd restart")
end

function aam_refresh()
    os.execute("/usr/local/bin/aredn_message.sh")
end

function alert_purge()
    os.remove("/tmp/aredn_message")
    os.remove("/tmp/local_message")
end

function writePackageRepo(repo)
    local uciurl = cursor_get("aredn", "@downloads[0]", "pkgs_" .. repo):chomp()
    local disturl = capture("grep aredn_" .. repo .. " /etc/opkg/distfeeds.conf | cut -d' ' -f3"):chomp()
    os.execute("sed -i 's|" .. disturl .. "|" .. uciurl .. "|g' /etc/opkg/distfeeds.conf")
end

function restrictTunnelLimitToValidRange()
    newval = tonumber(newval)
    if not newval then
        msg(key .. " must be an interger in the range [0,100]")
        newval = 0
    elseif newval < 0 then
        msg("Lower limit of " .. key .. " is 0")
        newval = 0
    elseif newval > 100 then
        msg("Hipper limit of " .. key .. " is 100")
        newval = 100
    end
end

function addTunnelInterface(file, tunnum)
    local section = "tun" .. tunnum
    cursor_add(file, section, "interface")
    cursor_set(file, section, "ifname", section)
    cursor_set(file, section, "proto", "none")
end

function deleteTunnelInterface(file, tunnum)
    local section = "tun" .. tunnum
    cursor_delete(file, section)
end

function adjustTunnelInterfaceCount()
    local tunnel_if_count = 0
    cursora:foreach('network_tun', 'interface', function(s) tunnel_if_count = tunnel_if_count + 1 end)
    local maxclients = cursor_get("aredn", "tunnel", "maxclients")
    if not maxclients then
        maxclients = 10
    end
    local maxservers = cursor_get("aredn", "tunnel", "maxservers")
    if not maxservers then
        maxservers = 10
    end
    local needed_if_count = maxclients + maxservers
    if tunnel_if_count ~= needed_if_count then
        for i = tunnel_if_count,needed_if_count-1
        do
            local tunnum = 50 + i
            addTunnelInterface("network_tun", tunnum)
            addTunnelInterface("network", tunnum)
        end
        for i = tunnel_if_count-1,needed_if_count,-1
        do
            local tunnum = 50 + i
            deleteTunnelInterface("network_tun", tunnum)
            deleteTunnelInterface("network", tunnum)
        end
        -- can't clone network because it contains macros; re-edit it instead
        os.execute("sed -i -e '$r /etc/config.mesh/network_tun' -e '/interface.*tun',$d' /etc/config.mesh/network") 
    end
end

-- read_postdata
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

if parms.button_firstboot then
    os.execute("firstboot -y")
end
if parms.button_firstboot or parms.button_reboot then
    reboot()
end
local node = aredn.info.get_nvram("node");

for i, setting in ipairs(settings)
do
    if parms["button_save_" .. i] then
        newval = parms["newval_" .. i]
        newval = newval:gsub("^%s+", ""):gsub("%s+$", "")
        if setting.type == "boolean" then
            if newval == "1" or newval == "true" then
                newval = "1"
            else
                newval = "0"
            end
        end
        key = setting.key
        if setting.precallback then
            loadstring(setting.precallback)()
        end
        local a, b, c = setting.key:match("(.+)%.(.+)%.(.*)")
        cursor_set(a, b, c, newval)
        msg("Changed " .. key)
        if setting.postcallback then
            loadstring(setting.postcallback)()
        end
        break
    end
end

-- generate the page

http_header()
html.header(node .. " Advanced Configuration", false)
html.print([[
<style>
/* The switch - the box around the slider */
.switch {
    position: relative;
    display: inline-block;
    width: 60px;
    height: 34px;
}

/* Hide default HTML checkbox */
.switch input {
    opacity: 0;
    width: 0;
    height: 0;
}

/* The slider */
.slider {
    position: absolute;
    cursor: pointer;
    top: 0;
    left: 0;
    right: 0;
    bottom: 0;
    background-color: #ccc;
    -webkit-transition: .4s;
    transition: .4s;
}

.slider:before {
    position: absolute;
    content: "";
    height: 26px;
    width: 26px;
    left: 4px;
    bottom: 4px;
    background-color: white;
    -webkit-transition: .4s;
    transition: .4s;
}

input:checked + .slider {
    background-color: #2196F3;
}

input:focus + .slider {
    box-shadow: 0 0 1px #2196F3;
}

input:checked + .slider:before {
    -webkit-transform: translateX(26px);
    -ms-transform: translateX(26px);
    transform: translateX(26px);
}

/* Rounded sliders */
.slider.round {
    border-radius: 34px;
}

.slider.round:before {
    border-radius: 50%;
}
</style>

<script>
function toggleDefault(fname, defval) {
    if(document.getElementById(fname).checked) {
    cval = '1'
    } else {
    cval = '0'
    }
    if(cval != defval) {
    document.getElementById(fname).click();
    }
    return true;
}
</script>
</head>
]])

html.print("<body><center>")
html.alert_banner();
html.print("<div style=\"padding:5px;background-color:#FF0000;color:#FFFFFF;width:650px;\"><strong>WARNING:</strong> Changing advanced settings can be harmful to the stability, security, and performance of this node and potentially the entire mesh network.<br><strong>You should only continue if you are sure of what you are doing.</strong></div><form method=post action=advancedconfig.lua enctype='multipart/form-data'><table width=790><tr><td>")

-- navbar
html.print("<hr><table cellpadding=5 border=0 width=100%><tr>")
html.print("<td align=center width=15%><a href='status.lua'>Node Status</a></td>")
html.print("<td align=center width=15%><a href='setup.lua'>Basic Setup</a></td>")
html.print("<td align=center width=15%><a href='ports'>Port Forwarding,<br>DHCP, and Services</a></td>")
html.print("<td align=center width=15%><a href='vpn.lua'>Tunnel<br>Server</a></td>")
html.print("<td align=center width=15%><a href='vpnc.lua'>Tunnel<br>Client</a></td>")
html.print("<td align=center width=15%><a href='admin'>Administration</a></td>")
html.print("<td align=center width=15% class=navbar_select><a href='advancedconfig.lua'>Advanced<br>Configuration</a></td>")
html.print("</tr></table><hr>")
html.print("</td></tr>")

html.print("<tr><td align=center><a href='/help.html#advancedconfig' target='_blank'>Help</a>&nbsp;&nbsp;<input type=submit name=button_reboot value=Reboot style='font-weight:bold' title='Immediately reboot this node'>&nbsp;&nbsp;<input type=submit name=button_firstboot value='Reset to Firstboot' onclick=\"return confirm('All config settings and add-on packages will be lost back to first boot state. Continue?')\"  title='Reset this node to the initial/firstboot status and reboot.'></td></tr>")

for _, m in ipairs(msgs)
do
    html.print("<tr><td align='center'><strong>" .. m .. "</strong></td></tr>")
end

html.print([[
<tr><td align=center>
<table border=1>
<thead>
    <tr>
    <th>Help<br><small>(hover)</small></th>
    <th>Config Setting</th>
    <th>Value</th>
    <th>Actions</th>
    </tr>
</thead>
]])

-- settings

for i, setting in ipairs(settings)
do
    if not setting.condition or loadstring(setting.condition)() then
        local a, b, c = setting.key:match("(.+)%.(.+)%.(.*)")
        local sval = cursor_get(a, b, c)
        if not sval then
            sval = ""
        end
        html.print([[<tr><td align="center"><span title="]] .. setting.desc .. [["><img src="/qmark.png" /></span></td><td>]] .. setting.key .. [[</td><td>]])
        if setting.type == "string" then
            html.print("<input type='text' id='field_" .. i .. "' name='newval_" .. i .. "' size='65' value='" .. sval .. "'>")
        elseif setting.type == "boolean" and sval == "1" then
            html.print("OFF<label class='switch'><input type='checkbox' id='field_" .. i .. "' name='newval_" .. i .."' value='1' checked><span class='slider round'></span></label>ON")
        elseif setting.type == "boolean" and sval == "0" then
            html.print("OFF<label class='switch'><input type='checkbox' id='field_" .. i .. "' name='newval_" .. i .. "' value='1'><span class='slider round'></span></label>ON")
        elseif setting.type == "none" then
            html.print("Click EXECUTE button to trigger this action<input type='hidden' id='field_" .. i .. "' name='newval_" .. i .."' value='" .. sval .."'>")
        end
        html.print("</td>")
        if setting.type ~= "none" then
            html.print("<td align='center'><input type='submit' name='button_save_" .. i .. "' value='Save Setting' /><br><br>")
        else
            html.print("<td align='center'><input type='submit' name='button_save_" .. i .. "' value='Execute' /><br><br>")
        end
        if setting.type == "string" then
            html.print("<input value='Set to Default' type='button' onclick=\"document.getElementById('field_" .. i .. "').value='" .. setting.default .. "';\">")
        elseif setting.type == "boolean" then
            html.print("<input value='Set to Default' type='button' onclick=\"return toggleDefault('field_" .. i .. "', '" .. setting.default .. "' );\">")
        end
        html.print("</td></tr>")
    end
end

html.print("</table></td></tr></table></form></center>")
html.footer()
html.print("</body></html>")
http_footer()
