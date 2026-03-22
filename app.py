from flask import Flask, render_template, request, redirect, url_for
from datetime import date

app = Flask(__name__)

SIDEBAR_CONFIGS = {
    'medico': {
        'logo_icon': 'fa-heart-pulse',
        'logo_title': 'MENTAL HEALTH',
        'logo_subtitle': 'PORTAL MÉDICO',
        'nav_items': [
            {'endpoint': 'medico_dashboard', 'icon': 'fa-table-columns', 'label': 'Dashboard'},
            {'endpoint': 'medico_pacientes', 'icon': 'fa-users',         'label': 'Mis Pacientes'},
            {'endpoint': 'medico_alertas',   'icon': 'fa-bell',          'label': 'Alertas', 'badge': 3},
            {'endpoint': 'medico_sesiones',  'icon': 'fa-video',         'label': 'Sesiones'},
        ],
        'user_img':  'https://picsum.photos/seed/sarah/100/100',
        'user_name': 'Dra. Sarah Miller',
        'user_role': 'Psiquiatra Senior',
    },
    'admin': {
        'logo_icon': 'fa-shield-halved',
        'logo_title': 'ELDERCARE',
        'logo_subtitle': 'PANEL ADMINISTRATIVO',
        'nav_items': [
            {'endpoint': 'admin_dashboard', 'icon': 'fa-gauge-high',       'label': 'Dashboard'},
            {'endpoint': 'admin_pacientes', 'icon': 'fa-users',            'label': 'Pacientes'},
            {'endpoint': 'admin_alertas',   'icon': 'fa-bell',             'label': 'Alertas', 'badge': 8},
            {'endpoint': 'admin_usuarios',  'icon': 'fa-user-gear',        'label': 'Gestión de Usuarios'},
            {'endpoint': 'admin_iot',       'icon': 'fa-map-location-dot', 'label': 'Mapa de Monitoreo IoT'},
            {'endpoint': 'admin_reportes',  'icon': 'fa-file-medical-alt', 'label': 'Reportes Clínicos'},
            {'endpoint': 'admin_auditoria', 'icon': 'fa-list-check',       'label': 'Log de Auditoría'},
        ],
        'user_img':  'https://picsum.photos/seed/admin/100/100',
        'user_name': 'Admin Sistema',
        'user_role': 'Super Usuario',
    },
    'cuidador': {
        'logo_icon': 'fa-hands-holding-circle',
        'logo_title': 'ELDERCARE',
        'logo_subtitle': 'PORTAL CUIDADOR',
        'nav_items': [
            {'endpoint': 'cuidador_dashboard', 'icon': 'fa-table-columns',    'label': 'Dashboard'},
            {'endpoint': 'cuidador_pacientes', 'icon': 'fa-users',            'label': 'Mis Pacientes'},
            {'endpoint': 'cuidador_mapa',      'icon': 'fa-map-location-dot', 'label': 'Mapa IoT'},
        ],
        'user_img':  'https://picsum.photos/seed/care1/100/100',
        'user_name': 'María López',
        'user_role': 'Cuidadora Principal',
    },
}


@app.context_processor
def inject_globals():
    return {'current_date': date.today().strftime('%-d %b %Y')}


# ── Páginas principales ────────────────────────────────────────────────────────

@app.route('/')
def index():
    return render_template('index.html')


@app.route('/login', methods=['GET', 'POST'])
def login():
    if request.method == 'POST':
        email = request.form.get('email', '').lower()
        if 'admin' in email:
            return redirect(url_for('admin_dashboard'))
        elif 'doctor' in email or 'medico' in email:
            return redirect(url_for('medico_dashboard'))
        elif 'cuidador' in email:
            return redirect(url_for('cuidador_dashboard'))
        else:
            return redirect(url_for('medico_dashboard'))
    return render_template('login.html')


# ── Portal Médico ──────────────────────────────────────────────────────────────

@app.route('/medico/dashboard')
def medico_dashboard():
    return render_template('medico/dashboard.html',
                           sidebar=SIDEBAR_CONFIGS['medico'],
                           active='medico_dashboard')


@app.route('/medico/pacientes')
def medico_pacientes():
    return render_template('medico/pacientes.html',
                           sidebar=SIDEBAR_CONFIGS['medico'],
                           active='medico_pacientes')


@app.route('/medico/alertas')
def medico_alertas():
    return render_template('medico/alertas.html',
                           sidebar=SIDEBAR_CONFIGS['medico'],
                           active='medico_alertas')


@app.route('/medico/sesiones')
def medico_sesiones():
    return render_template('medico/sesiones.html',
                           sidebar=SIDEBAR_CONFIGS['medico'],
                           active='medico_sesiones')


# ── Portal Administrativo ──────────────────────────────────────────────────────

@app.route('/admin/dashboard')
def admin_dashboard():
    return render_template('admin/dashboard.html',
                           sidebar=SIDEBAR_CONFIGS['admin'],
                           active='admin_dashboard')


@app.route('/admin/pacientes')
def admin_pacientes():
    return render_template('admin/pacientes.html',
                           sidebar=SIDEBAR_CONFIGS['admin'],
                           active='admin_pacientes')


@app.route('/admin/alertas')
def admin_alertas():
    return render_template('admin/alertas.html',
                           sidebar=SIDEBAR_CONFIGS['admin'],
                           active='admin_alertas')


@app.route('/admin/usuarios')
def admin_usuarios():
    return render_template('admin/usuarios.html',
                           sidebar=SIDEBAR_CONFIGS['admin'],
                           active='admin_usuarios')


@app.route('/admin/iot')
def admin_iot():
    return render_template('admin/iot.html',
                           sidebar=SIDEBAR_CONFIGS['admin'],
                           active='admin_iot')


@app.route('/admin/reportes')
def admin_reportes():
    return render_template('admin/reportes.html',
                           sidebar=SIDEBAR_CONFIGS['admin'],
                           active='admin_reportes')


@app.route('/admin/auditoria')
def admin_auditoria():
    return render_template('admin/auditoria.html',
                           sidebar=SIDEBAR_CONFIGS['admin'],
                           active='admin_auditoria')


# ── Portal Cuidador ────────────────────────────────────────────────────────────

@app.route('/cuidador/dashboard')
def cuidador_dashboard():
    return render_template('cuidador/dashboard.html',
                           sidebar=SIDEBAR_CONFIGS['cuidador'],
                           active='cuidador_dashboard')


@app.route('/cuidador/pacientes')
def cuidador_pacientes():
    return render_template('cuidador/pacientes.html',
                           sidebar=SIDEBAR_CONFIGS['cuidador'],
                           active='cuidador_pacientes')


@app.route('/cuidador/mapa')
def cuidador_mapa():
    return render_template('cuidador/mapa.html',
                           sidebar=SIDEBAR_CONFIGS['cuidador'],
                           active='cuidador_mapa')


if __name__ == '__main__':
    app.run(debug=True)
