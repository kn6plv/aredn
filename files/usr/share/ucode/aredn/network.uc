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

export function netmaskToCIDR(mask)
{
    const m = iptoarr(mask);
    let cidr = 32;
    for (let i = 3; i >= 0; i--) {
        switch (m[i]) {
            default:
            case 255:
                return cidr - 0;
            case 254:
                return cidr - 1;
            case 252:
                return cidr - 2;
            case 248:
                return cidr - 3;
            case 240:
                return cidr - 4;
            case 224:
                return cidr - 5;
            case 192:
                return cidr - 6;
            case 128:
                return cidr - 7;
            case 0:
                cidr -= 8;
                break;
        }
    }
    return 0;
};

export function CIDRToNetmask(cidr)
{
    const v = (0xFF00 >> (cidr % 8)) & 0xFF;
    switch (int(cidr / 8)) {
        case 0:
            return `${v}.0.0.0`;
        case 1:
            return `255.${v}.0.0`;
        case 2:
            return `255.255.${v}.0`;
        case 3:
            return `255.255.255.${v}`;
        default:
            return "255.255.255.255";
    }
};

