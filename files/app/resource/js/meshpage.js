function render()
{

const page = document.getElementById("meshpage");
const etx = mesh.etx;
const hosts = mesh.hosts;
const services = mesh.services;

function serv(ip, hostname)
{
    let view = "";
    const s = services[ip];
    if (s) {
        const re = new RegExp(`//${hostname}:`, "i");
        for (let i = 0; i < s.length; i++) {
            const name = s[i].name;
            const url = s[i].url;
            if (url.match(re)) {
                const r = url.match(/^(.+:\/\/)([^:]+):(\d+)(.*)$/);
                if (r[3] !== "0") {
                    if (r) switch (r[3]) {
                        case "0":
                            view += `<div class="service"><span>${name}</span></div>`;
                            break;
                        case "80":
                            view += `<div class="service"><a target="_blank" href="${r[1]}${r[2]}.local.mesh${r[4]}">${name}</a>&#8288;<div></div></div>`;
                            break;
                        case "443":
                            view += `<div class="service"><a target="_blank" href="${r[1]}${r[2]}.local.mesh${r[4]}">${name}</a>&#8288;<div></div></div>`;
                            break;
                        default:
                            view += `<div class="service"><a target="_blank" href="${r[1]}${r[2]}.local.mesh:${r[3]}${r[4]}">${name}</a>&#8288;<div></div></div>`;
                            break;
                    }
                }
                else {
                    view += `<div class="service"><span>${name}</span></div>`;
                }

            }
        }
    }
    return view;
}

const blocks = [ 0, 1, 2, 3, 5, 10, 10000, 10000 ];
let data = `<div class="block block0">`;
for (let i = 0; i < etx.length; i++) {
    const item = etx[i];
    const ip = item[0];
    const hostlist = hosts[ip];
    if (hostlist) {
        const hostname = (hostlist.find(h => !h[1]) || [])[0];
        if (hostname) {
            if (item[1] > blocks[1]) {
                while (item[1] > blocks[1]) {
                    blocks.shift();
                }
                data += `</div><div class="block block${blocks[0]}">`;
            }
            let lanview = "";
            for (let j = 0; j < hostlist.length; j++) {
                const lanhost = hostlist[j];
                if (lanhost[1] && lanhost[1] !== ip) {
                    const lan = lanhost[0].replace(/^\*./, "");
                    lanview += `<div class="lanhost"><div class="name">&nbsp;&nbsp;${lan}</div><div class="services">${serv(ip, lanhost[0])}</div></div>`;
                }
            }
            data += `<div class="node"><div class="host"><div class="name"><a href="http://${hostname}.local.mesh">${hostname}</a><span class="etx">${item[1]}</span></div><div class="services">${serv(ip, hostname)}</div></div>${lanview ? '<div class="lanhosts">' + lanview + '</div>' : ''}</div>`;
        }
    }
}
page.innerHTML = data + "</div>";

}
render();
