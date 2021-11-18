#! /usr/bin/lua
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

-- do the initial setup of the essential nvram variables
-- node - node name
-- mac2 - last 3 bytes of wifi mac address in the form ddd.ddd.ddd
-- wifi_mac - full mac address of wireless card in the form hh:hh:hh:hh:hh:hh
--
-- intended to run every boot but it should only actually do anything
-- on the first boot

require("aredn.utils")
require("iwinfo")
require("aredn.hardware")
local aredn_info = require('aredn.info')

local wifi_mac = aredn_info.get_nvram("wifimac")
local mac2 = aredn_info.get_nvram("mac2")
local node = aredn_info.get_nvram("node")
local dtdmac = aredn_info.get_nvram("dtdmac")

local hardware_mac
if wifi_mac == "" or mac2 == "" then
    local wifiif = get_ifname("wifi")
    local phy = iwinfo.nl80211.phyname(wifiiface)
    for line in io.lines("/sys/class/ieee80211/" .. phy .. "/macaddress")
    do
        local m = line:match("(%w%w:%w%w:%w%w:%w%w:%w%w:%w%w)")
        if m then
            hardware_mac = m
            break
        end
    end
    if not hardware_mac then
        io.stderr:write("ERROR: hardware mac not found\n")
        os.exit(-1)
    end
end

if wifi_mac == "" then
    aredn_info.set_nvram("wifimac", hardware_mac)
end

if mac2 == "" then
    local a, b, c = hardware_mac:match("%w%w:%w%w:%w%w:(%w%w):(%w%w):(%w%w)")
    mac2 = string.format("%d.%d.%d", tonumber(a, 16), tonumber(b, 16), tonumber(c, 16))
    aredn_info.set_nvram("mac2", mac2)
end

if node == "" then
    aredn_info.set_nvram("node", "NOCALL-" .. mac2:gsub("%.", "-"))
end

if dtdmac == "" then
    local a, b, c = aredn.hardware.get_interface_mac(aredn.hardware.get_iface_name("lan")):match("%w%w:%w%w:%w%w:(%w%w):(%w%w):(%w%w)")
    aredn_info.set_nvram("dtdmac", string.format("%d.%d.%d", tonumber(a, 16), tonumber(b, 16), tonumber(c, 16)))
end
