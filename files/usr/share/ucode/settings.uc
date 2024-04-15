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
    return setup.wifi_txpower;
};
