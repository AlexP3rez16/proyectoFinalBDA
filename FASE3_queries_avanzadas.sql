-- ============================================================
--  PLATAFORMA DE SALUD MENTAL PARA ADULTOS MAYORES
--  EQUIPO 5 — BASE DE DATOS AVANZADAS — UDEM
--  FASE 3 — QUERIES AVANZADAS Y DISEÑO CONCEPTUAL DE SPs
-- ============================================================


-- ============================================================
-- SECCIÓN 1: ANÁLISIS CLÍNICO
-- ============================================================

-- ------------------------------------------------------------
-- Q1. Tendencia de estado emocional por paciente
-- Problema: El médico necesita ver si un paciente está mejorando
--           o deteriorándose emocionalmente a lo largo del tiempo,
--           comparando el estado al inicio y al fin de cada sesión.
-- ------------------------------------------------------------
SELECT
    p.id_paciente,
    p.nombre || ' ' || p.apellidos                          AS paciente,
    TO_CHAR(s.fecha_sesion, 'YYYY-MM')                      AS mes,
    COUNT(s.id_sesion)                                      AS total_sesiones,
    ROUND(AVG(s.estado_emoc_inicio), 2)                     AS promedio_emoc_inicio,
    ROUND(AVG(s.estado_emoc_fin),    2)                     AS promedio_emoc_fin,
    ROUND(AVG(s.estado_emoc_fin - s.estado_emoc_inicio), 2) AS mejora_promedio
FROM paciente p
JOIN sesion_psicologica s ON p.id_paciente = s.id_paciente
WHERE s.estado_emoc_inicio IS NOT NULL
  AND s.estado_emoc_fin    IS NOT NULL
GROUP BY p.id_paciente, p.nombre, p.apellidos, TO_CHAR(s.fecha_sesion, 'YYYY-MM')
ORDER BY p.id_paciente, mes;

-- Resultado esperado:
-- id_paciente | paciente           | mes     | total_sesiones | promedio_emoc_inicio | promedio_emoc_fin | mejora_promedio
-- 1           | Rosa García López  | 2025-01 | 3              | 4.33                 | 5.67              | 1.33
-- 1           | Rosa García López  | 2025-02 | 2              | 5.50                 | 7.00              | 1.50
-- → Mejora_promedio positiva indica progreso terapéutico.


-- ------------------------------------------------------------
-- Q2. Evolución del nivel de riesgo por escala aplicada
-- Problema: Detectar si los puntajes de una escala clínica
--           específica muestran mejoría o empeoramiento a lo
--           largo del tiempo para un mismo paciente.
-- ------------------------------------------------------------
SELECT
    p.nombre || ' ' || p.apellidos      AS paciente,
    ae.id_escala,
    ec.nombre_escala,
    TO_CHAR(ae.fecha_aplicacion, 'YYYY-MM-DD') AS fecha,
    ae.puntaje_total,
    ae.nivel_riesgo,
    ae.puntaje_total - LAG(ae.puntaje_total) OVER (
        PARTITION BY ae.id_paciente, ae.id_escala
        ORDER BY ae.fecha_aplicacion
    ) AS delta_puntaje
FROM aplicacion_escala ae
JOIN paciente       p  ON ae.id_paciente = p.id_paciente
JOIN escala_clinica ec ON ae.id_escala   = ec.id_escala
ORDER BY ae.id_paciente, ae.id_escala, ae.fecha_aplicacion;

-- Resultado esperado:
-- paciente          | id_escala | nombre_escala       | fecha      | puntaje_total | nivel_riesgo | delta_puntaje
-- Rosa García López | GDS-15    | Escala Ger. Depres. | 2025-01-10 | 9             | Moderado     | NULL
-- Rosa García López | GDS-15    | Escala Ger. Depres. | 2025-02-14 | 6             | Leve         | -3
-- → delta_puntaje negativo en escalas de depresión = mejoría.


-- ------------------------------------------------------------
-- Q3. Pacientes con alertas graves sin atender (sin profesional asignado)
-- Problema: Identificar pacientes críticos cuyas alertas activas
--           no tienen un profesional responsable asignado.
-- ------------------------------------------------------------
SELECT
    p.id_paciente,
    p.nombre || ' ' || p.apellidos   AS paciente,
    p.diagnostico_principal,
    COUNT(a.id_alerta)               AS alertas_graves_sin_atender,
    MIN(a.fecha_generacion)          AS alerta_mas_antigua,
    MAX(a.fecha_generacion)          AS alerta_mas_reciente,
    EXTRACT(EPOCH FROM (NOW() - MIN(a.fecha_generacion))) / 3600 AS horas_sin_atencion
FROM paciente p
JOIN alerta_riesgo a ON p.id_paciente = a.id_paciente
WHERE a.nivel_severidad = 'Grave'
  AND a.estado_alerta   = 'Activa'
  AND a.id_prof_atiende IS NULL
