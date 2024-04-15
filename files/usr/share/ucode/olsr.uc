import * as fs from "fs";

export function getLinks()
{
    const f = fs.popen("exec /usr/bin/curl http://127.0.0.1:9090/links -o - 2> /dev/null");
    const links = json(f.read("all"))?.links;
    f.close();
    return links;
};
