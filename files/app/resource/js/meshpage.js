function render()
{

const search = document.querySelector("#meshfilter input");
const page = document.getElementById("meshpage");
const etx = mesh.etx;
const hosts = mesh.hosts;
const services = mesh.services;

let filtering;
let cfilter;
function filter()
{
    clearTimeout(filtering);
    filtering = setTimeout(function() {
        const filter = search.value.toLowerCase();
        if (filter === cfilter) {
            return;
        }
        cfilter = filter;
        const filtered = document.querySelectorAll(".valid");
        for (let i = 0; i < filtered.length; i++) {
            filtered[i].classList.remove("valid");
        }
        if (filter === "") {
            page.classList.remove("filtering");
        }
        else {
            page.classList.add("filtering");
            const targets = document.querySelectorAll("[data-search]");
            for (let i = 0; i < targets.length; i++) {
                const target = targets[i];
                if (target.dataset.search.indexOf(filter) !== -1) {
                    target.classList.add("valid");
                }
            }
        }
    }, 200);
}
search.addEventListener("keyup", filter);
search.addEventListener("click", filter);
search.addEventListener("keypress", event => event.keyCode == 13 && event.preventDefault());

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
                const lname = name.toLowerCase();
                const r = url.match(/^(.+:\/\/)([^:]+):(\d+)(.*)$/);
                switch (r[3]) {
                    case "0":
                        view += `<div class="service" data-search="${lname}"><span>${name}</span></div>`;
                        break;
                    case "80":
                    case "443":
                        view += `<div class="service" data-search="${lname}"><a target="_blank" href="${r[1]}${r[2]}.local.mesh${r[4]}">${name}</a>&#8288;<div></div></div>`;
                        break;
                    default:
                        view += `<div class="service" data-search="${lname}"><a target="_blank" href="${r[1]}${r[2]}.local.mesh:${r[3]}${r[4]}">${name}</a>&#8288;<div></div></div>`;
                        break;
                }
            }
        }
    }
    return view;
}

const blocks = [ 1, 2, 3, 5, 10, 10000 ];
let data = `<div class="block block1">`;
for (let i = 0; i < etx.length; i++) {
    const item = etx[i];
    const ip = item[0];
    const hostlist = hosts[ip];
    if (hostlist) {
        const hostname = (hostlist.find(h => !h[1]) || [])[0];
        if (hostname) {
            if (item[1] >= blocks[0]) {
                while (item[1] >= blocks[0]) {
                    blocks.shift();
                }
                data += `</div><div class="block block${blocks[0]}">`;
            }
            let lanview = "";
            for (let j = 0; j < hostlist.length; j++) {
                const lanhost = hostlist[j];
                if (lanhost[1] && lanhost[1] !== ip) {
                    const lan = lanhost[0].replace(/^\*./, "");
                    lanview += `<div class="lanhost" data-search="${lan.toLowerCase()}"><div class="name">&nbsp;&nbsp;${lan}</div><div class="services">${serv(ip, lanhost[0])}</div></div>`;
                }
            }
            data += `<div class="node"><div class="host" data-search="${hostname.toLowerCase()}"><div class="name"><a href="http://${hostname}.local.mesh">${hostname}</a><span class="etx">${item[1]}</span></div><div class="services">${serv(ip, hostname)}</div></div>${lanview ? '<div class="lanhosts">' + lanview + '</div>' : ''}</div>`;
        }
    }
}
page.innerHTML = data + "</div>";

}
render();
