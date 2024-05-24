{%
import * as config from "./config.uc";
import * as fs from "fs";
import * as math from "math";
import * as uci from "uci";
import * as ubus from "ubus";
import * as log from "log";
import * as lucihttp from "lucihttp";
import * as configuration from "aredn.configuration";
import * as hardware from "aredn.hardware";
import * as lqm from "aredn.lqm";
import * as network from "aredn.network";
import * as olsr from "aredn.olsr";
import * as units from "aredn.units";
import * as radios from "aredn.radios";

const pageCache = {};
const resourceVersions = {};

log.openlog("uhttpd.aredn", log.LOG_PID, log.LOG_USER);

if (!config.debug) {
    function cp(path) {
        const dir = fs.opendir(`${config.application}${path}`);
        for (;;) {
            const entry = dir.read();
            if (!entry) {
                break;
            }
            if (match(entry, /\.ut$/)) {
                const tpath = `${config.application}${path}${entry}`;
                pageCache[tpath] = loadfile(tpath, { raw_mode: false });
            }
        }
    }
    cp("/main/");
    cp("/partial/");
    cp("/main/status/e/");

    radios.getCommonConfiguration();

    function prepareResource(id, resource)
    {
        const path = `${config.application}/resource/${resource}`;
        const pathgz = `${config.application}/resource/${resource}.gz`;
        if (!fs.access(pathgz)) {
            fs.popen(`/bin/gzip -k ${path}`).close();
        }
        const md = fs.popen(`/usr/bin/md5sum ${pathgz}`);
        resourceVersions[id] = match(md.read("all"), /^([0-9a-f]+)/)[1];
        md.close();
        fs.symlink(pathgz, `${path}.${resourceVersions[id]}.gz`);
    }
    prepareResource("usercss", "css/user.css");
    prepareResource("admincss", "css/admin.css");
    prepareResource("aredncss", "css/aredn.css");
    prepareResource("htmx", "js/htmx.min.js");
    prepareResource("meshpage", "js/meshpage.js");
}

global._R = function(path, arg)
{
    const tpath = `${config.application}/partial/${path}.ut`;
    const fn = pageCache[tpath] || loadfile(tpath, { raw_mode: false });
    let old = inner;
    let r = "";
    try {
        inner = arg;
        r = render(fn);
    }
    catch (_) {
    }
    inner = old;
    return r;
};

global._H = function(str)
{
    return includeHelp ? `<div class="help">${str}</div>` : "";
};

const uciMethods =
{
    get: function(a, b, c)
    {
        if (!cursor)
        {
            cursor = uci.cursor();
        }
        return cursor.get(a, b, c);
    },

    set: function(a, b, c, d)
    {
        if (!cursor)
        {
            cursor = uci.cursor();
        }
        cursor.set(a, b, c, d);
    },

    foreach: function(a, b, fn)
    {
        if (!cursor)
        {
            cursor = uci.cursor();
        }
        cursor.foreach(a, b, fn);
    },

    commit: function(a)
    {
        if (cursor) {
            cursor.commit(a);
        }
    }
};

const uciMeshMethods =
{
    get: function(a, b, c)
    {
        if (!cursorm)
        {
            cursorm = uci.cursor("/etc/config.mesh");
        }
        return cursorm.get(a, b, c);
    },

    set: function(a, b, c, d)
    {
        if (!cursorm)
        {
            cursorm = uci.cursor("/etc/config.mesh");
        }
        cursorm.set(a, b, c, d);
    },

    foreach: function(a, b, fn)
    {
        if (!cursorm)
        {
            cursorm = uci.cursor("/etc/config.mesh");
        }
        cursorm.foreach(a, b, fn);
    },

    commit: function(a)
    {
        if (cursorm) {
            cursorm.commit(a);
        }
    }
};

const auth = {
    authenticated: false,
    key: null,
    age: 315360000, // 10 years
    //age: 120, // 2 minutes

    DAYS: [ "", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun" ],
    MONTHS: [ "", "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" ],

    initKey: function()
    {
        if (!this.key) {
            const f = fs.open("/etc/shadow");
            if (f) {
                for (;;) {
                    const l = f.read("line");
                    if (!length(l)) {
                        break;
                    }
                    if (index(l, "root:") === 0) {
                        this.key = trim(l);
                        break;
                    }
                }
                f.close();
            }
        }
    },

    runAuthentication: function(env)
    {
        const cookieheader = env.headers?.cookie;
        if (cookieheader) {
            const ca = split(cookieheader, ";");
            for (let i = 0; i < length(ca); i++) {
                if (index(ca[i], "authV1=") === 0) {
                    this.initKey();
                    if (this.key == b64dec(substr(ca[i], 7))) {
                        this.authenticated = true;
                    }
                    else {
                        this.authenticated = false;
                    }
                    break;
                }
            }
        }
    },

    authenticate: function(password)
    {
        if (!this.authenticated) {
            this.initKey();
            const s = split(this.key, /[:$]/); // s[3] = salt, s[4] = hashed
            const f = fs.popen(`exec /usr/bin/mkpasswd -S '${s[3]}' '${password}'`);
            if (f) {
                const pwd = rtrim(f.read("all"));
                f.close();
                if (index(this.key, `root:${pwd}:`) === 0) {
                    const time = clock();
                    const gm = gmtime(time[0] + this.age);
                    const tm = `${this.DAYS[gm.wday]}, ${gm.mday} ${this.MONTHS[gm.mon]} ${gm.year} 00:00:00 GMT`;
                    response.headers["Set-Cookie"] = `authV1=${b64enc(this.key)}; Path=/; Domain=${replace(request.headers.host, /:\d+$/, "")}; Expires=${tm}`;
                    this.authenticated = true;
                }
            }
        }
        return this.authenticated;
    },

    deauthenticate: function()
    {
        if (this.authenticated) {
            response.headers["Set-Cookie"] = `authV1=; Path=/; Domain=${replace(request.headers.host, /:\d+$/, "")}; Max-Age=0;`;
            this.authenticated = false;
        }
    }
};

const ubusMethods =
{
    call: function(path, method)
    {
        if (!connection) {
            connection = ubus.connect();
        }
        return connection.call(path, method);
    }
};

global.handle_request = function(env)
{
    const path = match(env.PATH_INFO, /^\/([-a-z]*)(.*)$/);
    const page = path[1] || "status";
    const secured = index(path[2], "/e/") === 0;

    if (path[2] == "" || secured) {
        let tpath;
        if (secured) {
            tpath = `${config.application}/main${env.PATH_INFO}.ut`;
        }
        else {
            tpath = `${config.application}/main/${page}.ut`;
            if (!((config.debug && fs.access(tpath)) || (!config.debug && pageCache[tpath]))) {
                tpath = `${config.application}/main/app.ut`;
            }
        }

        if (pageCache[tpath] || fs.access(tpath)) {
            auth.runAuthentication(env);
            if (secured && !auth.authenticated && !config.debug) {
                uhttpd.send("Status: 401 Unauthorized\r\n\r\n");
                return;
            }
            const args = {};
            if (env.CONTENT_TYPE === "application/x-www-form-urlencoded") {
                let b = "";
                for (;;) {
                    const v = uhttpd.recv(10240);
                    if (!length(v)) {
                        break;
                    }
                    b += v;
                }
                const v = split(b, "&");
                for (let i = 0; i < length(v); i++) {
                    const kv = split(v[i], "=");
                    const k = uhttpd.urldecode(kv[0]);
                    if (!(k in args)) {
                        args[k] = uhttpd.urldecode(kv[1]);
                    }
                }
            }
            if (index(env.CONTENT_TYPE, "multipart/form-data") === 0) {
                let key;
                let val;
                let header;
                let file;
                let parser;
                parser = lucihttp.multipart_parser(env.CONTENT_TYPE, (what, buffer, length) => {
                    switch (what) {
                        case parser.PART_INIT:
                            key = null;
                            val = null;
                            break;
                        case parser.HEADER_NAME:
                            header = lc(buffer);
                            break;
                        case parser.HEADER_VALUE:
                            if (header === "content-disposition") {
                                const filename = lucihttp.header_attribute(buffer, "filename");
                                key = lucihttp.header_attribute(buffer, "name");
                                file = {
                                    name: `/tmp/${key}`,
                                    filename: filename
                                };
                                val = filename;
                            }
                            break;
                        case parser.PART_BEGIN:
                            if (file) {
                                fs.writefile("/proc/sys/vm/drop_caches", "3");
                                file.fd = fs.open(file.name, "w");
                                return false
                            }
                            break;
                        case parser.PART_DATA:
                            if (file) {
                                file.fd.write(buffer);
                            }
                            else {
                                val = buffer;
                            }
                            break;
                        case parser.PART_END:
                            if (file) {
                                file.fd.close();
                                file.fd = null;
                                args[key] = file.name;
                            }
                            else if (key) {
                                args[key] = val;
                            }
                            key = null;
                            val = null;
                            file = null;
                            break;
                        case parser.ERROR:
                            log.syslog(log.LOG_ERR, `multipart error: ${buffer}`);
                            break;
                    }
                    return true;
                });
                for (;;) {
                    const v = uhttpd.recv(10240);
                    if (!length(v)) {
                        parser.parse(null);
                        break;
                    }
                    parser.parse(v);
                }
            }
            const response = { statusCode: 200, headers: { "Content-Type": "text/html", "Cache-Control": "no-store" } };
            const fn = pageCache[tpath] || loadfile(tpath, { raw_mode: false });
            let res = "";
            try {
                res = render(call, fn, null, {
                    config: config,
                    versions: resourceVersions,
                    request: { env: env, headers: env.headers, args: args, page: page },
                    response: response,
                    uci: uciMethods,
                    uciMesh: uciMeshMethods,
                    ubus: ubusMethods,
                    auth: auth,
                    includeHelp: (env.headers || {})["include-help"] === "1",
                    fs: fs,
                    configuration: configuration,
                    hardware: hardware,
                    lqm: lqm,
                    network: network,
                    olsr: olsr,
                    units: units,
                    radios: radios
                });
            }
            catch (e) {
                log.syslog(log.LOG_ERR, `${e.message}\n${e.stacktrace[0].context}`);
                res = `<div id="ctrl-modal" hx-on::after-swap="const e = event.target.querySelector('dialog'); if (e) { e.showModal(); }"><dialog style="font-size:12px"><b>ERROR: ${e.message}<b><div><pre>${e.stacktrace[0].context}</pre></dialog></div>`;
            }
            if (config.debug) {
                uhttpd.send(
                    `Status: ${response.statusCode} OK\r\n`,
                    join("", map(keys(response.headers), k => k + ": " + response.headers[k] + "\r\n")),
                    "\r\n",
                    res
                );
            }
            else {
                const datafile = "/tmp/" + time() + math.rand();
                try {
                    fs.writefile(datafile, res);
                    const z = fs.popen("exec /bin/gzip -c " + datafile);
                    try {
                        uhttpd.send(
                            `Status: ${response.statusCode} OK\r\nContent-Encoding: gzip\r\n`,
                            join("", map(keys(response.headers), k => k + ": " + response.headers[k] + "\r\n")),
                            "\r\n",
                            z.read("all")
                        );
                    }
                    catch (_) {
                    }
                    z.close();
                }
                catch (_) {
                }
                fs.unlink(datafile);
            }
            if (response.reboot) {
                system("exec /sbin/reboot");
            }
            if (response.upgrade) {
                system(response.upgrade);
            }
            return;
        }
        uhttpd.send("Status: 404 Not Found\r\n\r\n");
        return;
    }

    const rpath = `${config.application}/resource/${env.PATH_INFO || "unknown"}`;
    const gzrpath = `${rpath}.gz`;
    if (fs.access(gzrpath)) {
        uhttpd.send("Status: 200 OK\r\nContent-Encoding: gzip\r\n");
        if (substr(rpath, -3) === ".js") {
            uhttpd.send("Content-Type: application/javascript\r\n");
        }
        else if (substr(rpath, -4) === ".css") {
            uhttpd.send("Content-Type: text/css\r\n");
        }
        if (config.debug) {
            uhttpd.send("Cache-Control: no-store\r\n");
        }
        else {
            uhttpd.send("Cache-Control: max-age=604800\r\n");
        }
        uhttpd.send("\r\n", fs.readfile(gzrpath));
        return;
    }

    if (fs.access(rpath)) {
        uhttpd.send("Status: 200 OK\r\n");
        if (substr(rpath, -3) === ".js") {
            uhttpd.send("Content-Type: application/javascript\r\n");
        }
        else if (substr(rpath, -4) === ".png") {
            uhttpd.send("Content-Type: image/png\r\n");
        }
        else if (substr(rpath, -4) === ".jpg") {
            uhttpd.send("Content-Type: image/jpeg\r\n");
        }
        else if (substr(rpath, -4) === ".css") {
            uhttpd.send("Content-Type: text/css\r\n");
        }
        if (config.debug) {
            uhttpd.send("Cache-Control: no-store\r\n");
        }
        else {
            uhttpd.send("Cache-Control: max-age=604800\r\n");
        }
        uhttpd.send("\r\n", fs.readfile(rpath));
        return;
    }

    if (config.debug) {
        uhttpd.send("Status: 404 Not Found\r\nCache-Control: no-store\r\n\r\n");
    }
    else {
        uhttpd.send("Status: 404 Not Found\r\nCache-Control: max-age=600\r\n\r\n");
    }
};
%}
