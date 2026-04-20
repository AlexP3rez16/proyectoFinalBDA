# Setup Guide — proyectoFinalBDA (macOS)

---

## 1. Instalar PostgreSQL

Instala PostgreSQL 16 con Homebrew:

```
brew install postgresql@16
brew services start postgresql@16
```

Agrega al PATH si no está ya (añade esta línea a `~/.zshrc` o `~/.bash_profile`):

```
export PATH="/opt/homebrew/opt/postgresql@16/bin:$PATH"
```

Recarga el shell:

```
source ~/.zshrc
```

Verifica:

```
psql --version
```

---

## 2. Crear Base de Datos, Usuario y Permisos

Abre psql como superusuario y pega **todo esto de una vez**:

```
psql postgres
```

```sql
CREATE DATABASE asilo_db;
CREATE USER equipo5proyfin WITH PASSWORD '123';
GRANT ALL PRIVILEGES ON DATABASE asilo_db TO equipo5proyfin;

\c asilo_db

GRANT ALL ON SCHEMA public TO equipo5proyfin;
ALTER SCHEMA public OWNER TO equipo5proyfin;

GRANT EXECUTE ON ALL PROCEDURES IN SCHEMA public TO equipo5proyfin;
GRANT EXECUTE ON ALL FUNCTIONS  IN SCHEMA public TO equipo5proyfin;

ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT ALL ON TABLES    TO equipo5proyfin;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT ALL ON SEQUENCES TO equipo5proyfin;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT EXECUTE ON PROCEDURES TO equipo5proyfin;

\q
```

---

## 3. Ejecutar los Scripts SQL

Desde la carpeta raíz del proyecto ejecuta:

```
psql -U equipo5proyfin -d asilo_db -f DDL.sql
psql -U equipo5proyfin -d asilo_db -f PROCEDURES.sql
psql -U equipo5proyfin -d asilo_db -f VIEWS_TRIGGERS.sql
psql -U equipo5proyfin -d asilo_db -f SEED.sql
```

Contraseña cuando la pida: `123`

---

## 4. Instalar Dependencias Python

Activa el entorno virtual e instala:

```
python3 -m venv .venv
source .venv/bin/activate
pip install flask psycopg2-binary werkzeug
```

---

## 5. Correr la Aplicación

Con el venv activo:

```
source .venv/bin/activate
python app.py
```

Abre en el navegador: **http://127.0.0.1:8080**

---

## Credenciales de Prueba

| Usuario   | Contraseña   | Portal        |
|-----------|--------------|---------------|
| admin     | admin123     | Administrador |
| jramirez  | terapeuta123 | Terapeuta     |
| ltorres   | terapeuta123 | Terapeuta     |
| mlopez    | cuidador123  | Cuidador      |
| psanchez  | cuidador123  | Cuidador      |
| agarcia   | cuidador123  | Cuidador      |

---

## Si necesitas empezar de cero

```
psql postgres
```

```sql
DROP DATABASE IF EXISTS asilo_db;
DROP USER IF EXISTS equipo5proyfin;
```

Luego repite desde el paso 2.

---

## Solución de Problemas

| Problema | Solución |
|---|---|
| `psql: command not found` | Agrega `/opt/homebrew/opt/postgresql@16/bin` al PATH y recarga el shell |
| `permission denied for schema public` | Repite el paso 2 completo |
| `ERROR: procedure already exists` | Ignóralo — todos los scripts usan `CREATE OR REPLACE` |
| `ERROR: duplicate key` en SEED.sql | Ya hay datos. Haz drop y recrea desde cero, o ignora si la app funciona |
| `could not connect to server` | Ejecuta `brew services start postgresql@16` |
| `CALL sp_... does not exist` | Corriste los scripts en orden incorrecto. Borra la DB y repite desde el paso 3 |
