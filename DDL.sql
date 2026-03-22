-- ============================================================
--  PLATAFORMA DE SALUD MENTAL PARA ADULTOS MAYORES
--  EQUIPO 5 — BASE DE DATOS AVANZADAS — UDEM
--  FASE 2 — Script DDL PostgreSQL
-- ============================================================

-- ============================================================
-- CREAR BASE DE DATOS
-- ============================================================
-- USUARIO = equipo5proyfin

CREATE DATABASE salud_mental_db;

-- \c salud_mental_db

-- ============================================================
-- TABLAS MAESTRAS
-- ============================================================

CREATE TABLE rol (
    id_rol serial primary key,
    nombre_rol  varchar(50) NOT NULL,
    descripcion TEXT,
    nivel_acceso  int NOT NULL CHECK (nivel_acceso BETWEEN 1 AND 3),
    CONSTRAINT uq_rol_nombre UNIQUE (nombre_rol)
);

CREATE TABLE cuidador (
    id_cuidador serial primary key,
    nombre varchar(100) NOT NULL,
    apellidos varchar(100) NOT NULL,
    telefono varchar(15),
    email varchar(100),
    turno varchar(20)  NOT NULL CHECK (turno IN ('Matutino','Vespertino','Nocturno')),
    activo boolean NOT NULL DEFAULT TRUE,
    fecha_alta DATE NOT NULL DEFAULT CURRENT_DATE
);

CREATE TABLE escala_clinica (
    id_escala varchar(20) primary key,
    nombre_escala varchar(80) NOT NULL,
    tipo varchar(50) NOT NULL CHECK (tipo IN ('Depresion','Cognitivo','Funcionalidad','Ansiedad')),
    num_reactivos int NOT NULL CHECK (num_reactivos > 0),
    puntaje_min int NOT NULL,
    puntaje_max int NOT NULL,
    descripcion TEXT,
    CONSTRAINT uq_escala_nombre UNIQUE (nombre_escala),
    CONSTRAINT ck_escala_rango  CHECK  (puntaje_min < puntaje_max)
);

CREATE TABLE zona (
    id_zona serial primary key,
    nombre_zona varchar(80) NOT NULL,
    descripcion TEXT,
    activa boolean NOT NULL DEFAULT TRUE,
    CONSTRAINT uq_zona_nombre UNIQUE (nombre_zona)
);

-- ============================================================
-- TABLAS QUE DEPENDEN DE LAS MAESTRAS
-- ============================================================

CREATE TABLE paciente (
    id_paciente serial primary key,
    nombre varchar(100) NOT NULL,
    apellidos varchar(100) NOT NULL,
    fecha_nacimiento DATE NOT NULL,
    sexo CHAR(1) NOT NULL,
    curp varchar(18),
    telefono varchar(15),
    email varchar(100),
    diagnostico_principal TEXT,
    id_cuidador int,
    fecha_registro TIMESTAMP NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_paciente_curp  UNIQUE  (curp),
    CONSTRAINT ck_paciente_sexo  CHECK   (sexo IN ('M','F')),
    CONSTRAINT ck_paciente_edad  CHECK   (fecha_nacimiento <= CURRENT_DATE - INTERVAL '60 years'),
    CONSTRAINT fk_paciente_cuidador FOREIGN KEY (id_cuidador)
    REFERENCES cuidador(id_cuidador) ON UPDATE CASCADE
    ON DELETE SET NULL
);

CREATE TABLE profesional (
    id_profesional serial primary key,
    nombre varchar(100) NOT NULL,
    apellidos varchar(100) NOT NULL,
    cedula varchar(20)  NOT NULL,
    especialidad varchar(80)  NOT NULL,
    email varchar(100) NOT NULL,
    id_rol int NOT NULL,
    activo boolean NOT NULL DEFAULT TRUE,
    fecha_alta DATE NOT NULL DEFAULT CURRENT_DATE,
    CONSTRAINT uq_profesional_cedula UNIQUE (cedula),
    CONSTRAINT uq_profesional_email  UNIQUE (email),
    CONSTRAINT fk_profesional_rol FOREIGN KEY (id_rol)
        REFERENCES rol(id_rol)
        ON UPDATE CASCADE
);

CREATE TABLE umbral_alerta (
    id_umbral serial primary key,
    id_escala varchar(20) NOT NULL,
    nivel_riesgo varchar(20) NOT NULL,
    puntaje_minimo int NOT NULL,
    puntaje_maximo int NOT NULL,
    descripcion TEXT,
    activo boolean NOT NULL DEFAULT TRUE,
    CONSTRAINT ck_umbral_rango CHECK  (puntaje_minimo <= puntaje_maximo),
    CONSTRAINT ck_umbral_nivel CHECK  (nivel_riesgo IN ('Normal','Leve','Moderado','Grave')),
    CONSTRAINT uq_umbral_escala_nivel UNIQUE (id_escala, nivel_riesgo),
    CONSTRAINT fk_umbral_escala FOREIGN KEY (id_escala)
        REFERENCES escala_clinica(id_escala)
        ON UPDATE CASCADE
);

