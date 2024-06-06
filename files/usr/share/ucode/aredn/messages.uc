import * as fs from "fs";
import * as configuration from "aredn.configuration";

let nodename;

export function haveMessages()
{
    if (fs.access("/etc/cron.boot/reinstall-packages") && fs.access("/etc/package_store/catalog.json")) {
        return true;
    }
    if (fs.access("/tmp/aredn_message") || fs.access("/tmp/local_message")) {
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
