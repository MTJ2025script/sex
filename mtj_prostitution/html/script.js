const menu     = document.getElementById('menu');
const services = document.getElementById('services');
const progress = document.getElementById('progress');
const progFill = document.getElementById('prog-fill');
const progLbl  = document.getElementById('prog-label');

let progTimer = null;

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
    progLbl.textContent = (label || 'SERVICE').toUpperCase();
    progFill.style.transition = 'none';
    progFill.style.width = '0%';
    progress.classList.remove('hidden');
    // force reflow then animate
    void progFill.offsetWidth;
    progFill.style.transition = `width ${duration}s linear`;
    progFill.style.width = '100%';
}

function hideAll() {
    menu.classList.add('hidden');
    progress.classList.add('hidden');
    if (progTimer) { clearTimeout(progTimer); progTimer = null; }
}

window.addEventListener('message', (e) => {
    const d = e.data;
    if (d.action === 'openMenu') {
        renderMenu(d.services || []);
        menu.classList.remove('hidden');
        progress.classList.add('hidden');
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