CREATE TABLE dispositivo_iot (
    id_dispositivo serial primary key,
    tipo_dispositivo varchar(10)  NOT NULL,
    identificador_hw varchar(100) NOT NULL,
    id_paciente int,
    estado varchar(20)  NOT NULL DEFAULT 'Activo',
    ultima_conexion TIMESTAMP,
    fecha_registro DATE NOT NULL DEFAULT CURRENT_DATE,
    CONSTRAINT uq_dispositivo_hw UNIQUE (identificador_hw),
    CONSTRAINT ck_dispositivo_tipo CHECK  (tipo_dispositivo IN ('GPS','NFC','Beacon')),
    CONSTRAINT ck_dispositivo_estado CHECK (estado IN ('Activo','Inactivo','Mantenimiento')),
    CONSTRAINT fk_dispositivo_paciente FOREIGN KEY (id_paciente)
        REFERENCES paciente(id_paciente)
        ON UPDATE CASCADE
        ON DELETE SET NULL
);

-- ============================================================
-- TABLAS TRANSACCIONALES CLÍNICAS
-- ============================================================

CREATE TABLE sesion_psicologica (
    id_sesion serial primary key,
    id_paciente int NOT NULL,
    id_profesional int NOT NULL,
    fecha_sesion TIMESTAMP   NOT NULL,
    tipo_sesion varchar(20) NOT NULL,
    duracion_min int,
    notas_clinicas TEXT,
    estado_emoc_inicio int,
    estado_emoc_fin int,
    diagnostico_sesion TEXT,
    plan_siguiente TEXT,
    CONSTRAINT ck_sesion_tipo CHECK (tipo_sesion IN ('Individual','Grupal','Virtual')),
    CONSTRAINT ck_sesion_duracion CHECK (duracion_min > 0 AND duracion_min <= 480),
    CONSTRAINT ck_sesion_emoc_inicio CHECK (estado_emoc_inicio BETWEEN 1 AND 10),
    CONSTRAINT ck_sesion_emoc_fin CHECK (estado_emoc_fin    BETWEEN 1 AND 10),
    CONSTRAINT fk_sesion_paciente FOREIGN KEY (id_paciente)
        REFERENCES paciente(id_paciente)
        ON UPDATE CASCADE,
    CONSTRAINT fk_sesion_profesional FOREIGN KEY (id_profesional)
        REFERENCES profesional(id_profesional)
        ON UPDATE CASCADE
);

CREATE INDEX idx_sesion_paciente ON sesion_psicologica (id_paciente);
CREATE INDEX idx_sesion_profesional ON sesion_psicologica (id_profesional);
CREATE INDEX idx_sesion_fecha ON sesion_psicologica (fecha_sesion DESC);

CREATE TABLE aplicacion_escala (
    id_aplicacion serial primary key,
    id_sesion int NOT NULL,
    id_escala varchar(20) NOT NULL,
    id_paciente int NOT NULL,
    id_profesional int NOT NULL,
    fecha_aplicacion TIMESTAMP NOT NULL DEFAULT NOW(),
    puntaje_total int NOT NULL,
    interpretacion varchar(100),
    nivel_riesgo varchar(20) NOT NULL,
    observaciones TEXT,
    CONSTRAINT ck_aplic_puntaje CHECK (puntaje_total >= 0),
    CONSTRAINT ck_aplic_nivel CHECK (nivel_riesgo IN ('Normal','Leve','Moderado','Grave')),
    CONSTRAINT fk_aplic_sesion FOREIGN KEY (id_sesion)
        REFERENCES sesion_psicologica(id_sesion)
        ON UPDATE CASCADE,
    CONSTRAINT fk_aplic_escala FOREIGN KEY (id_escala)
        REFERENCES escala_clinica(id_escala)
        ON UPDATE CASCADE,
    CONSTRAINT fk_aplic_paciente FOREIGN KEY (id_paciente)
        REFERENCES paciente(id_paciente)
        ON UPDATE CASCADE,
    CONSTRAINT fk_aplic_profesional FOREIGN KEY (id_profesional)
        REFERENCES profesional(id_profesional)
        ON UPDATE CASCADE
);

CREATE INDEX idx_aplic_paciente ON aplicacion_escala (id_paciente);
CREATE INDEX idx_aplic_escala   ON aplicacion_escala (id_escala);
CREATE INDEX idx_aplic_fecha    ON aplicacion_escala (fecha_aplicacion DESC);

