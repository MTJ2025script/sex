const menu     = document.getElementById('menu');
const services = document.getElementById('services');
const progress = document.getElementById('progress');
const progFill = document.getElementById('prog-fill');
const progLbl  = document.getElementById('prog-label');
const condensation = document.getElementById('condensation');
const condFog = document.getElementById('cond-fog');
const condDrops = document.getElementById('cond-drops');

let progTimer = null;
let condRaf = null;

function post(name, data = {}) {
    fetch(`https://${GetParentResourceName()}/${name}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify(data)
    }).catch(() => {});
}

function renderMenu(list) {
    services.innerHTML = '';
    list.forEach((svc, i) => {
        const tag = svc.scene === 'blowjob' ? 'Blowjob' : 'Sex';
        const img = svc.image ? `img/${svc.image}` : 'img/service1.png';
        const el = document.createElement('div');
        el.className = 'svc';
        el.innerHTML = `
            <div class="svc-img" style="background-image:url('${img}')"></div>
            <div class="svc-shade"></div>
            <span class="svc-tag">${tag}</span>
            <span class="price">$${svc.price.toLocaleString('de-DE')}</span>
            <div class="svc-body">
                <div class="name">${svc.label}</div>
                <div class="go">Auswählen ➜</div>
            </div>
        `;
        el.addEventListener('click', () => {
            menu.classList.add('hidden');
            post('selectService', { index: i + 1 });
        });
        services.appendChild(el);
    });
}

function startProgress(duration, label) {
    const safeDuration = Math.max(Number(duration) || 0, 0.1);
    progLbl.textContent = (label || 'SERVICE').toUpperCase();
    progFill.style.transition = 'none';
    progFill.style.width = '0%';
    progress.classList.remove('hidden');
    condensation.classList.remove('hidden');
    condFog.style.opacity = '0';
    condDrops.style.opacity = '0';
    if (condRaf) cancelAnimationFrame(condRaf);

    const startAt = performance.now();
    const totalMs = safeDuration * 1000;
    const step = (now) => {
        const p = Math.min((now - startAt) / totalMs, 1);
        const fogIntensity = Math.pow(p, 1.35);
        const dropRamp = Math.max((p - 0.45) / 0.55, 0);
        condFog.style.opacity = (0.06 + fogIntensity * 0.56).toFixed(3);
        condDrops.style.opacity = (dropRamp * 0.72).toFixed(3);
        if (p < 1) condRaf = requestAnimationFrame(step);
    };
    condRaf = requestAnimationFrame(step);

    // force reflow then animate
    void progFill.offsetWidth;
    progFill.style.transition = `width ${safeDuration}s linear`;
    progFill.style.width = '100%';
}

function hideAll() {
    menu.classList.add('hidden');
    progress.classList.add('hidden');
    condensation.classList.add('hidden');
    condFog.style.opacity = '0';
    condDrops.style.opacity = '0';
    if (condRaf) { cancelAnimationFrame(condRaf); condRaf = null; }
    if (progTimer) { clearTimeout(progTimer); progTimer = null; }
}

window.addEventListener('message', (e) => {
    const d = e.data;
    if (d.action === 'openMenu') {
        renderMenu(d.services || []);
        menu.classList.remove('hidden');
        progress.classList.add('hidden');
        condensation.classList.add('hidden');
    } else if (d.action === 'progress') {
        startProgress(d.duration, d.label);
    } else if (d.action === 'hide') {
        hideAll();
    }
});

document.getElementById('cancel').addEventListener('click', () => {
    menu.classList.add('hidden');
    post('cancelMenu');
});

// ESC schließt das Menü
document.addEventListener('keydown', (ev) => {
    if (ev.key === 'Escape' && !menu.classList.contains('hidden')) {
        menu.classList.add('hidden');
        post('cancelMenu');
    }
});
