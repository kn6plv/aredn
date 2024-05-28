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

export function get()
{
    initLQM();
    return lqm || { trackers:{}, hidden_nodes:[], now: 0 };
};

export function getTrackers()
{
    initLQM();
    return lqm?.trackers || {};
};
