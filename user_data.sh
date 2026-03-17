#!/bin/bash -xe
exec > >(tee /var/log/user-data.log | logger -t user-data -s 2>/dev/console) 2>&1

# Package manager (AL2=yum, AL2023=dnf)
if command -v dnf >/dev/null 2>&1; then
  PM=dnf
else
  PM=yum
fi

$PM update -y
$PM install -y python3 python3-pip

# venv best-effort
$PM install -y python3-venv || true

mkdir -p /opt/rdsapp

# dedicated user
id -u rdsapp >/dev/null 2>&1 || useradd --system --home /opt/rdsapp --shell /sbin/nologin rdsapp
chown -R rdsapp:rdsapp /opt/rdsapp

# venv
python3 -m venv /opt/rdsapp/venv || true
/opt/rdsapp/venv/bin/pip install --upgrade pip
/opt/rdsapp/venv/bin/pip install flask "PyMySQL[rsa]" boto3 watchtower

cat >/opt/rdsapp/app.py <<'PY'
import json
import os
import time
import logging
import boto3
import pymysql
from flask import Flask, request

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("rdsapp")

REGION = os.environ.get("AWS_REGION", "current")
SECRET_ID = os.environ.get("SECRET_ID", "lab/rds/mysql")

# Optional CloudWatch Logs via Watchtower (won't crash app if it fails)
try:
    import watchtower
    cw = watchtower.CloudWatchLogHandler(
        log_group_name="/aws/ec2/lab2-rds-app",
        stream_name=f"rdsapp-{int(time.time())}",
        send_interval=10,
        boto3_client=boto3.client("logs", region_name=REGION),
    )
    logger.addHandler(cw)
except Exception as e:
    logger.warning("Watchtower disabled: %s", e)

secrets = boto3.client("secretsmanager", region_name=REGION)

def get_db_creds():
    resp = secrets.get_secret_value(SecretId=SECRET_ID)
    return json.loads(resp["SecretString"])

def get_db_name(c):
    return c.get("db_name") or c.get("dbname") or "labdb"

def get_conn():
    c = get_db_creds()
    return pymysql.connect(
        host=c["host"],
        user=c["username"],
        password=c["password"],
        port=int(c.get("port", 3306)),
        database=get_db_name(c),
        autocommit=True,
    )

app = Flask(__name__)

@app.route("/")
def home():
    return """
    <h2>EC2 → RDS Notes App</h2>
    <p>GET /init</p>
    <p>GET /add?note=hello</p>
    <p>GET /list</p>
    """
@app.route("/api/public-feed")
def public_feed():
    from flask import make_response
    resp = make_response('{"items":["one","two","three"]}', 200)
    resp.headers["Content-Type"] = "application/json"
    resp.headers["Cache-Control"] = "public, max-age=60"
    return resp

@app.route("/static/example.txt")
def static_example():
    from flask import make_response
    resp = make_response("hello from static", 200)
    resp.headers["Cache-Control"] = "public, max-age=60"
    resp.headers["Content-Type"] = "text/plain"
    return resp

@app.route("/init")
def init_db():
    try:
        c = get_db_creds()
        db = get_db_name(c)

        conn = pymysql.connect(
            host=c["host"],
            user=c["username"],
            password=c["password"],
            port=int(c.get("port", 3306)),
            autocommit=True,
        )
        cur = conn.cursor()
        cur.execute(f"CREATE DATABASE IF NOT EXISTS `{db}`;")
        cur.execute(f"USE `{db}`;")
        cur.execute("""
            CREATE TABLE IF NOT EXISTS notes (
                id INT AUTO_INCREMENT PRIMARY KEY,
                note VARCHAR(255) NOT NULL
            );
        """)
        cur.close()
        conn.close()
        logger.info("Initialized DB=%s", db)
        return f"Initialized {db} + notes table."
    except Exception as e:
        logger.exception("init_db failed")
        return f"Error during initialization: {e}", 500

@app.route("/add", methods=["GET", "POST"])
def add_note():
    note = request.args.get("note", "").strip()
    if not note:
        return "Missing note param. Try: /add?note=hello", 400
    try:
        conn = get_conn()
        cur = conn.cursor()
        cur.execute("INSERT INTO notes(note) VALUES(%s);", (note,))
        cur.close()
        conn.close()
        return f"Inserted note: {note}"
    except Exception as e:
        logger.exception("add_note failed")
        return f"Error adding note: {e}", 500

@app.route("/list")
def list_notes():
    try:
        conn = get_conn()
        cur = conn.cursor()
        cur.execute("SELECT id, note FROM notes ORDER BY id DESC;")
        rows = cur.fetchall()
        cur.close()
        conn.close()
        out = "<h3>Notes</h3><ul>"
        for r in rows:
            out += f"<li>{r[0]}: {r[1]}</li>"
        out += "</ul>"
        return out
    except Exception as e:
        logger.exception("list_notes failed")
        return f"Error listing notes: {e}", 500

if __name__ == "__main__":
    logger.info("Starting Flask on :80")
    app.run(host="0.0.0.0", port=80)
PY

chown -R rdsapp:rdsapp /opt/rdsapp

cat >/etc/systemd/system/rdsapp.service <<'SERVICE'
[Unit]
Description=EC2 to RDS Notes App
After=network.target

[Service]
User=rdsapp
Group=rdsapp
WorkingDirectory=/opt/rdsapp
Environment=AWS_REGION=eu-west-2
Environment=SECRET_ID=lab/rds/mysql

# allow non-root bind to port 80
AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE

ExecStart=/opt/rdsapp/venv/bin/python /opt/rdsapp/app.py
Restart=always

[Install]
WantedBy=multi-user.target
SERVICE

systemctl daemon-reload
systemctl enable rdsapp
systemctl restart rdsapp