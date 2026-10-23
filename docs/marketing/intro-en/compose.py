#!/usr/bin/env python3
"""Prepare the screenshot editor and import its exported English PNGs."""

import argparse
import base64
import html
import json
from pathlib import Path
import shutil
import struct
import xml.etree.ElementTree as ET
from zipfile import ZipFile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
OUTPUT = ROOT / 'docs/images/intro-en'
ASSET_PATH = 'screenshots/worktree-cleaner-en'
NAMES = ['01-repositories', '02-locations', '03-disk-usage',
         '04-cleanup-decision', '05-batch-cleanup', '06-sort-select']
CAPTURES = ['01-repositories.jpg', '02-locations.jpg', '03-disk-usage.jpg',
            '04-cleanup-decision.jpg', '05-batch-selected.jpg',
            '06-batch-confirmation.jpg', '07-sort-select.jpg']


def jpeg_size(data):
    """Read native JPEG dimensions without a third-party imaging dependency."""
    if data[:2] != b'\xff\xd8':
        raise ValueError('Expected a JPEG capture')
    offset = 2
    while offset < len(data):
        if data[offset] != 255:
            raise ValueError('Invalid JPEG marker')
        while data[offset] == 255:
            offset += 1
        marker = data[offset]
        offset += 1
        if marker in (0xD8, 0xD9) or 0xD0 <= marker <= 0xD7:
            continue
        length = int.from_bytes(data[offset:offset+2], 'big')
        if marker in (0xC0, 0xC1, 0xC2):
            height, width = struct.unpack('>HH', data[offset+3:offset+7])
            return width, height
        offset += length
    raise ValueError('JPEG dimensions not found')


def capture(name):
    data = (HERE / 'captures' / name).read_bytes()
    width, height = jpeg_size(data)
    return 'data:image/jpeg;base64,' + base64.b64encode(data).decode(), width, height


def text(x, y, value, size=34, color='#59677D', weight=500, anchor='start', mono=False):
    font = 'SFMono-Regular, Menlo, monospace' if mono else 'Arial, sans-serif'
    return (f'<text x="{x}" y="{y}" fill="{color}" font-size="{size}" '
            f'font-weight="{weight}" text-anchor="{anchor}" font-family="{font}">'
            f'{html.escape(value)}</text>')


def pixels(image, x, y, width, height, box):
    uri, sw, sh = image
    return (f'<svg x="{x}" y="{y}" width="{width}" height="{height}" '
            f'viewBox="{box}" preserveAspectRatio="xMinYMin slice" overflow="hidden">'
            f'<image href="{uri}" width="{sw}" height="{sh}"/></svg>')


def rect(x, y, width, height, radius=32, fill='#FFFFFF', stroke='#D5DFED', shadow=False):
    effect = ' filter="url(#window-shadow)"' if shadow else ''
    return (f'<rect x="{x}" y="{y}" width="{width}" height="{height}" rx="{radius}" '
            f'fill="{fill}" stroke="{stroke}" stroke-width="2"{effect}/>')


def window(x, y, width, height, title):
    return '\n'.join([
        rect(x, y, width, height, shadow=True),
        f'<circle cx="{x+40}" cy="{y+42}" r="9" fill="#EE817B"/>'
        f'<circle cx="{x+70}" cy="{y+42}" r="9" fill="#E8C478"/>'
        f'<circle cx="{x+100}" cy="{y+42}" r="9" fill="#94BA9C"/>',
        text(x+width/2, y+55, title, 32, '#34445C', anchor='middle'),
        f'<path d="M{x} {y+74}H{x+width}" stroke="#E1E7F0" stroke-width="1.5"/>',
    ])


