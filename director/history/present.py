"""Present-day NPC briefs derived from a generated history.

Each brief is plain data an NPC agent can be grounded in: identity, ancestry, what the
character plausibly knows, who they resent, what they want and what they carry. Townsfolk
use their own seeded stream so adding them never changes the history itself.

    python -m director.history.present --seed 42 --out world.db --npc 3
"""
from __future__ import annotations
import argparse
import json
import random

from director.history.generator import IDEOLOGIES, History, write_sqlite

ADULT_AGE = 20
KNOWLEDGE_LIMIT = 12
FAMOUS = ('raze', 'fall', 'schism', 'arrival')
DRAMATIC = FAMOUS + ('war', 'theft', 'betrayal', 'discovery', 'death', 'loss')
ROLES = {'technocrat': ['scribe', 'mechanic', 'archivist'],
         'zealot': ['preacher', 'inquisitor', 'pilgrim'],
         'mercantile': ['trader', 'caravan master', 'moneylender'],
         'tribal': ['elder', 'hunter', 'shaman'],
         'raider': ['enforcer', 'fence', 'slaver'],
         'militia': ['sergeant', 'medic', 'scout']}
COMMON_ROLES = ['bartender', 'doctor', 'scavenger', 'farmer', 'guard captain', 'drifter']
WANTS = {'technocrat': 'to recover pre-war technology', 'zealot': 'to see the unclean purged',
         'mercantile': 'to profit from the trade roads', 'tribal': 'to honor the old oaths',
         'raider': 'to take what others hoard', 'militia': 'to keep their people safe'}


