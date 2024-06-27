/*
 * Part of AREDN® -- Used for creating Amateur Radio Emergency Data Networks
 * Copyright (C) 2024 Tim Wilkinson
 * See Contributors file for additional contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation version 3 of the License.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 * Additional Terms:
 *
 * Additional use restrictions exist on the AREDN® trademark and logo.
 * See AREDNLicense.txt for more info.
 *
 * Attributions to the AREDN® Project must be retained in the source code.
 * If importing this code into a new or existing project attribution
 * to the AREDN® project must be added to the source code.
 *
 * You must not misrepresent the origin of the material contained within.
 *
 * Modified versions must be modified to attribute to the original source
 * and be marked in reasonable ways as differentiate it from the original
 * version
 */

import * as fs from "fs";
import * as uci from "uci";

let radioJson;
let boardJson;
const antennasCache = {};
const channelsCache = {};

export function getBoard()
{
    if (!boardJson) {
        const f = fs.open("/etc/board.json");
        if (!f) {
            return {};
        }
        boardJson = json(f.read("all"));
        f.close();
        // Collapse virtualized hardware into the two basic types
        if (index(boardJson.model.id, "qemu-") === 0) {
            boardJson.model.id = "qemu";
            boardJson.model.name = "QEMU";
        }
        else if (index(lc(boardJson.model.id), "vmware") === 0) {
            boardJson.model.id = "vmware";
            boardJson.model.name = "VMware";
        }
    }
    return boardJson;
};

export function getBoardId()
{
    let name = "";
    const board = getBoard();
    if (index(board.model.name, "Ubiquiti") === 0) {
        name = fs.readfile("/sys/devices/pci0000:00/0000:00:00.0/subsystem_device");
        if (!name || name === "" || name === "0x0000") {
            const f = fs.open("/dev/mtd7");
            if (f) {
                f.seek(12);
                const d = f.read(2);
                f.close();
                name = sprintf("0x%02x%02x", d[0], d[1]);
            }
        }
    }
    if (!name || name === "" || name === "0x0000") {
        name = board.model.name;
    }
    return trim(name);
};

export function getRadio()
{
    if (!radioJson) {
        const f = fs.open("/etc/radios.json");
        if (!f) {
            return {};
        }
        const radios = json(f.read("all"));
        f.close();
        const id = getBoardId();
        radioJson = radios[lc(id)];
        if (radioJson && !radioJson.name) {
            radioJson.name = id;
        }
    }
    return radioJson;
};

export function getRadioCount()
{
    const radio = getRadio();
    if (radio.wlan0) {
        if (radio.wlan1) {
            return 2;
        }
        else {
            return 1;
        }
    }
    else {
        let count = 0;
        const d = fs.opendir("/sys/class/ieee80211");
        if (d) {
            for (;;) {
                const l = d.read();
                if (!l) {
                    break;
                }
                if (l !== "." && l !== "..") {
                    count++;
                }
            }
            d.close();
        }
        return count;
    }
};

function getRadioIntf(wifiIface)
{
    const radio = getRadio();
    if (radio[wifiIface]) {
        return radio[wifiIface];
    }
    else {
        return radio;
    }
};

export function getRfChannels(wifiIface)
{
    let channels = channelsCache[wifiIface];
    if (!channels) {
        channels = [];
        const f = fs.popen("/usr/bin/iwinfo " + wifiIface + " freqlist");
        if (f) {
            let freq_adjust = 0;
            let freq_min = 0;
            let freq_max = 0x7FFFFFFF;
            if (wifiIface === "wlan0") {
                const radio = getRadio();
                if (index(radio.name, "M9") !== -1) {
                    freq_adjust = -1520;
                    freq_min = 907;
                    freq_max = 922;
                }
                else if (index(radio.name, "M3") !== -1) {
                    freq_adjust = -2000;
                    freq_min = 3380;
                    freq_max = 3495;
                }
            }
            for (;;) {
                const line = f.read("line");
                if (!line) {
                    break;
                }
                const fn = match(line, /(\d+\.\d+) GHz \(Band: .*, Channel (-?\d+)\)/);
                if (fn && index(line, "restricted") == -1 && index(line, "disabled") === -1) {
                    const freq = int(replace(fn[1], ".", "")) + freq_adjust;
                    if (freq >= freq_min && freq <= freq_max) {
                        const num = int(replace(fn[2], "0+", ""));
                        push(channels, {
                            label: freq_adjust === 0 ? num + " (" + freq + ")" : "" + freq,
                            number: num,
                            frequency: freq
                        });
                    }
                }
            }
            sort(channels, (a, b) => a.frequency - b.frequency);
            f.close();
            channelsCache[wifiIface] = channels;
        }
    }
    return channels;
};

