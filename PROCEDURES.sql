-- ============================================================
--  STORED PROCEDURES — ASILO SALUD MENTAL
--  EQUIPO 5 — BASE DE DATOS AVANZADAS — UDEM
--  Ejecutar después de DDL.sql
--  REGLA: Solo CREATE PROCEDURE (nunca CREATE FUNCTION salvo
--         trigger handlers que requieren RETURNS trigger).
-- ============================================================


-- ============================================================
-- AUDITORÍA
-- ============================================================

-- Registra una entrada en el log de auditoría.
-- Llamar desde Python después de cualquier INSERT/UPDATE/DELETE sensible.
CREATE OR REPLACE PROCEDURE sp_registrar_auditoria(
    p_id_usuario    INT,
    p_tabla         VARCHAR,
    p_operacion     VARCHAR,
    p_id_registro   INT,
    p_ip            VARCHAR
)
LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO log_auditoria (id_usuario, tabla_afectada, operacion, id_registro, ip_origen)
    VALUES (p_id_usuario, p_tabla, p_operacion, p_id_registro, p_ip);
END;
$$;


-- ============================================================
-- RESIDENTES
-- ============================================================

-- Alta de nuevo residente con asignación inicial de cuidador.
-- OUT ok: 1=éxito, 0=error. OUT msg: descripción del resultado.
CREATE OR REPLACE PROCEDURE sp_registrar_residente(
    p_nombre            VARCHAR,
    p_apellidos         VARCHAR,
    p_fecha_nacimiento  DATE,
    p_sexo              CHAR,
    p_habitacion        VARCHAR,
    p_diagnostico       TEXT,
    p_nivel_movilidad   VARCHAR,
    p_contacto          VARCHAR,
    p_tel_contacto      VARCHAR,
    p_id_cuidador       INT,        -- staff que se asignará como cuidador principal
    OUT ok              INT,
    OUT msg             TEXT
)
LANGUAGE plpgsql AS $$
DECLARE
    v_id_residente INT;
BEGIN
    -- Insertar residente
    INSERT INTO residente (nombre, apellidos, fecha_nacimiento, sexo, habitacion,
                           diagnostico_principal, nivel_movilidad,
                           contacto_emergencia, tel_emergencia)
    VALUES (p_nombre, p_apellidos, p_fecha_nacimiento, p_sexo, p_habitacion,
            p_diagnostico, p_nivel_movilidad, p_contacto, p_tel_contacto)
    RETURNING id_residente INTO v_id_residente;

    -- Asignación inicial
    IF p_id_cuidador IS NOT NULL THEN
        INSERT INTO asignacion (id_residente, id_staff, tipo_rol, es_principal)
        VALUES (v_id_residente, p_id_cuidador, 'Cuidador', TRUE);
    END IF;

    ok  := 1;
    msg := 'Residente registrado con ID ' || v_id_residente;
EXCEPTION WHEN OTHERS THEN
    ok  := 0;
    msg := 'Error: ' || SQLERRM;
END;
$$;


-- Baja lógica de residente (no elimina datos históricos).
CREATE OR REPLACE PROCEDURE sp_dar_baja_residente(
    p_id_residente  INT,
    OUT ok          INT,
    OUT msg         TEXT
)
LANGUAGE plpgsql AS $$
BEGIN
    UPDATE residente SET activo = FALSE WHERE id_residente = p_id_residente;
    IF NOT FOUND THEN
        ok := 0; msg := 'Residente no encontrado.';
    ELSE
        -- Cerrar asignaciones activas
        UPDATE asignacion SET fecha_fin = CURRENT_DATE
        WHERE id_residente = p_id_residente AND fecha_fin IS NULL;
        ok := 1; msg := 'Residente dado de baja correctamente.';
    END IF;
EXCEPTION WHEN OTHERS THEN
    ok := 0; msg := 'Error: ' || SQLERRM;
END;
$$;


-- Actualizar datos básicos del residente.
CREATE OR REPLACE PROCEDURE sp_actualizar_residente(
    p_id_residente      INT,
    p_habitacion        VARCHAR,
    p_diagnostico       TEXT,
    p_nivel_movilidad   VARCHAR,
    p_contacto          VARCHAR,
    p_tel_contacto      VARCHAR,
    OUT ok              INT,
    OUT msg             TEXT
)
LANGUAGE plpgsql AS $$
BEGIN
    UPDATE residente
    SET habitacion            = p_habitacion,
        diagnostico_principal = p_diagnostico,
        nivel_movilidad       = p_nivel_movilidad,
        contacto_emergencia   = p_contacto,
        tel_emergencia        = p_tel_contacto
    WHERE id_residente = p_id_residente AND activo = TRUE;

    IF NOT FOUND THEN
        ok := 0; msg := 'Residente no encontrado o inactivo.';
    ELSE
        ok := 1; msg := 'Residente actualizado.';
    END IF;
EXCEPTION WHEN OTHERS THEN
    ok := 0; msg := 'Error: ' || SQLERRM;
END;
$$;


-- ============================================================
-- SESIONES DE TERAPIA
-- ============================================================

-- Reservar sesión con detección de conflicto de horario.
-- Verifica que el terapeuta y la sala estén libres en ese bloque.
CREATE OR REPLACE PROCEDURE sp_reservar_sesion(
    p_id_residente  INT,
    p_id_terapeuta  INT,
    p_id_sala       INT,
    p_fecha_sesion  TIMESTAMP,
    p_duracion_min  INT,
    p_tipo_sesion   VARCHAR,
    OUT ok          INT,
    OUT msg         TEXT
)
LANGUAGE plpgsql AS $$
DECLARE
    v_fin           TIMESTAMP;
    v_conflicto_t   INT := 0;
    v_conflicto_s   INT := 0;
BEGIN
    v_fin := p_fecha_sesion + (p_duracion_min || ' minutes')::INTERVAL;

    -- Conflicto de terapeuta
    SELECT COUNT(*) INTO v_conflicto_t
    FROM sesion_terapia
    WHERE id_terapeuta = p_id_terapeuta
      AND fecha_sesion < v_fin
      AND (fecha_sesion + (duracion_min || ' minutes')::INTERVAL) > p_fecha_sesion;

    -- Conflicto de sala
    SELECT COUNT(*) INTO v_conflicto_s
    FROM sesion_terapia
    WHERE id_sala = p_id_sala
      AND fecha_sesion < v_fin
      AND (fecha_sesion + (duracion_min || ' minutes')::INTERVAL) > p_fecha_sesion;

    IF v_conflicto_t > 0 THEN
        ok := 0; msg := 'El terapeuta ya tiene una sesión en ese horario.';
        RETURN;
    END IF;

    IF v_conflicto_s > 0 THEN
        ok := 0; msg := 'La sala ya está ocupada en ese horario.';
        RETURN;
    END IF;

    INSERT INTO sesion_terapia (id_residente, id_terapeuta, id_sala,
                                fecha_sesion, tipo_sesion, duracion_min)
    VALUES (p_id_residente, p_id_terapeuta, p_id_sala,
            p_fecha_sesion, p_tipo_sesion, p_duracion_min);

    ok := 1; msg := 'Sesión registrada correctamente.';