GROUP BY p.id_paciente, p.nombre, p.apellidos, p.diagnostico_principal
HAVING COUNT(a.id_alerta) > 0
ORDER BY alertas_graves_sin_atender DESC, alerta_mas_antigua ASC;

-- Resultado esperado:
-- paciente         | alertas_graves_sin_atender | alerta_mas_antigua  | horas_sin_atencion
-- Manuel Torres M. | 2                          | 2025-03-01 08:15:00 | 72.4
-- → Permite priorizar intervención urgente.


-- ------------------------------------------------------------
-- Q4. Adherencia terapéutica por paciente en un periodo
-- Problema: Calcular qué tan regularmente asiste cada paciente
--           a sus sesiones, para detectar abandono terapéutico.
-- ------------------------------------------------------------
SELECT
    p.id_paciente,
    p.nombre || ' ' || p.apellidos  AS paciente,
    p.diagnostico_principal,
    COUNT(s.id_sesion)              AS total_sesiones,
    MIN(s.fecha_sesion)             AS primera_sesion,
    MAX(s.fecha_sesion)             AS ultima_sesion,
    ROUND(
        EXTRACT(EPOCH FROM (MAX(s.fecha_sesion) - MIN(s.fecha_sesion))) / 86400.0
        / NULLIF(COUNT(s.id_sesion) - 1, 0)
    , 1)                            AS dias_promedio_entre_sesiones,
    EXTRACT(DAY FROM NOW() - MAX(s.fecha_sesion)) AS dias_sin_sesion
FROM paciente p
LEFT JOIN sesion_psicologica s ON p.id_paciente = s.id_paciente
GROUP BY p.id_paciente, p.nombre, p.apellidos, p.diagnostico_principal
ORDER BY dias_sin_sesion DESC NULLS FIRST;

-- Resultado esperado:
-- paciente          | total_sesiones | dias_promedio_entre_sesiones | dias_sin_sesion
-- Elena Mora Vega   | 0              | NULL                         | NULL
-- Rosa García López | 4              | 14.3                         | 35
-- → Pacientes con dias_sin_sesion > 30 requieren contacto proactivo.


-- ============================================================
-- SECCIÓN 2: MÉTRICAS OPERATIVAS
-- ============================================================

-- ------------------------------------------------------------
-- Q5. Carga de trabajo y tiempo promedio por profesional
-- Problema: Medir cuántas sesiones atiende cada profesional,
--           el tiempo total invertido y el promedio por sesión,
--           para distribuir la carga equitativamente.
-- ------------------------------------------------------------
SELECT
    pr.id_profesional,
    pr.nombre || ' ' || pr.apellidos    AS profesional,
    pr.especialidad,
    r.nombre_rol,
    COUNT(DISTINCT s.id_sesion)         AS total_sesiones,
    COUNT(DISTINCT s.id_paciente)       AS pacientes_atendidos,
    SUM(s.duracion_min)                 AS minutos_totales,
    ROUND(AVG(s.duracion_min), 1)       AS duracion_promedio_min,
    COUNT(DISTINCT ae.id_aplicacion)    AS escalas_aplicadas
FROM profesional pr
JOIN rol r ON pr.id_rol = r.id_rol
LEFT JOIN sesion_psicologica s ON pr.id_profesional = s.id_profesional
LEFT JOIN aplicacion_escala ae ON pr.id_profesional = ae.id_profesional
WHERE pr.activo = TRUE
GROUP BY pr.id_profesional, pr.nombre, pr.apellidos, pr.especialidad, r.nombre_rol
ORDER BY total_sesiones DESC;

-- Resultado esperado:
-- profesional          | especialidad    | total_sesiones | pacientes_atendidos | duracion_promedio_min
-- Jorge Ramírez Cruz   | Psiquiatra      | 8              | 3                   | 52.5
-- Laura Torres Salas   | Psicóloga       | 5              | 2                   | 45.0
-- → Detecta desbalance de carga entre especialistas.


-- ------------------------------------------------------------
-- Q6. Tasa de resolución de alertas por profesional
-- Problema: Evaluar la eficiencia de cada médico para cerrar
--           alertas activas, y el tiempo promedio que tardan.
-- ------------------------------------------------------------
SELECT
    pr.nombre || ' ' || pr.apellidos    AS profesional,
    pr.especialidad,
    COUNT(a.id_alerta)                  AS alertas_atendidas,
    SUM(CASE WHEN a.estado_alerta = 'Cerrada'  THEN 1 ELSE 0 END) AS cerradas,
    SUM(CASE WHEN a.estado_alerta = 'Revisada' THEN 1 ELSE 0 END) AS revisadas,
    SUM(CASE WHEN a.estado_alerta = 'Activa'   THEN 1 ELSE 0 END) AS aun_activas,
    ROUND(
        100.0 * SUM(CASE WHEN a.estado_alerta = 'Cerrada' THEN 1 ELSE 0 END)
        / NULLIF(COUNT(a.id_alerta), 0)
    , 1)                                AS tasa_resolucion_pct,
    ROUND(
        AVG(CASE
            WHEN a.estado_alerta = 'Cerrada'
            THEN EXTRACT(EPOCH FROM (a.fecha_resolucion - a.fecha_generacion)) / 3600.0
        END)
    , 2)                                AS horas_promedio_resolucion
