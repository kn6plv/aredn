
export function getNodeList(doSort)
{
    const re = /^10.+\tdtdlink\.(.+)\.local\.mesh\t#.+$/;
    const nodes = [];
    const f = fs.open("/var/run/hosts_olsr");
    if (f) {
        for (let l = f.read("line"); length(l); l = f.read("line")) {
            const m = match(l, re);
            if (m) {
                push(nodes, m[1]);
            }
        }
        f.close();
    }
    if (doSort) {
        sort(nodes, (a, b) => lc(a) === lc(b) ? 0 : lc(a) < lc(b) ? -1 : 1);
    }
    return nodes;
};

export function getNodeCounts()
{
    let nodes = 0;
    let devices = 0;
    const f = fs.open("/var/run/hosts_olsr");
    if (f) {
        for (let l = f.read("line"); length(l); l = f.read("line")) {
            if (substr(l, 0, 3) == "10." && index(l, "\tmid") === -1) {
                devices++;
                if (index(l, "\tdtdlink.") !== -1) {
                    nodes++;
                }
            }
        }
        f.close();
    }
    return {
        nodes: nodes,
        devices: devices
    };
};
