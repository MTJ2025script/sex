const menu     = document.getElementById('menu');
const services = document.getElementById('services');
const progress = document.getElementById('progress');
const progFill = document.getElementById('prog-fill');
const progLbl  = document.getElementById('prog-label');
const condensation = document.getElementById('condensation');

let progTimer = null;
let condRaf = null;
const MIN_PROGRESS_DURATION_SECONDS = 0.1;
const FOG_GROWTH_EXPONENT = 1.35;
const DROP_START_THRESHOLD = 0.45;
const BASE_FOG_OPACITY = 0.06;
const MAX_FOG_OPACITY_GAIN = 0.56;
const MAX_DROP_OPACITY = 0.72;

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
    const safeDuration = Math.max(Number(duration) || 0, MIN_PROGRESS_DURATION_SECONDS);
    progLbl.textContent = (label || 'SERVICE').toUpperCase();
    progFill.style.transition = 'none';
    progFill.style.width = '0%';
    progress.classList.remove('hidden');
    condensation.classList.remove('hidden');
    condensation.style.setProperty('--cond-fog-opacity', '0');
    condensation.style.setProperty('--cond-drop-opacity', '0');
    if (condRaf) cancelAnimationFrame(condRaf);

    const startAt = performance.now();
    const totalMs = safeDuration * 1000;
    const step = (now) => {
        const p = Math.min((now - startAt) / totalMs, 1);
        const fogIntensity = Math.pow(p, FOG_GROWTH_EXPONENT);
        const dropRamp = Math.max((p - DROP_START_THRESHOLD) / (1 - DROP_START_THRESHOLD), 0);
        condensation.style.setProperty('--cond-fog-opacity', (BASE_FOG_OPACITY + fogIntensity * MAX_FOG_OPACITY_GAIN).toFixed(3));
        condensation.style.setProperty('--cond-drop-opacity', (dropRamp * MAX_DROP_OPACITY).toFixed(3));
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
    condensation.style.setProperty('--cond-fog-opacity', '0');
    condensation.style.setProperty('--cond-drop-opacity', '0');
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
