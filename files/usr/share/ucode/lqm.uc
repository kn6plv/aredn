import * as fs from "fs";

let lqm;

function initLQM()
{
    if (!lqm) {
        try {
            lqm = json(fs.readfile("/tmp/lqm.info"));
        }
        catch (_) {
        }
    }
}
export function getTrackers()
{
    initLQM();
    return lqm?.trackers || {};
};
