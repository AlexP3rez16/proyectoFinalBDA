import os
os.environ['PGCLIENTENCODING'] = 'UTF8'

from flask import (Flask, render_template, request, redirect,
                   url_for, session, flash, jsonify)
from functools import wraps
from datetime import date, timedelta
from collections import defaultdict
import psycopg2
from psycopg2.extras import RealDictCursor
from werkzeug.security import check_password_hash, generate_password_hash

app = Flask(__name__)
app.secret_key = 'asilo_eldercare_secret_2026'

DB_CONFIG = {
    'host':     'localhost',
    'dbname':   'asilo_db',
    'user':     'equipo5proyfin',
    'password': '123',
    'port':     5432,
}

# ── DB helpers ────────────────────────────────────────────────────────────────

def get_db():
    return psycopg2.connect(**DB_CONFIG)

def query(sql, params=None, fetchone=False, fetchall=False, commit=False):
    """Simple inline SELECT helper. For writes, use call_proc or call_refcursor."""
    try:
        conn = get_db()
        cur  = conn.cursor(cursor_factory=RealDictCursor)
        cur.execute(sql, params or ())
        result = None
        if fetchone:   result = cur.fetchone()
        elif fetchall: result = cur.fetchall()
        if commit:     conn.commit()
        cur.close(); conn.close()
        return result
    except Exception as e:
        print(f"DB ERROR: {e}")
        return None

def call_proc(sql, params=(), user_id=None):
    """Call a procedure with OUT ok INT, OUT msg TEXT.
    Returns (ok: int, msg: str).
    Pass user_id to stamp app.id_usuario for audit triggers.
    """
    conn = get_db()
    cur  = conn.cursor()
    try:
        if user_id is not None:
            cur.execute("SELECT set_config('app.id_usuario', %s, TRUE)", (str(user_id),))
        cur.execute(sql, params)
        conn.commit()
        row = cur.fetchone()
        return (int(row[0]), str(row[1])) if row else (0, 'Sin respuesta del servidor.')
    except Exception as e:
        conn.rollback()
        return (0, str(e))
    finally:
        cur.close(); conn.close()


def _check_password(stored_hash, provided):
    """Check password supporting both werkzeug hashes (new) and plain text (seed data)."""
    if stored_hash.startswith(('pbkdf2:', 'scrypt:')):
        return check_password_hash(stored_hash, provided)
    return stored_hash == provided

def call_refcursor(sql, params=()):
    """Call a procedure that opens a REFCURSOR named 'resultado'.
    Returns list of RealDictRow.
    """
    conn = get_db()
    cur  = conn.cursor(cursor_factory=RealDictCursor)
    try:
        cur.execute("BEGIN")
        cur.execute(sql, params)
        cur.execute("FETCH ALL FROM resultado")
        rows = cur.fetchall()
        cur.execute("COMMIT")
        return rows
    except Exception as e:
        try: cur.execute("ROLLBACK")
        except: pass
        print(f"REFCURSOR ERROR: {e}")
        return []
    finally:
        cur.close(); conn.close()

# ── Auth & decorators ─────────────────────────────────────────────────────────