CREATE TABLE respuesta_reactivo (
    id_respuesta serial primary key,
    id_aplicacion int NOT NULL,
    num_reactivo int NOT NULL,
    texto_reactivo TEXT NOT NULL,
    valor_respuesta int NOT NULL,
    texto_respuesta varchar(100),
    CONSTRAINT ck_reactivo_num CHECK  (num_reactivo    >= 1),
    CONSTRAINT ck_reactivo_valor CHECK  (valor_respuesta >= 0),
    CONSTRAINT uq_reactivo_aplicacion UNIQUE (id_aplicacion, num_reactivo),
    CONSTRAINT fk_reactivo_aplicacion FOREIGN KEY (id_aplicacion)
        REFERENCES aplicacion_escala(id_aplicacion)
        ON UPDATE CASCADE
        ON DELETE CASCADE
);

CREATE TABLE alerta_riesgo (
    id_alerta serial primary key,
    id_paciente int NOT NULL,
    id_aplicacion int NOT NULL,
    tipo_alerta varchar(80) NOT NULL,
    nivel_severidad varchar(20) NOT NULL,
    descripcion TEXT,
    fecha_generacion TIMESTAMP NOT NULL DEFAULT NOW(),
    estado_alerta varchar(20) NOT NULL DEFAULT 'Activa',
    id_prof_atiende  int,
    fecha_resolucion TIMESTAMP,
    acciones_tomadas TEXT,
    CONSTRAINT ck_alerta_severidad CHECK (nivel_severidad IN ('Leve','Moderado','Grave')),
    CONSTRAINT ck_alerta_estado CHECK (estado_alerta IN ('Activa','Revisada','Cerrada')),
    CONSTRAINT ck_alerta_resolucion  CHECK (estado_alerta != 'Cerrada' OR fecha_resolucion IS NOT NULL),
    CONSTRAINT fk_alerta_paciente FOREIGN KEY (id_paciente)
        REFERENCES paciente(id_paciente)
        ON UPDATE CASCADE,
    CONSTRAINT fk_alerta_aplicacion FOREIGN KEY (id_aplicacion)
        REFERENCES aplicacion_escala(id_aplicacion)
        ON UPDATE CASCADE,
    CONSTRAINT fk_alerta_profesional FOREIGN KEY (id_prof_atiende)
        REFERENCES profesional(id_profesional)
        ON UPDATE CASCADE
);

CREATE INDEX idx_alerta_paciente ON alerta_riesgo (id_paciente);
CREATE INDEX idx_alerta_estado   ON alerta_riesgo (estado_alerta);

CREATE TABLE evolucion_emocional (
    id_evolucion serial primary key,
    id_paciente int NOT NULL,
    id_sesion int NOT NULL,
    fecha_registro DATE NOT NULL DEFAULT CURRENT_DATE,
    puntaje_emocional int NOT NULL,
    etiqueta_estado varchar(50),
    notas_profesional TEXT,
    CONSTRAINT ck_evolucion_puntaje CHECK (puntaje_emocional BETWEEN 1 AND 10),
    CONSTRAINT uq_evolucion_sesion  UNIQUE (id_sesion),
    CONSTRAINT fk_evolucion_paciente FOREIGN KEY (id_paciente)
        REFERENCES paciente(id_paciente)
        ON UPDATE CASCADE,
    CONSTRAINT fk_evolucion_sesion FOREIGN KEY (id_sesion)
        REFERENCES sesion_psicologica(id_sesion)
        ON UPDATE CASCADE
);

CREATE INDEX idx_evolucion_paciente ON evolucion_emocional (id_paciente);

CREATE TABLE observacion_cuidador (
    id_observacion serial primary key,
    id_cuidador int NOT NULL,
    id_paciente int NOT NULL,
    fecha_observacion TIMESTAMP  NOT NULL DEFAULT NOW(),
    descripcion TEXT NOT NULL,
    nivel_agitacion int,
    incidencias TEXT,
    CONSTRAINT ck_obs_agitacion CHECK (nivel_agitacion BETWEEN 1 AND 5),
    CONSTRAINT fk_obs_cuidador FOREIGN KEY (id_cuidador)
        REFERENCES cuidador(id_cuidador)
        ON UPDATE CASCADE,
    CONSTRAINT fk_obs_paciente FOREIGN KEY (id_paciente)
        REFERENCES paciente(id_paciente)
        ON UPDATE CASCADE
);

CREATE INDEX idx_obs_paciente ON observacion_cuidador (id_paciente);

-- ============================================================
-- TABLAS DE EVENTOS IoT
-- ============================================================