FROM profesional pr
JOIN alerta_riesgo a ON pr.id_profesional = a.id_prof_atiende
GROUP BY pr.id_profesional, pr.nombre, pr.apellidos, pr.especialidad
ORDER BY tasa_resolucion_pct DESC;

-- Resultado esperado:
-- profesional       | alertas_atendidas | cerradas | tasa_resolucion_pct | horas_promedio_resolucion
-- Jorge Ramírez     | 5                 | 4        | 80.0                | 6.35
-- → tasa_resolucion_pct < 60% es señal de sobrecarga o falta de seguimiento.


-- ------------------------------------------------------------
-- Q7. Distribución de diagnósticos por nivel de severidad actual
-- Problema: Obtener un panorama clínico del total de pacientes,
--           agrupados por diagnóstico y su nivel de riesgo vigente.
-- ------------------------------------------------------------
SELECT
    p.diagnostico_principal,
    a.nivel_severidad,
    COUNT(*)                           AS total_pacientes,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (
        PARTITION BY p.diagnostico_principal
    ), 1)                              AS pct_dentro_diagnostico
FROM paciente p
LEFT JOIN (
    SELECT DISTINCT ON (id_paciente)
           id_paciente, nivel_severidad
    FROM alerta_riesgo
    ORDER BY id_paciente, fecha_generacion DESC
) a ON p.id_paciente = a.id_paciente
GROUP BY p.diagnostico_principal, a.nivel_severidad
ORDER BY p.diagnostico_principal, a.nivel_severidad;

-- Resultado esperado:
-- diagnostico_principal   | nivel_severidad | total_pacientes | pct_dentro_diagnostico
-- Alzheimer leve          | Leve            | 1               | 50.0
-- Alzheimer leve          | Moderado        | 1               | 50.0
-- Depresión mayor         | Grave           | 1               | 100.0


-- ------------------------------------------------------------
-- Q8. Pacientes sin sesión en los últimos N días (por encima de umbral)
-- Problema: Generar una lista de pacientes que llevan más de
--           30 días sin sesión, ordenados por tiempo de abandono.
-- ------------------------------------------------------------
SELECT
    p.id_paciente,
    p.nombre || ' ' || p.apellidos        AS paciente,
    p.diagnostico_principal,
    c.nombre || ' ' || c.apellidos        AS cuidador_responsable,
    c.telefono                            AS tel_cuidador,
    MAX(s.fecha_sesion)                   AS ultima_sesion,
    EXTRACT(DAY FROM NOW() - MAX(s.fecha_sesion))::int AS dias_sin_sesion,
    (SELECT nivel_severidad FROM alerta_riesgo ar
     WHERE ar.id_paciente = p.id_paciente
     ORDER BY ar.fecha_generacion DESC LIMIT 1) AS riesgo_actual
FROM paciente p
LEFT JOIN sesion_psicologica s ON p.id_paciente = s.id_paciente
LEFT JOIN cuidador c           ON p.id_cuidador  = c.id_cuidador
GROUP BY p.id_paciente, p.nombre, p.apellidos,
         p.diagnostico_principal, c.nombre, c.apellidos, c.telefono
HAVING MAX(s.fecha_sesion) < NOW() - INTERVAL '30 days'
    OR MAX(s.fecha_sesion) IS NULL
ORDER BY dias_sin_sesion DESC NULLS FIRST;

-- Resultado esperado:
-- paciente         | ultima_sesion       | dias_sin_sesion | riesgo_actual
-- Elena Mora Vega  | NULL                | NULL            | Grave
-- → Permite al administrador contactar cuidadores para reagendar.


-- ============================================================
-- SECCIÓN 3: MONITOREO DE EVENTOS IoT
-- ============================================================

-- ------------------------------------------------------------
-- Q9. Pacientes fuera de zona segura en las últimas 24 horas
-- Problema: Identificar de forma inmediata a qué pacientes
--           se les detectó una salida de zona segura reciente,
--           para activar protocolo de búsqueda.
-- ------------------------------------------------------------
SELECT
    p.id_paciente,
    p.nombre || ' ' || p.apellidos  AS paciente,
    p.diagnostico_principal,
    c.nombre || ' ' || c.apellidos  AS cuidador,
    c.telefono,
    d.tipo_dispositivo,
    d.identificador_hw,
    g.latitud,
    g.longitud,
    TO_CHAR(g.timestamp_evento, 'DD Mon YYYY HH24:MI:SS') AS timestamp_salida,
    ROUND(EXTRACT(EPOCH FROM (NOW() - g.timestamp_evento)) / 60.0, 1) AS minutos_transcurridos