export function getRfBandwidths(wifiIface)
{
    const radio = getRadioIntf(wifiIface);
    if (radio.bandwidths) {
        return radio.bandwidths;
    }
    else {
        return [ 5, 10, 20 ];
    }
};

export function getDefaultChannel(wifiIface)
{
    const rfchannels = getRfChannels(wifiIface);
    for (let i = 0; i < length(rfchannels); i++) {
        const c = rfchannels[i];
        if (c.frequency == 912) {
            return { channel: 5, bandwidth: 5, band: "900MHz" };
        }
        const bws = {};
        const b = getRfBandwidths(wifiIface);
        for (let j = 0; j < length(b); j++) {
            bws[b[j]] = b[j];
        }
        const bw = bws[10] || bws[20] || bws[5] || 0;
        if (c.frequency === 2397) {
            return { channel: -2, bandwidth: bw, band: "2.4GHz" };
        }
        if (c.frequency === 2412) {
            return { channel: 1, bandwidth: bw, band: "2.4GHz" };
        }
        if (c.frequency === 3420) {
            return { channel: 84, bandwidth: bw, band: "3GHz" };
        }
        if (c.frequency === 5745) {
            return { channel: 149, bandwidth: bw, band: "5GHz" };
        }
    }
    return null;
};

export function getAntennas(wifiIface)
{
    let ants = antennasCache[wifiIface];
    if (!ants) {
        const radio = getRadioIntf(wifiIface);
        if (radio && radio.antenna) {
            if (radio.antenna === "external") {
                const dchan = getDefaultChannel(wifiIface);
                if (dchan && dchan.band) {
                    const f = fs.open("/etc/antennas.json");
                    if (f) {
                        ants = json(f.read("all"));
                        f.close();
                        ants = ants[dchan.band];
                    }
                }
            }
            else {
                radio.antenna.builtin = true;
                ants = [ radio.antenna ];
            }
            antennasCache[wifiIface] = ants;
        }
    }
    return ants;
};

export function getAntennasAux(wifiIface)
{
    let ants = antennasCache["aux:" + wifiIface];
    if (!ants) {
        const radio = getRadioIntf(wifiIface);
        if (radio && radio.antenna_aux === "external") {
            const dchan = getDefaultChannel(wifiIface);
            if (dchan && dchan.band) {
                const f = fs.open("/etc/antennas.json");
                if (f) {
                    ants = json(f.read("all"));
                    f.close();
                    ants = ants[dchan.band];
                }
            }
            antennasCache["aux:" + wifiIface] = ants;
        }
    }
    return ants;
};

export function getAntennaInfo(wifiIface, antenna)
{
    const ants = getAntennas(wifiIface);
    if (ants) {
        if (length(ants) === 1) {
            return ants[0];
        }
        if (antenna) {
            for (let i = 0; i < length(ants); i++) {
                if (ants[i].model === antenna) {
                    return ants[i];
                }
            }
        }
    }
    return null;
};

export function getAntennaAuxInfo(wifiIface, antenna)
{
    const ants = getAntennasAux(wifiIface);
    if (ants) {
        if (length(ants) === 1) {
            return ants[0];
        }
        if (antenna) {
            for (let i = 0; i < length(ants); i++) {
                if (ants[i].model === antenna) {
                    return ants[i];
                }
            }
        }
    }
    return null;
};

export function getChannelFrequency(wifiIface, channel)
{
    const rfchans = getRfChannels(wifiIface);
    if (rfchans[0]) {
        for (let i = 0; i < length(rfchans); i++) {
            const c = rfchans[i];
            if (c.number === channel) {
                return c.frequency;
            }
        }
    }
    return null;
};

export function getChannelFrequencyRange(wifiIface, channel, bandwidth)
{
    const rfchans = getRfChannels(wifiIface);
    if (rfchans[0]) {
        for (let i = 0; i < length(rfchans); i++) {
            const c = rfchans[i];
            if (c.number === channel) {
                return (c.frequency - bandwidth / 2) + " - " + (c.frequency + bandwidth / 2) + " MHz";
            }
        }
    }
    return null;
};

