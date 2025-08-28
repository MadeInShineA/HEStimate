#!/usr/bin/env python3
"""
Upload CSV listings to Firestore (project: hestimate-438df) with:
- ownerUid fixed
- availability_start / availability_end as Firestore Timestamps
- nearest_hesso_id looked up from 'schools' collection by name
- type normalized to "room" or "entire_home"

Install:
  python -m pip install firebase-admin pandas python-dateutil
  # If your Python < 3.9:
  python -m pip install backports.zoneinfo
Run:
  python upload_csv_to_firestore.py \
    --csv /path/to/synthetic_valais_price.csv \
    --sa-key /path/to/hestimate-438df-service-account.json
"""
import argparse
import math
from datetime import datetime, time, timezone
from typing import Any, Dict, Optional

import pandas as pd
import firebase_admin
from firebase_admin import credentials, firestore

# zoneinfo for Europe/Zurich (Py3.9+), with fallback for older Pythons
try:
    from zoneinfo import ZoneInfo  # Python 3.9+
except Exception:
    try:
        from backports.zoneinfo import ZoneInfo  # pip install backports.zoneinfo
    except Exception:
        ZoneInfo = None  # will fall back to UTC midnight

PROJECT_ID = "hestimate-438df"
DEFAULT_COLLECTION = "listings"
BATCH_LIMIT = 475  # below Firestore 500-op limit
FIXED_OWNER_UID = "ZefYzK9W4OU8oqAmDcFWikUeZJ83"


def _to_bool(x) -> bool:
    if isinstance(x, bool):
        return x
    if x is None or (isinstance(x, float) and math.isnan(x)):
        return False
    s = str(x).strip().lower()
    return s in {"1", "true", "yes", "y", "t"}


def _to_int(x):
    if x is None or (isinstance(x, float) and math.isnan(x)):
        return None
    try:
        return int(x)
    except Exception:
        try:
            return int(float(x))
        except Exception:
            return None


def _to_float(x):
    if x is None or (isinstance(x, float) and math.isnan(x)):
        return None
    try:
        return float(x)
    except Exception:
        return None


def _norm_type(t: Any) -> Optional[str]:
    """
    Normalize to exactly two categories:
      - "room"         (private room in a shared place)
      - "entire_home"  (studio, apartment, whole place)
    Returns None if we can't tell.
    """
    if t is None or (isinstance(t, float) and math.isnan(t)):
        return None

    s = str(t).strip().lower()

    room_aliases = {
        "room", "single room", "single-room", "chambre", "private room", "colocation"
    }
    entire_aliases = {
        "entire_home", "entire home", "studio", "apartment", "flat", "appartement", "logement entier"
    }

    if s in room_aliases:
        return "room"
    if s in entire_aliases:
        return "entire_home"

    if any(k in s for k in ["studio", "apartment", "flat", "entire"]):
        return "entire_home"
    if "room" in s:
        return "room"

    return None


def _today_midnight_europe_zurich_dt() -> datetime:
    """
    Returns a timezone-aware datetime for 'today at 00:00:00' in Europe/Zurich.
    If zoneinfo is unavailable, falls back to UTC midnight.
    """
    if ZoneInfo is not None:
        tz = ZoneInfo("Europe/Zurich")
        now = datetime.now(tz)
        return datetime(now.year, now.month, now.day, 0, 0, 0, tzinfo=tz)
    # Fallback: UTC midnight (still a proper Timestamp, just not Zurich's local midnight)
    now_utc = datetime.now(timezone.utc)
    return datetime(now_utc.year, now_utc.month, now_utc.day, 0, 0, 0, tzinfo=timezone.utc)


def load_school_name_to_id(db: firestore.Client) -> Dict[str, str]:
    """
    Reads the 'schools' collection and returns a map: lowercased name -> doc_id.
    Assumes each school document has a 'name' field equal to the names used in the CSV.
    """
    mapping: Dict[str, str] = {}
    for snap in db.collection("schools").stream():
        data = snap.to_dict() or {}
        name = str(data.get("name", "")).strip()
        if name:
            mapping[name.lower()] = snap.id
    return mapping


