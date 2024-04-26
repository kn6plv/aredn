{%
import * as config from "./config.uc";
import * as fs from "fs";
import * as math from "math";
import * as uci from "uci";
import * as ubus from "ubus";
import * as settings from "settings";
import * as hardware from "hardware";
import * as lqm from "lqm";
import * as network from "network";
import * as olsr from "olsr";
import * as units from "units";
import * as radios from "radios";

const pageCache = {};

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
                    response.headers["Set-Cookie"] = `authV1=${b64enc(this.key)}; Path=/; Domain=${request.headers.host}; Max-Age=${this.age}`;
                    this.authenticated = true;
                }
            }
        }
        return this.authenticated;
    },

    deauthenticate: function()
    {
        if (this.authenticated) {
            response.headers["Set-Cookie"] = `authV1=; Path=/; Domain=${request.headers.host}; Max-Age=0;`;
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
    const tpath = `${config.application}/main/${env.PATH_INFO || "status"}.ut`;
    if (fs.access(tpath)) {
        auth.runAuthentication(env);
        if (index(env.PATH_INFO, "/e/") !== -1 && !auth.authenticated && !config.debug) {
            uhttpd.send("Status: 401 Unauthorized\r\n\r\n");
            return;
        }
        const args = {};
        if (env.CONTENT_TYPE === "application/x-www-form-urlencoded") {
            const v = split(uhttpd.recv(1024), "&");
            for (let i = 0; i < length(v); i++) {
                const kv = split(v[i], "=");
                const k = uhttpd.urldecode(kv[0]);
                if (!(k in args)) {
                    args[k] = uhttpd.urldecode(kv[1]);
                }
            }
        }
        const response = { statusCode: 200, headers: { "Content-Type": "text/html" } };
        const fn = pageCache[tpath] || loadfile(tpath, { raw_mode: false });
        const res = render(call, fn, null, {
            config: config,
            request: { env: env, headers: env.headers, args: args },
            response: response,
            uci: uciMethods,
            uciMesh: uciMeshMethods,
            ubus: ubusMethods,
            auth: auth,
            includeHelp: (env.headers || {})["include-help"] === "1",
            fs: fs,
            settings: settings,
            hardware: hardware,
            lqm: lqm,
            network: network,
            olsr: olsr,
            units: units,
            radios: radios
        });
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
        uhttpd.send("\r\n", fs.readfile(rpath));
        return;
    }

    uhttpd.send("Status: 404 Not Found\r\n\r\n");
};
%}
