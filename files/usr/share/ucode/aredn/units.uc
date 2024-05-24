
const meters_to_miles = 0.000621371;
const meters_to_km = 0.001;
let metric = null;

function isMetric()
{
    if (metric === null) {
        const lang = request?.env?.HTTP_ACCEPT_LANGUAGE || "en-US";
        if (index(lang, "-US") !== -1 || index(lang, "-GB") !== -1) {
            metric = false;
        }
        else {
            metric = true;
        }
    }
    return metric;
};

export function distanceUnit()
{
    return isMetric() ? "km" : "miles";
};

export function meters2distance(meters)
{
    if (isMetric()) {
        return meters * meters_to_km;
    }
    else {
        return meters * meters_to_miles;
    }
};

export function distance2meters(distance)
{
    if (isMetric()) {
        return distance / meters_to_km;
    }
    else {
        return distance / meters_to_miles;
    }
};