FROM evento_gps g
JOIN dispositivo_iot d ON g.id_dispositivo = d.id_dispositivo
JOIN paciente p        ON g.id_paciente    = p.id_paciente
LEFT JOIN cuidador c   ON p.id_cuidador    = c.id_cuidador
WHERE g.dentro_zona_segura = FALSE
  AND g.timestamp_evento  >= NOW() - INTERVAL '24 hours'
ORDER BY g.timestamp_evento DESC;

-- Resultado esperado:
-- paciente         | cuidador       | latitud    | longitud    | timestamp_salida          | minutos_transcurridos
-- Manuel Torres M. | María López G. | 25.6714532 | -100.309876 | 21 Mar 2026 14:23:11      | 47.3
-- → Dispara notificación al cuidador asignado.


-- ------------------------------------------------------------
-- Q10. Tiempo promedio de permanencia en cada zona (NFC)
-- Problema: Calcular cuánto tiempo pasan los pacientes en cada
--           zona del hogar/residencia usando los eventos de
--           entrada/salida NFC, para detectar patrones de aislamiento.
-- ------------------------------------------------------------
WITH pares_nfc AS (
    SELECT
        e.id_paciente,
        e.id_zona,
        e.timestamp_evento AS ts_entrada,
        LEAD(e.timestamp_evento) OVER (
            PARTITION BY e.id_paciente, e.id_zona
            ORDER BY e.timestamp_evento
        ) AS ts_salida,
        e.tipo_evento
    FROM evento_nfc e
    WHERE e.tipo_evento = 'Entrada'
)
SELECT
    p.nombre || ' ' || p.apellidos  AS paciente,
    z.nombre_zona,
    COUNT(*)                        AS total_visitas,
    ROUND(
        AVG(EXTRACT(EPOCH FROM (pn.ts_salida - pn.ts_entrada)) / 60.0)
    , 1)                            AS minutos_promedio_estancia,
    MAX(EXTRACT(EPOCH FROM (pn.ts_salida - pn.ts_entrada)) / 60.0)::int AS max_estancia_min
FROM pares_nfc pn
JOIN paciente p ON pn.id_paciente = p.id_paciente
JOIN zona     z ON pn.id_zona     = z.id_zona
WHERE pn.ts_salida IS NOT NULL
GROUP BY p.id_paciente, p.nombre, p.apellidos, z.id_zona, z.nombre_zona
ORDER BY p.id_paciente, total_visitas DESC;

-- Resultado esperado:
-- paciente         | nombre_zona   | total_visitas | minutos_promedio_estancia | max_estancia_min
-- Rosa García López| Habitación 1  | 12            | 480.5                     | 720
-- Rosa García López| Comedor       | 8             | 32.0                      | 65
-- → Estancias >8h en habitación pueden indicar aislamiento depresivo.


-- ------------------------------------------------------------
-- Q11. Dispositivos IoT sin conexión reciente (más de 6 horas)
-- Problema: Detectar dispositivos que podrían estar sin batería
--           o con falla técnica, generando puntos ciegos de monitoreo.
-- ------------------------------------------------------------
SELECT
    d.id_dispositivo,
    d.tipo_dispositivo,
    d.identificador_hw,
    d.estado,
    p.nombre || ' ' || p.apellidos   AS paciente_asignado,
    TO_CHAR(d.ultima_conexion, 'DD Mon YYYY HH24:MI') AS ultima_conexion,
    ROUND(EXTRACT(EPOCH FROM (NOW() - d.ultima_conexion)) / 3600.0, 1) AS horas_sin_conexion,
    CASE
        WHEN d.ultima_conexion < NOW() - INTERVAL '24 hours' THEN 'CRITICO'
        WHEN d.ultima_conexion < NOW() - INTERVAL '6 hours'  THEN 'ADVERTENCIA'
        ELSE 'OK'
    END AS estado_conexion
FROM dispositivo_iot d
LEFT JOIN paciente p ON d.id_paciente = p.id_paciente
WHERE d.estado = 'Activo'
  AND (d.ultima_conexion < NOW() - INTERVAL '6 hours'
       OR d.ultima_conexion IS NULL)
ORDER BY horas_sin_conexion DESC NULLS FIRST;

-- Resultado esperado:
-- tipo_dispositivo | paciente_asignado | ultima_conexion      | horas_sin_conexion | estado_conexion
-- GPS              | Manuel Torres M.  | 20 Mar 2026 22:10    | 16.3               | CRITICO
-- NFC              | Rosa García López | 21 Mar 2026 10:00    | 9.2                | ADVERTENCIA


-- ------------------------------------------------------------
-- Q12. Resumen de actividad IoT por paciente (últimas 48 h)
-- Problema: Dar al cuidador y al médico un resumen consolidado
--           de todos los eventos registrados por cada paciente,
--           incluyendo GPS, NFC y Beacon.
-- ------------------------------------------------------------
SELECT
    p.id_paciente,
    p.nombre || ' ' || p.apellidos  AS paciente,
    COALESCE(gps.total_gps, 0)      AS eventos_gps,
    COALESCE(gps.fuera_zona, 0)     AS salidas_zona_segura,
    COALESCE(nfc.total_nfc, 0)      AS eventos_nfc,
    COALESCE(bcn.total_beacon, 0)   AS eventos_beacon,
    COALESCE(gps.total_gps, 0) + COALESCE(nfc.total_nfc, 0)
        + COALESCE(bcn.total_beacon, 0) AS total_eventos
