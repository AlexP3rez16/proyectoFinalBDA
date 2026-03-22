from flask import Flask, render_template, request, redirect, url_for, session, flash
from datetime import date
from functools import wraps
import psycopg2
from psycopg2.extras import RealDictCursor

app = Flask(__name__)
app.secret_key = 'eldercare_secret_2024'

DB_CONFIG = {
    'host':     'localhost',
    'dbname':   'salud_mental_db',
    'user':     'equipo5proyfin',
    'password': '123',
    'port':     5432,
}

def get_db():
    conn = psycopg2.connect(**DB_CONFIG)
    return conn


def login_required(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        if 'user_id' not in session:
            return redirect(url_for('login'))
        return f(*args, **kwargs)
    return decorated

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
    return {
        'current_date': date.today().strftime('%-d %b %Y'),
        'current_user': {
            'name': session.get('user_name', ''),
            'role': session.get('user_role', ''),
            'img':  session.get('user_img',  'https://picsum.photos/seed/user/100/100'),
        }
    }


# ── Páginas principales ────────────────────────────────────────────────────────

@app.route('/')
def index():
    return render_template('index.html')


@app.route('/login', methods=['GET', 'POST'])
def login():
    error = None
    if request.method == 'POST':
        email    = request.form.get('email', '').strip()
        password = request.form.get('password', '').strip()
        conn = get_db()
        cur  = conn.cursor(cursor_factory=RealDictCursor)
        cur.execute('''
            SELECT p.id_profesional, p.nombre, p.apellidos,
                   p.especialidad, p.email, p.id_rol, r.nombre_rol, r.nivel_acceso
            FROM profesional p
            JOIN rol r ON p.id_rol = r.id_rol
            WHERE p.email = %s AND p.password = %s AND p.activo = TRUE
        ''', (email, password))
        user = cur.fetchone()
        conn.close()

        if user:
            session['user_id']   = user['id_profesional']
            session['user_name'] = f"{user['nombre']} {user['apellidos']}"
            session['user_role'] = user['especialidad']
            session['user_img']  = f"https://picsum.photos/seed/{user['id_profesional']}/100/100"
            session['nivel_acceso'] = user['nivel_acceso']

            if user['nivel_acceso'] == 1:
                return redirect(url_for('admin_dashboard'))
            elif user['nivel_acceso'] == 2:
                return redirect(url_for('medico_dashboard'))
            else:
                return redirect(url_for('cuidador_dashboard'))
        else:
            error = 'Correo o contraseña incorrectos.'

    return render_template('login.html', error=error)


@app.route('/logout')
def logout():
    session.clear()
    return redirect(url_for('login'))


# ── Portal Médico ──────────────────────────────────────────────────────────────

@app.route('/medico/dashboard')
@login_required
def medico_dashboard():
    conn = get_db()
    cur  = conn.cursor(cursor_factory=RealDictCursor)
    cur.execute('SELECT COUNT(*) AS total FROM paciente')
    total_pacientes = cur.fetchone()['total']
    cur.execute("SELECT COUNT(*) AS total FROM alerta_riesgo WHERE estado_alerta = 'Activa'")
    alertas_activas = cur.fetchone()['total']
    cur.execute('SELECT COUNT(*) AS total FROM sesion_psicologica')
    total_sesiones = cur.fetchone()['total']
    cur.execute("SELECT COUNT(*) AS total FROM alerta_riesgo WHERE nivel_severidad = 'Grave'")
    riesgos_graves = cur.fetchone()['total']
    cur.execute('''
        SELECT p.nombre || ' ' || p.apellidos AS paciente,
               s.tipo_sesion, s.notas_clinicas,
               TO_CHAR(s.fecha_sesion, 'DD Mon, HH12:MI AM') AS fecha,
               a.nivel_severidad
        FROM sesion_psicologica s
        JOIN paciente p ON s.id_paciente = p.id_paciente
        LEFT JOIN (
            SELECT DISTINCT ON (id_paciente) id_paciente, nivel_severidad
            FROM alerta_riesgo ORDER BY id_paciente, fecha_generacion DESC
        ) a ON p.id_paciente = a.id_paciente
        ORDER BY s.fecha_sesion DESC LIMIT 5
    ''')
    sesiones_recientes = cur.fetchall()
    conn.close()
    return render_template('medico/dashboard.html',
                           sidebar=SIDEBAR_CONFIGS['medico'],
                           active='medico_dashboard',
                           total_pacientes=total_pacientes,
                           alertas_activas=alertas_activas,
                           total_sesiones=total_sesiones,
                           riesgos_graves=riesgos_graves,
                           sesiones_recientes=sesiones_recientes)


@app.route('/medico/pacientes')
@login_required
def medico_pacientes():
    conn = get_db()
    cur  = conn.cursor(cursor_factory=RealDictCursor)
    cur.execute('''
        SELECT p.id_paciente,
               p.nombre, p.apellidos,
               EXTRACT(YEAR FROM AGE(p.fecha_nacimiento))::int AS edad,
               p.diagnostico_principal,
               TO_CHAR(s.ultima_sesion, 'DD Mon, HH12:MI AM') AS ultima_sesion,
               a.nivel_severidad
        FROM paciente p
        LEFT JOIN (
            SELECT id_paciente, MAX(fecha_sesion) AS ultima_sesion
            FROM sesion_psicologica GROUP BY id_paciente
        ) s ON p.id_paciente = s.id_paciente
        LEFT JOIN (
            SELECT DISTINCT ON (id_paciente) id_paciente, nivel_severidad
            FROM alerta_riesgo ORDER BY id_paciente, fecha_generacion DESC
        ) a ON p.id_paciente = a.id_paciente
        ORDER BY p.id_paciente
    ''')
    pacientes = cur.fetchall()
    total     = len(pacientes)
    criticos  = sum(1 for p in pacientes if p['nivel_severidad'] == 'Grave')
    conn.close()
    return render_template('medico/pacientes.html',
                           sidebar=SIDEBAR_CONFIGS['medico'],
                           active='medico_pacientes',
                           pacientes=pacientes,
                           total=total,
                           criticos=criticos)


@app.route('/medico/alertas')
@login_required
def medico_alertas():
    conn = get_db()
    cur  = conn.cursor(cursor_factory=RealDictCursor)
    cur.execute('''
        SELECT a.id_alerta,
               p.id_paciente, p.nombre || ' ' || p.apellidos AS paciente,
               a.tipo_alerta, a.nivel_severidad, a.estado_alerta,
               TO_CHAR(a.fecha_generacion, 'DD Mon HH12:MI AM') AS fecha
        FROM alerta_riesgo a
        JOIN paciente p ON a.id_paciente = p.id_paciente
        ORDER BY a.fecha_generacion DESC
    ''')
    alertas   = cur.fetchall()
    total     = len(alertas)
    graves    = sum(1 for a in alertas if a['nivel_severidad'] == 'Grave')
    moderadas = sum(1 for a in alertas if a['nivel_severidad'] == 'Moderado')
    resueltas = sum(1 for a in alertas if a['estado_alerta']   == 'Cerrada')
    conn.close()
    return render_template('medico/alertas.html',
                           sidebar=SIDEBAR_CONFIGS['medico'],
                           active='medico_alertas',
                           alertas=alertas, total=total,
                           graves=graves, moderadas=moderadas, resueltas=resueltas)


@app.route('/medico/sesiones')
@login_required
def medico_sesiones():
    conn = get_db()
    cur  = conn.cursor(cursor_factory=RealDictCursor)

    # Lista de sesiones
    cur.execute('''
        SELECT s.id_sesion,
               p.id_paciente,
               p.nombre || ' ' || p.apellidos           AS paciente,
               pr.nombre || ' ' || pr.apellidos         AS profesional,
               s.tipo_sesion, s.duracion_min,
               s.notas_clinicas,
               s.estado_emoc_inicio, s.estado_emoc_fin,
               TO_CHAR(s.fecha_sesion, 'DD Mon YYYY')   AS fecha,
               TO_CHAR(s.fecha_sesion, 'HH12:MI AM')    AS hora
        FROM sesion_psicologica s
        JOIN paciente    p  ON s.id_paciente    = p.id_paciente
        JOIN profesional pr ON s.id_profesional = pr.id_profesional
        ORDER BY s.fecha_sesion DESC
    ''')
    sesiones = cur.fetchall()

    # Detalle de la primera sesión (panel derecho)
    detalle = sesiones[0] if sesiones else None

    # Evolución emocional del paciente de la primera sesión
    evolucion = []
    if detalle:
        cur.execute('''
            SELECT e.puntaje_emocional, e.etiqueta_estado,
                   TO_CHAR(s.fecha_sesion, 'DD Mon') AS fecha
            FROM evolucion_emocional e
            JOIN sesion_psicologica s ON e.id_sesion = s.id_sesion
            WHERE e.id_paciente = %s
            ORDER BY s.fecha_sesion
        ''', (detalle['id_paciente'],))
        evolucion = cur.fetchall()

    total     = len(sesiones)
    completadas = total  # todas tienen notas = completadas en este modelo
    conn.close()
    return render_template('medico/sesiones.html',
                           sidebar=SIDEBAR_CONFIGS['medico'],
                           active='medico_sesiones',
                           sesiones=sesiones, detalle=detalle,
                           evolucion=evolucion,
                           total=total, completadas=completadas)


@app.route('/medico/sesiones/nueva', methods=['GET', 'POST'])
@login_required
def medico_sesion_nueva():
    conn = get_db()
    cur  = conn.cursor(cursor_factory=RealDictCursor)
    cur.execute('SELECT id_paciente, nombre, apellidos FROM paciente ORDER BY nombre')
    pacientes = cur.fetchall()
    conn.close()
    if request.method == 'POST':
        f = request.form
        conn = get_db()
        cur  = conn.cursor()
        cur.execute('''
            INSERT INTO sesion_psicologica
                (id_paciente, id_profesional, fecha_sesion, tipo_sesion,
                 duracion_min, notas_clinicas, estado_emoc_inicio, estado_emoc_fin)
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
        ''', (f['id_paciente'], session['user_id'], f['fecha_sesion'], f['tipo_sesion'],
              f.get('duracion_min') or None, f.get('notas_clinicas') or None,
              f.get('estado_emoc_inicio') or None, f.get('estado_emoc_fin') or None))
        conn.commit()
        conn.close()
        return redirect(url_for('medico_sesiones'))
    return render_template('medico/sesion_nueva.html',
                           sidebar=SIDEBAR_CONFIGS['medico'],
                           active='medico_sesiones',
                           pacientes=pacientes)


# ── Portal Administrativo ──────────────────────────────────────────────────────

@app.route('/admin/dashboard')
@login_required
def admin_dashboard():
    conn = get_db()
    cur  = conn.cursor(cursor_factory=RealDictCursor)
    cur.execute('SELECT COUNT(*) AS total FROM paciente')
    total_pacientes = cur.fetchone()['total']
    cur.execute("SELECT COUNT(*) AS total FROM alerta_riesgo WHERE nivel_severidad = 'Grave' AND estado_alerta = 'Activa'")
    alertas_graves = cur.fetchone()['total']
    cur.execute('SELECT COUNT(*) AS total FROM sesion_psicologica')
    total_sesiones = cur.fetchone()['total']
    cur.execute("SELECT COUNT(*) AS total FROM profesional WHERE activo = TRUE")
    total_staff = cur.fetchone()['total']
    cur.execute('''
        SELECT a.id_alerta, p.nombre || ' ' || p.apellidos AS paciente,
               p.id_paciente, a.tipo_alerta, a.nivel_severidad,
               TO_CHAR(a.fecha_generacion, 'DD Mon, HH12:MI AM') AS fecha
        FROM alerta_riesgo a JOIN paciente p ON a.id_paciente = p.id_paciente
        WHERE a.estado_alerta = 'Activa'
        ORDER BY a.fecha_generacion DESC LIMIT 5
    ''')
    alertas_recientes = cur.fetchall()
    cur.execute('''
        SELECT l.id_log, pr.nombre || ' ' || pr.apellidos AS usuario,
               l.tabla_afectada, l.operacion,
               TO_CHAR(l.timestamp_operacion, 'DD Mon, HH12:MI AM') AS hora
        FROM log_auditoria l JOIN profesional pr ON l.id_usuario = pr.id_profesional
        ORDER BY l.timestamp_operacion DESC LIMIT 5
    ''')
    logs = cur.fetchall()
    conn.close()
    return render_template('admin/dashboard.html',
                           sidebar=SIDEBAR_CONFIGS['admin'],
                           active='admin_dashboard',
                           total_pacientes=total_pacientes,
                           alertas_graves=alertas_graves,
                           total_sesiones=total_sesiones,
                           total_staff=total_staff,
                           alertas_recientes=alertas_recientes,
                           logs=logs)


@app.route('/admin/pacientes')
@login_required
def admin_pacientes():
    conn = get_db()
    cur  = conn.cursor(cursor_factory=RealDictCursor)
    cur.execute('''
        SELECT p.id_paciente,
               p.nombre, p.apellidos,
               EXTRACT(YEAR FROM AGE(p.fecha_nacimiento))::int AS edad,
               p.diagnostico_principal,
               c.nombre || ' ' || c.apellidos AS cuidador,
               TO_CHAR(s.ultima_sesion, 'DD Mon, HH12:MI AM') AS ultima_sesion,
               a.nivel_severidad
        FROM paciente p
        LEFT JOIN cuidador c ON p.id_cuidador = c.id_cuidador
        LEFT JOIN (
            SELECT id_paciente, MAX(fecha_sesion) AS ultima_sesion
            FROM sesion_psicologica GROUP BY id_paciente
        ) s ON p.id_paciente = s.id_paciente
        LEFT JOIN (
            SELECT DISTINCT ON (id_paciente) id_paciente, nivel_severidad
            FROM alerta_riesgo ORDER BY id_paciente, fecha_generacion DESC
        ) a ON p.id_paciente = a.id_paciente
        ORDER BY p.id_paciente
    ''')
    pacientes = cur.fetchall()
    total     = len(pacientes)
    criticos  = sum(1 for p in pacientes if p['nivel_severidad'] == 'Grave')
    moderados = sum(1 for p in pacientes if p['nivel_severidad'] == 'Moderado')
    estables  = sum(1 for p in pacientes if p['nivel_severidad'] not in ('Grave', 'Moderado'))
    conn.close()
    return render_template('admin/pacientes.html',
                           sidebar=SIDEBAR_CONFIGS['admin'],
                           active='admin_pacientes',
                           pacientes=pacientes,
                           total=total,
                           criticos=criticos,
                           moderados=moderados,
                           estables=estables)


@app.route('/admin/alertas')
@login_required
def admin_alertas():
    conn = get_db()
    cur  = conn.cursor(cursor_factory=RealDictCursor)
    cur.execute('''
        SELECT a.id_alerta,
               p.id_paciente, p.nombre || ' ' || p.apellidos AS paciente,
               a.tipo_alerta, a.nivel_severidad, a.estado_alerta,
               TO_CHAR(a.fecha_generacion, 'DD Mon HH12:MI AM') AS fecha
        FROM alerta_riesgo a
        JOIN paciente p ON a.id_paciente = p.id_paciente
        ORDER BY a.fecha_generacion DESC
    ''')
    alertas   = cur.fetchall()
    total     = len(alertas)
    graves    = sum(1 for a in alertas if a['nivel_severidad'] == 'Grave')
    moderadas = sum(1 for a in alertas if a['nivel_severidad'] == 'Moderado')
    resueltas = sum(1 for a in alertas if a['estado_alerta']   == 'Cerrada')
    conn.close()
    return render_template('admin/alertas.html',
                           sidebar=SIDEBAR_CONFIGS['admin'],
                           active='admin_alertas',
                           alertas=alertas, total=total,
                           graves=graves, moderadas=moderadas, resueltas=resueltas)


@app.route('/admin/pacientes/nuevo', methods=['GET', 'POST'])
@login_required
def admin_paciente_nuevo():
    conn = get_db()
    cur  = conn.cursor(cursor_factory=RealDictCursor)
    cur.execute('SELECT id_cuidador, nombre, apellidos FROM cuidador ORDER BY nombre')
    cuidadores = cur.fetchall()
    conn.close()
    if request.method == 'POST':
        f = request.form
        conn = get_db()
        cur  = conn.cursor()
        cur.execute('''
            INSERT INTO paciente (nombre, apellidos, fecha_nacimiento, sexo, curp, telefono, diagnostico_principal, id_cuidador)
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
        ''', (f['nombre'], f['apellidos'], f['fecha_nacimiento'], f['sexo'],
              f.get('curp') or None, f.get('telefono') or None,
              f.get('diagnostico_principal') or None,
              f.get('id_cuidador') or None))
        conn.commit()
        conn.close()
        return redirect(url_for('admin_pacientes'))
    return render_template('admin/paciente_nuevo.html',
                           sidebar=SIDEBAR_CONFIGS['admin'],
                           active='admin_pacientes',
                           cuidadores=cuidadores)


@app.route('/admin/usuarios')
@login_required
def admin_usuarios():
    conn = get_db()
    cur  = conn.cursor(cursor_factory=RealDictCursor)
    cur.execute('''
        SELECT pr.id_profesional, pr.nombre, pr.apellidos,
               pr.especialidad, pr.email, pr.cedula,
               pr.activo, r.nombre_rol,
               TO_CHAR(pr.fecha_alta, 'DD Mon YYYY') AS fecha_alta
        FROM profesional pr JOIN rol r ON pr.id_rol = r.id_rol
        ORDER BY pr.id_profesional
    ''')
    profesionales = cur.fetchall()
    cur.execute('''
        SELECT id_cuidador, nombre, apellidos, email, turno, activo,
               TO_CHAR(fecha_alta, 'DD Mon YYYY') AS fecha_alta
        FROM cuidador ORDER BY id_cuidador
    ''')
    cuidadores = cur.fetchall()
    total_prof  = len(profesionales)
    total_cuid  = len(cuidadores)
    conn.close()
    return render_template('admin/usuarios.html',
                           sidebar=SIDEBAR_CONFIGS['admin'],
                           active='admin_usuarios',
                           profesionales=profesionales,
                           cuidadores=cuidadores,
                           total_prof=total_prof,
                           total_cuid=total_cuid)


@app.route('/admin/iot')
@login_required
def admin_iot():
    return render_template('admin/iot.html',
                           sidebar=SIDEBAR_CONFIGS['admin'],
                           active='admin_iot')


@app.route('/admin/reportes')
@login_required
def admin_reportes():
    conn = get_db()
    cur  = conn.cursor(cursor_factory=RealDictCursor)
    cur.execute('''
        SELECT p.nombre || ' ' || p.apellidos AS paciente,
               ae.id_escala, ae.puntaje_total, ae.nivel_riesgo, ae.interpretacion,
               TO_CHAR(ae.fecha_aplicacion, 'DD Mon YYYY') AS fecha,
               pr.nombre || ' ' || pr.apellidos AS profesional
        FROM aplicacion_escala ae
        JOIN paciente    p  ON ae.id_paciente    = p.id_paciente
        JOIN profesional pr ON ae.id_profesional = pr.id_profesional
        ORDER BY ae.fecha_aplicacion DESC
    ''')
    reportes = cur.fetchall()
    cur.execute('''
        SELECT nivel_riesgo, COUNT(*) AS total
        FROM aplicacion_escala GROUP BY nivel_riesgo
    ''')
    resumen = {r['nivel_riesgo']: r['total'] for r in cur.fetchall()}
    conn.close()
    return render_template('admin/reportes.html',
                           sidebar=SIDEBAR_CONFIGS['admin'],
                           active='admin_reportes',
                           reportes=reportes,
                           resumen=resumen)


@app.route('/admin/auditoria')
@login_required
def admin_auditoria():
    conn = get_db()
    cur  = conn.cursor(cursor_factory=RealDictCursor)
    cur.execute('''
        SELECT l.id_log, pr.nombre || ' ' || pr.apellidos AS usuario,
               l.tabla_afectada, l.operacion, l.id_registro_afectado, l.ip_origen,
               TO_CHAR(l.timestamp_operacion, 'DD Mon YYYY HH12:MI AM') AS hora
        FROM log_auditoria l JOIN profesional pr ON l.id_usuario = pr.id_profesional
        ORDER BY l.timestamp_operacion DESC
    ''')
    logs = cur.fetchall()
    total = len(logs)
    conn.close()
    return render_template('admin/auditoria.html',
                           sidebar=SIDEBAR_CONFIGS['admin'],
                           active='admin_auditoria',
                           logs=logs, total=total)


# ── Portal Cuidador ────────────────────────────────────────────────────────────

@app.route('/cuidador/dashboard')
@login_required
def cuidador_dashboard():
    conn = get_db()
    cur  = conn.cursor(cursor_factory=RealDictCursor)
    cur.execute('SELECT COUNT(*) AS total FROM paciente')
    total_pacientes = cur.fetchone()['total']
    cur.execute("SELECT COUNT(*) AS total FROM alerta_riesgo WHERE estado_alerta = 'Activa'")
    alertas_activas = cur.fetchone()['total']
    cur.execute('SELECT COUNT(*) AS total FROM cuidador')
    total_cuidadores = cur.fetchone()['total']
    cur.execute('''
        SELECT p.id_paciente, p.nombre || ' ' || p.apellidos AS paciente,
               p.diagnostico_principal, a.nivel_severidad,
               o.descripcion AS ultima_obs,
               TO_CHAR(o.fecha_observacion, 'DD Mon') AS fecha_obs
        FROM paciente p
        LEFT JOIN (
            SELECT DISTINCT ON (id_paciente) id_paciente, nivel_severidad
            FROM alerta_riesgo ORDER BY id_paciente, fecha_generacion DESC
        ) a ON p.id_paciente = a.id_paciente
        LEFT JOIN (
            SELECT DISTINCT ON (id_paciente) id_paciente, descripcion, fecha_observacion
            FROM observacion_cuidador ORDER BY id_paciente, fecha_observacion DESC
        ) o ON p.id_paciente = o.id_paciente
        ORDER BY p.id_paciente
    ''')
    pacientes = cur.fetchall()
    conn.close()
    return render_template('cuidador/dashboard.html',
                           sidebar=SIDEBAR_CONFIGS['cuidador'],
                           active='cuidador_dashboard',
                           total_pacientes=total_pacientes,
                           alertas_activas=alertas_activas,
                           total_cuidadores=total_cuidadores,
                           pacientes=pacientes)


@app.route('/cuidador/pacientes')
@login_required
def cuidador_pacientes():
    conn = get_db()
    cur  = conn.cursor(cursor_factory=RealDictCursor)
    cur.execute('''
        SELECT p.id_paciente, p.nombre, p.apellidos,
               EXTRACT(YEAR FROM AGE(p.fecha_nacimiento))::int AS edad,
               p.diagnostico_principal, p.telefono,
               c.nombre || ' ' || c.apellidos AS cuidador,
               a.nivel_severidad,
               TO_CHAR(o.fecha_observacion, 'DD Mon') AS ultima_obs
        FROM paciente p
        LEFT JOIN cuidador c ON p.id_cuidador = c.id_cuidador
        LEFT JOIN (
            SELECT DISTINCT ON (id_paciente) id_paciente, nivel_severidad
            FROM alerta_riesgo ORDER BY id_paciente, fecha_generacion DESC
        ) a ON p.id_paciente = a.id_paciente
        LEFT JOIN (
            SELECT DISTINCT ON (id_paciente) id_paciente, fecha_observacion
            FROM observacion_cuidador ORDER BY id_paciente, fecha_observacion DESC
        ) o ON p.id_paciente = o.id_paciente
        ORDER BY p.id_paciente
    ''')
    pacientes = cur.fetchall()
    conn.close()
    return render_template('cuidador/pacientes.html',
                           sidebar=SIDEBAR_CONFIGS['cuidador'],
                           active='cuidador_pacientes',
                           pacientes=pacientes)


@app.route('/cuidador/mapa')
@login_required
def cuidador_mapa():
    return render_template('cuidador/mapa.html',
                           sidebar=SIDEBAR_CONFIGS['cuidador'],
                           active='cuidador_mapa')


@app.route('/alerta/<int:id_alerta>/resolver', methods=['POST'])
@login_required
def alerta_resolver(id_alerta):
    conn = get_db()
    cur  = conn.cursor()
    cur.execute('''
        UPDATE alerta_riesgo
        SET estado_alerta = 'Cerrada', fecha_resolucion = NOW()
        WHERE id_alerta = %s
    ''', (id_alerta,))
    conn.commit()
    conn.close()
    return redirect(request.referrer or url_for('medico_alertas'))


if __name__ == '__main__':
    app.run(debug=True, port=8080)