def login_required(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        if 'user_id' not in session:
            return redirect(url_for('login'))
        return f(*args, **kwargs)
    return decorated

def rol_required(*niveles):
    """Restrict route to one or more nivel_acceso values."""
    def decorator(f):
        @wraps(f)
        def decorated(*args, **kwargs):
            if 'user_id' not in session:
                return redirect(url_for('login'))
            if session.get('nivel_acceso') not in niveles:
                flash('No tienes permiso para acceder a esa sección.', 'error')
                return redirect(url_for('index'))
            return f(*args, **kwargs)
        return decorated
    return decorator

# ── Sidebar config per role ───────────────────────────────────────────────────

SIDEBAR = {
    1: {  # Administrador
        'logo_icon':    'fa-shield-halved',
        'logo_title':   'ELDERCARE',
        'logo_subtitle':'PANEL ADMINISTRATIVO',
        'nav_items': [
            {'endpoint': 'admin_dashboard',  'icon': 'fa-gauge-high',       'label': 'Dashboard'},
            {'endpoint': 'admin_residentes', 'icon': 'fa-users',            'label': 'Residentes'},
            {'endpoint': 'admin_staff',      'icon': 'fa-user-gear',        'label': 'Personal'},
            {'endpoint': 'admin_iot',        'icon': 'fa-map-location-dot', 'label': 'Monitoreo IoT'},
            {'endpoint': 'admin_rfid',       'icon': 'fa-door-open',        'label': 'Accesos RFID'},
            {'endpoint': 'admin_reportes',   'icon': 'fa-file-chart-column','label': 'Reportes'},
            {'endpoint': 'admin_auditoria',  'icon': 'fa-list-check',       'label': 'Auditoría'},
        ],
    },
    2: {  # Terapeuta
        'logo_icon':    'fa-heart-pulse',
        'logo_title':   'ELDERCARE',
        'logo_subtitle':'PORTAL TERAPEUTA',
        'nav_items': [
            {'endpoint': 'terapeuta_dashboard',  'icon': 'fa-table-columns',         'label': 'Dashboard'},
            {'endpoint': 'terapeuta_residentes', 'icon': 'fa-users',                 'label': 'Mis Residentes'},
            {'endpoint': 'terapeuta_sesiones',   'icon': 'fa-calendar-check',        'label': 'Sesiones'},
            {'endpoint': 'terapeuta_incidentes', 'icon': 'fa-triangle-exclamation',  'label': 'Incidentes'},
        ],
    },
    3: {  # Cuidador
        'logo_icon':    'fa-hands-holding-circle',
        'logo_title':   'ELDERCARE',
        'logo_subtitle':'PORTAL CUIDADOR',
        'nav_items': [
            {'endpoint': 'cuidador_dashboard',    'icon': 'fa-table-columns', 'label': 'Dashboard'},
            {'endpoint': 'cuidador_residentes',   'icon': 'fa-users',         'label': 'Mis Residentes'},
            {'endpoint': 'cuidador_medicamentos', 'icon': 'fa-pills',         'label': 'Medicamentos'},
            {'endpoint': 'cuidador_nfc',          'icon': 'fa-mobile-screen', 'label': 'Escaneo NFC'},
        ],
    },
}

@app.context_processor
def inject_globals():
    nivel      = session.get('nivel_acceso', 0)
    full_name  = session.get('user_name', '')
    first_name = full_name.split(' ')[0] if full_name else ''
    today      = date.today()
    return {
        # current_date: date object so templates can call .strftime() freely
        'current_date':     today,
        # current_date_str: pre-formatted string for base.html topbar
        'current_date_str': today.strftime('%d %b %Y'),
        'sidebar':          SIDEBAR.get(nivel, {}),
        'active':           request.endpoint or '',
        'current_user': {
            'name':   full_name,     # "Ana García" — for avatar/greeting where full name needed
            'nombre': first_name,    # "Ana" — for dashboard salutations
            'role':   session.get('user_role', ''),
            'nivel':  nivel,
        },
    }

# ── Index / Login / Logout ────────────────────────────────────────────────────

@app.route('/')
def index():
    if 'user_id' in session:
        nivel = session.get('nivel_acceso')
        if nivel == 1: return redirect(url_for('admin_dashboard'))
        if nivel == 2: return redirect(url_for('terapeuta_dashboard'))
        if nivel == 3: return redirect(url_for('cuidador_dashboard'))
    return render_template('index.html')

@app.route('/login', methods=['GET', 'POST'])
def login():
    if request.method == 'POST':
        username = request.form.get('username', '').strip()
        password = request.form.get('password', '').strip()

        user = query('''
            SELECT u.id_usuario, u.username, u.password_hash,
                   s.id_staff, s.nombre, s.apellidos, s.especialidad,
                   r.nivel_acceso, r.nombre_rol
            FROM usuario_sistema u
            JOIN staff s ON u.id_staff = s.id_staff
            JOIN rol   r ON s.id_rol   = r.id_rol
            WHERE u.username = %s
              AND u.activo   = TRUE
              AND s.activo   = TRUE
        ''', (username,), fetchone=True)

        if user and _check_password(user['password_hash'], password):
            query('UPDATE usuario_sistema SET ultimo_login = NOW() WHERE id_usuario = %s',
                  (user['id_usuario'],), commit=True)

            session['user_id']      = user['id_usuario']
            session['staff_id']     = user['id_staff']
            session['user_name']    = f"{user['nombre']} {user['apellidos']}"
            session['user_role']    = user['especialidad']
            session['nivel_acceso'] = user['nivel_acceso']

            nivel = user['nivel_acceso']
            if nivel == 1: return redirect(url_for('admin_dashboard'))
            if nivel == 2: return redirect(url_for('terapeuta_dashboard'))
            return redirect(url_for('cuidador_dashboard'))

        flash('Usuario o contraseña incorrectos.', 'error')

    return render_template('login.html')

@app.route('/logout')
def logout():
    session.clear()
    return redirect(url_for('login'))

# ═════════════════════════════════════════════════════════════════════════════
# PORTAL ADMINISTRADOR
# ═════════════════════════════════════════════════════════════════════════════

@app.route('/admin/dashboard')
@rol_required(1)
def admin_dashboard():
    total_residentes = query(
        "SELECT COUNT(*) AS c FROM residente WHERE activo = TRUE", fetchone=True)['c']
    total_staff = query(
        "SELECT COUNT(*) AS c FROM staff WHERE activo = TRUE", fetchone=True)['c']
    incidentes_alta = query(
        "SELECT COUNT(*) AS c FROM reporte_incidente WHERE severidad = 'Alta' "
        "AND fecha >= NOW() - INTERVAL '7 days'", fetchone=True)['c']
    medicamentos_pendientes = query(
        "SELECT COUNT(*) AS c FROM v_medicamentos_pendientes_hoy", fetchone=True)['c']

    incidentes_recientes = query(
        "SELECT * FROM v_incidentes_recientes LIMIT 5", fetchall=True) or []
    sesiones_hoy         = query(
        "SELECT * FROM v_sesiones_hoy", fetchall=True) or []
    staff_turno          = query(
        "SELECT * FROM v_staff_en_turno_hoy", fetchall=True) or []

    return render_template('admin/dashboard.html',
                           total_residentes=total_residentes,
                           total_staff=total_staff,
                           incidentes_alta=incidentes_alta,
                           medicamentos_pendientes=medicamentos_pendientes,
                           incidentes_recientes=incidentes_recientes,
                           sesiones_hoy=sesiones_hoy,
                           staff_turno=staff_turno)

# ── Residentes ────────────────────────────────────────────────────────────────

@app.route('/admin/residentes')
@rol_required(1)
def admin_residentes():
    residentes = query("SELECT * FROM v_residentes_resumen", fetchall=True) or []
    return render_template('admin/residentes.html', residentes=residentes)

@app.route('/admin/residentes/nuevo', methods=['GET', 'POST'])
@rol_required(1)
def admin_residente_nuevo():
    cuidadores = query(
        "SELECT s.id_staff, s.nombre || ' ' || s.apellidos AS nombre "
        "FROM staff s JOIN rol r ON s.id_rol = r.id_rol "
        "WHERE r.nivel_acceso = 3 AND s.activo = TRUE ORDER BY s.apellidos",
        fetchall=True) or []

    if request.method == 'POST':
        f = request.form
        ok, msg = call_proc(
            "CALL sp_registrar_residente(%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,NULL,NULL)",
            (f['nombre'], f['apellidos'], f['fecha_nacimiento'], f['sexo'],
             f.get('habitacion') or None, f.get('diagnostico') or None,
             f.get('nivel_movilidad', 'Autonomo'),
             f.get('contacto') or None, f.get('tel_contacto') or None,
             f.get('id_cuidador') or None),
            user_id=session.get('user_id'))
        flash(msg, 'exito' if ok else 'error')
        if ok:
            return redirect(url_for('admin_residentes'))

    return render_template('admin/residente_nuevo.html', cuidadores=cuidadores)

@app.route('/admin/residentes/<int:id_residente>')
@rol_required(1)
def admin_residente_detalle(id_residente):
    residente = query(
        "SELECT r.*, EXTRACT(YEAR FROM AGE(r.fecha_nacimiento))::INT AS edad, "
        "TO_CHAR(r.fecha_ingreso, 'DD Mon YYYY') AS fecha_ingreso "
        "FROM residente r WHERE r.id_residente = %s",
        (id_residente,), fetchone=True)
    if not residente:
        flash('Residente no encontrado.', 'error')
        return redirect(url_for('admin_residentes'))

    asignaciones = query(
        "SELECT a.*, s.nombre || ' ' || s.apellidos AS staff_nombre, "
        "ro.nombre_rol AS tipo_rol, a.es_principal "
        "FROM asignacion a JOIN staff s ON a.id_staff = s.id_staff "
        "JOIN rol ro ON s.id_rol = ro.id_rol "
        "WHERE a.id_residente = %s AND a.fecha_fin IS NULL ORDER BY a.es_principal DESC",
        (id_residente,), fetchall=True) or []

    sesiones = query(
        "SELECT st.*, s.nombre || ' ' || s.apellidos AS terapeuta, sa.nombre AS sala "
        "FROM sesion_terapia st "
        "JOIN staff s ON st.id_terapeuta = s.id_staff "
        "JOIN sala sa ON st.id_sala = sa.id_sala "
        "WHERE st.id_residente = %s ORDER BY st.fecha_sesion DESC LIMIT 10",
        (id_residente,), fetchall=True) or []

    checkins = query(
        "SELECT c.*, s.nombre || ' ' || s.apellidos AS cuidador "
        "FROM checkin_estado_animo c JOIN staff s ON c.id_cuidador = s.id_staff "
        "WHERE c.id_residente = %s ORDER BY c.fecha_registro DESC LIMIT 10",
        (id_residente,), fetchall=True) or []

    incidentes = query(
        "SELECT ri.*, s.nombre || ' ' || s.apellidos AS reportado_por, "
        "TO_CHAR(ri.fecha, 'DD Mon YYYY HH12:MI AM') AS fecha "
        "FROM reporte_incidente ri JOIN staff s ON ri.id_staff = s.id_staff "
        "WHERE ri.id_residente = %s ORDER BY ri.fecha DESC LIMIT 5",
        (id_residente,), fetchall=True) or []

    return render_template('admin/residente_detalle.html',
                           residente=residente,
                           asignaciones=asignaciones,
                           sesiones=sesiones,
                           checkins=checkins,
                           incidentes=incidentes)

@app.route('/admin/residentes/<int:id_residente>/editar', methods=['POST'])
@rol_required(1)
def admin_residente_editar(id_residente):
    f = request.form
    ok, msg = call_proc(
        "CALL sp_actualizar_residente(%s,%s,%s,%s,%s,%s,NULL,NULL)",
        (id_residente, f.get('habitacion') or None, f.get('diagnostico') or None,
         f.get('nivel_movilidad', 'Autonomo'),
         f.get('contacto') or None, f.get('tel_contacto') or None),
        user_id=session.get('user_id'))
    flash(msg, 'exito' if ok else 'error')
    return redirect(url_for('admin_residente_detalle', id_residente=id_residente))

@app.route('/admin/residentes/<int:id_residente>/baja', methods=['POST'])
@rol_required(1)
def admin_residente_baja(id_residente):
    ok, msg = call_proc(
        "CALL sp_dar_baja_residente(%s,NULL,NULL)", (id_residente,),
        user_id=session.get('user_id'))
    flash(msg, 'exito' if ok else 'error')
    return redirect(url_for('admin_residentes'))

# ── Staff ─────────────────────────────────────────────────────────────────────

@app.route('/admin/staff')
@rol_required(1)
def admin_staff():
    staff = query(
        "SELECT s.*, r.nombre_rol, r.nivel_acceso, "
        "TO_CHAR(s.fecha_alta, 'DD Mon YYYY') AS fecha_alta_fmt "
        "FROM staff s JOIN rol r ON s.id_rol = r.id_rol "
        "ORDER BY r.nivel_acceso, s.apellidos",
        fetchall=True) or []
    roles = query("SELECT * FROM rol ORDER BY nivel_acceso", fetchall=True) or []
    return render_template('admin/staff.html', staff=staff, roles=roles)

@app.route('/admin/staff/nuevo', methods=['POST'])
@rol_required(1)
def admin_staff_nuevo():
    f = request.form
    ok, msg = call_proc(
        "CALL sp_registrar_staff(%s,%s,%s,%s,%s,%s,%s,NULL,NULL)",
        (f['nombre'], f['apellidos'], f['especialidad'], f['email'],
         f['id_rol'], f['username'], generate_password_hash(f['password'])),
        user_id=session.get('user_id'))
    flash(msg, 'exito' if ok else 'error')
    return redirect(url_for('admin_staff'))

@app.route('/admin/staff/<int:id_staff>/editar', methods=['POST'])
@rol_required(1)
def admin_staff_editar(id_staff):
    f = request.form
    ok, msg = call_proc(
        "CALL sp_actualizar_staff(%s,%s,%s,%s,%s,%s,NULL,NULL)",
        (id_staff, f['nombre'], f['apellidos'], f['especialidad'],
         f['email'], f['id_rol']),
        user_id=session.get('user_id'))
    flash(msg, 'exito' if ok else 'error')
    return redirect(url_for('admin_staff'))


@app.route('/admin/staff/<int:id_staff>/toggle', methods=['POST'])
@rol_required(1)
def admin_staff_toggle(id_staff):
    ok, msg = call_proc(
        "CALL sp_toggle_staff(%s,NULL,NULL)", (id_staff,),
        user_id=session.get('user_id'))
    flash(msg, 'exito' if ok else 'error')
    return redirect(url_for('admin_staff'))

# ── IoT: GPS + Beacon ─────────────────────────────────────────────────────────

@app.route('/admin/iot')
@rol_required(1)
def admin_iot():
    gps_status      = query("SELECT * FROM v_estado_gps_residentes",  fetchall=True) or []
    staff_ubicacion = query("SELECT * FROM v_ubicacion_actual_staff",  fetchall=True) or []
    limite          = query("SELECT * FROM limite_jardin LIMIT 1",     fetchone=True)
    fuera_limite    = [r for r in gps_status if not r['dentro_limite']]

    return render_template('admin/iot.html',
                           gps_status=gps_status,
                           staff_ubicacion=staff_ubicacion,
                           limite=limite,
                           fuera_limite=fuera_limite)

# ── RFID: Accesos ─────────────────────────────────────────────────────────────

@app.route('/admin/rfid')
@rol_required(1)
def admin_rfid():
    accesos_hoy    = query("SELECT * FROM v_accesos_rfid_hoy", fetchall=True) or []
    no_autorizados = call_refcursor(
        "CALL sp_accesos_no_autorizados(%s, 'resultado')", (date.today(),))
    lectores = query(
        "SELECT lr.*, a.nombre AS ala, sa.nombre AS sala "
        "FROM lector_rfid lr "
        "LEFT JOIN ala  a  ON lr.id_ala  = a.id_ala "
        "LEFT JOIN sala sa ON lr.id_sala = sa.id_sala "
        "ORDER BY lr.id_lector",
        fetchall=True) or []
    staff_list = query(
        "SELECT s.id_staff, s.nombre, s.apellidos, r.nombre_rol "
        "FROM staff s JOIN rol r ON s.id_rol = r.id_rol "
        "WHERE s.activo = TRUE ORDER BY s.apellidos",
        fetchall=True) or []

    return render_template('admin/rfid.html',
                           accesos_hoy=accesos_hoy,
                           no_autorizados=no_autorizados,
                           lectores=lectores,
                           staff_list=staff_list)

@app.route('/admin/rfid/registrar', methods=['POST'])
@rol_required(1)
def admin_rfid_registrar():
    f = request.form
    ok, msg = call_proc(
        "CALL sp_registrar_acceso_rfid(%s,%s,NULL,NULL,NULL)",
        (f['id_lector'], f['id_staff']),
        user_id=session.get('user_id'))
    flash(msg, 'exito' if ok else 'error')
    return redirect(url_for('admin_rfid'))

# ── Reportes ──────────────────────────────────────────────────────────────────

@app.route('/admin/reportes')
@rol_required(1)
def admin_reportes():
    dias = int(request.args.get('dias', 30))
    semana_inicio = request.args.get(
        'semana', (date.today() - timedelta(days=date.today().weekday())).isoformat())
    selected_cuidador = request.args.get('id_cuidador', '')
    tab = request.args.get('tab', 'cuidadores')

    # ── Tab 1: Resumen semanal cuidadores ────────────────────────────────────
    resumen_todos = call_refcursor(
        "CALL sp_resumen_semanal_cuidador(%s, 'resultado')", (semana_inicio,))
    resumen = ([r for r in resumen_todos if str(r.get('id_staff', '')) == selected_cuidador]
               if selected_cuidador else resumen_todos)
    cuidadores = query(
        "SELECT s.id_staff, s.nombre || ' ' || s.apellidos AS nombre "
        "FROM staff s JOIN rol r ON s.id_rol = r.id_rol "
        "WHERE r.nivel_acceso = 3 AND s.activo = TRUE ORDER BY s.apellidos",
        fetchall=True) or []

    # ── Tab 2: Evolución ánimo global (línea) ────────────────────────────────
    animo_rows      = call_refcursor("CALL sp_evolucion_animo_global(%s, 'resultado')", (dias,))
    animo_labels    = [str(r['fecha']) for r in animo_rows]
    animo_data      = [float(r['puntaje_promedio']) for r in animo_rows]
    animo_counts    = [int(r['num_registros'])       for r in animo_rows]

    # ── Tab 3: Incidentes por tipo y severidad (barras apiladas) ─────────────
    inc_rows = call_refcursor("CALL sp_incidentes_por_severidad(%s, 'resultado')", (dias,))
    inc_map  = defaultdict(lambda: {'Alta': 0, 'Media': 0, 'Baja': 0})
    for r in inc_rows:
        inc_map[r['tipo']][r['severidad']] = int(r['total'])
    tipos     = sorted(inc_map.keys())
    inc_alta  = [inc_map[t]['Alta']  for t in tipos]
    inc_media = [inc_map[t]['Media'] for t in tipos]
    inc_baja  = [inc_map[t]['Baja']  for t in tipos]

    # ── Tab 4: Adherencia terapéutica (barras agrupadas) ─────────────────────
    adh_rows        = call_refcursor("CALL sp_adherencia_terapeutica(%s, 'resultado')", (dias,))
    adh_labels      = [r['terapeuta']         for r in adh_rows]
    adh_programadas = [int(r['total_programadas']) for r in adh_rows]
    adh_realizadas  = [int(r['realizadas'])        for r in adh_rows]

    # ── Tab 5: Resumen IoT (barras) ───────────────────────────────────────────
    iot_rows   = call_refcursor("CALL sp_resumen_iot(%s, 'resultado')", (dias,))
    iot_labels = [r['tipo_evento']   for r in iot_rows]
    iot_data   = [int(r['total'])    for r in iot_rows]

    # ── Tab 6: Carga operativa (barras horizontales) ─────────────────────────
    car_rows       = call_refcursor("CALL sp_carga_operativa(%s, 'resultado')", (dias,))
    car_labels     = [r['profesional']      for r in car_rows]
    car_roles      = [r['rol']              for r in car_rows]
    car_sesiones   = [int(r['sesiones'])    for r in car_rows]
    car_checkins   = [int(r['checkins'])    for r in car_rows]
    car_incidentes = [int(r['incidentes'])  for r in car_rows]

    return render_template('admin/reportes.html',
        tab=tab, dias=dias,
        semana_inicio=semana_inicio, selected_cuidador=selected_cuidador,
        resumen=resumen, cuidadores=cuidadores,
        animo_labels=animo_labels, animo_data=animo_data, animo_counts=animo_counts,
        tipos=tipos, inc_alta=inc_alta, inc_media=inc_media, inc_baja=inc_baja,
        adh_labels=adh_labels, adh_programadas=adh_programadas, adh_realizadas=adh_realizadas,
        iot_labels=iot_labels, iot_data=iot_data,
        car_labels=car_labels, car_roles=car_roles,
        car_sesiones=car_sesiones, car_checkins=car_checkins, car_incidentes=car_incidentes)

# ── Auditoría ─────────────────────────────────────────────────────────────────

@app.route('/admin/auditoria')
@rol_required(1)
def admin_auditoria():
    logs = query(
        "SELECT l.*, u.username, s.nombre || ' ' || s.apellidos AS usuario_nombre, "
        "TO_CHAR(l.timestamp_operacion, 'DD Mon YYYY HH12:MI AM') AS fecha_hora "
        "FROM log_auditoria l "
        "JOIN usuario_sistema u ON l.id_usuario = u.id_usuario "
        "JOIN staff s ON u.id_staff = s.id_staff "
        "ORDER BY l.timestamp_operacion DESC LIMIT 200",
        fetchall=True) or []
    return render_template('admin/auditoria.html', logs=logs)

# ═════════════════════════════════════════════════════════════════════════════
# PORTAL TERAPEUTA
# ═════════════════════════════════════════════════════════════════════════════

@app.route('/terapeuta/dashboard')
@rol_required(2)
def terapeuta_dashboard():
    id_staff = session['staff_id']

    total_residentes = query(
        "SELECT COUNT(DISTINCT a.id_residente) AS c FROM asignacion a "
        "JOIN residente r ON a.id_residente = r.id_residente "
        "WHERE a.id_staff = %s AND a.fecha_fin IS NULL AND r.activo = TRUE",
        (id_staff,), fetchone=True)['c']

    sesiones_hoy = query(
        "SELECT st.*, r.nombre || ' ' || r.apellidos AS residente, sa.nombre AS sala, "
        "TO_CHAR(st.fecha_sesion, 'HH12:MI AM') AS hora_inicio "
        "FROM sesion_terapia st "
        "JOIN residente r ON st.id_residente = r.id_residente "
        "JOIN sala sa ON st.id_sala = sa.id_sala "
        "WHERE st.id_terapeuta = %s AND st.fecha_sesion::DATE = CURRENT_DATE "
        "ORDER BY st.fecha_sesion",
        (id_staff,), fetchall=True) or []

    incidentes_activos = query(
        "SELECT COUNT(*) AS c FROM reporte_incidente "
        "WHERE fecha >= NOW() - INTERVAL '7 days'",
        fetchone=True)['c']

    animo_promedio = query(
        "SELECT AVG(c.puntaje)::NUMERIC(3,1) AS avg_p "
        "FROM checkin_estado_animo c "
        "JOIN asignacion a ON c.id_residente = a.id_residente "
        "WHERE a.id_staff = %s AND a.fecha_fin IS NULL "
        "AND c.fecha_registro >= NOW() - INTERVAL '7 days'",
        (id_staff,), fetchone=True)

    incidentes = query(
        "SELECT * FROM v_incidentes_recientes LIMIT 5", fetchall=True) or []

    return render_template('terapeuta/dashboard.html',
                           total_residentes=total_residentes,
                           sesiones_hoy=sesiones_hoy,
                           incidentes_activos=incidentes_activos,
                           animo_promedio=animo_promedio['avg_p'] if animo_promedio else None,
                           incidentes=incidentes)

@app.route('/terapeuta/residentes')
@rol_required(2)
def terapeuta_residentes():
    id_staff = session['staff_id']
    residentes = query(
        "SELECT vr.*, "
        "(SELECT COUNT(*) FROM sesion_terapia st "
        " WHERE st.id_residente = vr.id_residente AND st.id_terapeuta = %s) AS total_sesiones "
        "FROM v_residentes_resumen vr "
        "WHERE EXISTS ("
        "  SELECT 1 FROM asignacion a "
        "  WHERE a.id_residente = vr.id_residente "
        "    AND a.id_staff = %s AND a.fecha_fin IS NULL"
        ")",
        (id_staff, id_staff), fetchall=True) or []
    return render_template('terapeuta/residentes.html', residentes=residentes)

@app.route('/terapeuta/residentes/<int:id_residente>')
@rol_required(2)
def terapeuta_residente_detalle(id_residente):
    residente = query(
        "SELECT r.*, EXTRACT(YEAR FROM AGE(r.fecha_nacimiento))::INT AS edad, "
        "TO_CHAR(r.fecha_ingreso, 'DD Mon YYYY') AS fecha_ingreso "
        "FROM residente r WHERE r.id_residente = %s",
        (id_residente,), fetchone=True)
    if not residente:
        flash('Residente no encontrado.', 'error')
        return redirect(url_for('terapeuta_residentes'))

    sesiones = query(
        "SELECT st.*, sa.nombre AS sala "
        "FROM sesion_terapia st JOIN sala sa ON st.id_sala = sa.id_sala "
        "WHERE st.id_residente = %s AND st.id_terapeuta = %s "
        "ORDER BY st.fecha_sesion DESC",
        (id_residente, session['staff_id']), fetchall=True) or []

    # Escenario 1: mood evolution for Chart.js line chart
    evolucion_animo = call_refcursor(
        "CALL sp_evolucion_animo_residente(%s, %s, 'resultado')",
        (id_residente, 30))

    incidentes = query(
        "SELECT ri.*, s.nombre || ' ' || s.apellidos AS reportado_por, "
        "TO_CHAR(ri.fecha, 'DD Mon YYYY') AS fecha "
        "FROM reporte_incidente ri JOIN staff s ON ri.id_staff = s.id_staff "
        "WHERE ri.id_residente = %s ORDER BY ri.fecha DESC",
        (id_residente,), fetchall=True) or []

    salas = query("SELECT s.*, a.nombre AS ala FROM sala s "
                  "LEFT JOIN ala a ON s.id_ala = a.id_ala ORDER BY s.nombre",
                  fetchall=True) or []

    return render_template('terapeuta/residente_detalle.html',
                           residente=residente,
                           sesiones=sesiones,
                           evolucion_animo=evolucion_animo,
                           incidentes=incidentes,
                           salas=salas,
                           preselect_residente=str(id_residente))

@app.route('/terapeuta/sesiones')
@rol_required(2)
def terapeuta_sesiones():
    sesiones = query(
        "SELECT st.*, r.nombre || ' ' || r.apellidos AS residente, sa.nombre AS sala, "
        "TO_CHAR(st.fecha_sesion, 'DD Mon YYYY HH12:MI AM') AS fecha_sesion_fmt "
        "FROM sesion_terapia st "
        "JOIN residente r ON st.id_residente = r.id_residente "
        "JOIN sala sa ON st.id_sala = sa.id_sala "
        "WHERE st.id_terapeuta = %s ORDER BY st.fecha_sesion DESC",
        (session['staff_id'],), fetchall=True) or []

    return render_template('terapeuta/sesiones.html', sesiones=sesiones)

@app.route('/terapeuta/sesiones/nueva', methods=['GET', 'POST'])
@rol_required(2)
def terapeuta_sesion_nueva():
    id_staff = session['staff_id']

    residentes = query(
        "SELECT r.id_residente, r.nombre, r.apellidos, r.habitacion "
        "FROM residente r "
        "JOIN asignacion a ON a.id_residente = r.id_residente "
        "WHERE a.id_staff = %s AND a.fecha_fin IS NULL AND r.activo = TRUE "
        "ORDER BY r.apellidos",
        (id_staff,), fetchall=True) or []

    salas = query(
        "SELECT s.*, a.nombre AS ala FROM sala s "
        "LEFT JOIN ala a ON s.id_ala = a.id_ala ORDER BY s.nombre",
        fetchall=True) or []

    # Support pre-selecting a resident from the detail page
    preselect_residente = request.args.get('id_residente', '')

    conflicto = None
    if request.method == 'POST':
        f = request.form
        ok, msg = call_proc(
            "CALL sp_reservar_sesion(%s,%s,%s,%s,%s,%s,NULL,NULL)",
            (f['id_residente'], id_staff, f['id_sala'],
             f['fecha_sesion'], f['duracion_min'], f['tipo_sesion']))
        if ok:
            flash(msg, 'exito')
            return redirect(url_for('terapeuta_sesiones'))
        else:
            conflicto = msg

    return render_template('terapeuta/sesion_nueva.html',
                           residentes=residentes,
                           salas=salas,
                           conflicto=conflicto,
                           preselect_residente=preselect_residente)

@app.route('/terapeuta/sesiones/<int:id_sesion>/editar', methods=['POST'])
@rol_required(2)
def terapeuta_sesion_editar(id_sesion):
    f = request.form
    asistio = f.get('asistio') in ('on', '1', 'true')
    ok, msg = call_proc(
        "CALL sp_actualizar_sesion(%s,%s,%s,NULL,NULL)",
        (id_sesion, asistio, f.get('notas') or None))
    flash(msg, 'exito' if ok else 'error')
    return redirect(url_for('terapeuta_sesiones'))

@app.route('/terapeuta/sesiones/<int:id_sesion>/eliminar', methods=['POST'])
@rol_required(2)
def terapeuta_sesion_eliminar(id_sesion):
    ok, msg = call_proc(
        "CALL sp_eliminar_sesion(%s,%s,NULL,NULL)",
        (id_sesion, session['staff_id']))
    flash(msg, 'exito' if ok else 'error')
    return redirect(url_for('terapeuta_sesiones'))

@app.route('/terapeuta/incidentes')
@rol_required(2)
def terapeuta_incidentes():
    incidentes = query(
        "SELECT ri.*, r.nombre || ' ' || r.apellidos AS residente, "
        "s.nombre || ' ' || s.apellidos AS reportado_por, "
        "TO_CHAR(ri.fecha, 'DD Mon YYYY HH12:MI AM') AS fecha "
        "FROM reporte_incidente ri "
        "JOIN residente r ON ri.id_residente = r.id_residente "
        "JOIN staff s ON ri.id_staff = s.id_staff "
        "ORDER BY ri.fecha DESC",
        fetchall=True) or []
    return render_template('terapeuta/incidentes.html', incidentes=incidentes)


@app.route('/terapeuta/incidentes/<int:id_incidente>/editar', methods=['POST'])
@rol_required(2)
def terapeuta_incidente_editar(id_incidente):
    f = request.form
    ok, msg = call_proc(
        "CALL sp_actualizar_incidente(%s,%s,%s,%s,NULL,NULL)",
        (id_incidente, f['tipo'], f.get('descripcion') or None, f['severidad']))
    flash(msg, 'exito' if ok else 'error')
    return redirect(url_for('terapeuta_incidentes'))

# ═════════════════════════════════════════════════════════════════════════════
# PORTAL CUIDADOR
# ═════════════════════════════════════════════════════════════════════════════

def _mis_residentes_ids(id_staff):
    """Return list of id_residente assigned to this cuidador."""
    rows = query(
        "SELECT a.id_residente FROM asignacion a "
        "JOIN residente r ON a.id_residente = r.id_residente "
        "WHERE a.id_staff = %s AND a.tipo_rol = 'Cuidador' "
        "AND a.fecha_fin IS NULL AND r.activo = TRUE",
        (id_staff,), fetchall=True) or []
    return [r['id_residente'] for r in rows]

@app.route('/cuidador/dashboard')
@rol_required(3)
def cuidador_dashboard():
    id_staff = session['staff_id']
    ids = _mis_residentes_ids(id_staff)
    total_residentes = len(ids)

    meds_pendientes = query(
        "SELECT mpd.* FROM v_medicamentos_pendientes_hoy mpd "
        "JOIN asignacion a ON mpd.id_residente = a.id_residente "
        "WHERE a.id_staff = %s AND a.tipo_rol = 'Cuidador' AND a.fecha_fin IS NULL",
        (id_staff,), fetchall=True) or []

    checkins_hoy = query(
        "SELECT COUNT(*) AS c FROM checkin_estado_animo "
        "WHERE id_cuidador = %s AND fecha_registro::DATE = CURRENT_DATE",
        (id_staff,), fetchone=True)['c']

    incidentes_hoy = query(
        "SELECT COUNT(*) AS c FROM reporte_incidente "
        "WHERE id_staff = %s AND fecha::DATE = CURRENT_DATE",
        (id_staff,), fetchone=True)['c']

    # Residents with last mood score <= 2 (needs attention)
    animo_bajo = []
    if ids:
        animo_bajo = query(
            "SELECT DISTINCT ON (c.id_residente) "
            "r.nombre || ' ' || r.apellidos AS residente, c.puntaje "
            "FROM checkin_estado_animo c "
            "JOIN residente r ON c.id_residente = r.id_residente "
            "WHERE c.id_residente = ANY(%s) "
            "ORDER BY c.id_residente, c.fecha_registro DESC",
            (ids,), fetchall=True) or []
        animo_bajo = [a for a in animo_bajo if a['puntaje'] <= 2]

    return render_template('cuidador/dashboard.html',
                           total_residentes=total_residentes,
                           meds_pendientes=meds_pendientes,
                           checkins_hoy=checkins_hoy,
                           incidentes_hoy=incidentes_hoy,
                           animo_bajo=animo_bajo)

@app.route('/cuidador/residentes')
@rol_required(3)
def cuidador_residentes():
    id_staff = session['staff_id']
    residentes = query(
        "SELECT vr.* FROM v_residentes_resumen vr "
        "WHERE EXISTS ("
        "  SELECT 1 FROM asignacion a "
        "  WHERE a.id_residente = vr.id_residente "
        "    AND a.id_staff = %s "
        "    AND a.tipo_rol = 'Cuidador' "
        "    AND a.fecha_fin IS NULL"
        ")",
        (id_staff,), fetchall=True) or []
    return render_template('cuidador/residentes.html', residentes=residentes)

@app.route('/cuidador/medicamentos')
@rol_required(3)
def cuidador_medicamentos():
    id_staff = session['staff_id']
    pendientes = query(
        "SELECT mpd.* FROM v_medicamentos_pendientes_hoy mpd "
        "JOIN asignacion a ON mpd.id_residente = a.id_residente "
        "WHERE a.id_staff = %s AND a.tipo_rol = 'Cuidador' AND a.fecha_fin IS NULL",
        (id_staff,), fetchall=True) or []

    administrados = query(
        "SELECT lm.*, m.nombre AS medicamento, m.dosis_default AS dosis, "
        "r.nombre || ' ' || r.apellidos AS residente, r.habitacion, "
        "s.nombre || ' ' || s.apellidos AS confirmado_por, "
        "TO_CHAR(lm.fecha_administracion, 'HH12:MI AM') AS hora_administrado, "
        "CASE WHEN ne.id_evento IS NOT NULL THEN 'NFC' ELSE 'Manual' END AS metodo "
        "FROM log_medicamento lm "
        "JOIN horario_medicamento hm ON lm.id_horario = hm.id_horario "
        "JOIN medicamento m ON hm.id_medicamento = m.id_medicamento "
        "JOIN residente r ON hm.id_residente = r.id_residente "
        "JOIN staff s ON lm.id_cuidador = s.id_staff "
        "LEFT JOIN nfc_evento ne ON ne.id_log_med = lm.id_log "
        "WHERE lm.id_cuidador = %s AND lm.fecha_administracion::DATE = CURRENT_DATE "
        "ORDER BY lm.fecha_administracion DESC",
        (id_staff,), fetchall=True) or []

    return render_template('cuidador/medicamentos.html',
                           pendientes=pendientes,
                           administrados=administrados)

@app.route('/cuidador/checkin', methods=['GET', 'POST'])
@rol_required(3)
def cuidador_checkin():
    id_staff = session['staff_id']
    if request.method == 'POST':
        f = request.form
        puntaje = int(f['puntaje'])
        ok, msg = call_proc(
            "CALL sp_checkin_estado_animo(%s,%s,%s,%s,NULL,NULL)",
            (f['id_residente'], id_staff, puntaje, f.get('notas') or None))
        if ok:
            extra = ' ⚠ Ánimo bajo — se generó incidente automático.' if puntaje <= 2 else ''
            flash(f'Check-in registrado correctamente.{extra}', 'exito')
        else:
            flash(msg, 'error')
        return redirect(url_for('cuidador_residentes'))

    # GET — render standalone form
    residentes = query(
        "SELECT r.id_residente, r.nombre, r.apellidos, r.habitacion "
        "FROM residente r "
        "JOIN asignacion a ON a.id_residente = r.id_residente "
        "WHERE a.id_staff = %s AND a.tipo_rol = 'Cuidador' "
        "AND a.fecha_fin IS NULL AND r.activo = TRUE ORDER BY r.apellidos",
        (id_staff,), fetchall=True) or []
    return render_template('cuidador/checkin.html', residentes=residentes)

@app.route('/cuidador/incidente', methods=['GET', 'POST'])
@rol_required(3)
def cuidador_incidente():
    id_staff = session['staff_id']
    if request.method == 'POST':
        f = request.form
        ok, msg = call_proc(
            "CALL sp_registrar_incidente(%s,%s,%s,%s,%s,NULL,NULL)",
            (f['id_residente'], id_staff,
             f['tipo_incidente'], f.get('descripcion') or None, f['severidad']))
        flash('Incidente reportado correctamente.' if ok else msg,
              'exito' if ok else 'error')
        return redirect(url_for('cuidador_residentes'))

    # GET — render standalone form
    residentes = query(
        "SELECT r.id_residente, r.nombre, r.apellidos, r.habitacion "
        "FROM residente r "
        "JOIN asignacion a ON a.id_residente = r.id_residente "
        "WHERE a.id_staff = %s AND a.tipo_rol = 'Cuidador' "
        "AND a.fecha_fin IS NULL AND r.activo = TRUE ORDER BY r.apellidos",
        (id_staff,), fetchall=True) or []
    return render_template('cuidador/incidente.html', residentes=residentes)

# ── NFC: Simulación de escaneo ────────────────────────────────────────────────

@app.route('/cuidador/nfc', methods=['GET', 'POST'])
@rol_required(3)
def cuidador_nfc():
    id_staff = session['staff_id']

    # Tags with joined medication name for display
    tags_nfc = query(
        "SELECT DISTINCT ON (nt.id_tag) nt.id_tag, nt.codigo_tag, nt.descripcion, "
        "r.nombre || ' ' || r.apellidos AS residente, r.habitacion, "
        "COALESCE(m.nombre, nt.descripcion) AS medicamento "
        "FROM nfc_tag nt "
        "JOIN residente r ON nt.id_residente = r.id_residente "
        "LEFT JOIN horario_medicamento hm ON hm.id_residente = nt.id_residente "
        "LEFT JOIN medicamento m ON hm.id_medicamento = m.id_medicamento "
        "ORDER BY nt.id_tag, r.habitacion",
        fetchall=True) or []

    resultado = None
    if request.method == 'POST':
        codigo_tag = request.form.get('codigo_tag', '').strip()
        ok, msg = call_proc(
            "CALL sp_log_medicamento_nfc(%s,%s,NULL,NULL)",
            (codigo_tag, id_staff))
        resultado = {'ok': ok, 'msg': msg}
        flash(msg, 'exito' if ok else 'error')

    log_nfc = query(
        "SELECT TO_CHAR(ne.escaneado_en, 'HH12:MI AM') AS hora, "
        "nt.descripcion AS medicamento, "
        "r.nombre || ' ' || r.apellidos AS residente "
        "FROM nfc_evento ne "
        "JOIN nfc_tag nt ON ne.id_tag = nt.id_tag "
        "JOIN residente r ON nt.id_residente = r.id_residente "
        "WHERE ne.id_staff = %s AND ne.escaneado_en::DATE = CURRENT_DATE "
        "ORDER BY ne.escaneado_en DESC LIMIT 10",
        (id_staff,), fetchall=True) or []

    return render_template('cuidador/nfc.html',
                           tags_nfc=tags_nfc,
                           resultado=resultado,
                           log_nfc=log_nfc)


if __name__ == '__main__':
    app.run(debug=True, port=8080)
