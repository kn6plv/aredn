import * as fs from "fs";

export function hasInternet()
{
    const p = fs.popen("exec /bin/ping -W1 -c1 8.8.8.8");
    if (p) {
        const d = p.read("all");
        p.close();
        if (index(d, "1 packets received") !== -1) {
            return true;
        }
    }
    return false;
};

export function getIPAddressFromHostname(hostname)
{
    const p = fs.popen(`exec /usr/bin/nslookup ${hostname}`);
    if (p) {
        const d = p.read("all");
        p.close();
        const i = match(d, /Address: ([0-9.]+)/);
        if (i) {
            return i[1];
        }
    }
    return null;
};
