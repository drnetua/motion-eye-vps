#!/usr/bin/env python3
"""Run inside the motioneye container: log in as admin and viewer, check roles,
list cameras and their motion connection status. Prints JSON. Exit 0 always;
the caller asserts on the fields."""
import json, os, sys, urllib.request, urllib.error, http.cookiejar

BASE = "http://127.0.0.1:8765"
MOTION = "http://127.0.0.1:7999"


def session():
    return urllib.request.build_opener(urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()))


def call(op, path, data=None, method=None):
    body = json.dumps(data).encode() if data is not None else None
    req = urllib.request.Request(BASE + path, data=body, method=method,
                                 headers={"Content-Type": "application/json"} if body else {})
    try:
        with op.open(req, timeout=15) as r:
            raw = r.read().decode()
            try:
                return r.status, json.loads(raw)
            except ValueError:
                return r.status, None
    except urllib.error.HTTPError as e:
        return e.code, None
    except Exception as e:  # noqa: BLE001
        return 0, str(e)


def motion(path):
    try:
        with urllib.request.urlopen(MOTION + path, timeout=10) as r:
            return r.read().decode()
    except Exception as e:  # noqa: BLE001
        return "ERROR " + str(e)


out = {"admin": {}, "viewer": {}, "cameras": [], "wrong_password_status": None}
admin = session()
st, body = call(admin, "/login/", {"username": os.environ["ADMIN_USER"], "password": os.environ["ADMIN_PASS"]})
out["admin"]["login_status"] = st
out["admin"]["config_list_status"] = call(admin, "/config/list/")[0]
out["admin"]["main_get_status"] = call(admin, "/config/main/get/")[0]

viewer = session()
st, body = call(viewer, "/login/", {"username": os.environ["VIEWER_USER"], "password": os.environ["VIEWER_PASS"]})
out["viewer"]["login_status"] = st
out["viewer"]["user_type"] = (body or {}).get("user") if isinstance(body, dict) else None
out["viewer"]["config_list_status"] = call(viewer, "/config/list/")[0]
out["viewer"]["main_get_status"] = call(viewer, "/config/main/get/")[0]
out["viewer"]["main_set_status"] = call(viewer, "/config/main/set/", {}, "POST")[0]

out["wrong_password_status"] = call(session(), "/login/", {"username": os.environ["ADMIN_USER"], "password": "definitely-wrong-" + os.urandom(4).hex()})[0]

st, body = call(admin, "/config/list/")
cams = (body or {}).get("cameras", []) if isinstance(body, dict) else []
for c in cams:
    cid = c.get("id")
    conn = motion(f"/{cid}/detection/connection")
    status = motion(f"/{cid}/detection/status")
    out["cameras"].append({
        "id": cid,
        "name": c.get("name"),
        "enabled": c.get("enabled"),
        "connected": "Connection OK" in conn,
        "detection_active": "ACTIVE" in status,
        "connection_raw": " ".join(conn.split()),
    })
print(json.dumps(out))