def row_to_doc(
    r: pd.Series,
    *,
    created_dt_utc: datetime,
    availability_start_dt: datetime,
    school_name_to_id: Dict[str, str],
) -> Dict[str, Any]:
    # nearest_hesso_name -> nearest_hesso_id via 'schools' collection
    nearest_name = str(r.get("nearest_hesso_name", "")).strip() if pd.notna(r.get("nearest_hesso_name", None)) else ""
    nearest_id = school_name_to_id.get(nearest_name.lower()) if nearest_name else None

    return {
        # Fixed / defaults
        "ownerUid": FIXED_OWNER_UID,
        "address": "",
        "photos": [],

        # CSV-mapped fields
        "car_park": _to_bool(r.get("car_park")),
        "charges_incl": _to_bool(r.get("charges_incl")),
        "city": str(r.get("city", "")) if pd.notna(r.get("city", None)) else "",
        "createdAt": created_dt_utc,  # <-- Firestore Timestamp
        "dist_public_transport_km": _to_float(r.get("dist_public_transport_km")),
        "floor": _to_int(r.get("floor")),
        "is_furnish": _to_bool(r.get("is_furnished")),
        "latitude": _to_float(r.get("latitude")),
        "longitude": _to_float(r.get("longitude")),
        "npa": str(r.get("postal_code", "")) if pd.notna(r.get("postal_code", None)) else "",
        "num_rooms": _to_int(r.get("num_rooms")),
        "price": _to_int(r.get("price_chf")),
        "proxim_hesso_km": _to_float(r.get("proxim_hesso_km")),
        "surface": _to_float(r.get("surface_m2")),
        "type": _norm_type(r.get("type")),
        "wifi_incl": _to_bool(r.get("wifi_incl")),

        # Replace name with school doc id (or None if not found)
        "nearest_hesso_id": nearest_id,

        # Availability as Timestamps
        "availability_start": availability_start_dt,  # <-- Firestore Timestamp (Europe/Zurich midnight)
        "availability_end": None,                     # <-- Firestore null
    }


def upload_csv(csv_path: str, sa_key_path: str, collection: str):
    # Init Admin SDK
    cred = credentials.Certificate(sa_key_path)
    firebase_admin.initialize_app(cred, {"projectId": PROJECT_ID})
    db = firestore.client()

    # Preload schools
    school_name_to_id = load_school_name_to_id(db)

    # CSV + timestamps
    df = pd.read_csv(csv_path)
    created_dt_utc = datetime.now(timezone.utc)            # Timestamp (UTC "now")
    availability_start_dt = _today_midnight_europe_zurich_dt()  # Timestamp (Europe/Zurich midnight)

    # Batch write with RANDOM doc IDs (always new docs)
    batch = db.batch()
    ops = 0
    total = 0

    for _, r in df.iterrows():
        doc = row_to_doc(
            r,
            created_dt_utc=created_dt_utc,
            availability_start_dt=availability_start_dt,
            school_name_to_id=school_name_to_id,
        )
        ref = db.collection(collection).document()  # auto-ID
        batch.set(ref, doc, merge=True)
        ops += 1
        total += 1
        if ops >= BATCH_LIMIT:
            batch.commit()
            print(f"Committed {total}...")
            batch = db.batch()
            ops = 0

    if ops:
        batch.commit()

    print(f"Done. Wrote {total} documents to collection '{collection}' in project '{PROJECT_ID}'.")


def main():
    ap = argparse.ArgumentParser(description="Upload CSV listings to Firestore (hestimate-438df) with timestamps + school ID.")
    ap.add_argument("--csv", required=True, help="Path to the CSV (e.g., synthetic_valais_price.csv)")
    ap.add_argument("--sa-key", required=True, help="Path to service account JSON for hestimate-438df")
    ap.add_argument("--collection", default=DEFAULT_COLLECTION, help="Firestore collection name (default: listings)")

    args = ap.parse_args()
    upload_csv(csv_path=args.csv, sa_key_path=args.sa_key, collection=args.collection)


if __name__ == "__main__":
    main()