def folder(x, y, scale=1):
    return f'''<g transform="translate({x} {y}) scale({scale})">
      <path d="M0 9Q0 0 9 0H34L47 13H87Q96 13 96 22V64Q96 73 87 73H9Q0 73 0 64Z" fill="#889BB6"/>
      <path d="M0 30Q0 22 9 22H87Q96 22 96 31V69Q96 78 87 78H9Q0 78 0 69Z" fill="#BDCCDE"/>
      <path d="M9 22H87Q96 22 96 31H0Q0 22 9 22Z" fill="#D9E2ED"/>
      <path d="M6 69H90" stroke="#8EA4BE" stroke-opacity=".35" stroke-width="4"/>
    </g>'''


def start(definitions=''):
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="2880" height="1800" viewBox="0 0 2880 1800">
    <defs>
      <radialGradient id="ambient" cx="73%" cy="61%" r="65%"><stop offset="0" stop-color="#DFE8F9"/><stop offset=".48" stop-color="#EEF2F9"/><stop offset="1" stop-color="#F6F7FA"/></radialGradient>
      <radialGradient id="stage" cx="48%" cy="27%" r="92%"><stop offset="0" stop-color="#FFFFFF"/><stop offset=".52" stop-color="#F1F5FC"/><stop offset="1" stop-color="#E6EDF8"/></radialGradient>
      <radialGradient id="dark-stage" cx="45%" cy="20%" r="90%"><stop offset="0" stop-color="#2B4265"/><stop offset=".5" stop-color="#243754"/><stop offset="1" stop-color="#192A43"/></radialGradient>
      <linearGradient id="bar"><stop offset="0" stop-color="#2969CB"/><stop offset=".5" stop-color="#427DD9"/><stop offset="1" stop-color="#6896DE"/></linearGradient>
      <filter id="window-shadow" x="-35%" y="-20%" width="180%" height="155%"><feDropShadow dx="0" dy="46" stdDeviation="45" flood-color="#334E78" flood-opacity=".15"/><feDropShadow dx="0" dy="5" stdDeviation="7" flood-color="#203D65" flood-opacity=".07"/></filter>
      {definitions}
    </defs>
    <rect width="2880" height="1800" fill="url(#ambient)"/>
    <circle cx="158" cy="112" r="8" fill="#185DCC"/>
    <path d="M148 172H2728" stroke="#D9E0EA" stroke-width="1.5"/>
    '''


def repositories(image):
    p = [start('<clipPath id="screen"><rect x="1314" y="443" width="892" height="1104" rx="18"/></clipPath>')]
    p += [rect(1092, 238, 1636, 1438, 48, 'url(#stage)', '#E0E7F1'),
          text(162, 998, 'Check each repo separately'), rect(150, 1040, 700, 88, 18, '#EAF0F7'),
          folder(182, 1061, .51), text(259, 1098, '~/repos', 38, '#425675', 600, mono=True),
          '<path d="M880 1084H1245M1229 1071L1245 1084L1229 1097" fill="none" stroke="#849EC2" stroke-width="3"/>',
          text(1035, 1048, 'Add folder', 32, '#435F85', anchor='middle')]
    for i, name in enumerate(['aurora-editor', 'nebula-api', 'pixel-dashboard']):
        x, y, angle = 170+i*22, 1180+i*150, [-3, -1, 1][i]
        p += [f'<g transform="rotate({angle} {x+320} {y+73})">', rect(x, y, 640, 146, 20, '#FBFCFE'),
              folder(x+25, y+22, .35), text(x+76, y+52, name, 30, '#42536E', mono=True),
              f'<path d="M{x+26} {y+72}H{x+614}" stroke="#E5EAF2" stroke-width="1.5"/>',
              text(x+28, y+118, '$ git worktree list', 35, '#435672', mono=True), '</g>']
    p += [text(1290, 310, 'All scanned repos', 34, '#235CB1', 600),
          window(1290, 352, 940, 1228, 'Worktree Cleaner'), '<g clip-path="url(#screen)">',
          pixels(image, 1314, 443, 892, 1104, '20 112 560 694'), '</g>',
          text(2338, 494, '9', 96, '#1B2C47', 600), text(2420, 488, 'repos', 40, '#344B6C'),
          text(2342, 550, 'From one folder', 30),
          '<circle cx="2165" cy="685" r="33" fill="none" stroke="#C8DDFF" stroke-width="3"/>',
          '<path d="M2198 685H2302" stroke="#4579CA" stroke-width="2.5"/>',
          text(2327, 677, '7 worktrees', 38, '#234F91'), text(2330, 729, 'Linked to this repo', 30), '</svg>']
    return '\n'.join(p)


def locations(image):
    p = [start('<clipPath id="screen"><rect x="1174" y="610" width="1502" height="909" rx="18"/></clipPath>'),
         rect(1092, 238, 1636, 1438, 48, 'url(#stage)', '#E0E7F1'), text(162, 998, 'Common locations')]
    for i, (label, path) in enumerate([
        ('Beside the main repo', '~/repos/aurora-docs'),
        ('Temporary folder', '/tmp/...'),
        ('Agent folder', '~/.codex/worktrees/...'),
    ]):
        y, target = 1030+i*200, 1026+i*203
        p += [rect(150, y, 700, 155, 20, '#FBFCFE'), folder(182, y+33, .53),
              text(260, y+59, label, 32, '#42536E'), text(260, y+115, path, 28, '#435672', mono=True),
              f'<path d="M872 {y+78}C996 {y+78} 990 {target} 1140 {target}M1126 {target-11}L1140 {target}L1126 {target+11}" fill="none" stroke="#93A9C8" stroke-width="2.5"/>']
    p += [text(1170, 321, 'Grouped by repository', 34, '#235CB1', 600),
          text(1170, 448, '3', 96, '#1B2C47', 600), text(1260, 440, 'locations', 40, '#344B6C'),
          text(1695, 430, 'Linked to the same repo', 34),
          window(1150, 520, 1550, 1020, 'aurora-editor'), '<g clip-path="url(#screen)">',
          pixels(image, 1174, 610, 1502, 887, '1904 185 830 490'), '</g>',
          text(2670, 1619, 'Main worktree + 3 linked worktrees', 30, anchor='end'), '</svg>']
    return '\n'.join(p)


def disk_usage(image):
    p = [start('<clipPath id="screen"><rect x="1174" y="908" width="1502" height="622" rx="18"/></clipPath>'),
         rect(148, 680, 886, 974, 40, '#FBFCFE', '#DCE4EF'),
         rect(1092, 680, 1636, 974, 40, 'url(#stage)', '#E0E7F1'),
         text(202, 776, 'Disk usage by worktree', 32, '#344B6C')]
    for i, (branch, amount, detail, ratio) in enumerate([
        ('agent/build', '402.7', 'Build output (.build)', 1),
        ('agent/preview', '134.2', 'Dependencies (node_modules)', 134.2/402.7),
        ('main', '16.8', 'Main worktree', 16.8/402.7),
    ]):
        y = 889+i*213
        p += [text(202, y, branch, 38, '#34445C', mono=True),
              text(929, y+4, amount, 64, '#155CCD' if i == 0 else '#596F94', 600, 'end'),
              text(980, y, 'MB', 28, anchor='end'), rect(202, y+41, 778, 35, 17.5, '#E8EDF5', '#E8EDF5'),
              rect(202, y+41, round(778*ratio, 2), 35, 17.5, 'url(#bar)' if i == 0 else '#A7BAD7', 'none'),
              text(202, y+129, detail, 30)]
    p += [text(1150, 776, 'Worktree details', 34, '#235CB1', 600),
          window(1150, 822, 1550, 728, 'aurora-editor'), '<g clip-path="url(#screen)">',
          pixels(image, 1174, 908, 1502, 622, '88 185 1040 431'), '</g>',
          '<rect x="2380" y="920" width="283" height="571" rx="12" fill="#155CCD" fill-opacity=".035" stroke="#8CAADF" stroke-width="2"/>',
          text(2670, 1601, 'Review the largest worktrees first.', 30, anchor='end'), '</svg>']
    return '\n'.join(p)


def cleanup_decision(image):
    p = [start('<clipPath id="screen"><rect x="1174" y="610" width="1502" height="907" rx="18"/></clipPath>'),
         rect(1092, 238, 1636, 1438, 48, 'url(#dark-stage)', '#314564'),
         text(1170, 321, 'LOCAL GIT STATUS', 34, '#DAE6FA', 600),
         text(1170, 444, 'Cleanup recommendations', 64, '#F3F7FE', 600)]
    states = [('Ready for cleanup', 'Clean · merged', '#216B4A', '#EDF6F0'),
              ('Review first', 'Clean · unmerged', '#8A580F', '#FAF3E8'),
              ('Keep for now', 'Uncommitted changes', '#A33541', '#FAEFF1')]
    for i, (label, detail, color, fill) in enumerate(states):
        y, target = 1020+i*200, 879+i*255
        p += [rect(150, y, 700, 155, 20, fill),
              f'<circle cx="198" cy="{y+48}" r="10" fill="{color}"/>',
              text(234, y+65, label, 44, color, 600), text(234, y+120, detail, 32, '#43536B'),
              f'<path d="M872 {y+78}C1004 {y+78} 990 {target} 1140 {target}M1126 {target-11}L1140 {target}L1126 {target+11}" fill="none" stroke="#91A7C8" stroke-width="2.5"/>']
    p += [window(1150, 520, 1550, 1020, 'aurora-editor · Recommendations'), '<g clip-path="url(#screen)">',
          pixels(image, 1174, 610, 1502, 141, '1468 185 660 62'),
          pixels(image, 1174, 751, 1502, 765, '1468 358 660 336'), '</g>',
          text(2670, 1619, 'Make sure no agent is still using the worktree.', 30, '#D8E3F4', anchor='end'), '</svg>']
    return '\n'.join(p)


def batch_cleanup(selected, confirmation):
    height = round(1240*confirmation[2]/confirmation[1])
    p = [start(f'''<clipPath id="selection"><rect x="224" y="914" width="1032" height="668" rx="12"/></clipPath>
        <clipPath id="confirmation"><rect x="1430" y="828" width="1240" height="{height}" rx="64"/></clipPath>'''),
         rect(148, 680, 2580, 974, 40, 'url(#stage)', '#E0E7F1')]
    for x, label, number in [(200, 'Select worktrees', '01'), (1430, 'Confirm cleanup', '02')]:
        p += [f'<circle cx="{x+24}" cy="765" r="24" fill="#DFE9F9"/>',
              text(x+24, 775, number, 27, '#235CB1', 600, 'middle'),
              text(x+70, 778, label, 38, '#344B6C', 600)]
    p += [window(200, 828, 1080, 770, 'aurora-editor'), '<g clip-path="url(#selection)">',
          pixels(selected, 224, 914, 1032, 668, '0 103 914 591'), '</g>',
          text(224, 1630, 'Uncommitted changes are protected.', 28),
          '<path d="M1310 1194H1395M1378 1177L1395 1194L1378 1211" fill="none" stroke="#8CA6CB" stroke-width="4"/>',
          rect(1430, 828, 1240, height, 64, shadow=True), '<g clip-path="url(#confirmation)">',
          pixels(confirmation, 1430, 828, 1240, height, f'0 0 {confirmation[1]} {confirmation[2]}'), '</g>', '</svg>']
    return '\n'.join(p)


def sort_select(image):
    p = [start('<clipPath id="screen"><rect x="1174" y="443" width="1502" height="1116" rx="18"/></clipPath>'),
         rect(1092, 238, 1636, 1438, 48, 'url(#stage)', '#E0E7F1'),
         text(1170, 321, 'SHIFT-CLICK TO SELECT A RANGE', 34, '#235CB1', 600),
         text(162, 1000, 'Sort by', 36, '#344B6C', 600)]
    for i, label in enumerate(['Last Commit', 'Disk Usage', 'Branch', 'Path']):
        x, y = 150+(i % 2)*360, 1040+(i // 2)*140
        p += [rect(x, y, 340, 108, 20, '#FBFCFE'),
              text(x+28, y+66, label, 34, '#42536E'),
              f'<path d="M{x+303} {y+31}V{y+74}M{x+293} {y+41}L{x+303} {y+31}L{x+313} {y+41}M{x+293} {y+64}L{x+303} {y+74}L{x+313} {y+64}" fill="none" stroke="#8AA2C5" stroke-width="2.5"/>']
    p += [text(162, 1390, 'Select a range', 36, '#344B6C', 600),
          rect(150, 1420, 220, 110, 20, '#FBFCFE'),
          text(260, 1491, 'Shift', 48, '#235CB1', 600, 'middle'),
          text(412, 1492, '+', 46, '#8499B6', anchor='middle'),
          rect(455, 1420, 300, 110, 20, '#FBFCFE'),
          text(605, 1491, 'click', 48, '#235CB1', 600, 'middle'),
          window(1150, 352, 1550, 1260, 'aurora-editor'), '<g clip-path="url(#screen)">',
          pixels(image, 1174, 443, 1502, 113.3, '0 103 1100 83'),
          pixels(image, 1174, 556.3, 1502, 84.7, '0 185 1100 62'),
          pixels(image, 1174, 641, 1502, 917.6, '0 358 1100 672'), '</g>',
          '<path d="M1140 719H1120V1483H1140" fill="none" stroke="#5F8DD2" stroke-width="3"/>',
          text(2670, 1652, 'Worktrees with uncommitted changes or locks are skipped.', 30, anchor='end'), '</svg>']
    return '\n'.join(p)


def prepare(editor):
    editor = editor.resolve()
    if not (editor / 'src/components/editor/screenshot-editor.tsx').is_file():
        raise ValueError('Use an app-store-screenshots editor template directory')
    destination = editor / 'public' / ASSET_PATH
    destination.mkdir(parents=True, exist_ok=True)
    shutil.copytree(HERE / 'captures', destination / 'captures', dirs_exist_ok=True)
    images = [capture(name) for name in CAPTURES]
    diagrams = [repositories(images[0]), locations(images[1]), disk_usage(images[2]),
                cleanup_decision(images[3]), batch_cleanup(images[4], images[5]),
                sort_select(images[6])]
    for name, diagram in zip(NAMES, diagrams):
        ET.fromstring(diagram)
        (destination / f'{name}.svg').write_text(diagram+'\n')
    project = json.loads((HERE / 'project.json').read_text())
    (editor / 'app-store-screenshots.json').write_text(json.dumps(project, indent=2)+'\n')
    print(f'Prepared {len(NAMES)} English slides in {editor}')


def import_export(bundle):
    results = {}
    with ZipFile(bundle) as archive:
        for index, name in enumerate(NAMES, 1):
            matches = [entry for entry in archive.namelist()
                       if '/2880x1800/en/' in entry and Path(entry).name.startswith(f'{index:02}-')
                       and entry.endswith('.png')]
            if len(matches) != 1:
                raise ValueError(f'Expected one 2880 x 1800 English image for slide {index}')
            data = archive.read(matches[0])
            if data[:8] != b'\x89PNG\r\n\x1a\n' or struct.unpack('>IIBB', data[16:26]) != (2880, 1800, 8, 2):
                raise ValueError(f'Slide {index} must be an opaque RGB PNG at 2880 x 1800')
            results[name] = data
    OUTPUT.mkdir(parents=True, exist_ok=True)
    for name, data in results.items():
        (OUTPUT / f'{name}.png').write_bytes(data)
    print(f'Imported {len(NAMES)} opaque RGB PNGs into {OUTPUT}')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    action = parser.add_mutually_exclusive_group(required=True)
    action.add_argument('--editor', type=Path, help='Prepare assets in a prebuilt editor')
    action.add_argument('--import-export', type=Path, help='Import the editor ZIP into README assets')
    args = parser.parse_args()
    if args.editor:
        prepare(args.editor)
    else:
        import_export(args.import_export)


if __name__ == '__main__':
    main()
