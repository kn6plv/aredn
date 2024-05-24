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