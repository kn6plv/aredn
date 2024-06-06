import * as fs from "fs";
import * as uci from "uci";
import * as math from "math";
import * as network from "aredn.network";

let cursor;
let setup;
let setupKeys;
let setupChanged = false;
let firmwareVersion = null;

const currentConfig = "/tmp/config.current";
const currentArednInclude = "/tmp/aredn_include.current";
const arednIncludes = [ "dtdlink.network.user", "lan.network.user", "wan.network.user" ];

function initCursor()
{
    if (!cursor) {
        cursor = uci.cursor("/etc/local/uci");
    }
};

function initSetup()
{
    if (!setup) {
        setup = {};
        setupKeys = [];
        const f = fs.open("/etc/config.mesh/_setup");
        if (f) {
            for (;;) {
                const line = f.read("line");
                if (!length(line)) {
                    break;
                }
                const kv = split(line, " =");
                setup[kv[0]] = trim(kv[1]);
                push(setupKeys, kv[0]);
            }
            f.close();
        }
    }
};

export function getSettingAsString(key, def)
{
    initSetup();
    return setup[key] || def;
};

export function getSettingAsInt(key, def)
{
    initSetup();
    const v = int(setup[key]);
    if (type(v) === "int") {
        return v;
    }
    return def;
};

export function setSetting(key, value, def)
{
    initSetup();
    const old = setup[key];
    setup[key] = `${value || def}`;
    if (old !== setup[key]) {
        setupChanged = true;
        return true;
    }
    return false;
};

export function saveSettings()
{
    if (setupChanged) {
        const f = fs.open("/etc/config.mesh/_setup", "w");
        if (f) {
            for (let i = 0; i < length(setupKeys); i++) {
                const k = setupKeys[i];
                f.write(`${k} = ${setup[k] || ""}\n`);
            }
            f.close();
            setupChanged = false;
        }
    }
};

export function getName()
{
    initCursor();
    return cursor.get("hsmmmesh", "settings", "node");
};

export function getFirmwareVersion()
{
    if (firmwareVersion === null) {
        firmwareVersion = trim(fs.readfile("/etc/mesh-release"));
    }
    return firmwareVersion;
};

export function setUpgrade(v)
{
    initCursor();
    cursor.set("hsmmmesh", "settings", "nodeupgraded", v);
    cursor.commit("hsmmmesh");
};

export function getDHCP(mode)
{
    initSetup();
    if (mode === "nat" || (setup.dmz_mode === "0" && !mode)) {
        const root = replace(setup.lan_ip, /\d+$/, "");
        return {
            enabled: setup.lan_dhcp ? true : false,
            mode: 0,
            start: `${root}${setup.dhcp_start}`,
            end: `${root}${setup.dhcp_end}`,
            gateway: setup.lan_ip,
            mask: setup.lan_mask,
            cidr: network.netmaskToCIDR(setup.lan_mask),
            leases: "/tmp/dhcp.leases",
            reservations: "/etc/config.mesh/_setup.dhcp.nat",
            services: "/etc/config.mesh/_setup.services.nat",
            aliases: "/etc/config.mesh/aliases.nat"
        };
    }
    else {
        const root = replace(setup.dmz_lan_ip, /\d+$/, "");
        return {
            enabled: setup.lan_dhcp ? true : false,
            mode: int(setup.dmz_mode),
            start: `${root}${setup.dmz_dhcp_start}`,
            end: `${root}${setup.dmz_dhcp_end}`,
            gateway: setup.dmz_lan_ip,
            mask: setup.dmz_lan_mask,
            cidr: network.netmaskToCIDR(setup.dmz_lan_mask),
            leases: "/tmp/dhcp.leases",
            reservations: "/etc/config.mesh/_setup.dhcp.dmz",
            services: "/etc/config.mesh/_setup.services.dmz",
            aliases: "/etc/config.mesh/aliases.dmz"
        };
    }
};