EXCEPTION WHEN OTHERS THEN
    ok := 0; msg := 'Error: ' || SQLERRM;
END;
$$;


-- Actualizar notas y asistencia de una sesión.
CREATE OR REPLACE PROCEDURE sp_actualizar_sesion(
    p_id_sesion INT,
    p_asistio   BOOLEAN,
    p_notas     TEXT,
    OUT ok      INT,
    OUT msg     TEXT
)
LANGUAGE plpgsql AS $$
BEGIN
    UPDATE sesion_terapia
    SET asistio = p_asistio, notas = p_notas
    WHERE id_sesion = p_id_sesion;

    IF NOT FOUND THEN
        ok := 0; msg := 'Sesión no encontrada.';
    ELSE
        ok := 1; msg := 'Sesión actualizada.';
    END IF;
EXCEPTION WHEN OTHERS THEN
    ok := 0; msg := 'Error: ' || SQLERRM;
END;
$$;


-- ============================================================
-- MEDICAMENTOS — NFC
-- ============================================================

-- Registra administración de medicamento via escaneo NFC.
-- Flujo: NFC tag → identifica residente → busca horario activo
--        → inserta nfc_evento + log_medicamento (transacción).
CREATE OR REPLACE PROCEDURE sp_log_medicamento_nfc(
    p_codigo_tag    VARCHAR,
    p_id_staff      INT,
    OUT ok          INT,
    OUT msg         TEXT
)
LANGUAGE plpgsql AS $$
DECLARE
    v_id_tag        INT;
    v_id_residente  INT;
    v_id_horario    INT;
    v_id_log        BIGINT;
    v_id_evento     BIGINT;
BEGIN
    -- Buscar el tag
    SELECT id_tag, id_residente INTO v_id_tag, v_id_residente
    FROM nfc_tag
    WHERE codigo_tag = p_codigo_tag;

    IF NOT FOUND THEN
        ok := 0; msg := 'Tag NFC no registrado.';
        RETURN;
    END IF;

    -- Buscar horario activo más cercano a la hora actual (±2 horas)
    SELECT id_horario INTO v_id_horario
    FROM horario_medicamento
    WHERE id_residente = v_id_residente
      AND activo = TRUE
      AND hora_programada BETWEEN (CURRENT_TIME - INTERVAL '2 hours')
                               AND (CURRENT_TIME + INTERVAL '2 hours')
    ORDER BY ABS(EXTRACT(EPOCH FROM (hora_programada - CURRENT_TIME)))
    LIMIT 1;

    IF NOT FOUND THEN
        ok := 0; msg := 'No se encontró horario de medicamento activo para esta hora.';
        RETURN;
    END IF;

    -- Registrar administración primero para obtener id_log
    INSERT INTO log_medicamento (id_horario, id_cuidador)
    VALUES (v_id_horario, p_id_staff)
    RETURNING id_log INTO v_id_log;

    -- Registrar evento NFC con referencia al log
    INSERT INTO nfc_evento (id_tag, id_staff, id_log_med)
    VALUES (v_id_tag, p_id_staff, v_id_log)
    RETURNING id_evento INTO v_id_evento;

    ok := 1;
    msg := 'Medicamento registrado para residente ID ' || v_id_residente;
EXCEPTION WHEN OTHERS THEN
    ok := 0; msg := 'Error: ' || SQLERRM;
END;
$$;


-- ============================================================
-- IoT — GPS: ESTADO DE RESIDENTES EN EXTERIOR
-- ============================================================

