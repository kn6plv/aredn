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
import * as configuration from "aredn.configuration";

let nodename;

export function haveMessages()
{
    if (fs.access("/etc/cron.boot/reinstall-packages") && fs.access("/etc/package_store/catalog.json")) {
        return true;
    }
    if (fs.stat("/tmp/aredn_message")?.size || fs.stat("/tmp/local_message")?.size) {
        return true;
    }
    return false;
};

function parseMessages(msgs, text)
{
    if (text) {
        const t = split(text, "<strong>");
        for (let i = 0; i < length(t); i++) {
            const m = match(t[i], /&#8611; (.+):<\/strong>(.+)<p>/);
            if (m) {
                const label = m[1] !== nodename ? m[1] : "yournode";
                if (!msgs[label]) {
                    msgs[label] = [];
                }
                push(msgs[label], trim(m[2]));
            }
        }
    }
}

export function getMessages()
{
    nodename = lc(configuration.getName());
    const msgs = {};
    if (fs.access("/etc/cron.boot/reinstall-packages") && fs.access("/etc/package_store/catalog.json")) {
        msgs.system = [ "Packages are being reinstalled in the background. This can take a few minutes." ];
    }
    parseMessages(msgs, fs.readfile("/tmp/aredn_message"));
    parseMessages(msgs, fs.readfile("/tmp/local_message"));
    return msgs;
};
