-- ============================================================
--  SEED.sql — DATOS DE PRUEBA (5 ESCENARIOS)
--  EQUIPO 5 — BASE DE DATOS AVANZADAS — UDEM
--  Ejecutar DESPUÉS de DDL.sql, PROCEDURES.sql, VIEWS_TRIGGERS.sql
-- ============================================================

BEGIN;

-- ============================================================
-- 1. CATÁLOGOS BASE
-- ============================================================

INSERT INTO rol (nombre_rol, nivel_acceso) VALUES
('Administrador', 1),
('Terapeuta',     2),
('Cuidador',      3);

INSERT INTO ala (nombre, piso, descripcion) VALUES
('Ala A — Demencia',    1, 'Residentes con demencia y deterioro cognitivo severo'),
('Ala B — Ambulatorio', 1, 'Residentes con movilidad autónoma o asistida'),
('Patio y Jardín',      0, 'Área exterior del asilo');

INSERT INTO sala (nombre, id_ala, capacidad) VALUES
('Sala de Terapia 1',  1, 3),
('Sala de Terapia 2',  2, 3),
('Sala Grupal',        2, 8),
('Consultorio Médico', 2, 2);

-- Límite del jardín — bounding box (coords simuladas)
-- Dentro:  lat 20.6597–20.6603 | lon -103.3496–-103.3490
-- Fuera:   lat > 20.6603 o < 20.6597
INSERT INTO limite_jardin (descripcion, lat_min, lat_max, lon_min, lon_max)
VALUES ('Perímetro jardín principal', 20.6597, 20.6603, -103.3496, -103.3490);

INSERT INTO medicamento (nombre, descripcion, unidad) VALUES
('Sertralina',  'Antidepresivo ISRS',              'mg'),
('Lorazepam',   'Ansiolítico benzodiacepínico',     'mg'),
('Memantina',   'Tratamiento demencia moderada',    'mg'),
('Omeprazol',   'Protector gástrico',               'mg'),
('Vitamina D3', 'Suplemento vitamínico',            'UI');

-- ============================================================
-- 2. STAFF Y USUARIOS DEL SISTEMA
-- ============================================================
-- NOTA: password_hash almacena texto plano para el MVP académico.
-- En producción reemplazar con werkzeug.security.generate_password_hash.
-- Credenciales:
--   admin     / admin123
--   jramirez  / terapeuta123
--   ltorres   / terapeuta123
--   mlopez    / cuidador123
--   psanchez  / cuidador123
--   agarcia   / cuidador123

INSERT INTO staff (nombre, apellidos, especialidad, email, id_rol) VALUES
('Carlos', 'Medina Ortiz',  'Administrador',     'admin@asilo.mx',    1),  -- id 1
('Juan',   'Ramírez Soto',  'Psicólogo Clínico', 'jramirez@asilo.mx', 2),  -- id 2
('Laura',  'Torres Vega',   'Geriatra',          'ltorres@asilo.mx',  2),  -- id 3
('María',  'López Herrera', 'Cuidadora',         'mlopez@asilo.mx',   3),  -- id 4
('Pedro',  'Sánchez Ruiz',  'Cuidador',          'psanchez@asilo.mx', 3),  -- id 5
('Ana',    'García Díaz',   'Cuidadora',         'agarcia@asilo.mx',  3);  -- id 6

INSERT INTO usuario_sistema (username, password_hash, id_staff) VALUES
('admin',    'admin123',     1),
('jramirez', 'terapeuta123', 2),
('ltorres',  'terapeuta123', 3),
('mlopez',   'cuidador123',  4),
('psanchez', 'cuidador123',  5),
('agarcia',  'cuidador123',  6);

-- ============================================================
-- 3. RESIDENTES
-- ============================================================

INSERT INTO residente
    (nombre, apellidos, fecha_nacimiento, sexo, habitacion,
     diagnostico_principal, nivel_movilidad, contacto_emergencia, tel_emergencia)
VALUES
-- id 1 — Escenario 2: múltiples cuidadores
('Roberto', 'García Mendoza',  '1944-03-15', 'M', '101',
 'Demencia leve',          'Asistido', 'Rosa García',   '3310001111'),