-- Devuelve el último ping GPS de cada residente y si está
-- dentro del límite del jardín. Usa refcursor para retornar filas.
CREATE OR REPLACE PROCEDURE sp_residentes_al_aire_libre(
    INOUT resultado REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN resultado FOR
    SELECT
        r.id_residente,
        r.nombre || ' ' || r.apellidos       AS residente,
        r.habitacion,
        g.latitud,
        g.longitud,
        g.registrado_en,
        (g.latitud  BETWEEN lj.lat_min AND lj.lat_max
         AND g.longitud BETWEEN lj.lon_min AND lj.lon_max) AS dentro_limite,
        EXTRACT(EPOCH FROM (NOW() - g.registrado_en)) / 60 AS minutos_desde_ping
    FROM residente r
    JOIN LATERAL (
        SELECT latitud, longitud, registrado_en
        FROM gps_ping
        WHERE id_residente = r.id_residente
        ORDER BY registrado_en DESC
        LIMIT 1
    ) g ON TRUE
    CROSS JOIN limite_jardin lj
    WHERE r.activo = TRUE
    ORDER BY dentro_limite ASC, minutos_desde_ping ASC;
END;
$$;


-- ============================================================
-- IoT — RFID: LOG DE ACCESOS
-- ============================================================

-- Registra un evento de acceso RFID.
CREATE OR REPLACE PROCEDURE sp_registrar_acceso_rfid(
    p_id_lector         INT,
    p_id_staff          INT,
    p_acceso_concedido  BOOLEAN,
    OUT ok              INT,
    OUT msg             TEXT
)
LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO acceso_rfid (id_lector, id_staff, acceso_concedido)
    VALUES (p_id_lector, p_id_staff, COALESCE(p_acceso_concedido, TRUE));
    ok := 1; msg := 'Acceso registrado.';
EXCEPTION WHEN OTHERS THEN
    ok := 0; msg := 'Error: ' || SQLERRM;
END;
$$;


-- Devuelve el log de accesos RFID para una fecha dada.
CREATE OR REPLACE PROCEDURE sp_log_acceso_rfid(
    p_fecha     DATE,
    INOUT resultado REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN resultado FOR
    SELECT
        ar.id_acceso,
        s.nombre || ' ' || s.apellidos  AS staff,
        s.especialidad,
        lr.ubicacion,
        a.nombre                         AS ala,
        lr.es_restringido,
        ar.acceso_concedido,
        TO_CHAR(ar.accedido_en, 'HH12:MI AM') AS hora
    FROM acceso_rfid ar
    JOIN staff      s  ON ar.id_staff  = s.id_staff
    JOIN lector_rfid lr ON ar.id_lector = lr.id_lector
    LEFT JOIN ala   a  ON lr.id_ala    = a.id_ala
    WHERE ar.accedido_en::DATE = p_fecha
    ORDER BY ar.accedido_en DESC;
END;
$$;


-- Detecta accesos a áreas restringidas por staff sin turno asignado
-- en ese ala en esa fecha.
CREATE OR REPLACE PROCEDURE sp_accesos_no_autorizados(
    p_fecha DATE,
    INOUT resultado REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN resultado FOR
    SELECT
        ar.id_acceso,
        s.nombre || ' ' || s.apellidos  AS staff,
        s.especialidad,
        lr.ubicacion,
        a.nombre                         AS ala,
        TO_CHAR(ar.accedido_en, 'HH12:MI AM') AS hora
    FROM acceso_rfid ar
    JOIN staff       s   ON ar.id_staff   = s.id_staff
    JOIN lector_rfid lr  ON ar.id_lector  = lr.id_lector
    LEFT JOIN ala    a   ON lr.id_ala     = a.id_ala
    WHERE ar.accedido_en::DATE = p_fecha
      AND lr.es_restringido = TRUE
      AND ar.acceso_concedido = TRUE
      AND NOT EXISTS (
          SELECT 1 FROM turno t
          WHERE t.id_staff = ar.id_staff
            AND t.fecha    = p_fecha
            AND t.id_ala   = lr.id_ala
      )
    ORDER BY ar.accedido_en DESC;
END;
$$;


-- ============================================================
-- IoT — BEACON: UBICACIÓN ACTUAL DEL STAFF
-- ============================================================

-- Devuelve la última detección beacon de cada miembro del staff
-- en turno hoy, indicando en qué ala se encontraba.
CREATE OR REPLACE PROCEDURE sp_ubicacion_actual_staff(
    INOUT resultado REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN resultado FOR
    SELECT
        s.id_staff,
        s.nombre || ' ' || s.apellidos  AS staff,
        s.especialidad,
        r.nombre_rol                     AS rol,
        a.nombre                         AS ala_detectada,
        db.detectado_en,
        EXTRACT(EPOCH FROM (NOW() - db.detectado_en)) / 60 AS minutos_desde_deteccion
    FROM staff s
    JOIN rol r ON s.id_rol = r.id_rol
    JOIN turno t ON t.id_staff = s.id_staff AND t.fecha = CURRENT_DATE
    LEFT JOIN LATERAL (
        SELECT db2.detectado_en, b.id_ala
        FROM deteccion_beacon db2
        JOIN beacon b ON db2.id_beacon = b.id_beacon
        WHERE db2.id_staff = s.id_staff
        ORDER BY db2.detectado_en DESC
        LIMIT 1
    ) db ON TRUE
    LEFT JOIN ala a ON db.id_ala = a.id_ala
    WHERE s.activo = TRUE
    ORDER BY a.nombre, s.apellidos;
END;
$$;


-- ============================================================
-- REPORTES
-- ============================================================

-- Reporte semanal por cuidador: residentes, check-ins, ánimo, meds, incidentes, dosis perdidas.
CREATE OR REPLACE PROCEDURE sp_resumen_semanal_cuidador(
    p_semana_inicio DATE,
    INOUT resultado REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN resultado FOR
    SELECT
        s.id_staff,
        s.nombre || ' ' || s.apellidos      AS cuidador,
        p_semana_inicio                      AS semana_inicio,
        p_semana_inicio + 6                  AS semana_fin,
        (SELECT COUNT(DISTINCT a2.id_residente)
         FROM asignacion a2
         WHERE a2.id_staff  = s.id_staff
           AND a2.tipo_rol  = 'Cuidador'
           AND (a2.fecha_fin IS NULL OR a2.fecha_fin >= p_semana_inicio)
        )                                    AS residentes_atendidos,
        COUNT(DISTINCT c.id_checkin)         AS total_checkins,
        ROUND(AVG(c.puntaje), 2)             AS puntaje_animo_promedio,
        COUNT(DISTINCT lm.id_log)            AS meds_administrados,
        (SELECT COUNT(*)
         FROM reporte_incidente ri
         WHERE ri.id_staff = s.id_staff
           AND ri.fecha::DATE BETWEEN p_semana_inicio AND p_semana_inicio + 6
        )                                    AS incidentes_reportados,
        (
            SELECT COUNT(*)
            FROM horario_medicamento hm
            JOIN asignacion a3 ON hm.id_residente = a3.id_residente
            WHERE a3.id_staff = s.id_staff
              AND a3.tipo_rol = 'Cuidador'
              AND hm.activo = TRUE
              AND NOT EXISTS (
                  SELECT 1 FROM log_medicamento lm2
                  WHERE lm2.id_horario = hm.id_horario
                    AND lm2.fecha_administracion::DATE
                        BETWEEN p_semana_inicio AND p_semana_inicio + 6
              )
        ) AS dosis_perdidas
    FROM staff s
    LEFT JOIN checkin_estado_animo c
           ON c.id_cuidador = s.id_staff
          AND c.fecha_registro::DATE BETWEEN p_semana_inicio AND p_semana_inicio + 6
    LEFT JOIN log_medicamento lm
           ON lm.id_cuidador = s.id_staff
          AND lm.fecha_administracion::DATE BETWEEN p_semana_inicio AND p_semana_inicio + 6
    JOIN rol r ON s.id_rol = r.id_rol AND r.nivel_acceso = 3
    WHERE s.activo = TRUE
    GROUP BY s.id_staff, s.nombre, s.apellidos
    ORDER BY puntaje_animo_promedio ASC NULLS LAST;
END;
$$;


-- Evolución de estado de ánimo de un residente (para gráfica de línea).
CREATE OR REPLACE PROCEDURE sp_evolucion_animo_residente(
    p_id_residente  INT,
    p_dias          INT,   -- últimos N días
    INOUT resultado REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN resultado FOR
    SELECT
        DATE(fecha_registro)             AS fecha,
        ROUND(AVG(puntaje), 2)          AS puntaje_promedio,
        COUNT(*)                         AS num_registros
    FROM checkin_estado_animo
    WHERE id_residente = p_id_residente
      AND fecha_registro >= NOW() - (p_dias || ' days')::INTERVAL
    GROUP BY DATE(fecha_registro)
    ORDER BY fecha;
END;
$$;


-- ============================================================
-- TRIGGERS DE AUDITORÍA
-- (única excepción permitida para CREATE FUNCTION)
-- ============================================================

-- Trigger handler para log_auditoria en tabla residente.
-- Se activa en UPDATE y DELETE sobre residente.
CREATE OR REPLACE FUNCTION trg_auditoria_residente()
RETURNS TRIGGER
LANGUAGE plpgsql AS $$
DECLARE
    v_id_usuario INT;
BEGIN
    -- El id de usuario se pasa vía configuración de sesión: SET LOCAL app.id_usuario = X
    BEGIN
        v_id_usuario := current_setting('app.id_usuario')::INT;
    EXCEPTION WHEN OTHERS THEN
        v_id_usuario := 0;  -- fallback si no está seteado
    END;

    IF TG_OP = 'DELETE' THEN
        INSERT INTO log_auditoria (id_usuario, tabla_afectada, operacion, id_registro)
        VALUES (v_id_usuario, 'residente', 'DELETE', OLD.id_residente);
    ELSE
        INSERT INTO log_auditoria (id_usuario, tabla_afectada, operacion, id_registro)
        VALUES (v_id_usuario, 'residente', 'UPDATE', NEW.id_residente);
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_after_residente
AFTER UPDATE OR DELETE ON residente
FOR EACH ROW EXECUTE FUNCTION trg_auditoria_residente();


-- ============================================================
-- STAFF
-- ============================================================

-- Registra nuevo miembro del personal y su usuario del sistema.
CREATE OR REPLACE PROCEDURE sp_registrar_staff(
    p_nombre        VARCHAR,
    p_apellidos     VARCHAR,
    p_especialidad  VARCHAR,
    p_email         VARCHAR,
    p_id_rol        INT,
    p_username      VARCHAR,
    p_password_hash VARCHAR,
    OUT ok          INT,
    OUT msg         TEXT
)
LANGUAGE plpgsql AS $$
DECLARE
    v_id_staff INT;
BEGIN
    INSERT INTO staff (nombre, apellidos, especialidad, email, id_rol)
    VALUES (p_nombre, p_apellidos, p_especialidad, p_email, p_id_rol)
    RETURNING id_staff INTO v_id_staff;

    INSERT INTO usuario_sistema (username, password_hash, id_staff)
    VALUES (p_username, p_password_hash, v_id_staff);

    ok := 1; msg := 'Personal registrado con ID ' || v_id_staff;
EXCEPTION WHEN OTHERS THEN
    ok := 0; msg := 'Error: ' || SQLERRM;
END;
$$;


-- Actualiza datos básicos de un miembro del personal.
CREATE OR REPLACE PROCEDURE sp_actualizar_staff(
    p_id_staff      INT,
    p_nombre        VARCHAR,
    p_apellidos     VARCHAR,
    p_especialidad  VARCHAR,
    p_email         VARCHAR,
    p_id_rol        INT,
    OUT ok          INT,
    OUT msg         TEXT
)
LANGUAGE plpgsql AS $$
BEGIN
    UPDATE staff
    SET nombre       = p_nombre,
        apellidos    = p_apellidos,
        especialidad = p_especialidad,
        email        = p_email,
        id_rol       = p_id_rol
    WHERE id_staff = p_id_staff;

    IF NOT FOUND THEN
        ok := 0; msg := 'Personal no encontrado.';
    ELSE
        ok := 1; msg := 'Personal actualizado.';
    END IF;
EXCEPTION WHEN OTHERS THEN
    ok := 0; msg := 'Error: ' || SQLERRM;
END;
$$;


-- Activa o desactiva un miembro del personal.
CREATE OR REPLACE PROCEDURE sp_toggle_staff(
    p_id_staff  INT,
    OUT ok      INT,
    OUT msg     TEXT
)
LANGUAGE plpgsql AS $$
BEGIN
    UPDATE staff SET activo = NOT activo WHERE id_staff = p_id_staff;
    IF NOT FOUND THEN
        ok := 0; msg := 'Personal no encontrado.';
    ELSE
        ok := 1; msg := 'Estado del personal actualizado.';
    END IF;
EXCEPTION WHEN OTHERS THEN
    ok := 0; msg := 'Error: ' || SQLERRM;
END;
$$;


-- ============================================================
-- CUIDADO DIARIO
-- ============================================================

-- Registra check-in de estado de ánimo de un residente.
CREATE OR REPLACE PROCEDURE sp_checkin_estado_animo(
    p_id_residente  INT,
    p_id_cuidador   INT,
    p_puntaje       INT,
    p_notas         TEXT,
    OUT ok          INT,
    OUT msg         TEXT
)
LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO checkin_estado_animo (id_residente, id_cuidador, puntaje, notas)
    VALUES (p_id_residente, p_id_cuidador, p_puntaje, p_notas);
    ok := 1; msg := 'Check-in registrado.';
EXCEPTION WHEN OTHERS THEN
    ok := 0; msg := 'Error: ' || SQLERRM;
END;
$$;


-- Actualiza tipo, descripción y severidad de un incidente existente.
CREATE OR REPLACE PROCEDURE sp_actualizar_incidente(
    p_id_incidente  INT,
    p_tipo          VARCHAR,
    p_descripcion   TEXT,
    p_severidad     VARCHAR,
    OUT ok          INT,
    OUT msg         TEXT
)
LANGUAGE plpgsql AS $$
BEGIN
    UPDATE reporte_incidente
    SET tipo        = p_tipo,
        descripcion = p_descripcion,
        severidad   = p_severidad
    WHERE id_incidente = p_id_incidente;

    IF NOT FOUND THEN
        ok := 0; msg := 'Incidente no encontrado.';
    ELSE
        ok := 1; msg := 'Incidente actualizado.';
    END IF;
EXCEPTION WHEN OTHERS THEN
    ok := 0; msg := 'Error: ' || SQLERRM;
END;
$$;


-- Registra un reporte de incidente.
CREATE OR REPLACE PROCEDURE sp_registrar_incidente(
    p_id_residente  INT,
    p_id_staff      INT,
    p_tipo          VARCHAR,
    p_descripcion   TEXT,
    p_severidad     VARCHAR,
    OUT ok          INT,
    OUT msg         TEXT
)
LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO reporte_incidente (id_residente, id_staff, tipo, descripcion, severidad)
    VALUES (p_id_residente, p_id_staff, p_tipo, p_descripcion, p_severidad);
    ok := 1; msg := 'Incidente registrado.';
EXCEPTION WHEN OTHERS THEN
    ok := 0; msg := 'Error: ' || SQLERRM;
END;
$$;


-- Elimina una sesión de terapia (solo el propio terapeuta puede borrarla).
CREATE OR REPLACE PROCEDURE sp_eliminar_sesion(
    p_id_sesion     INT,
    p_id_terapeuta  INT,
    OUT ok          INT,
    OUT msg         TEXT
)
LANGUAGE plpgsql AS $$
BEGIN
    DELETE FROM sesion_terapia
    WHERE id_sesion = p_id_sesion AND id_terapeuta = p_id_terapeuta;
    IF NOT FOUND THEN
        ok := 0; msg := 'Sesión no encontrada o no pertenece a este terapeuta.';
    ELSE
        ok := 1; msg := 'Sesión eliminada.';
    END IF;
EXCEPTION WHEN OTHERS THEN
    ok := 0; msg := 'Error: ' || SQLERRM;
END;
$$;


-- ============================================================
-- REPORTES CON GRÁFICAS
-- ============================================================

-- Evolución promedio de ánimo de todos los residentes por día.
CREATE OR REPLACE PROCEDURE sp_evolucion_animo_global(
    p_dias      INT,
    INOUT resultado REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN resultado FOR
    SELECT
        DATE(fecha_registro)            AS fecha,
        ROUND(AVG(puntaje), 2)          AS puntaje_promedio,
        COUNT(*)                        AS num_registros
    FROM checkin_estado_animo
    WHERE fecha_registro >= NOW() - (p_dias || ' days')::INTERVAL
    GROUP BY DATE(fecha_registro)
    ORDER BY fecha;
END;
$$;


-- Incidentes agrupados por tipo y severidad (últimos N días).
CREATE OR REPLACE PROCEDURE sp_incidentes_por_severidad(
    p_dias      INT,
    INOUT resultado REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN resultado FOR
    SELECT
        tipo,
        severidad,
        COUNT(*) AS total
    FROM reporte_incidente
    WHERE fecha >= NOW() - (p_dias || ' days')::INTERVAL
    GROUP BY tipo, severidad
    ORDER BY tipo, severidad;
END;
$$;


-- Adherencia terapéutica: sesiones programadas vs realizadas por terapeuta.
CREATE OR REPLACE PROCEDURE sp_adherencia_terapeutica(
    p_dias      INT,
    INOUT resultado REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN resultado FOR
    SELECT
        s.nombre || ' ' || s.apellidos                                              AS terapeuta,
        COUNT(st.id_sesion)                                                         AS total_programadas,
        COUNT(st.id_sesion) FILTER (WHERE st.asistio = TRUE)                        AS realizadas,
        COUNT(st.id_sesion) FILTER (WHERE st.asistio = FALSE)                       AS no_realizadas
    FROM staff s
    JOIN rol r ON s.id_rol = r.id_rol AND r.nivel_acceso = 2
    LEFT JOIN sesion_terapia st
           ON st.id_terapeuta = s.id_staff
          AND st.fecha_sesion >= NOW() - (p_dias || ' days')::INTERVAL
    WHERE s.activo = TRUE
    GROUP BY s.id_staff, s.nombre, s.apellidos
    ORDER BY total_programadas DESC;
END;
$$;


-- Resumen de eventos IoT por tipo (últimos N días).
CREATE OR REPLACE PROCEDURE sp_resumen_iot(
    p_dias      INT,
    INOUT resultado REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN resultado FOR
    SELECT tipo_evento, total FROM (
        SELECT 'GPS'    AS tipo_evento, COUNT(*) AS total
          FROM gps_ping WHERE registrado_en >= NOW() - (p_dias || ' days')::INTERVAL
        UNION ALL
        SELECT 'NFC',    COUNT(*) FROM nfc_evento
          WHERE escaneado_en >= NOW() - (p_dias || ' days')::INTERVAL
        UNION ALL
        SELECT 'RFID',   COUNT(*) FROM acceso_rfid
          WHERE accedido_en >= NOW() - (p_dias || ' days')::INTERVAL
        UNION ALL
        SELECT 'Beacon', COUNT(*) FROM deteccion_beacon
          WHERE detectado_en >= NOW() - (p_dias || ' days')::INTERVAL
    ) t
    ORDER BY tipo_evento;
END;
$$;


-- Carga operativa por profesional: sesiones, check-ins e incidentes en N días.
CREATE OR REPLACE PROCEDURE sp_carga_operativa(
    p_dias      INT,
    INOUT resultado REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN resultado FOR
    SELECT
        s.nombre || ' ' || s.apellidos                                              AS profesional,
        r.nombre_rol                                                                 AS rol,
        COUNT(DISTINCT st.id_sesion)    FILTER (WHERE st.id_sesion    IS NOT NULL)  AS sesiones,
        COUNT(DISTINCT c.id_checkin)    FILTER (WHERE c.id_checkin    IS NOT NULL)  AS checkins,
        COUNT(DISTINCT ri.id_incidente) FILTER (WHERE ri.id_incidente IS NOT NULL)  AS incidentes
    FROM staff s
    JOIN rol r ON s.id_rol = r.id_rol
    LEFT JOIN sesion_terapia st
           ON st.id_terapeuta = s.id_staff
          AND st.fecha_sesion  >= NOW() - (p_dias || ' days')::INTERVAL
    LEFT JOIN checkin_estado_animo c
           ON c.id_cuidador   = s.id_staff
          AND c.fecha_registro >= NOW() - (p_dias || ' days')::INTERVAL
    LEFT JOIN reporte_incidente ri
           ON ri.id_staff = s.id_staff
          AND ri.fecha    >= NOW() - (p_dias || ' days')::INTERVAL
    WHERE s.activo = TRUE
    GROUP BY s.id_staff, s.nombre, s.apellidos, r.nombre_rol
    ORDER BY (COUNT(DISTINCT st.id_sesion) + COUNT(DISTINCT c.id_checkin)) DESC;
END;
$$;


-- ============================================================
-- CONSULTAS DE DATOS (REFCURSOR)
-- Procedimientos que reemplazan queries inline en Flask.
-- Todos retornan filas via INOUT resultado REFCURSOR.
-- ============================================================

-- Autenticacion: retorna datos del usuario activo por username.
CREATE OR REPLACE PROCEDURE sp_auth_usuario(
    p_username  TEXT,
    INOUT resultado REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN resultado FOR
        SELECT u.id_usuario, u.username, u.password_hash,
               s.id_staff, s.nombre, s.apellidos, s.especialidad,
               r.nivel_acceso, r.nombre_rol
        FROM usuario_sistema u
        JOIN staff s ON u.id_staff = s.id_staff
        JOIN rol   r ON s.id_rol   = r.id_rol
        WHERE u.username = p_username
          AND u.activo   = TRUE
          AND s.activo   = TRUE;
END;
$$;

CREATE OR REPLACE PROCEDURE sp_actualizar_ultimo_login(
    p_id_usuario INT,
    OUT ok       INT,
    OUT msg      TEXT
)
LANGUAGE plpgsql AS $$
BEGIN
    UPDATE usuario_sistema SET ultimo_login = NOW() WHERE id_usuario = p_id_usuario;
    ok := 1; msg := 'Login registrado.';
EXCEPTION WHEN OTHERS THEN
    ok := 0; msg := SQLERRM;
END;
$$;


-- Dashboard admin: una fila con los 4 contadores del panel.
CREATE OR REPLACE PROCEDURE sp_dashboard_admin(
    INOUT resultado REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN resultado FOR
        SELECT
            (SELECT COUNT(*) FROM residente WHERE activo = TRUE)::INT              AS total_residentes,
            (SELECT COUNT(*) FROM staff    WHERE activo = TRUE)::INT              AS total_staff,
            (SELECT COUNT(*) FROM reporte_incidente
             WHERE severidad = 'Alta' AND fecha >= NOW() - INTERVAL '7 days')::INT AS incidentes_alta,
            (SELECT COUNT(*) FROM v_medicamentos_pendientes_hoy)::INT             AS meds_pendientes;
END;
$$;


-- Lista de cuidadores activos (para dropdowns de asignacion).
CREATE OR REPLACE PROCEDURE sp_lista_cuidadores(
    INOUT resultado REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN resultado FOR
        SELECT s.id_staff, s.nombre || ' ' || s.apellidos AS nombre
        FROM staff s JOIN rol r ON s.id_rol = r.id_rol
        WHERE r.nivel_acceso = 3 AND s.activo = TRUE
        ORDER BY s.apellidos;
END;
$$;


-- Detalle de un residente (incluye edad calculada y fecha formateada).
CREATE OR REPLACE PROCEDURE sp_detalle_residente(
    p_id_residente INT,
    INOUT resultado REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN resultado FOR
        SELECT r.*,
               EXTRACT(YEAR FROM AGE(r.fecha_nacimiento))::INT AS edad,
               TO_CHAR(r.fecha_ingreso, 'DD Mon YYYY') AS fecha_ingreso
        FROM residente r
        WHERE r.id_residente = p_id_residente;
END;
$$;


-- Asignaciones activas de un residente.
CREATE OR REPLACE PROCEDURE sp_asignaciones_residente(
    p_id_residente INT,
    INOUT resultado REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN resultado FOR
        SELECT a.*, s.nombre || ' ' || s.apellidos AS staff_nombre,
               ro.nombre_rol AS tipo_rol, a.es_principal
        FROM asignacion a
        JOIN staff s  ON a.id_staff = s.id_staff
        JOIN rol   ro ON s.id_rol   = ro.id_rol
        WHERE a.id_residente = p_id_residente AND a.fecha_fin IS NULL
        ORDER BY a.es_principal DESC;
END;
$$;


-- Ultimas 10 sesiones de terapia de un residente (vista admin).
CREATE OR REPLACE PROCEDURE sp_historial_sesiones_residente(
    p_id_residente INT,
    INOUT resultado REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN resultado FOR
        SELECT st.*, s.nombre || ' ' || s.apellidos AS terapeuta, sa.nombre AS sala
        FROM sesion_terapia st
        JOIN staff s  ON st.id_terapeuta = s.id_staff
        JOIN sala  sa ON st.id_sala      = sa.id_sala
        WHERE st.id_residente = p_id_residente
        ORDER BY st.fecha_sesion DESC
        LIMIT 10;
END;
$$;


-- Ultimos 10 check-ins de animo de un residente.
CREATE OR REPLACE PROCEDURE sp_historial_checkins_residente(
    p_id_residente INT,
    INOUT resultado REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN resultado FOR
        SELECT c.*, s.nombre || ' ' || s.apellidos AS cuidador
        FROM checkin_estado_animo c
        JOIN staff s ON c.id_cuidador = s.id_staff
        WHERE c.id_residente = p_id_residente
        ORDER BY c.fecha_registro DESC
        LIMIT 10;
END;
$$;


-- Ultimos 5 incidentes de un residente (vista admin).
CREATE OR REPLACE PROCEDURE sp_historial_incidentes_residente(
    p_id_residente INT,
    INOUT resultado REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN resultado FOR
        SELECT ri.*, s.nombre || ' ' || s.apellidos AS reportado_por,
               TO_CHAR(ri.fecha, 'DD Mon YYYY HH12:MI AM') AS fecha
        FROM reporte_incidente ri
        JOIN staff s ON ri.id_staff = s.id_staff
        WHERE ri.id_residente = p_id_residente
        ORDER BY ri.fecha DESC
        LIMIT 5;
END;
$$;


-- Lista completa de staff con rol y fecha de alta.
CREATE OR REPLACE PROCEDURE sp_lista_staff(
    INOUT resultado REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN resultado FOR
        SELECT s.*, r.nombre_rol, r.nivel_acceso,
               TO_CHAR(s.fecha_alta, 'DD Mon YYYY') AS fecha_alta_fmt
        FROM staff s JOIN rol r ON s.id_rol = r.id_rol
        ORDER BY r.nivel_acceso, s.apellidos;
END;
$$;


-- Todos los roles ordenados por nivel de acceso.
CREATE OR REPLACE PROCEDURE sp_lista_roles(
    INOUT resultado REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN resultado FOR
        SELECT * FROM rol ORDER BY nivel_acceso;
END;
$$;


-- Lectores RFID con datos de ala y sala.
CREATE OR REPLACE PROCEDURE sp_lectores_rfid(
    INOUT resultado REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN resultado FOR
        SELECT lr.*, a.nombre AS ala, sa.nombre AS sala
        FROM lector_rfid lr
        LEFT JOIN ala  a  ON lr.id_ala  = a.id_ala
        LEFT JOIN sala sa ON lr.id_sala = sa.id_sala
        ORDER BY lr.id_lector;
END;
$$;


-- Staff activo con rol (para dropdowns de RFID y asignaciones).
CREATE OR REPLACE PROCEDURE sp_lista_staff_activo(
    INOUT resultado REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN resultado FOR
        SELECT s.id_staff, s.nombre, s.apellidos, r.nombre_rol
        FROM staff s JOIN rol r ON s.id_rol = r.id_rol
        WHERE s.activo = TRUE
        ORDER BY s.apellidos;
END;
$$;


-- Limite geografico del jardin (primera fila).
CREATE OR REPLACE PROCEDURE sp_limite_jardin(
    INOUT resultado REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN resultado FOR
        SELECT * FROM limite_jardin LIMIT 1;
END;
$$;


-- Log de auditoria con datos de usuario (ultimos 200 registros).
CREATE OR REPLACE PROCEDURE sp_log_auditoria(
    INOUT resultado REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN resultado FOR
        SELECT l.*, u.username, s.nombre || ' ' || s.apellidos AS usuario_nombre,
               TO_CHAR(l.timestamp_operacion, 'DD Mon YYYY HH12:MI AM') AS fecha_hora
        FROM log_auditoria l
        JOIN usuario_sistema u ON l.id_usuario = u.id_usuario
        JOIN staff s ON u.id_staff = s.id_staff
        ORDER BY l.timestamp_operacion DESC
        LIMIT 200;
END;
$$;


-- Dashboard terapeuta: una fila con estadisticas clave.
CREATE OR REPLACE PROCEDURE sp_dashboard_terapeuta(
    p_id_staff  INT,
    INOUT resultado REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN resultado FOR
        SELECT
            (SELECT COUNT(DISTINCT a.id_residente)
             FROM asignacion a
             JOIN residente r ON a.id_residente = r.id_residente
             WHERE a.id_staff = p_id_staff AND a.fecha_fin IS NULL AND r.activo = TRUE
            )::INT AS total_residentes,
            (SELECT COUNT(*) FROM reporte_incidente
             WHERE fecha >= NOW() - INTERVAL '7 days')::INT AS incidentes_activos,
            (SELECT AVG(c.puntaje)::NUMERIC(3,1)
             FROM checkin_estado_animo c
             JOIN asignacion a ON c.id_residente = a.id_residente
             WHERE a.id_staff = p_id_staff AND a.fecha_fin IS NULL
               AND c.fecha_registro >= NOW() - INTERVAL '7 days'
            ) AS animo_promedio;
END;
$$;


-- Sesiones de hoy para un terapeuta especifico.
CREATE OR REPLACE PROCEDURE sp_sesiones_hoy_terapeuta(
    p_id_staff  INT,
    INOUT resultado REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN resultado FOR
        SELECT st.*, r.nombre || ' ' || r.apellidos AS residente, sa.nombre AS sala,
               TO_CHAR(st.fecha_sesion, 'HH12:MI AM') AS hora_inicio
        FROM sesion_terapia st
        JOIN residente r ON st.id_residente = r.id_residente
        JOIN sala sa     ON st.id_sala      = sa.id_sala
        WHERE st.id_terapeuta = p_id_staff
          AND st.fecha_sesion::DATE = CURRENT_DATE
        ORDER BY st.fecha_sesion;
END;
$$;


-- Residentes asignados a un terapeuta (con conteo de sesiones).
CREATE OR REPLACE PROCEDURE sp_residentes_asignados_terapeuta(
    p_id_staff  INT,
    INOUT resultado REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN resultado FOR
        SELECT vr.*,
               (SELECT COUNT(*) FROM sesion_terapia st
                WHERE st.id_residente = vr.id_residente
                  AND st.id_terapeuta = p_id_staff)::INT AS total_sesiones
        FROM v_residentes_resumen vr
        WHERE EXISTS (
            SELECT 1 FROM asignacion a
            WHERE a.id_residente = vr.id_residente
              AND a.id_staff = p_id_staff AND a.fecha_fin IS NULL
        );
END;
$$;


-- Todas las sesiones de un terapeuta ordenadas por fecha.
CREATE OR REPLACE PROCEDURE sp_sesiones_terapeuta(
    p_id_staff  INT,
    INOUT resultado REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN resultado FOR
        SELECT st.*, r.nombre || ' ' || r.apellidos AS residente, sa.nombre AS sala,
               TO_CHAR(st.fecha_sesion, 'DD Mon YYYY HH12:MI AM') AS fecha_sesion_fmt
        FROM sesion_terapia st
        JOIN residente r ON st.id_residente = r.id_residente
        JOIN sala sa     ON st.id_sala      = sa.id_sala
        WHERE st.id_terapeuta = p_id_staff
        ORDER BY st.fecha_sesion DESC;
END;
$$;


-- Residentes asignados a un terapeuta (para formulario de nueva sesion).
CREATE OR REPLACE PROCEDURE sp_residentes_sesion_nueva(
    p_id_staff  INT,
    INOUT resultado REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN resultado FOR
        SELECT r.id_residente, r.nombre, r.apellidos, r.habitacion
        FROM residente r
        JOIN asignacion a ON a.id_residente = r.id_residente
        WHERE a.id_staff = p_id_staff AND a.fecha_fin IS NULL AND r.activo = TRUE
        ORDER BY r.apellidos;
END;
$$;


-- Todas las salas con nombre de ala.
CREATE OR REPLACE PROCEDURE sp_salas(
    INOUT resultado REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN resultado FOR
        SELECT s.*, a.nombre AS ala
        FROM sala s
        LEFT JOIN ala a ON s.id_ala = a.id_ala
        ORDER BY s.nombre;
END;
$$;


-- Sesiones de un residente filtradas por terapeuta (vista detalle terapeuta).
CREATE OR REPLACE PROCEDURE sp_sesiones_residente_terapeuta(
    p_id_residente  INT,
    p_id_staff      INT,
    INOUT resultado REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN resultado FOR
        SELECT st.*, sa.nombre AS sala
        FROM sesion_terapia st
        JOIN sala sa ON st.id_sala = sa.id_sala
        WHERE st.id_residente = p_id_residente AND st.id_terapeuta = p_id_staff
        ORDER BY st.fecha_sesion DESC;
END;
$$;


-- Todos los incidentes de un residente (vista detalle terapeuta).
CREATE OR REPLACE PROCEDURE sp_incidentes_residente_lista(
    p_id_residente  INT,
    INOUT resultado REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN resultado FOR
        SELECT ri.*, s.nombre || ' ' || s.apellidos AS reportado_por,
               TO_CHAR(ri.fecha, 'DD Mon YYYY') AS fecha
        FROM reporte_incidente ri
        JOIN staff s ON ri.id_staff = s.id_staff
        WHERE ri.id_residente = p_id_residente
        ORDER BY ri.fecha DESC;
END;
$$;


-- Todos los incidentes con residente y staff (vista lista terapeuta).
CREATE OR REPLACE PROCEDURE sp_todos_incidentes(
    INOUT resultado REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN resultado FOR
        SELECT ri.*, r.nombre || ' ' || r.apellidos AS residente,
               s.nombre || ' ' || s.apellidos AS reportado_por,
               TO_CHAR(ri.fecha, 'DD Mon YYYY HH12:MI AM') AS fecha
        FROM reporte_incidente ri
        JOIN residente r ON ri.id_residente = r.id_residente
        JOIN staff s     ON ri.id_staff     = s.id_staff
        ORDER BY ri.fecha DESC;
END;
$$;


-- IDs de residentes asignados a un cuidador.
CREATE OR REPLACE PROCEDURE sp_ids_residentes_cuidador(
    p_id_staff  INT,
    INOUT resultado REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN resultado FOR
        SELECT a.id_residente
        FROM asignacion a
        JOIN residente r ON a.id_residente = r.id_residente
        WHERE a.id_staff = p_id_staff AND a.tipo_rol = 'Cuidador'
          AND a.fecha_fin IS NULL AND r.activo = TRUE;
END;
$$;


-- Medicamentos pendientes del dia para los residentes de un cuidador.
CREATE OR REPLACE PROCEDURE sp_meds_pendientes_cuidador(
    p_id_staff  INT,
    INOUT resultado REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN resultado FOR
        SELECT mpd.*
        FROM v_medicamentos_pendientes_hoy mpd
        JOIN asignacion a ON mpd.id_residente = a.id_residente
        WHERE a.id_staff = p_id_staff AND a.tipo_rol = 'Cuidador' AND a.fecha_fin IS NULL;
END;
$$;


-- Dashboard cuidador: una fila con checkins e incidentes de hoy.
CREATE OR REPLACE PROCEDURE sp_dashboard_cuidador(
    p_id_staff  INT,
    INOUT resultado REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN resultado FOR
        SELECT
            (SELECT COUNT(*) FROM checkin_estado_animo
             WHERE id_cuidador = p_id_staff
               AND fecha_registro::DATE = CURRENT_DATE)::INT AS checkins_hoy,
            (SELECT COUNT(*) FROM reporte_incidente
             WHERE id_staff = p_id_staff
               AND fecha::DATE = CURRENT_DATE)::INT AS incidentes_hoy;
END;
$$;


-- Residentes con ultimo puntaje de animo bajo (para alertas en dashboard).
CREATE OR REPLACE PROCEDURE sp_animo_bajo_cuidador(
    p_id_staff  INT,
    INOUT resultado REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN resultado FOR
        SELECT DISTINCT ON (c.id_residente)
               r.nombre || ' ' || r.apellidos AS residente, c.puntaje
        FROM checkin_estado_animo c
        JOIN residente r  ON c.id_residente  = r.id_residente
        JOIN asignacion a ON c.id_residente  = a.id_residente
        WHERE a.id_staff = p_id_staff AND a.tipo_rol = 'Cuidador'
          AND a.fecha_fin IS NULL
        ORDER BY c.id_residente, c.fecha_registro DESC;
END;
$$;


-- Residentes de un cuidador desde la vista resumen (pagina lista).
CREATE OR REPLACE PROCEDURE sp_residentes_cuidador_vista(
    p_id_staff  INT,
    INOUT resultado REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN resultado FOR
        SELECT vr.*
        FROM v_residentes_resumen vr
        WHERE EXISTS (
            SELECT 1 FROM asignacion a
            WHERE a.id_residente = vr.id_residente
              AND a.id_staff   = p_id_staff
              AND a.tipo_rol   = 'Cuidador'
              AND a.fecha_fin IS NULL
        );
END;
$$;


-- Residentes de un cuidador (id, nombre, habitacion — para formularios).
CREATE OR REPLACE PROCEDURE sp_residentes_cuidador_lista(
    p_id_staff  INT,
    INOUT resultado REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN resultado FOR
        SELECT r.id_residente, r.nombre, r.apellidos, r.habitacion
        FROM residente r
        JOIN asignacion a ON a.id_residente = r.id_residente
        WHERE a.id_staff = p_id_staff AND a.tipo_rol = 'Cuidador'
          AND a.fecha_fin IS NULL AND r.activo = TRUE
        ORDER BY r.apellidos;
END;
$$;


-- Medicamentos administrados hoy por un cuidador.
CREATE OR REPLACE PROCEDURE sp_medicamentos_admin_hoy(
    p_id_staff  INT,
    INOUT resultado REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN resultado FOR
        SELECT lm.*, m.nombre AS medicamento, m.dosis_default AS dosis,
               r.nombre || ' ' || r.apellidos AS residente, r.habitacion,
               s.nombre || ' ' || s.apellidos AS confirmado_por,
               TO_CHAR(lm.fecha_administracion, 'HH12:MI AM') AS hora_administrado,
               CASE WHEN ne.id_evento IS NOT NULL THEN 'NFC' ELSE 'Manual' END AS metodo
        FROM log_medicamento lm
        JOIN horario_medicamento hm ON lm.id_horario     = hm.id_horario
        JOIN medicamento m          ON hm.id_medicamento = m.id_medicamento
        JOIN residente r            ON hm.id_residente   = r.id_residente
        JOIN staff s                ON lm.id_cuidador    = s.id_staff
        LEFT JOIN nfc_evento ne     ON ne.id_log_med     = lm.id_log
        WHERE lm.id_cuidador = p_id_staff
          AND lm.fecha_administracion::DATE = CURRENT_DATE
        ORDER BY lm.fecha_administracion DESC;
END;
$$;


-- Tags NFC con residente y medicamento asociado.
CREATE OR REPLACE PROCEDURE sp_tags_nfc(
    INOUT resultado REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN resultado FOR
        SELECT DISTINCT ON (nt.id_tag)
               nt.id_tag, nt.codigo_tag, nt.descripcion,
               r.nombre || ' ' || r.apellidos AS residente, r.habitacion,
               COALESCE(m.nombre, nt.descripcion) AS medicamento
        FROM nfc_tag nt
        JOIN residente r ON nt.id_residente = r.id_residente
        LEFT JOIN horario_medicamento hm ON hm.id_residente   = nt.id_residente
        LEFT JOIN medicamento m          ON hm.id_medicamento = m.id_medicamento
        ORDER BY nt.id_tag, r.habitacion;
END;
$$;


-- Log NFC de hoy para un cuidador (ultimos 10 escaneos).
CREATE OR REPLACE PROCEDURE sp_log_nfc_hoy(
    p_id_staff  INT,
    INOUT resultado REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN resultado FOR
        SELECT TO_CHAR(ne.escaneado_en, 'HH12:MI AM') AS hora,
               nt.descripcion AS medicamento,
               r.nombre || ' ' || r.apellidos AS residente
        FROM nfc_evento ne
        JOIN nfc_tag nt  ON ne.id_tag       = nt.id_tag
        JOIN residente r ON nt.id_residente = r.id_residente
        WHERE ne.id_staff = p_id_staff
          AND ne.escaneado_en::DATE = CURRENT_DATE
        ORDER BY ne.escaneado_en DESC
        LIMIT 10;
END;
$$;
