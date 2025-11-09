#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import time
import traceback
from typing import List

import pymysql         # pip install pymysql
import requests        # pip install requests

# =========================
# CONFIG — EDIT THESE ONLY
# =========================

# DB (MariaDB)
DB_HOST = "localhost"
DB_PORT = 3306
DB_USER = "dreamr_user"
DB_PASS = "M!ke&7@r425!"
DB_NAME = "dreamr"
DB_CHARSET = "utf8mb4"

TABLE = "dream"
ID_COL = "id"
IMAGE_COL = "image_file"
EXTRA_WHERE = ""             # e.g., 'AND hidden = 0'

# API
API_BASE = "https://dreamr-us-west-01.zentha.me"
IMAGE_ENDPOINT = "/api/image_generate"   # POST {"dream_id": <id>}
TIMEOUT_SECS = 90

# Optional cookie auth (leave EMAIL/PASSWORD empty if not needed)
LOGIN_ENDPOINT = "/api/login"
EMAIL = "mikekuriger@gmail.com"
PASSWORD = "Mrkamk2021#"

# Behavior
DRY_RUN = False
SLEEP_BETWEEN = 0.0   # seconds between calls

# =========================

def log(msg: str) -> None:
    print(msg, flush=True)

def connect_db():
    return pymysql.connect(
        host=DB_HOST,
        port=DB_PORT,
        user=DB_USER,
        password=DB_PASS,
        database=DB_NAME,
        charset=DB_CHARSET,
        cursorclass=pymysql.cursors.Cursor,
        autocommit=True,
    )

def fetch_missing_ids(conn) -> List[int]:
    where = f"{IMAGE_COL} IS NULL"
    if EXTRA_WHERE.strip():
        where += f" {EXTRA_WHERE.strip()}"
    sql = f"SELECT {ID_COL} FROM {TABLE} WHERE {where} ORDER BY {ID_COL} ASC"
    log(f"SQL: {sql}")
    ids: List[int] = []
    with conn.cursor() as cur:
        cur.execute(sql)
        for (row_id,) in cur.fetchall():
            ids.append(int(row_id))
    return ids

def login_session() -> requests.Session:
    s = requests.Session()
    url = f"{API_BASE.rstrip('/')}{LOGIN_ENDPOINT}"
    r = s.post(url, json={"email": EMAIL, "password": PASSWORD}, timeout=30)
    if r.status_code != 200:
        raise RuntimeError(f"Login failed: {r.status_code} {r.text[:200]}")
    print("Login OK (cookie session).", flush=True)
    return s

def trigger_image(session: requests.Session, dream_id: int) -> bool:
    url = f"{API_BASE.rstrip('/')}/api/image_generate"
    r = session.post(url, json={"dream_id": dream_id}, timeout=90)
    if 200 <= r.status_code < 300:
        try:
            body = r.json()
        except Exception:
            body = {}
        image_url = body.get("image_url") or body.get("imagePath") or body.get("image") or ""
        print(f"OK  id={dream_id}  status={r.status_code}  image={image_url or '<not in body>'}", flush=True)
        return True
    elif r.status_code == 202:
        print(f"ACCEPTED  id={dream_id}  status=202 (background render)", flush=True)
        return True
    else:
        print(f"ERR id={dream_id}  HTTP {r.status_code}  body={r.text[:300].replace(chr(10),' ')}", flush=True)
        return False

def main():
    log("Connecting to DB…")
    try:
        conn = connect_db()
    except Exception:
        log("DB connection failed:")
        traceback.print_exc()
        return

    try:
        ids = fetch_missing_ids(conn)
        if not ids:
            log("Nothing to do: no rows where image_file IS NULL.")
            return

        log(f"Found {len(ids)} dream(s) needing images: {ids}")

        if DRY_RUN:
            log("DRY_RUN=True — not calling the API.")
            return

        sess = login_session()
        ok = 0
        for did in ids:
            if trigger_image(sess, did):
                ok += 1
            if SLEEP_BETWEEN > 0:
                time.sleep(SLEEP_BETWEEN)

        log(f"Done. Triggered {ok}/{len(ids)} successfully.")
    finally:
        try:
            conn.close()
        except Exception:
            pass

if __name__ == "__main__":
    main()