FROM paciente p
LEFT JOIN (
    SELECT id_paciente,
           COUNT(*) AS total_gps,
           SUM(CASE WHEN dentro_zona_segura = FALSE THEN 1 ELSE 0 END) AS fuera_zona
    FROM evento_gps
    WHERE timestamp_evento >= NOW() - INTERVAL '48 hours'
    GROUP BY id_paciente
) gps ON p.id_paciente = gps.id_paciente
LEFT JOIN (
    SELECT id_paciente, COUNT(*) AS total_nfc
    FROM evento_nfc
    WHERE timestamp_evento >= NOW() - INTERVAL '48 hours'
    GROUP BY id_paciente
) nfc ON p.id_paciente = nfc.id_paciente
LEFT JOIN (
    SELECT id_paciente, COUNT(*) AS total_beacon
    FROM evento_beacon
    WHERE timestamp_evento >= NOW() - INTERVAL '48 hours'
    GROUP BY id_paciente
) bcn ON p.id_paciente = bcn.id_paciente
ORDER BY total_eventos DESC;

-- Resultado esperado:
-- paciente         | eventos_gps | salidas_zona_segura | eventos_nfc | eventos_beacon | total_eventos
-- Rosa García López| 48          | 0                   | 22          | 30             | 100
-- Manuel Torres M. | 30          | 2                   | 18          | 25             | 73


-- ============================================================
-- SECCIÓN 4: REPORTES ADMINISTRATIVOS
-- ============================================================

-- ------------------------------------------------------------
-- Q13. Resumen mensual de actividad clínica
-- Problema: Generar un KPI mensual para la dirección con los
--           indicadores clave: sesiones, alertas, escalas,
--           nuevos pacientes y porcentaje de alertas resueltas.
-- ------------------------------------------------------------
SELECT
    TO_CHAR(fecha_mes, 'YYYY-MM')             AS mes,
    nuevos_pacientes,
    total_sesiones,
    minutos_atencion,
    escalas_aplicadas,
    alertas_generadas,
    alertas_cerradas,
    ROUND(100.0 * alertas_cerradas / NULLIF(alertas_generadas, 0), 1) AS tasa_resolucion_pct
FROM (
    SELECT
        DATE_TRUNC('month', s.fecha_sesion)         AS fecha_mes,
        COUNT(DISTINCT s.id_sesion)                 AS total_sesiones,
        SUM(s.duracion_min)                         AS minutos_atencion,
        COUNT(DISTINCT ae.id_aplicacion)            AS escalas_aplicadas,
        (SELECT COUNT(*) FROM alerta_riesgo a
         WHERE DATE_TRUNC('month', a.fecha_generacion) = DATE_TRUNC('month', s.fecha_sesion)) AS alertas_generadas,
        (SELECT COUNT(*) FROM alerta_riesgo a
         WHERE DATE_TRUNC('month', a.fecha_generacion) = DATE_TRUNC('month', s.fecha_sesion)
           AND a.estado_alerta = 'Cerrada') AS alertas_cerradas,
        (SELECT COUNT(*) FROM paciente p
         WHERE DATE_TRUNC('month', p.fecha_registro) = DATE_TRUNC('month', s.fecha_sesion)) AS nuevos_pacientes
    FROM sesion_psicologica s
    LEFT JOIN aplicacion_escala ae ON s.id_sesion = ae.id_sesion
    GROUP BY DATE_TRUNC('month', s.fecha_sesion)
) sub
ORDER BY fecha_mes;

-- Resultado esperado:
-- mes     | nuevos_pacientes | total_sesiones | minutos_atencion | escalas_aplicadas | alertas_generadas | tasa_resolucion_pct
-- 2025-01 | 3                | 5              | 275              | 5                 | 3                 | 66.7
-- 2025-02 | 0                | 4              | 200              | 4                 | 2                 | 100.0


-- ------------------------------------------------------------
-- Q14. Escalas más aplicadas y distribución de resultados
-- Problema: Identificar qué instrumentos clínicos se usan más
--           y qué porcentaje de aplicaciones resultan en riesgo
--           grave, para revisar protocolos de evaluación.
-- ------------------------------------------------------------
SELECT
    ec.id_escala,
    ec.nombre_escala,
    ec.tipo,
    COUNT(ae.id_aplicacion)    AS total_aplicaciones,
    ROUND(AVG(ae.puntaje_total), 2) AS puntaje_promedio,
    SUM(CASE WHEN ae.nivel_riesgo = 'Normal'   THEN 1 ELSE 0 END) AS normal,
    SUM(CASE WHEN ae.nivel_riesgo = 'Leve'     THEN 1 ELSE 0 END) AS leve,
    SUM(CASE WHEN ae.nivel_riesgo = 'Moderado' THEN 1 ELSE 0 END) AS moderado,
    SUM(CASE WHEN ae.nivel_riesgo = 'Grave'    THEN 1 ELSE 0 END) AS grave,
    ROUND(100.0 * SUM(CASE WHEN ae.nivel_riesgo = 'Grave' THEN 1 ELSE 0 END)
          / NULLIF(COUNT(ae.id_aplicacion), 0), 1) AS pct_grave
