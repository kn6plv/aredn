{%
import config from "./config.uc";
import * as fs from "fs";
import * as math from "math";
import * as uci from "uci";
import * as ubus from "ubus";

const pageCache = {};

global._R = function(path)
{
    return render(config.application + "/partial/" + path + ".ut");
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
    const path = config.application + (env.PATH_INFO || "root");
    const tpath = path + ".ut";
    const gzpath = path + ".gz";
    if (fs.access(tpath)) {
        const response = { statusCode: 200, headers: { "Content-Type": "text/html" } };
        const fn = pageCache[tpath] || loadfile(tpath, { raw_mode: false });
        if (!config.debug) {
            pageCache[tpath] = fn;
        }
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
    }
    else if (fs.access(gzpath)) {
        uhttpd.send("Status: 200 OK\r\nContent-Encoding: gzip\r\n");
        if (substr(path, -3) === ".js") {
            uhttpd.send("Content-Type: application/javascript\r\n");
        }
        else if (substr(path, -4) === ".png") {
            uhttpd.send("Content-Type: image/png\r\n");
        }
        else if (substr(path, -4) === ".css") {
            uhttpd.send("Content-Type: text/css\r\n");
        }
        uhttpd.send("\r\n", fs.readfile(gzpath));
    }
    else if (fs.access(path)) {
        uhttpd.send("Status: 200 OK\r\n");
        if (substr(path, -3) === ".js") {
            uhttpd.send("Content-Type: application/javascript\r\n");
        }
        else if (substr(path, -4) === ".png") {
            uhttpd.send("Content-Type: image/png\r\n");
        }
        else if (substr(path, -4) === ".css") {
            uhttpd.send("Content-Type: text/css\r\n");
        }
        uhttpd.send("\r\n", fs.readfile(path));
    }
    else {
        uhttpd.send("Status: 404 Not Found\r\n\r\n");
    }
};
%}
