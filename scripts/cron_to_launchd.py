#!/usr/bin/env python3
"""cron_to_launchd.py — convert a 5-field cron expression to a macOS launchd plist.

Usage:
  cron_to_launchd.py <label> <program> <arg> <cron> <stdout-log> <stderr-log>

Prints a plist XML document to stdout. Used by relay.sh (relay_cron_create).

Design notes:
  - launchd StartCalendarInterval uses LOCAL time, NOT UTC. Cron hour is passed
    through verbatim — do NOT apply any timezone offset. (See SKILL.md R-24.)
  - "*/N" on minute/hour becomes StartInterval (seconds).
  - Comma/range lists become arrays of calendar dicts.
"""
import sys


def expand_field(field, lo, hi):
    """Expand '1-5' -> [1..5], '1,3' -> [1,3], '*'/'*/n' -> None."""
    if field == '*' or '/' in field:
        return None
    values = set()
    for part in field.split(','):
        if '-' in part:
            a, b = part.split('-')
            values.update(range(int(a), int(b) + 1))
        else:
            values.add(int(part))
    return sorted(values) or None


def parse_cron(expr):
    parts = expr.split()
    if len(parts) != 5:
        return None
    minute, hour, dom, month, dow = parts
    # Every N minutes / N hours -> interval
    if '/' in minute and hour == '*':
        return {'StartInterval': int(minute.split('/')[1]) * 60}
    if '/' in hour and minute.replace('*', '').replace('/', '') == '':
        return {'StartInterval': int(hour.split('/')[1]) * 3600}
    cal = {}
    for key, field, lo, hi in [('Minute', minute, 0, 59), ('Hour', hour, 0, 23),
                               ('Day', dom, 1, 31), ('Month', month, 1, 12),
                               ('Weekday', dow, 0, 6)]:
        v = expand_field(field, lo, hi)
        if v:
            cal[key] = v
    return {'StartCalendarInterval': cal} if cal else None


def gen_plist(label, program, arg, cron, logp, errp):
    parsed = parse_cron(cron)
    if not parsed:
        return None
    L = ['<?xml version="1.0" encoding="UTF-8"?>',
         '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" '
         '"http://www.apple.com/DTDs/PropertyList-1.0.dtd">',
         '<plist version="1.0"><dict>',
         f'  <key>Label</key><string>{label}</string>',
         '  <key>ProgramArguments</key><array>',
         f'    <string>{program}</string>',
         f'    <string>{arg}</string>',
         '  </array>',
         f'  <key>StandardOutPath</key><string>{logp}</string>',
         f'  <key>StandardErrorPath</key><string>{errp}</string>']
    if 'StartInterval' in parsed:
        L.append(f'  <key>StartInterval</key><integer>{parsed["StartInterval"]}</integer>')
    elif 'StartCalendarInterval' in parsed:
        cal = parsed['StartCalendarInterval']
        entries = [{}]
        for key in ('Minute', 'Hour', 'Day', 'Month', 'Weekday'):
            vals = cal.get(key)
            if not vals:
                continue
            if len(vals) > 1:
                entries = [{**e, key: v} for e in entries for v in vals]
            else:
                for e in entries:
                    e[key] = vals[0]
        if len(entries) == 1:
            L.append('  <key>StartCalendarInterval</key><dict>')
            for k, v in entries[0].items():
                L.append(f'    <key>{k}</key><integer>{v}</integer>')
            L.append('  </dict>')
        else:
            L.append('  <key>StartCalendarInterval</key><array>')
            for entry in entries:
                L.append('    <dict>')
                for k, v in entry.items():
                    L.append(f'      <key>{k}</key><integer>{v}</integer>')
                L.append('    </dict>')
            L.append('  </array>')
    L.append('</dict></plist>')
    return '\n'.join(L)


if __name__ == '__main__':
    if len(sys.argv) != 7:
        sys.stderr.write(
            'usage: cron_to_launchd.py <label> <program> <arg> <cron> <stdout-log> <stderr-log>\n')
        sys.exit(1)
    out = gen_plist(*sys.argv[1:7])
    if out is None:
        sys.stderr.write(f'error: could not parse cron expression: {sys.argv[4]}\n')
        sys.exit(1)
    print(out)