-- id 2 — Escenario 1: deterioro emocional progresivo
('Carmen',  'Vega Salinas',    '1949-07-22', 'F', '102',
 'Depresión mayor',        'Autonomo', 'Luis Vega',     '3310002222'),
-- id 3 — Escenarios 3 y 4: NFC medicamento + GPS jardín
('Luis',    'Morales Fuentes', '1951-11-08', 'M', '103',
 'Ansiedad generalizada',  'Autonomo', 'Sofía Morales', '3310003333'),
-- id 4 — general
('Elena',   'Ruiz Castillo',   '1946-05-30', 'F', '104',
 'Deterioro cognitivo leve','Asistido','Marta Ruiz',    '3310004444');

-- ============================================================
-- 4. ASIGNACIONES N:M (residente <-> staff)
-- ============================================================

-- Roberto (Escenario 2): cuidador matutino Y nocturno
INSERT INTO asignacion (id_residente, id_staff, tipo_rol, es_principal) VALUES
(1, 4, 'Cuidador',  TRUE),   -- María López — matutino, principal
(1, 5, 'Cuidador',  FALSE),  -- Pedro Sánchez — nocturno
(1, 2, 'Terapeuta', FALSE);  -- Dr. Ramírez

-- Carmen (Escenario 1)
INSERT INTO asignacion (id_residente, id_staff, tipo_rol, es_principal) VALUES
(2, 4, 'Cuidador',  TRUE),
(2, 2, 'Terapeuta', FALSE);

-- Luis (Escenarios 3 y 4)
INSERT INTO asignacion (id_residente, id_staff, tipo_rol, es_principal) VALUES
(3, 6, 'Cuidador',  TRUE),   -- Ana García
(3, 3, 'Terapeuta', FALSE);  -- Dra. Torres

-- Elena (general)
INSERT INTO asignacion (id_residente, id_staff, tipo_rol, es_principal) VALUES
(4, 6, 'Cuidador',  TRUE),
(4, 3, 'Terapeuta', FALSE);

-- ============================================================
-- 5. TURNOS
-- Escenario 5 depende de que Pedro tenga turno SOLO en Ala B.
-- ============================================================

INSERT INTO turno (id_staff, id_ala, fecha, hora_inicio, hora_fin) VALUES
(4, 1, CURRENT_DATE, '07:00', '15:00'),  -- María  — Ala A matutino
(6, 1, CURRENT_DATE, '07:00', '15:00'),  -- Ana    — Ala A matutino
(5, 2, CURRENT_DATE, '15:00', '23:00'),  -- Pedro  — Ala B vespertino (NO tiene turno en Ala A)
(2, 2, CURRENT_DATE, '09:00', '17:00'),  -- Dr. Ramírez  — Ala B
(3, 2, CURRENT_DATE, '09:00', '17:00');  -- Dra. Torres  — Ala B

-- ============================================================
-- 6. SESIONES DE TERAPIA
-- ============================================================

INSERT INTO sesion_terapia
    (id_residente, id_terapeuta, id_sala, fecha_sesion, tipo_sesion, duracion_min, asistio, notas)
VALUES
(2, 2, 1, NOW() - INTERVAL '3 days', 'Individual', 50, TRUE,
 'Paciente muestra signos de aislamiento social. Se ajustará plan terapéutico.'),
(2, 2, 1, NOW() - INTERVAL '1 day',  'Individual', 50, TRUE,
 'Empeoramiento notable del estado de ánimo. Posible ajuste de medicación.'),
(1, 2, 3, NOW() - INTERVAL '2 days', 'Grupal',     60, TRUE,
 'Participación activa en actividades grupales. Buena respuesta social.'),
(3, 3, 2, NOW() - INTERVAL '1 day',  'Individual', 45, TRUE,
 'Practica técnicas de respiración. Progreso controlado.'),
(4, 3, 2, CURRENT_DATE + INTERVAL '2 hours', 'Individual', 45, TRUE, NULL);

