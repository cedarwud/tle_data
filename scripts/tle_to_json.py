#!/usr/bin/env python3
"""
Convert a 3-line TLE file to the Celestrak GP JSON format.

Usage: tle_to_json.py <input.tle> <output.json>

Output JSON matches the format from:
  https://celestrak.org/NORAD/elements/gp.php?GROUP=...&FORMAT=json
"""

import json
import sys
from datetime import datetime, timedelta


def parse_tle_exp(field: str) -> float:
    """
    Parse TLE assumed-decimal scientific notation: ±NNNNN±N
    e.g. ' 10679-2' → 0.10679 × 10^-2 = 0.0010679
         ' 00000+0' → 0.0
         '-31178-3' → -0.00031178
    """
    s = field.strip()
    if not s:
        return 0.0

    sign = -1.0 if s[0] == '-' else 1.0
    digits = s.lstrip('+-')

    if len(digits) < 7:
        return 0.0

    mantissa_digits = digits[:5]     # 5-digit mantissa
    exp_part = digits[5:]             # ±N exponent

    exp_sign = -1 if exp_part[0] == '-' else 1
    exp_val = int(exp_part[1:])

    mantissa = sign * float('0.' + mantissa_digits)
    return mantissa * (10 ** (exp_sign * exp_val))


def parse_intl_desig(raw: str) -> str:
    """
    Convert TLE international designator to COSPAR format.
    e.g. '19074B  ' → '2019-074B'
    """
    s = raw.strip()
    if not s:
        return ''
    year_2 = int(s[:2])
    year = 2000 + year_2 if year_2 < 57 else 1900 + year_2
    rest = s[2:].strip()
    return f"{year}-{rest}"


def parse_epoch(raw: str) -> str:
    """
    Convert TLE epoch (YYDDD.DDDDDDDD) to ISO 8601 with microseconds.
    e.g. '26085.28060152' → '2026-03-26T06:44:03.971328'
    """
    s = raw.strip()
    year_2 = int(s[:2])
    year = 2000 + year_2 if year_2 < 57 else 1900 + year_2
    day_decimal = float(s[2:])

    dt = datetime(year, 1, 1) + timedelta(days=day_decimal - 1)
    return dt.strftime('%Y-%m-%dT%H:%M:%S.%f')


def tle_file_to_json(tle_path: str) -> list:
    with open(tle_path, 'r') as f:
        lines = [l.rstrip('\n').rstrip('\r') for l in f]

    # Remove blank lines
    lines = [l for l in lines if l.strip()]

    results = []
    i = 0
    while i < len(lines):
        # Determine if this is a name line or a line-1
        if lines[i].startswith('1 ') or lines[i].startswith('1\t'):
            name = ''
            line1 = lines[i]
            line2 = lines[i + 1] if i + 1 < len(lines) else ''
            i += 2
        else:
            name = lines[i].strip()
            line1 = lines[i + 1] if i + 1 < len(lines) else ''
            line2 = lines[i + 2] if i + 2 < len(lines) else ''
            i += 3

        if not line1.startswith('1') or not line2.startswith('2'):
            continue

        # ── Line 1 ──────────────────────────────────────────────────────────
        norad_id         = int(line1[2:7])
        classification   = line1[7]
        object_id        = parse_intl_desig(line1[9:17])
        epoch            = parse_epoch(line1[18:32])
        mean_motion_dot  = float(line1[33:43])
        mean_motion_ddot = parse_tle_exp(line1[44:52])
        bstar            = parse_tle_exp(line1[53:61])
        ephemeris_type   = int(line1[62])
        element_set_no   = int(line1[64:68])

        # ── Line 2 ──────────────────────────────────────────────────────────
        inclination       = float(line2[8:16])
        ra_of_asc_node    = float(line2[17:25])
        eccentricity      = float('0.' + line2[26:33])
        arg_of_pericenter = float(line2[34:42])
        mean_anomaly      = float(line2[43:51])
        mean_motion       = float(line2[52:63])
        rev_at_epoch      = int(line2[63:68])

        results.append({
            'OBJECT_NAME':        name,
            'OBJECT_ID':          object_id,
            'EPOCH':              epoch,
            'MEAN_MOTION':        mean_motion,
            'ECCENTRICITY':       eccentricity,
            'INCLINATION':        inclination,
            'RA_OF_ASC_NODE':     ra_of_asc_node,
            'ARG_OF_PERICENTER':  arg_of_pericenter,
            'MEAN_ANOMALY':       mean_anomaly,
            'EPHEMERIS_TYPE':     ephemeris_type,
            'CLASSIFICATION_TYPE': classification,
            'NORAD_CAT_ID':       norad_id,
            'ELEMENT_SET_NO':     element_set_no,
            'REV_AT_EPOCH':       rev_at_epoch,
            'BSTAR':              bstar,
            'MEAN_MOTION_DOT':    mean_motion_dot,
            'MEAN_MOTION_DDOT':   mean_motion_ddot,
        })

    return results


def main():
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} <input.tle> <output.json>", file=sys.stderr)
        sys.exit(1)

    tle_path = sys.argv[1]
    json_path = sys.argv[2]

    data = tle_file_to_json(tle_path)

    if not data:
        print(f"Error: no TLE entries parsed from {tle_path}", file=sys.stderr)
        sys.exit(1)

    with open(json_path, 'w') as f:
        json.dump(data, f, separators=(',', ':'))

    print(f"Converted {len(data)} satellites → {json_path}")


if __name__ == '__main__':
    main()
