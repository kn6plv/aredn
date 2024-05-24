import * as fs from "fs";

export function getLinks()
{
    const f = fs.popen("exec /usr/bin/curl http://127.0.0.1:9090/links -o - 2> /dev/null");
    try {
        const links = json(f.read("all")).links;
        f.close();
        return links;
    }
    catch (_) {
        f.close();
        return [];
    }
};

export function getRoutes()
{
    const f = fs.popen("exec /usr/bin/curl http://127.0.0.1:9090/routes -o - 2> /dev/null");
    try {
        const routes = json(f.read("all")).routes;
        f.close();
        return routes;
    }
    catch (_) {
        f.close();
        return [];
    }
};

export function getHNAs()
{
    const f = fs.popen("exec /usr/bin/curl http://127.0.0.1:9090/hna -o - 2> /dev/null");
    try {
        const hna = json(f.read("all")).hna;
        f.close();
        return hna;
    }
    catch (_) {
        f.close();
        return [];
    }
};

export function getMids()
{
    const f = fs.popen("exec /usr/bin/curl http://127.0.0.1:9090/mid -o - 2> /dev/null");
    try {
        const mid = json(f.read("all")).mid;
        f.close();
        return mid;
    }
    catch (_) {
        f.close();
        return [];
    }
};