-- ============================================================
-- 7. ESCENARIO 1 — DETERIORO EMOCIONAL PROGRESIVO
--    Doña Carmen (id=2): 4 check-ins con puntaje descendente.
--    puntaje=2 → trigger crea incidente MEDIA automáticamente.
--    puntaje=1 → trigger crea incidente ALTA automáticamente.
-- ============================================================

INSERT INTO checkin_estado_animo (id_residente, id_cuidador, fecha_registro, puntaje, notas) VALUES
(2, 4, NOW() - INTERVAL '3 days', 4, 'Tranquila pero con poco apetito.'),
(2, 4, NOW() - INTERVAL '2 days', 3, 'Llanto espontáneo durante la tarde.'),
(2, 4, NOW() - INTERVAL '1 day',  2, 'No quiso salir de la habitación. [AUTO-INCIDENTE Media]'),
(2, 4, NOW(),                     1, 'Crisis de angustia severa. [AUTO-INCIDENTE Alta]');

-- ============================================================
-- 8. ESCENARIO 2 — MÚLTIPLES CUIDADORES (N:M)
--    Don Roberto (id=1): María (matutino) y Pedro (nocturno)
--    ambos registran check-ins y medicamentos el mismo día.
-- ============================================================

INSERT INTO checkin_estado_animo (id_residente, id_cuidador, fecha_registro, puntaje, notas) VALUES
(1, 4, NOW() - INTERVAL '8 hours', 3,
 'Turno matutino — María: confusión moderada al despertar, orientado hacia el mediodía.'),
(1, 5, NOW() - INTERVAL '1 hour',  3,
 'Turno nocturno — Pedro: tranquilo, tomó la cena completa, sin incidencias.');

-- Check-ins generales de otros residentes
INSERT INTO checkin_estado_animo (id_residente, id_cuidador, fecha_registro, puntaje, notas) VALUES
(3, 6, NOW() - INTERVAL '1 day', 4, 'Bien. Practicó respiración con Ana.'),
(4, 6, NOW() - INTERVAL '1 day', 3, 'Algo desorientada por la tarde, requirió acompañamiento.');

-- ============================================================
-- 9. MEDICAMENTOS — HORARIOS Y LOGS
-- ============================================================

INSERT INTO horario_medicamento (id_residente, id_medicamento, hora_programada, dosis, frecuencia) VALUES
(2, 1, '08:00', '50mg',   'Diaria'),      -- id 1 — Carmen: Sertralina
(2, 4, '08:00', '20mg',   'Diaria'),      -- id 2 — Carmen: Omeprazol
(1, 3, '09:00', '10mg',   'Diaria'),      -- id 3 — Roberto: Memantina
(3, 5, '08:30', '1000UI', 'Diaria'),      -- id 4 — Luis: Vitamina D3  ← usado en Escenario 3
(3, 2, '22:00', '1mg',    'Condicional'), -- id 5 — Luis: Lorazepam noche
(4, 3, '09:00', '10mg',   'Diaria');      -- id 6 — Elena: Memantina

-- Logs anteriores (turnos pasados)
INSERT INTO log_medicamento (id_horario, id_cuidador, fecha_administracion) VALUES
(1, 4, NOW() - INTERVAL '1 day 8 hours'), -- Carmen Sertralina — ayer mañana (María)
(2, 4, NOW() - INTERVAL '1 day 8 hours'), -- Carmen Omeprazol  — ayer mañana (María)
(3, 4, NOW() - INTERVAL '1 day 9 hours'), -- Roberto Memantina — ayer (María)
(3, 5, NOW() - INTERVAL '9 hours');       -- Roberto Memantina — hoy (Pedro — Escenario 2)

-- ============================================================
-- 10. ESCENARIO 3 — NFC: MEDICAMENTO VÍA ESCANEO
--     Ana García (id=6) escanea tag de Luis → se registra
--     nfc_evento + log_medicamento de forma transaccional.
-- ============================================================

INSERT INTO nfc_tag (codigo_tag, id_residente, descripcion) VALUES
('NFC-LM-103', 3, 'Estación de medicamentos — Hab. 103 (Luis Morales)');