FROM escala_clinica ec
LEFT JOIN aplicacion_escala ae ON ec.id_escala = ae.id_escala
GROUP BY ec.id_escala, ec.nombre_escala, ec.tipo
ORDER BY total_aplicaciones DESC;

-- Resultado esperado:
-- nombre_escala                | tipo       | total_aplicaciones | puntaje_promedio | normal | leve | moderado | grave | pct_grave
-- Escala Ger. de Depresión-15  | Depresion  | 6                  | 8.33             | 0      | 2    | 3        | 1     | 16.7
-- MoCA                         | Cognitivo  | 4                  | 22.50            | 1      | 1    | 2        | 0     | 0.0


-- ------------------------------------------------------------
-- Q15. Actividad del log de auditoría por usuario y operación
-- Problema: Detectar patrones de uso inusuales en el sistema
--           (exceso de DELETEs, accesos fuera de horario, etc.)
--           para cumplimiento de seguridad.
-- ------------------------------------------------------------
SELECT
    pr.nombre || ' ' || pr.apellidos  AS usuario,
    r.nombre_rol,
    l.operacion,
    l.tabla_afectada,
    COUNT(*)                          AS total_operaciones,
    MIN(TO_CHAR(l.timestamp_operacion, 'HH24:MI')) AS hora_min,
    MAX(TO_CHAR(l.timestamp_operacion, 'HH24:MI')) AS hora_max,
    COUNT(DISTINCT l.ip_origen)       AS ips_distintas
FROM log_auditoria l
JOIN profesional pr ON l.id_usuario = pr.id_profesional
JOIN rol          r  ON pr.id_rol   = r.id_rol
GROUP BY pr.id_profesional, pr.nombre, pr.apellidos,
         r.nombre_rol, l.operacion, l.tabla_afectada
HAVING COUNT(*) > 0
ORDER BY total_operaciones DESC, l.operacion;

-- Resultado esperado:
-- usuario          | nombre_rol | operacion | tabla_afectada    | total_operaciones | ips_distintas
-- Carlos Medina    | Admin      | SELECT    | paciente          | 42                | 1
-- Jorge Ramírez    | Médico     | INSERT    | sesion_psicologica| 8                 | 2
-- → ips_distintas > 3 puede indicar acceso desde múltiples ubicaciones.


-- ============================================================
-- SECCIÓN 5: DISEÑO CONCEPTUAL DE STORED PROCEDURES
-- ============================================================
-- Nota: Diseño de parámetros y lógica. La implementación
--       completa corresponde a una fase posterior.
-- ============================================================

-- ------------------------------------------------------------
-- SP1. sp_generar_alerta_automatica
-- Problema que resuelve:
--   Cuando se registra una aplicación de escala con nivel_riesgo
--   'Grave' o 'Moderado', el sistema debe generar automáticamente
--   una alerta en alerta_riesgo sin intervención manual.
--
-- Parámetros:
--   IN  p_id_aplicacion   INT      -- ID de la aplicación recién insertada
--   IN  p_id_paciente     INT      -- Paciente evaluado
--   IN  p_nivel_riesgo    VARCHAR  -- 'Grave' | 'Moderado'
--   IN  p_id_escala       VARCHAR  -- Escala que generó el resultado
--   IN  p_puntaje         INT      -- Puntaje obtenido
--   OUT p_id_alerta       INT      -- ID de la alerta creada (0 si no aplica)
--
-- Reglas de negocio:
--   1. Solo genera alerta si nivel_riesgo IN ('Moderado','Grave').
--   2. Si ya existe una alerta 'Activa' para el mismo paciente
--      y misma escala en las últimas 24h, no duplica.
--   3. El tipo_alerta se construye como: 'Evaluación <id_escala>: Riesgo <nivel_riesgo>'
-- ------------------------------------------------------------

