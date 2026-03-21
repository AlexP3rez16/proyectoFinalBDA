/* =========================
   COMPONENTE: SIDEBAR DINÁMICO
   Inyecta el sidebar correcto según el rol (carpeta)
   y actualiza la fecha en todos los .date-badge
   ========================= */

(function () {

    const path     = window.location.pathname;
    const filename = path.split('/').pop() || '';

    // Detectar rol por carpeta en la URL
    let role = null;
    if      (path.includes('/medico/'))   role = 'medico';
    else if (path.includes('/admin/'))    role = 'admin';
    else if (path.includes('/cuidador/')) role = 'cuidador';

    if (!role) return;

    // ─── CONFIGURACIONES POR ROL ──────────────────────────────
    const configs = {
        medico: {
            logoIcon:     'fa-heart-pulse',
            logoTitle:    'MENTAL HEALTH',
            logoSubtitle: 'PORTAL MÉDICO',
            navItems: [
                { href: 'dashboard.html', icon: 'fa-table-columns', label: 'Dashboard' },
                { href: 'pacientes.html', icon: 'fa-users',         label: 'Mis Pacientes' },
                { href: 'alertas.html',   icon: 'fa-bell',          label: 'Alertas', badge: 3 },
                { href: 'sesiones.html',  icon: 'fa-video',         label: 'Sesiones' },
            ],
            user: {
                img:  'https://picsum.photos/seed/sarah/100/100',
                name: 'Dra. Sarah Miller',
                role: 'Psiquiatra Senior',
            }
        },
        admin: {
            logoIcon:     'fa-shield-halved',
            logoTitle:    'ELDERCARE',
            logoSubtitle: 'PANEL ADMINISTRATIVO',
            navItems: [
                { href: 'admin-dashboard.html', icon: 'fa-gauge-high',       label: 'Dashboard' },
                { href: 'pacientes.html',        icon: 'fa-users',            label: 'Pacientes' },
                { href: 'alertas.html',          icon: 'fa-bell',             label: 'Alertas', badge: 8 },
                { href: 'usuarios.html',         icon: 'fa-user-gear',        label: 'Gestión de Usuarios' },
                { href: 'iot.html',              icon: 'fa-map-location-dot', label: 'Mapa de Monitoreo IoT' },
                { href: 'reportes.html',         icon: 'fa-file-medical-alt', label: 'Reportes Clínicos' },
                { href: 'auditoria.html',        icon: 'fa-list-check',       label: 'Log de Auditoría' },
            ],
            user: {
                img:  'https://picsum.photos/seed/admin/100/100',
                name: 'Admin Sistema',
                role: 'Super Usuario',
            }
        },
        cuidador: {
            logoIcon:     'fa-hands-holding-circle',
            logoTitle:    'ELDERCARE',
            logoSubtitle: 'PORTAL CUIDADOR',
            navItems: [
                { href: 'dashboard.html', icon: 'fa-table-columns',    label: 'Dashboard' },
                { href: 'pacientes.html', icon: 'fa-users',            label: 'Mis Pacientes' },
                { href: 'mapa.html',      icon: 'fa-map-location-dot', label: 'Mapa IoT' },
            ],
            user: {
                img:  'https://picsum.photos/seed/care1/100/100',
                name: 'María López',
                role: 'Cuidadora Principal',
            }
        }
    };

    const config = configs[role];

    // ─── CONSTRUIR NAV ITEMS ──────────────────────────────────
    const navItemsHTML = config.navItems.map(item => {
        const isActive  = filename === item.href;
        const badgeHTML = item.badge
            ? `<span class="badge-alert">${item.badge}</span>`
            : '';
        return `
                <li class="nav-item">
                    <a href="${item.href}" class="nav-link${isActive ? ' active' : ''}">
                        <span class="nav-icon"><i class="fa-solid ${item.icon}"></i></span>
                        ${item.label}
                        ${badgeHTML}
                    </a>
                </li>`;
    }).join('');

    // ─── INYECTAR SIDEBAR ─────────────────────────────────────
    const sidebar = document.getElementById('sidebar');
    if (sidebar) {
        sidebar.innerHTML = `
            <div>
                <div class="sidebar-header">
                    <div class="logo-icon">
                        <i class="fa-solid ${config.logoIcon}"></i>
                    </div>
                    <div class="logo-title">${config.logoTitle}</div>
                    <div class="logo-subtitle">${config.logoSubtitle}</div>
                </div>
                <ul class="nav-menu">
                    ${navItemsHTML}
                </ul>
            </div>
            <div class="user-profile">
                <img src="${config.user.img}" alt="${config.user.name}" class="avatar">
                <div class="user-info">
                    <h4>${config.user.name}</h4>
                    <p>${config.user.role}</p>
                </div>
            </div>`;
    }

    // ─── FECHA DINÁMICA ───────────────────────────────────────
    const dateStr = new Date().toLocaleDateString('es-MX', {
        day: 'numeric', month: 'short', year: 'numeric'
    });
    document.querySelectorAll('.date-badge').forEach(el => {
        el.textContent = dateStr;
    });

})();
