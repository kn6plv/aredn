{%
import config from "./config.uc";
import * as fs from "fs";
import * as math from "math";

global.handle_request = function(env)
{
    const path = config.application + (env.PATH_INFO || "root");
    const tpath = path + ".ut";
    const rpath = path + ".gz";
    if (fs.access(tpath)) {
        const datafile = "/tmp/" + time() + math.rand();
        const response = { statusCode: 200, headers: { "Content-Type": "text/html" } };
        const fn = loadfile(tpath, { raw_mode: false });
        const res = render(call, fn, null, { request: { env: env, headers: env.headers }, response: response });
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
    else if (fs.access(rpath)) {
        uhttpd.send("Status: 200 OK\r\nContent-Encoding: gzip\r\n");
        if (substr(path, -3) === ".js") {
            uhttpd.send("Content-Type: application/javascript; charset=utf-8\r\n");
        }
        else if (substr(path, -4) === ".png") {
            uhttpd.send("Content-Type: image/png\r\n");
        }
        uhttpd.send("\r\n", fs.readfile(rpath));
    }
    else {
        uhttpd.send("Status: 404 Not Found\r\n\r\n");
    }
}
%}