/*
CREATE OR REPLACE PROCEDURE sp_generar_alerta_automatica(
    IN  p_id_aplicacion   INT,
    IN  p_id_paciente     INT,
    IN  p_nivel_riesgo    VARCHAR(20),
    IN  p_id_escala       VARCHAR(20),
    IN  p_puntaje         INT,
    OUT p_id_alerta       INT
)
LANGUAGE plpgsql AS $$
DECLARE
    v_existe_alerta INT;
BEGIN
    p_id_alerta := 0;

    -- Solo procesar riesgos que requieren alerta
    IF p_nivel_riesgo NOT IN ('Moderado', 'Grave') THEN
        RETURN;
    END IF;

    -- Verificar duplicado en 24h
    SELECT COUNT(*) INTO v_existe_alerta
    FROM alerta_riesgo
    WHERE id_paciente = p_id_paciente
      AND tipo_alerta LIKE '%' || p_id_escala || '%'
      AND estado_alerta = 'Activa'
      AND fecha_generacion >= NOW() - INTERVAL '24 hours';

    IF v_existe_alerta > 0 THEN
        RETURN;
    END IF;

    -- Insertar alerta
    INSERT INTO alerta_riesgo (
        id_paciente, id_aplicacion, tipo_alerta,
        nivel_severidad, descripcion
    ) VALUES (
        p_id_paciente,
        p_id_aplicacion,
        'Evaluación ' || p_id_escala || ': Riesgo ' || p_nivel_riesgo,
        p_nivel_riesgo,
        'Generada automáticamente. Puntaje: ' || p_puntaje
    )
    RETURNING id_alerta INTO p_id_alerta;

    COMMIT;
END;
$$;
*/


-- ------------------------------------------------------------
-- SP2. sp_reporte_mensual_clinico
-- Problema que resuelve:
--   Generar y devolver el resumen mensual de KPIs clínicos
--   para el portal administrativo, con un solo CALL.
--
-- Parámetros:
--   IN  p_anio   INT  -- Año del reporte (ej: 2026)
--   IN  p_mes    INT  -- Mes del reporte (1-12)
--   OUT p_total_sesiones        INT
--   OUT p_minutos_atencion      INT
--   OUT p_nuevos_pacientes      INT
--   OUT p_alertas_generadas     INT
--   OUT p_alertas_resueltas     INT
--   OUT p_tasa_resolucion       NUMERIC
--   OUT p_escalas_aplicadas     INT
--
-- Reglas de negocio:
--   1. Filtra por DATE_TRUNC del parámetro mes/año.
--   2. Si p_mes o p_anio = 0, usa el mes/año actual.
--   3. tasa_resolucion = alertas_resueltas / alertas_generadas * 100.
-- ------------------------------------------------------------

/*
CREATE OR REPLACE PROCEDURE sp_reporte_mensual_clinico(
    IN  p_anio                INT,
    IN  p_mes                 INT,
    OUT p_total_sesiones      INT,
    OUT p_minutos_atencion    INT,
    OUT p_nuevos_pacientes    INT,
    OUT p_alertas_generadas   INT,
    OUT p_alertas_resueltas   INT,
    OUT p_tasa_resolucion     NUMERIC,
    OUT p_escalas_aplicadas   INT
)
LANGUAGE plpgsql AS $$
DECLARE
    v_fecha_inicio DATE;
    v_fecha_fin    DATE;
BEGIN
    v_fecha_inicio := MAKE_DATE(
        CASE WHEN p_anio = 0 THEN EXTRACT(YEAR  FROM NOW())::INT ELSE p_anio END,
        CASE WHEN p_mes  = 0 THEN EXTRACT(MONTH FROM NOW())::INT ELSE p_mes  END,
        1
    );
    v_fecha_fin := v_fecha_inicio + INTERVAL '1 month';

    SELECT COUNT(*), COALESCE(SUM(duracion_min), 0)
    INTO p_total_sesiones, p_minutos_atencion
    FROM sesion_psicologica
    WHERE fecha_sesion >= v_fecha_inicio AND fecha_sesion < v_fecha_fin;

    SELECT COUNT(*) INTO p_nuevos_pacientes
    FROM paciente
    WHERE fecha_registro >= v_fecha_inicio AND fecha_registro < v_fecha_fin;

    SELECT COUNT(*) INTO p_alertas_generadas
    FROM alerta_riesgo
    WHERE fecha_generacion >= v_fecha_inicio AND fecha_generacion < v_fecha_fin;

    SELECT COUNT(*) INTO p_alertas_resueltas
    FROM alerta_riesgo
    WHERE fecha_generacion >= v_fecha_inicio AND fecha_generacion < v_fecha_fin
      AND estado_alerta = 'Cerrada';

    SELECT COUNT(*) INTO p_escalas_aplicadas
    FROM aplicacion_escala
    WHERE fecha_aplicacion >= v_fecha_inicio AND fecha_aplicacion < v_fecha_fin;

    p_tasa_resolucion := ROUND(
        100.0 * p_alertas_resueltas / NULLIF(p_alertas_generadas, 0), 1
    );
END;
$$;
*/