export function getChannelFromFrequency(freq)
{
    if (freq < 256) {
        return null;
    }
    if (freq === 2484) {
        return 14;
    }
    if (freq === 2407) {
        return 0;
    }
    if (freq < 2484) {
        return (freq - 2407) / 5;
    }
    if (freq < 5000) {
        return null;
    }
    if (freq < 5380) {
        return (freq - 5000) / 5;
    }
    if (freq < 5500) {
        return freq - 2000;
    }
    if (freq < 6000) {
        return (freq - 5000) / 5;
    }
};

export function getMaxTxPower(wifiIface, channel)
{
    const radio = getRadioIntf(wifiIface);
    if (radio) {
        const maxpower = radio.maxpower;
        const chanpower = radio.chanpower;
        if (channel && chanpower) {
            for (let k in chanpower) {
                if (channel <= k) {
                    return chanpower[k];
                }
            }
        }
        if (maxpower) {
            return maxpower;
        }
    }
    return 27;
};

export function getTxPowerOffset(wifiIface)
{
    const radio = getRadioIntf(wifiIface);
    if (radio && radio.pwroffset) {
        return radio.pwroffset;
    }
    const f = fs.popen("/usr/bin/iwinfo " + wifiIface + " info");
    if (f) {
        for (;;) {
            const line = f.read("line");
            if (!line) {
                break;
            }
            if (index(line, "TX power offset: ") !== -1) {
                const pwroff = match(line, /TX power offset: (\d+)/);
                if (pwroff) {
                    f.close();
                    return int(pwroff[1]);
                }
                return 0;
            }
        }
        f.close();
    }
    return 0;
};

export function supportsXLink()
{
    switch (getBoard().model.id) {
        case "mikrotik,hap-ac2":
        case "mikrotik,hap-ac3":
        case "glinet,gl-b1300":
        case "qemu":
        case "vmware":
            return true;
        default:
            return false;
    }
};

const default5PortLayout = [ "wan", "lan1", "lan2", "lan3", "lan4" ];
const default3PortLayout = [ "lan2", "lan1", "wan" ];
const defaultNPortLayout = [];

export function getEthernetPorts()
{
    switch (getBoard().model.id) {
        case "mikrotik,hap-ac2":
        case "mikrotik,hap-ac3":
            return default5PortLayout;
        case "glinet,gl-b1300":
            return default3PortLayout;
        case "qemu":
        case "vmware":
            if (length(defaultNPortLayout) === 0) {
                const dir = fs.opendir("/sys/class/net");
                if (dir) {
                    for (;;) {
                        const file = dir.read();
                        if (!file) {
                            break;
                        }
                        if (match(file, /^eth\d+$/)) {
                            push(defaultNPortLayout, file);
                        }
                    }
                    dir.close();
                    sort(defaultNPortLayout);
                }
            }
            return defaultNPortLayout;
        default:
            return [];
    }
};

export function getEthernetPortInfo(port)
{
    const s = { active: false };
    if (fs.readfile(`/sys/class/net/${port}/carrier`, 1) === "1") {
        s.active = true;
    }
    return s;
};

export function getDefaultNetworkConfiguration()
{
    const c = {
        dtdlink: { vlan: 2, ports: { eth0: true } },
        lan: { vlan: 0, ports: { eth0: true } },
        wan: { vlan: 1, ports: { eth0: true } },
    };
    const board = getBoard();
    const network = board.network;
    for (let k in network) {
        if (c[k]) {
            const devices = split(network[k].device, " ");
            for (let i = 0; i < length(devices); i++) {
                const m = match(devices[i], /^([^\.])\.?(\d*)$/);
                if (m) {
                    c[k].ports[m[1]] = true;
                    c[k].vlan = int(m[2] || 0);
                }
            }
        }
    }
    return c;
};

export function hasPOE()
{
    const board = getBoard();
    if (board?.gpioswitch?.poe_passthrough?.pin) {
        return true;
    }
    // Handle typo
    if (board?.gpioswitch?.poe_passtrough?.pin) {
        return true;
    }
    const gpios = fs.lsdir("/sys/class/gpio/");
    for (let i = 0; i < length(gpios); i++) {
        if (match(gpios[i], /^enable-poe:/)) {
            return true;
        }
    }
    return false;
};

export function hasUSBPower()
{
    const board = getBoard();
    if (board?.gpioswitch?.usb_power_switch?.pin) {
        return true;
    }
    if (fs.access("/sys/class/gpio/usb-power")) {
        return true;
    }
    return false;
};