export function prepareChanges()
{
    fs.mkdir(currentConfig);
    fs.mkdir(currentArednInclude);
    if (!fs.access(`${currentConfig}/_setup`)) {
        const d = fs.opendir("/etc/config.mesh");
        if (d) {
            for (;;) {
                const entry = d.read();
                if (!entry) {
                    break;
                }
                if (entry !== "." && entry !== ".." && entry !== "aliases") {
                    fs.writefile(`${currentConfig}/${entry}`, fs.readfile(`/etc/config.mesh/${entry}`));
                }
            }
            d.close();
        }
        map(arednIncludes, entry => {
            if (fs.access(`/etc/aredn_include/${entry}`)) {
                fs.writefile(`${currentArednInclude}/${entry}`, fs.readfile(`/etc/aredn_include/${entry}`));
            }
        });
    }
};

export function commitChanges()
{
    const status = {};
    if (fs.access(`${currentConfig}/_setup`)) {
        const d = fs.opendir(currentConfig);
        if (d) {
            for (;;) {
                const entry = d.read();
                if (!entry) {
                    break;
                }
                if (entry !== "." && entry !== "..") {
                    fs.unlink(`${currentConfig}/${entry}`);
                }
            }
            d.close();
            map(arednIncludes, entry => {
                fs.unlink(`${currentArednInclude}/${entry}`);
            });
            fs.rmdir(currentConfig);
            fs.rmdir(currentArednInclude);
            const n = fs.popen("exec /usr/local/bin/node-setup");
            if (n) {
                status.setup = n.read("all");
                n.close();
                const c = fs.popen("exec /usr/local/bin/restart-services.sh");
                if (c) {
                    status.restart = c.read("all");
                    c.close();
                }
            }
        }
    }
    return status;
};

export function revertChanges()
{
    if (fs.access(`${currentConfig}/_setup`)) {
        const d = fs.opendir(currentConfig);
        if (d) {
            for (;;) {
                const entry = d.read();
                if (!entry) {
                    break;
                }
                if (entry !== "." && entry !== "..") {
                    const from = `${currentConfig}/${entry}`;
                    fs.writefile(`/etc/config.mesh/${entry}`, fs.readfile(from));
                    fs.unlink(from);
                }
            }
            d.close();
            map(arednIncludes, entry => {
                const from = `${currentArednInclude}/${entry}`;
                if (fs.access(from)) {
                    fs.writefile(`/etc/aredn_include/${entry}`, fs.readfile(from));
                    fs.unlink(from);
                }
                else {
                    fs.unlink(`/etc/aredn_include/${entry}`);
                }
            });
            fs.rmdir(currentConfig);
            fs.rmdir(currentArednInclude);
        }
    }
};

function fileChanges(from, to)
{
    let count = 0;
    const p = fs.popen(`exec /usr/bin/diff -NBbdiU0 ${from} ${to}`);
    if (p) {
        for (;;) {
            const l = rtrim(p.read("line"));
            if (!l) {
                break;
            }
            if (index(l, "@@") === 0) {
                const v = match(l, /^@@ [+-]\d+,?(\d*) [+-]\d+,?(\d*) @@$/);
                if (v) {
                    count += max(math.abs(int(v[1] === "" ? 1 : v[1])), math.abs(int(v[2] === "" ? 1 : v[2])));
                }
            }
        }
        p.close();
    }
    return count;
}

export function countChanges()
{
    let count = 0;
    if (fs.access(`${currentConfig}/_setup`)) {
        const d = fs.opendir(currentConfig);
        if (d) {
            for (;;) {
                const entry = d.read();
                if (!entry) {
                    break;
                }
                if (entry !== "." && entry !== "..") {
                    count += fileChanges(`${currentConfig}/${entry}`, `/etc/config.mesh/${entry}`);
                }
            }
            d.close();
            map(arednIncludes, entry => {
                count += fileChanges(`${currentArednInclude}/${entry}`, `/etc/aredn_include/${entry}`);
            });
        }
    }
    return count;
};