-- ------------------------------------------------------------
-- SP3. sp_verificar_zona_segura
-- Problema que resuelve:
--   Al insertar un evento GPS fuera de zona (dentro_zona_segura=FALSE),
--   registrar automáticamente una alerta de tipo 'Salida de Zona Segura'
--   y notificar en log de auditoría.
--
-- Parámetros:
--   IN  p_id_paciente     INT       -- Paciente detectado fuera de zona
--   IN  p_id_dispositivo  INT       -- Dispositivo GPS que reportó
--   IN  p_latitud         DECIMAL   -- Coordenadas del evento
--   IN  p_longitud        DECIMAL
--   IN  p_timestamp       TIMESTAMP -- Momento del evento
--   OUT p_alerta_creada   BOOLEAN   -- TRUE si se generó alerta nueva
--
-- Reglas de negocio:
--   1. Si existe alerta activa de 'Salida de Zona' en las últimas 2h
--      para el mismo paciente, no duplica la alerta.
--   2. Siempre inserta el evento en evento_gps.
--   3. Si genera alerta, registra en log_auditoria con operacion='INSERT'.
-- ------------------------------------------------------------

/*
CREATE OR REPLACE PROCEDURE sp_verificar_zona_segura(
    IN  p_id_paciente     INT,
    IN  p_id_dispositivo  INT,
    IN  p_latitud         DECIMAL(10,7),
    IN  p_longitud        DECIMAL(10,7),
    IN  p_timestamp       TIMESTAMP,
    OUT p_alerta_creada   BOOLEAN
)
LANGUAGE plpgsql AS $$
DECLARE
    v_existe   INT;
    v_id_aplic INT;
BEGIN
    p_alerta_creada := FALSE;

    -- Revisar alerta reciente (ventana 2h)
    SELECT COUNT(*) INTO v_existe
    FROM alerta_riesgo
    WHERE id_paciente   = p_id_paciente
      AND tipo_alerta   = 'Salida de Zona Segura'
      AND estado_alerta = 'Activa'
      AND fecha_generacion >= NOW() - INTERVAL '2 hours';

    IF v_existe = 0 THEN
        -- Obtener última aplicacion para FK requerida
        SELECT id_aplicacion INTO v_id_aplic
        FROM aplicacion_escala
        WHERE id_paciente = p_id_paciente
        ORDER BY fecha_aplicacion DESC LIMIT 1;

        INSERT INTO alerta_riesgo (
            id_paciente, id_aplicacion, tipo_alerta,
            nivel_severidad, descripcion
        ) VALUES (
            p_id_paciente, v_id_aplic,
            'Salida de Zona Segura',
            'Grave',
            'GPS detectó al paciente fuera de zona segura en ' ||
            p_latitud::TEXT || ', ' || p_longitud::TEXT
        );

        p_alerta_creada := TRUE;
    END IF;

    COMMIT;
END;
$$;
*/


-- ------------------------------------------------------------
-- SP4. sp_calcular_adherencia_terapeutica
-- Problema que resuelve:
--   Calcular el índice de adherencia de un paciente específico
--   comparando sesiones esperadas vs sesiones realizadas en
--   un período dado, y clasificar el resultado.
--
-- Parámetros:
--   IN  p_id_paciente          INT      -- Paciente a evaluar
--   IN  p_fecha_inicio         DATE     -- Inicio del periodo
--   IN  p_fecha_fin            DATE     -- Fin del periodo
--   IN  p_sesiones_esperadas   INT      -- Sesiones que deberían haberse tenido
--   OUT p_sesiones_realizadas  INT      -- Sesiones que realmente ocurrieron
--   OUT p_indice_adherencia    NUMERIC  -- % de cumplimiento (0-100)
--   OUT p_clasificacion        VARCHAR  -- 'Alta' | 'Media' | 'Baja' | 'Nula'
--
-- Reglas de negocio:
--   1. indice = (realizadas / esperadas) * 100, máximo 100.
--   2. Alta >= 80%, Media 50-79%, Baja 1-49%, Nula = 0%.
-- ------------------------------------------------------------

/*
CREATE OR REPLACE PROCEDURE sp_calcular_adherencia_terapeutica(
    IN  p_id_paciente         INT,
    IN  p_fecha_inicio        DATE,
    IN  p_fecha_fin           DATE,
    IN  p_sesiones_esperadas  INT,
    OUT p_sesiones_realizadas INT,
    OUT p_indice_adherencia   NUMERIC,
    OUT p_clasificacion       VARCHAR(20)
)
LANGUAGE plpgsql AS $$
BEGIN
    SELECT COUNT(*) INTO p_sesiones_realizadas
    FROM sesion_psicologica
    WHERE id_paciente  = p_id_paciente
      AND fecha_sesion BETWEEN p_fecha_inicio AND p_fecha_fin;

    p_indice_adherencia := LEAST(
        ROUND(100.0 * p_sesiones_realizadas / NULLIF(p_sesiones_esperadas, 0), 1),
        100.0
    );

    p_clasificacion := CASE
        WHEN p_indice_adherencia = 0             THEN 'Nula'
        WHEN p_indice_adherencia < 50            THEN 'Baja'
        WHEN p_indice_adherencia < 80            THEN 'Media'
        ELSE                                          'Alta'
    END;
END;
$$;
*/

-- ============================================================
-- FIN FASE 3
-- ============================================================