-- Simulación del resultado de CALL sp_log_medicamento_nfc('NFC-LM-103', 6, NULL, NULL)
-- log_medicamento se inserta primero para obtener id_log, luego nfc_evento lo referencia.
INSERT INTO log_medicamento (id_horario, id_cuidador, fecha_administracion)
VALUES (4, 6, NOW() - INTERVAL '30 minutes');  -- Vitamina D3 de Luis, hoy

INSERT INTO nfc_evento (id_tag, id_staff, escaneado_en, id_log_med)
VALUES (1, 6, NOW() - INTERVAL '30 minutes', currval('log_medicamento_id_log_seq'));

-- Para ejecutar el SP de forma transaccional real (psql o pgAdmin):
-- DO $$
-- DECLARE v_ok INT; v_msg TEXT;
-- BEGIN
--     CALL sp_log_medicamento_nfc('NFC-LM-103', 6, v_ok, v_msg);
--     RAISE NOTICE 'Resultado: ok=%, msg=%', v_ok, v_msg;
-- END;
-- $$;

-- ============================================================
-- 11. ESCENARIO 4 — GPS: SALIDA DE PERÍMETRO
--     Don Luis (id=3): 3 pings dentro del jardín, 1 fuera.
--     El ping exterior (lat=20.6610 > lat_max=20.6603) dispara
--     trg_alerta_gps_fuera_limite → crea incidente 'Deambulacion' Alta.
-- ============================================================

INSERT INTO gps_ping (id_residente, latitud, longitud, registrado_en) VALUES
(3, 20.6599, -103.3493, NOW() - INTERVAL '45 minutes'),  -- dentro ✓
(3, 20.6601, -103.3492, NOW() - INTERVAL '30 minutes'),  -- dentro ✓
(3, 20.6602, -103.3491, NOW() - INTERVAL '15 minutes'),  -- dentro ✓
(3, 20.6610, -103.3493, NOW() - INTERVAL '5 minutes');   -- FUERA ✗ → trigger

-- ============================================================
-- 12. ESCENARIO 5 — RFID: ACCESO NO AUTORIZADO
--     Pedro (id=5) tiene turno en Ala B. Accede al lector de
--     la Sala de Medicamentos (Ala A, restringido) sin autorización.
--     trg_auditoria_acceso_rfid escribe a log_auditoria.
--     sp_accesos_no_autorizados(CURRENT_DATE) lo detecta.
-- ============================================================

INSERT INTO lector_rfid (ubicacion, es_restringido, id_ala, id_sala) VALUES
('Entrada Principal',     FALSE, 2, NULL),  -- id 1 — Ala B, público
('Sala de Medicamentos',  TRUE,  1, NULL),  -- id 2 — Ala A, restringido ← acceso indebido
('Enfermería',            TRUE,  2, 4   ),  -- id 3 — Ala B, Consultorio Médico
('Cuarto de Suministros', TRUE,  1, NULL);  -- id 4 — Ala A, restringido

-- Accesos legítimos del día
INSERT INTO acceso_rfid (id_lector, id_staff, accedido_en, acceso_concedido) VALUES
(1, 4, NOW() - INTERVAL '7 hours',  TRUE),  -- María — Entrada Principal (Ala B) ok
(3, 2, NOW() - INTERVAL '6 hours',  TRUE),  -- Dr. Ramírez — Enfermería (Ala B, turno ok)
(3, 3, NOW() - INTERVAL '5 hours',  TRUE);  -- Dra. Torres — Enfermería (Ala B, turno ok)

-- Acceso NO autorizado: Pedro entra a Sala de Medicamentos (Ala A)
-- sin tener turno en Ala A. El trigger lo registra en log_auditoria.
INSERT INTO acceso_rfid (id_lector, id_staff, accedido_en, acceso_concedido)
VALUES (2, 5, NOW() - INTERVAL '2 hours', TRUE);  -- Pedro — Ala A SIN TURNO ← ALERTA

-- ============================================================
-- 13. BEACONS — DETECCIÓN DE PRESENCIA DE STAFF
-- ============================================================

INSERT INTO beacon (id_ala, nombre) VALUES
(1, 'Beacon-AlaA-Corredor'),    -- id 1
(2, 'Beacon-AlaB-Corredor'),    -- id 2
(2, 'Beacon-AlaB-SalaGrupal');  -- id 3

