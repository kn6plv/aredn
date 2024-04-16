import * as fs from "fs";
import * as uci from "uci";

let cursor;
let setup;

function initCursor()
{
    if (!cursor) {
        cursor = uci.cursor("/etc/local/uci");
    }
}

function initSetup()
{
    if (!setup) {
        setup = {};
        const f = fs.open("/etc/config.mesh/_setup");
        if (f) {
            for (;;) {
                const line = f.read("line");
                if (!length(line)) {
                    break;
                }
                const kv = split(rtrim(line), " = ");
                setup[kv[0]] = kv[1];
            }
            f.close();
        }
    }
}

export function getName()
{
    initCursor();
    return cursor.get("hsmmmesh", "settings", "node");
};

export function getDescription()
{
    initSetup();
    return setup.description_node;
};

export function getFirmwareVersion()
{
    return trim(fs.readfile("/etc/mesh-release"));
};

export function getTxPower()
{
    initSetup();
    return int(setup.wifi_txpower);
};

export function getDHCP()
{
    initSetup();
    const root = replace(setup.dmz_lan_ip, /\d+$/, "");
    const r = {
        enabled: setup.lan_dhcp ? true : false,
        start: `${root}${setup.dmz_dhcp_start}`,
        end: `${root}${setup.dmz_dhcp_end}`,
        gateway: setup.dmz_lan_ip,
        mask: setup.dmz_lan_mask,
        cidr: 32,
        leases: "/tmp/dhcp.leases",
        reservations: "/etc/config.mesh/_setup.dhcp.dmz"
    };
    switch (r.mask)
    {
        case "255.255.255.252":
            r.cidr = 30;
            break;
        case "255.255.255.248":
            r.cidr = 29;
            break;
        case "255.255.255.240":
            r.cidr = 28;
            break;
        case "255.255.255.224":
            r.cidr = 27;
            break;
    }
    return r;
};
