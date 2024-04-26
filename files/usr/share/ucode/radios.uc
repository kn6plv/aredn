import * as hardware from "hardware";
import * as uci from "uci";
import * as settings from "settings";

export const RADIO_OFF = 0;
export const RADIO_MESH = 1;
export const RADIO_LAN = 2;
export const RADION_WAN = 3;

export function getCommonConfiguration()
{
    const radio = [];
    const nrradios = hardware.getRadioCount();
    for (let i = 0; i < nrradios; i++) {
        const iface = `wlan${i}`;
        radio[i] = {
            iface: iface,
            mode: 0,
            modes: [],
            ant: null,
            antaux: null,
            def: hardware.getDefaultChannel(iface),
            bws: hardware.getRfBandwidths(iface),
            channels: hardware.getRfChannels(iface),
            ants: hardware.getAntennas(iface),
            antsaux: hardware.getAntennasAux(iface),
            txpoweroffset: hardware.getTxPowerOffset(iface),
            txmaxpower: hardware.getMaxTxPower(iface)
        };
    }
    return radio;
};

export function getActiveConfiguration()
{
    const cursor = uci.cursor();
    const radio = getCommonConfiguration();
    const nrradios = length(radio);
    if (nrradios > 0) {
        const meshrf = cursor.get("network", "wifi", "device");
        const widx = match(meshrf, /^wlan(\d+)$/);
        if (widx) {
            let device;
            const mode = {
                channel: 0,
                bandwidth: 10,
                ssid: "AREDN",
                txpower: settings.getSettingAsInt("wifi_txpower")
            };
            cursor.foreach("wireless", "wifi-iface", function(s)
            {
                if (s.network === "wifi" && s.ifname === meshrf) {
                    device = s.device;
                    mode.ssid = s.ssid;
                    return false;
                }
            });
            cursor.foreach("wireless", "wifi-device", function(s)
            {
                if (s[".name"] === device) {
                    mode.channel = int(s.channel);
                    mode.bandwidth = int(s.chanbw);
                    return false;
                }
            });
            radio[widx[1]].mode = 1;
            radio[widx[1]].modes = [ null, mode, null, null ];
        }
    }
    return radio;
};

export function getConfiguration()
{
    const cursor = uci.cursor("/etc/config.mesh");
    const radio = getCommonConfiguration();
    const nrradios = length(radio);
    if (nrradios > 0) {
        const modes = [ null, {
            channel: settings.getSettingAsInt("wifi_channel"),
            bandwidth: settings.getSettingAsInt("wifi_chanbw", 10),
            ssid: settings.getSettingAsString("wifi_ssid", "AREDN"),
            txpower: settings.getSettingAsInt("wifi_txpower", 27)
        },
        {
            channel: settings.getSettingAsInt("wifi2_channel"),
            encryption: settings.getSettingAsString("wifi2_encryption", "psk2"),
            key: settings.getSettingAsString("wifi2_key", ""),
            ssid: settings.getSettingAsString("wifi2_ssid", "")
        },
        {
            key: settings.getSettingAsString("wifi3_key", ""),
            ssid: settings.getSettingAsString("wifi3_ssid", "")
        }];
        for (let i = 0; i < nrradios; i++) {
            radio[i].modes = modes;
        }

        radio[0].ant = hardware.getAntennaInfo(radio[0].iface, cursor.get("aredn", "@location[0]", "antenna"));
        radio[0].antaux = hardware.getAntennaAuxInfo(radio[0].iface, cursor.get("aredn", "@location[0]", "antenna_aux"));

        const wifi_enable = settings.getSettingAsInt("wifi_enable", 0);
        const wifi2_enable = settings.getSettingAsInt("wifi2_enable", 0);
        const wifi3_enable = settings.getSettingAsInt("wifi3_enable", 0);
        if (nrradios === 1) {
            if (wifi_enable) {
                radio[0].mode = 1;
            }
            else if (wifi2_enable) {
                radio[0].mode = 2;
            }
            else if (wifi3_enable) {
                radio[0].mode = 3;
            }
        }
        else if (wifi_enable) {
            const wifi_iface = settings.getSettingAsString("wifi_intf", "wlan0");
            if (wifi_iface === "wlan0") {
                radio[0].mode = 1;
                if (wifi2_enable) {
                    radio[1].mode = 2;
                }
                else if (wifi3_enable) {
                    radio[1].mode = 3;
                }
            }
            else {
                radio[1].mode = 1;
                if (wifi2_enable) {
                    radio[0].mode = 2;
                }
                else if (wifi3_enable) {
                    radio[0].mode = 3;
                }
            }
        }
        else if (wifi2_enable) {
            const wifi2_hwmode = settings.getSettingAsString("wifi2_hwmode", "11a");
            if ((wifi2_hwmode === "11a" && radio[0].def.band === "5GHz") || (wifi2_hwmode === "11g" && radio[0].def.band === "2.4GHz")) {
                radio[0].mode = 2;
                if (wifi3_enable) {
                    radio[1].mode = 3;
                }
            }
            else {
                radio[1].mode = 2;
                if (wifi3_enable) {
                    radio[0].mode = 3;
                }
            }
        }
        else if (wifi3_enable) {
            const wifi3_hwmode = settings.getSettingAsString("wifi3_hwmode", "11a");
            if ((wifi3_hwmode === "11a" && radio[0].def.band === "5GHz") || (wifi3_hwmode === "11g" && radio[0].def.band === "2.4GHz")) {
                radio[0].mode = 3;
            }
            else {
                radio[1].mode = 3;
            }
        }
    }
    return radio;
};