CREATE TABLE evento_gps (
    id_evento_gps BIGSERIAL primary key,
    id_dispositivo int NOT NULL,
    id_paciente int NOT NULL,
    latitud DECIMAL(10,7) NOT NULL,
    longitud DECIMAL(10,7) NOT NULL,
    altitud DECIMAL(8,2),
    precision_m DECIMAL(6,2),
    timestamp_evento TIMESTAMP NOT NULL DEFAULT NOW(),
    dentro_zona_segura boolean NOT NULL DEFAULT TRUE,
    CONSTRAINT ck_gps_latitud CHECK (latitud    BETWEEN -90  AND  90),
    CONSTRAINT ck_gps_longitud CHECK (longitud   BETWEEN -180 AND 180),
    CONSTRAINT ck_gps_precision CHECK (precision_m >= 0),
    CONSTRAINT fk_gps_dispositivo FOREIGN KEY (id_dispositivo)
        REFERENCES dispositivo_iot(id_dispositivo)
        ON UPDATE CASCADE,
    CONSTRAINT fk_gps_paciente FOREIGN KEY (id_paciente)
        REFERENCES paciente(id_paciente)
        ON UPDATE CASCADE
);

CREATE INDEX idx_gps_paciente  ON evento_gps (id_paciente);
CREATE INDEX idx_gps_timestamp ON evento_gps (timestamp_evento DESC);

CREATE TABLE evento_nfc (
    id_evento_nfc BIGSERIAL primary key,
    id_dispositivo int NOT NULL,
    id_paciente int NOT NULL,
    id_zona int NOT NULL,
    tipo_evento varchar(20) NOT NULL,
    timestamp_evento TIMESTAMP NOT NULL DEFAULT NOW(),
    CONSTRAINT ck_nfc_tipo CHECK (tipo_evento IN ('Entrada','Salida','Interaccion')),
    CONSTRAINT fk_nfc_dispositivo FOREIGN KEY (id_dispositivo)
        REFERENCES dispositivo_iot(id_dispositivo)
        ON UPDATE CASCADE,
    CONSTRAINT fk_nfc_paciente FOREIGN KEY (id_paciente)
        REFERENCES paciente(id_paciente)
        ON UPDATE CASCADE,
    CONSTRAINT fk_nfc_zona FOREIGN KEY (id_zona)
        REFERENCES zona(id_zona)
        ON UPDATE CASCADE
);

CREATE INDEX idx_nfc_paciente  ON evento_nfc (id_paciente);
CREATE INDEX idx_nfc_zona      ON evento_nfc (id_zona);
CREATE INDEX idx_nfc_timestamp ON evento_nfc (timestamp_evento DESC);

CREATE TABLE evento_beacon (
    id_evento_beacon BIGSERIAL primary key,
    id_dispositivo int NOT NULL,
    id_paciente int NOT NULL,
    id_zona int NOT NULL,
    distancia_m DECIMAL(6,2),
    rssi int,
    timestamp_evento TIMESTAMP NOT NULL DEFAULT NOW(),
    CONSTRAINT ck_beacon_distancia CHECK (distancia_m >= 0),
    CONSTRAINT ck_beacon_rssi CHECK (rssi BETWEEN -120 AND 0),
    CONSTRAINT fk_beacon_dispositivo FOREIGN KEY (id_dispositivo)
        REFERENCES dispositivo_iot(id_dispositivo)
        ON UPDATE CASCADE,
    CONSTRAINT fk_beacon_paciente FOREIGN KEY (id_paciente)
        REFERENCES paciente(id_paciente)
        ON UPDATE CASCADE,
    CONSTRAINT fk_beacon_zona FOREIGN KEY (id_zona)
        REFERENCES zona(id_zona)
        ON UPDATE CASCADE
);

CREATE INDEX idx_beacon_paciente  ON evento_beacon (id_paciente);
CREATE INDEX idx_beacon_zona      ON evento_beacon (id_zona);
CREATE INDEX idx_beacon_timestamp ON evento_beacon (timestamp_evento DESC);

-- ============================================================
-- TABLA DE AUDITORÍA
-- ============================================================

CREATE TABLE log_auditoria (
    id_log  BIGSERIAL  primary key,
    id_usuario int NOT NULL,
    tabla_afectada varchar(80) NOT NULL,
    operacion varchar(10) NOT NULL,
    id_registro_afectado int,
    ip_origen varchar(45) NOT NULL,
    timestamp_operacion TIMESTAMP NOT NULL DEFAULT NOW(),
    CONSTRAINT ck_log_operacion CHECK (operacion IN ('INSERT','UPDATE','DELETE','SELECT')),
    CONSTRAINT fk_log_usuario FOREIGN KEY (id_usuario)
        REFERENCES profesional(id_profesional)
        ON UPDATE CASCADE
);

CREATE INDEX idx_log_usuario   ON log_auditoria (id_usuario);
CREATE INDEX idx_log_timestamp ON log_auditoria (timestamp_operacion DESC);