class Present:
    def __init__(self, history: History):
        self.h = history
        self.now = history.year
        self.rng = random.Random(f'{history.seed}:present')
        self.npcs: list[dict] = []

    def build(self):
        for figure in self.h.active():
            self.add(figure.name, 'leader' if self.h.leader(self.h.get(figure.data['faction']))
                     is figure else 'notable', figure.data['faction'], figure.data['home'],
                     figure.data['trait'], ADULT_AGE + self.now - figure.data['born'], figure.id)
        for town in self.h.living('settlement'):
            faction = self.h.get(town.data['owner'])
            if not faction.data['alive']:
                continue
            pool = ROLES[faction.data['ideology']] + COMMON_ROLES
            for role in self.rng.sample(pool, self.rng.randint(3, 5)):
                self.add(f'{self.h.word()} {self.h.word(1)}', role, faction.id, town.id,
                         self.rng.choice(['cruel', 'cunning', 'pious', 'greedy', 'brave',
                                          'paranoid', 'merciful', 'mad', 'weary', 'kind']),
                         self.rng.randint(16, 70), None)
        return self

    def add(self, name, role, faction_id, home_id, trait, age, figure_id):
        faction, home = self.h.get(faction_id), self.h.get(home_id)
        ancestor = None
        if figure_id is None:
            dead = [f for f in self.h.of('figure', home=home_id, alive=False)]
            if dead and self.rng.random() < 0.5:
                ancestor = self.rng.choice(dead).id
        npc = {'id': len(self.npcs) + 1, 'name': name, 'role': role, 'figure': figure_id,
               'faction': faction_id, 'settlement': home_id, 'trait': trait, 'age': age,
               'ancestor': ancestor}
        npc['deeds'] = [e['id'] for e in self.h.events if figure_id
                        and figure_id in e['roles'].values() and e['roles'].get('figure') == figure_id]
        npc['knows'] = self.knowledge(npc)
        npc['grudges'] = self.grudges(faction)
        npc['wants'] = self.wants(npc, faction, home)
        npc['carries'] = [a.id for a in self.h.of('artifact', lost=False)
                          if a.data['holder'] == figure_id
                          or (role == 'leader' and a.data['faction'] == faction_id
                              and not self.h.get(a.data['holder']).data['alive'])]
        self.npcs.append(npc)

    def knowledge(self, npc):
        """The collapse, the NPC's own and ancestral past, then local and factional drama."""
        born = self.now - npc['age']
        personal = {npc['ancestor'], npc['figure']} - {None}
        known = []
        for e in self.h.events:
            refs = set(e['roles'].values())
            if e['kind'] == 'collapse' or personal & refs:
                known.append((0, e['id']))
            elif e['year'] >= born and npc['settlement'] in refs:
                known.append((1, e['id']))
            elif e['year'] >= born and npc['faction'] in refs and e['kind'] in DRAMATIC:
                known.append((2, e['id']))
            elif e['kind'] in FAMOUS and self.now - e['year'] < 60:
                known.append((3, e['id']))
        return sorted(i for _, i in sorted(known)[:KNOWLEDGE_LIMIT])

    def grudges(self, faction):
        result = []
        for other in self.h.living('faction'):
            if other.id != faction.id:
                past = self.h.grievance(faction, other)
                if past:
                    result.append({'faction': other.id, 'event': past['id']})
        return result

    def wants(self, npc, faction, home):
        wants = [WANTS[faction.data['ideology']]]
        lost = [a for a in self.h.of('artifact', lost=True) if a.data['faction'] == faction.id]
        if lost:
            wants.append(f'to recover {self.rng.choice(lost).name}')
        if npc['grudges']:
            wants.append(f'to see {self.h.get(npc["grudges"][-1]["faction"]).name} pay')
        recent = [e for e in self.h.events if e['kind'] == 'disaster'
                  and e['roles'].get('settlement') == home.id and self.now - e['year'] < 20]
        if recent:
            wants.append(f'to rebuild {home.name}')
        return wants

    def brief(self, npc):
        """Readable grounding text for one NPC (data only; the agent prompt lives elsewhere)."""
        get, ev = self.h.get, {e['id']: e for e in self.h.events}
        lines = [f'{npc["name"]}, {npc["age"]}, {npc["trait"]} {npc["role"]} of '
                 f'{get(npc["faction"]).name} ({IDEOLOGIES[get(npc["faction"]).data["ideology"]]}),'
                 f' living in {get(npc["settlement"]).name}. Year {self.now} after the collapse.']
        if npc['ancestor']:
            lines.append(f'Descended from {get(npc["ancestor"]).name}.')
        if npc['deeds']:
            lines.append('Deeds: ' + ' '.join(f'({ev[i]["year"]}) {ev[i]["text"]}'
                                              for i in npc['deeds'][-5:]))
        lines.append('Knows: ' + ' '.join(f'({ev[i]["year"]}) {ev[i]["text"]}'
                                          for i in npc['knows']))
        for grudge in npc['grudges']:
            lines.append(f'Resents {get(grudge["faction"]).name}: {ev[grudge["event"]]["text"]}')
        lines.append('Wants: ' + '; '.join(npc['wants']) + '.')
        if npc['carries']:
            lines.append('Carries: ' + ', '.join(get(a).name for a in npc['carries']) + '.')
        return '\n'.join(lines)


def write_npcs(present: Present, path: str):
    import sqlite3
    with sqlite3.connect(path) as db:
        db.executescript('DROP TABLE IF EXISTS npcs; CREATE TABLE npcs (id INTEGER PRIMARY KEY,'
                         ' settlement INTEGER REFERENCES entities(id), name TEXT, data TEXT);')
        db.executemany('INSERT INTO npcs VALUES (?, ?, ?, ?)',
                       [(n['id'], n['settlement'], n['name'], json.dumps(n, sort_keys=True))
                        for n in present.npcs])


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument('--seed', type=int, required=True)
    parser.add_argument('--out', help='SQLite path to write (history + npcs)')
    parser.add_argument('--npc', type=int, help='print the brief for one NPC id')
    args = parser.parse_args(argv)
    history = History(args.seed).generate()
    present = Present(history).build()
    if args.out:
        write_sqlite(history, args.out)
        write_npcs(present, args.out)
    if args.npc:
        print(present.brief(present.npcs[args.npc - 1]))
    else:
        for npc in present.npcs:
            print(f'{npc["id"]:>3}  {npc["name"]:<22} {npc["role"]:<15} '
                  f'{history.get(npc["settlement"]).name}')


if __name__ == '__main__':
    main()