INSERT INTO deteccion_beacon (id_beacon, id_staff, detectado_en) VALUES
(1, 4, NOW() - INTERVAL '6 hours'),    -- María en Ala A
(1, 6, NOW() - INTERVAL '5 hours'),    -- Ana en Ala A
(2, 5, NOW() - INTERVAL '2 hours'),    -- Pedro en Ala B
(2, 2, NOW() - INTERVAL '4 hours'),    -- Dr. Ramírez en Ala B
(3, 3, NOW() - INTERVAL '3 hours'),    -- Dra. Torres en Sala Grupal
(1, 4, NOW() - INTERVAL '1 hour'),     -- María sigue en Ala A
(1, 6, NOW() - INTERVAL '30 minutes'); -- Ana sigue en Ala A

-- ============================================================
-- 14. INCIDENTES MANUALES ADICIONALES (históricos)
-- ============================================================

INSERT INTO reporte_incidente (id_residente, id_staff, fecha, tipo, descripcion, severidad) VALUES
(1, 4, NOW() - INTERVAL '5 days', 'Caida',
 'Residente resbaló al salir de la ducha. Sin lesiones graves, se notificó a familiar.', 'Media'),
(4, 6, NOW() - INTERVAL '3 days', 'Rechazo_Medicamento',
 'Elena rechazó tomar la Memantina durante el desayuno. Se intentó administrar con jugo.', 'Baja'),
(2, 4, NOW() - INTERVAL '6 days', 'Agitacion',
 'Episodio de llanto prolongado durante visita familiar. Se ofreció acompañamiento.', 'Baja');

COMMIT;


-- ============================================================
-- CONSULTAS DE VERIFICACIÓN POR ESCENARIO
-- ============================================================

-- ESCENARIO 1 — Evolución emocional de Carmen (deterioro)
-- SELECT * FROM v_residentes_resumen WHERE residente ILIKE '%Carmen%';
-- BEGIN;
--   CALL sp_evolucion_animo_residente(2, 10, 'cur1');
--   FETCH ALL FROM cur1;
-- COMMIT;
-- Verificar incidentes auto-generados por trigger:
-- SELECT * FROM reporte_incidente WHERE id_residente = 2 ORDER BY fecha;

-- ESCENARIO 2 — Múltiples cuidadores de Roberto (N:M)
-- SELECT * FROM asignacion WHERE id_residente = 1;
-- SELECT id_cuidador, fecha_registro, puntaje, notas
--   FROM checkin_estado_animo WHERE id_residente = 1 ORDER BY fecha_registro;
-- SELECT id_cuidador, fecha_administracion
--   FROM log_medicamento lm
--   JOIN horario_medicamento hm ON lm.id_horario = hm.id_horario
--   WHERE hm.id_residente = 1;

-- ESCENARIO 3 — NFC medicamento (transacción)
-- SELECT ne.escaneado_en, nt.codigo_tag, s.nombre AS cuidador, lm.fecha_administracion
--   FROM nfc_evento ne
--   JOIN nfc_tag nt ON ne.id_tag = nt.id_tag
--   JOIN staff   s  ON ne.id_staff = s.id_staff
--   JOIN log_medicamento lm ON lm.id_cuidador = ne.id_staff
--     AND lm.fecha_administracion::DATE = ne.escaneado_en::DATE;

-- ESCENARIO 4 — GPS salida de perímetro
-- SELECT * FROM v_estado_gps_residentes;
-- Verificar incidente auto-generado por trigger GPS:
-- SELECT * FROM reporte_incidente WHERE tipo = 'Deambulacion';

-- ESCENARIO 5 — Acceso RFID no autorizado
-- BEGIN;
--   CALL sp_accesos_no_autorizados(CURRENT_DATE, 'cur5');
--   FETCH ALL FROM cur5;
-- COMMIT;
-- Ver log de auditoría (registrado por trigger al insertar acceso_rfid):
-- SELECT * FROM log_auditoria ORDER BY timestamp_operacion DESC LIMIT 10;
-- Ver vista de accesos de hoy:
-- SELECT * FROM v_accesos_rfid_hoy;
