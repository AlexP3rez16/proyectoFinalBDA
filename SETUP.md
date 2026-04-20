# Setup Guide — proyectoFinalBDA (Windows)

---

## 1. Instalar PostgreSQL

Descarga e instala **PostgreSQL 16** para Windows:  
https://www.postgresql.org/download/windows/

- Puerto: **5432** (default, no cambiar)
- Anota la contraseña del superusuario `postgres` — la usas en el paso 2
- Instala **pgAdmin 4** si quieres interfaz gráfica (opcional)

Después de instalar, verifica en una terminal nueva:
```
psql --version
```
Si aparece `'psql' is not recognized...`, agrega al PATH de Windows:
```
C:\Program Files\PostgreSQL\16\bin
```
*(Panel de control → Variables de entorno → Path → Editar → Nueva)*

---

## 2. Abrir psql como Administrador

En Windows no existe `sudo`. El equivalente es abrir la terminal como Administrador:

**Opción A — SQL Shell (más fácil, no requiere PATH):**
1. Inicio → busca **"SQL Shell (psql)"** → ábrelo
2. Presiona Enter en cada prompt hasta llegar a `Password for user postgres:`
3. Escribe la contraseña de `postgres` que pusiste al instalar

**Opción B — Command Prompt como Administrador:**
1. Inicio → busca **"cmd"**
2. Clic derecho → **"Ejecutar como administrador"**
3. Luego ejecuta:
   ```
   psql -U postgres -p 5432
   ```

---

## 3. Crear Base de Datos, Usuario y Permisos

Una vez dentro del prompt `postgres=#`, pega **todo esto de una vez**:

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

> **Por qué tantos GRANT:**  
> `GRANT ALL ON DATABASE` solo da permiso de conexión.  
> Los stored procedures y triggers también necesitan permiso sobre el **schema public**  
> y sobre las tablas/secuencias que crean internamente.

---

## 4. Ejecutar los Scripts SQL

Abre una terminal (normal, no necesita ser administrador) en la carpeta `proyectoFinalBDA` y corre los 4 scripts **en este orden exacto**:

```
psql -U equipo5proyfin -d asilo_db -f DDL.sql
psql -U equipo5proyfin -d asilo_db -f PROCEDURES.sql
psql -U equipo5proyfin -d asilo_db -f VIEWS_TRIGGERS.sql
psql -U equipo5proyfin -d asilo_db -f SEED.sql
```

Contraseña cuando la pida: `123`

Si psql pide contraseña pero no abre prompt, agrega `-W`:
```
psql -U equipo5proyfin -d asilo_db -W -f DDL.sql
```

---

## 5. Instalar Dependencias Python

```
pip install flask psycopg2-binary werkzeug
```

---

## 6. Correr la Aplicación

```
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

Abre psql como Administrador (paso 2) y ejecuta:

```sql
DROP DATABASE IF EXISTS asilo_db;
DROP USER IF EXISTS equipo5proyfin;
```

Luego repite desde el paso 3.

---

## Solución de Problemas

| Problema | Solución |
|---|---|
| `psql` not recognized | Agrega `C:\Program Files\PostgreSQL\16\bin` al PATH y reinicia la terminal |
| `permission denied for schema public` | Volviste a correr los scripts sin hacer el paso 3 completo. Repite el paso 3 como admin |
| `ERROR: procedure already exists` | Ignóralo — todos los scripts usan `CREATE OR REPLACE`, es seguro re-ejecutarlos |
| `ERROR: duplicate key` en SEED.sql | Ya hay datos. Haz drop y recrea desde cero, o ignora si la app funciona |
| `could not connect to server` | PostgreSQL no está corriendo. Inicio → Servicios → `postgresql-x64-16` → Iniciar |
| `CALL sp_... does not exist` | Corriste los scripts en orden incorrecto. Borra la DB y repite desde el paso 4 |
