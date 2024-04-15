{%
import config from "./config.uc";
import * as fs from "fs";
import * as math from "math";
import * as uci from "uci";
import * as ubus from "ubus";

const pageCache = {};

if (!config.debug) {
    function cp(path) {
        const dir = fs.opendir(config.application + path);
        for (;;) {
            const entry = dir.read();
            if (!entry) {
                break;
            }
            const tpath = config.application + path + entry;
            pageCache[tpath] = loadfile(tpath, { raw_mode: false });
        }
    }
    cp("/main/");
    cp("/partial/");
}

global._R = function(path)
{
    const tpath = config.application + "/partial/" + path + ".ut";
    const fn = pageCache[tpath] || loadfile(tpath, { raw_mode: false });
    return render(fn);
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
        const response = { statusCode: 200, headers: { "Content-Type": "text/html" } };
        const fn = pageCache[tpath] || loadfile(tpath, { raw_mode: false });
        const res = render(call, fn, null, {
            config: config,
            request: { env: env, headers: env.headers },
            response: response,
            uci: uciMethods,
            ubus: ubusMethods
        });
        if (config.debug) {
            uhttpd.send(
                sprintf("Status: %d OK\r\n", response.statusCode),
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
                        sprintf("Status: %d OK\r\nContent-Encoding: gzip\r\n", response.statusCode),
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
