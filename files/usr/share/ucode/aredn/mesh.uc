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
