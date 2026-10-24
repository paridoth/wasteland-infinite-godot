"""Deterministic post-collapse history, after Caves of Qud's "event first, rationalize after".

Events are rolled first; a cause is then found by searching earlier events that touch the
same actors (revenge, debt, rivalry) or, failing that, invented from the actor's ideology.
Output is plain data written to SQLite. No model calls and no executable content.

    python -m director.history.generator --seed 42 --out world.db --print
"""
from __future__ import annotations
import argparse
import json
import random
import sqlite3
from dataclasses import dataclass, field

SCHEMA_VERSION = 1
YEARS = 250

SYLLABLES = ['ash', 'bar', 'cor', 'dun', 'eck', 'fal', 'gra', 'hol', 'ira', 'jex', 'kel',
             'lor', 'mag', 'nox', 'ost', 'pell', 'quin', 'rad', 'sul', 'tor', 'urd', 'vex',
             'wen', 'yor', 'zan']
PLACE_SUFFIX = ['Crossing', 'Hollow', 'Spire', 'Wells', 'Depot', 'Crater', 'Yard', 'Dam',
                'Junction', 'Vault', 'Silo', 'Flats']
FACTION_FORM = {'technocrat': ['Brotherhood of {}', 'The {} Archive'],
                'zealot': ['Children of {}', 'Order of the {} Flame'],
                'mercantile': ['The {} Caravan Guild', 'The {} Compact'],
                'tribal': ['The {} Clans', 'Sons of {}'],
                'raider': ['{} Raiders', 'The {} Jackals'],
                'militia': ['{} Free Militia', 'The {} Wardens']}
COLLAPSES = ['the Fire Rain', 'the Long Winter', 'the Green Plague', 'the Silent Signal',
             'the Machine Revolt']
GRIEVANCES = {'war': 'the attack on {}', 'raze': 'the burning of {}',
              'betrayal': 'the treachery of {}', 'theft': 'the theft of {}',
              'schism': 'the rebellion at {}'}
IDEOLOGIES = {'technocrat': 'hoarding the old machines', 'zealot': 'purging the unclean',
              'mercantile': 'control of the trade roads', 'tribal': 'the old blood-oaths',
              'raider': 'plunder', 'militia': 'protecting the weak'}
RESOURCES = ['clean water', 'a working reactor', 'seed vaults', 'a rail yard',
             'salvage fields', 'a radio tower']
ARTIFACTS = ['power armor', 'a GECK', 'a holotape of launch codes', 'a medical autodoc',
             'a plasma lance', 'a navigation computer', 'a sealed seed canister']
TRAITS = ['cruel', 'cunning', 'pious', 'greedy', 'brave', 'paranoid', 'merciful', 'mad']
DISASTERS = ['a radstorm', 'a ghoul plague', 'a drought', 'a deathclaw migration',
             'a reactor fire']


@dataclass
class Entity:
    id: int
    kind: str
    name: str
    data: dict = field(default_factory=dict)


class History:
    def __init__(self, seed: int):
        self.seed = seed
        self.rng = random.Random(seed)
        self.entities: list[Entity] = []
        self.events: list[dict] = []
        self.year = 0

    # -- naming / creation ---------------------------------------------------------------
    def word(self, parts=2):
        return ''.join(self.rng.choice(SYLLABLES) for _ in range(parts)).capitalize()

    def add(self, kind, name, **data):
        entity = Entity(len(self.entities) + 1, kind, name, data)
        self.entities.append(entity)
        return entity

    def of(self, kind, **match):
        return [e for e in self.entities if e.kind == kind
                and all(e.data.get(k) == v for k, v in match.items())]

    def new_figure(self, faction, home):
        name = f'{self.word()} {self.rng.choice(["the", "of"])} {self.word(1).capitalize()}'
        return self.add('figure', name, faction=faction.id, home=home.id, born=self.year,
                        trait=self.rng.choice(TRAITS), alive=True)

    def new_faction(self, ideology=None):
        ideology = ideology or self.rng.choice(list(IDEOLOGIES))
        name = self.rng.choice(FACTION_FORM[ideology]).format(self.word())
        return self.add('faction', name, ideology=ideology,
                        strength=self.rng.randint(3, 8), alive=True)

    def new_settlement(self, owner):
        return self.add('settlement', f'{self.word()} {self.rng.choice(PLACE_SUFFIX)}',
                        owner=owner.id, resource=self.rng.choice(RESOURCES),
                        population=self.rng.randint(40, 400), standing=True)

    def get(self, entity_id):
        return self.entities[entity_id - 1]

    # -- event log -----------------------------------------------------------------------
    def record(self, kind, text, roles, cause=None):
        event = {'id': len(self.events) + 1, 'year': self.year, 'kind': kind, 'text': text,
                 'roles': roles, 'cause': cause}
        self.events.append(event)
        return event

    def grievance(self, aggressor, victim):
        """Rationalize after the fact: the latest event where victim's side wronged aggressor."""
        for event in reversed(self.events):
            roles = event['roles']
            if event['kind'] in GRIEVANCES \
                    and roles.get('aggressor') == victim.id and roles.get('victim') == aggressor.id:
                return event
        return None

    def motive(self, aggressor, victim):
        past = self.grievance(aggressor, victim)
        if past:
            roles = past['roles']
            subject = roles.get('settlement') or roles.get('artifact') or roles.get('figure')
            what = GRIEVANCES[past['kind']].format(self.get(subject).name)
            return f'avenging {what} in year {past["year"]}', past['id']
        return f'driven by {IDEOLOGIES[aggressor.data["ideology"]]}', None

    # -- simulation ----------------------------------------------------------------------
    def generate(self, years=YEARS):
        collapse = self.rng.choice(COLLAPSES)
        self.record('collapse', f'The old world ended in {collapse}.', {})
        for _ in range(self.rng.randint(3, 5)):
            faction = self.new_faction()
            home = self.new_settlement(faction)
            founder = self.new_figure(faction, home)
            self.record('founding', f'{founder.name} gathered survivors at {home.name}, '
                        f'founding {faction.name}.',
                        {'figure': founder.id, 'faction': faction.id, 'settlement': home.id})
        for self.year in range(1, years + 1):
            for _ in range(self.rng.choices([0, 1, 2], [5, 4, 1])[0]):
                self.rng.choice([self.war, self.war, self.rise, self.rise, self.found,
                                 self.discovery, self.theft, self.betrayal, self.disaster,
                                 self.death, self.schism])()
            if len(self.living('faction')) < 3 and self.rng.random() < 0.15:
                self.arrival()
            for figure in self.living('figure'):
                if self.year - figure.data['born'] > 50 and self.rng.random() < 0.08:
                    self.kill(figure, 'died of old age')
        return self

    def living(self, kind, **match):
        key = {'figure': 'alive', 'faction': 'alive', 'settlement': 'standing'}[kind]
        return [e for e in self.of(kind, **match) if e.data[key]]

    def active(self):
        """Living figures whose faction still exists; survivors of a fallen faction only age."""
        return [f for f in self.living('figure') if self.get(f.data['faction']).data['alive']]

    def leader(self, faction):
        members = self.living('figure', faction=faction.id)
        return min(members, key=lambda f: f.data['born']) if members else None

    def war(self):
        factions = self.living('faction')
        if len(factions) < 2:
            return
        attacker, defender = self.rng.sample(factions, 2)
        targets = self.living('settlement', owner=defender.id)
        if not targets:
            return
        target = self.rng.choice(targets)
        why, cause = self.motive(attacker, defender)
        roles = {'aggressor': attacker.id, 'victim': defender.id, 'settlement': target.id}
        if attacker.data['strength'] + self.rng.randint(0, 6) > defender.data['strength'] + 3:
            if attacker.data['ideology'] in ('raider', 'zealot') and self.rng.random() < 0.5:
                target.data['standing'] = False
                text = f'{attacker.name}, {why}, razed {target.name} and scattered {defender.name}.'
                self.record('raze', text, roles, cause)
            else:
                target.data['owner'] = attacker.id
                attacker.data['strength'] += 1
                self.record('war', f'{attacker.name}, {why}, seized {target.name} from '
                            f'{defender.name}.', roles, cause)
            defender.data['strength'] -= 1
            for victim in self.living('figure', home=target.id):
                if self.rng.random() < 0.3:
                    self.kill(victim, f'fell defending {target.name}')
        else:
            attacker.data['strength'] -= 1
            self.record('war', f'{attacker.name}, {why}, marched on {target.name} but was '
                        f'thrown back by {defender.name}.', roles, cause)
        self.collapse_check(defender)
        self.collapse_check(attacker)

    def collapse_check(self, faction):
        if faction.data['alive'] and (faction.data['strength'] <= 0
                                      or not self.living('settlement', owner=faction.id)):
            faction.data['alive'] = False
            for artifact in self.of('artifact', faction=faction.id, lost=False):
                artifact.data['lost'] = True
            self.record('fall', f'{faction.name} was broken and passed into legend.',
                        {'faction': faction.id})

    def arrival(self):
        faction = self.new_faction()
        home = self.new_settlement(faction)
        leader = self.new_figure(faction, home)
        origin = self.rng.choice(['the east', 'the irradiated south', 'a buried vault',
                                  'the dead coast', 'across the salt flats'])
        self.record('arrival', f'{faction.name} came out of {origin} under {leader.name} '
                    f'and claimed {home.name}.',
                    {'figure': leader.id, 'faction': faction.id, 'settlement': home.id})

    def rise(self):
        settlements = [s for s in self.living('settlement')
                       if self.get(s.data['owner']).data['alive']]
        if settlements:
            home = self.rng.choice(settlements)
            faction = self.get(home.data['owner'])
            figure = self.new_figure(faction, home)
            self.record('rise', f'{figure.name}, a {figure.data["trait"]} soul, rose to '
                        f'prominence in {home.name}.',
                        {'figure': figure.id, 'faction': faction.id, 'settlement': home.id})

    def found(self):
        factions = self.living('faction')
        if factions:
            faction = self.rng.choice(factions)
            founder = self.leader(faction)
            home = self.new_settlement(faction)
            who = founder.name if founder else f'Settlers of {faction.name}'
            self.record('founding', f'{who} founded {home.name} near {home.data["resource"]}.',
                        {'figure': founder.id if founder else None, 'faction': faction.id,
                         'settlement': home.id})

    def discovery(self):
        figures = self.active()
        if figures:
            finder = self.rng.choice(figures)
            found = self.rng.choice(ARTIFACTS)
            name = f"{finder.name.split()[0]}'s {found.removeprefix('a ')}"
            artifact = self.add('artifact', name, holder=finder.id,
                                faction=finder.data['faction'], lost=False)
            self.get(finder.data['faction']).data['strength'] += 1
            self.record('discovery', f'{finder.name} unearthed {found} from a sealed pre-war '
                        f'ruin; it became known as {artifact.name}.', {'figure': finder.id, 'artifact': artifact.id})

    def theft(self):
        held = [a for a in self.of('artifact', lost=False)]
        thieves = self.active()
        if not held or not thieves:
            return
        artifact = self.rng.choice(held)
        thief = self.rng.choice(thieves)
        if thief.data['faction'] == artifact.data['faction']:
            return
        victim = self.get(artifact.data['faction'])
        if self.rng.random() < 0.4:
            artifact.data['lost'] = True
            self.record('loss', f'{thief.name} tried to steal {artifact.name} from {victim.name}'
                        f', but it was lost in the wastes.',
                        {'figure': thief.id, 'artifact': artifact.id})
            return
        artifact.data.update(holder=thief.id, faction=thief.data['faction'])
        self.record('theft', f'{thief.name} stole {artifact.name} from {victim.name}.',
                    {'figure': thief.id, 'artifact': artifact.id, 'victim': victim.id,
                     'aggressor': thief.data['faction']})

    def betrayal(self):
        figures, factions = self.active(), self.living('faction')
        if not figures or len(factions) < 2:
            return
        traitor = self.rng.choice(figures)
        old = self.get(traitor.data['faction'])
        new = self.rng.choice([f for f in factions if f.id != old.id])
        homes = self.living('settlement', owner=new.id)
        if not homes:
            return
        traitor.data.update(faction=new.id, home=self.rng.choice(homes).id)
        self.record('betrayal', f'{traitor.name} betrayed {old.name} and sold their secrets to '
                    f'{new.name}.', {'figure': traitor.id, 'victim': old.id, 'aggressor': new.id})

    def disaster(self):
        settlements = self.living('settlement')
        if settlements:
            place = self.rng.choice(settlements)
            what = self.rng.choice(DISASTERS)
            place.data['population'] = max(5, place.data['population'] // 2)
            self.record('disaster', f'{what.capitalize()} struck {place.name}; half its people '
                        f'perished.', {'settlement': place.id})

    def death(self):
        old = [f for f in self.living('figure') if self.year - f.data['born'] > 30]
        if old:
            self.kill(self.rng.choice(old), self.rng.choice(
                ['died of old age', 'vanished into the Glow', 'was poisoned at a feast',
                 'was slain in a duel']))

    def kill(self, figure, how):
        figure.data.update(alive=False, died=self.year)
        for artifact in self.of('artifact', holder=figure.id, lost=False):
            if self.rng.random() < 0.5:
                artifact.data['lost'] = True
        self.record('death', f'{figure.name} {how}.', {'figure': figure.id})

    def schism(self):
        figures = [f for f in self.active() if f.data['trait'] in ('mad', 'paranoid',
                                                                     'cunning', 'pious')]
        if not figures:
            return
        rebel = self.rng.choice(figures)
        old = self.get(rebel.data['faction'])
        if old.data['strength'] < 3:
            return
        home = self.get(rebel.data['home'])
        if not home.data['standing'] or home.data['owner'] != old.id:
            return
        new = self.new_faction()
        old.data['strength'] -= 2
        new.data['strength'] = 2
        home.data['owner'] = new.id
        rebel.data['faction'] = new.id
        self.record('schism', f'{rebel.name} broke from {old.name}, declaring {home.name} the '
                    f'seat of {new.name}.', {'figure': rebel.id, 'aggressor': new.id,
                                             'victim': old.id, 'settlement': home.id})

    # -- present-day quest hooks ---------------------------------------------------------
    def hooks(self):
        hooks = [{'kind': 'lost_artifact', 'artifact': a.id,
                  'text': f'{a.name} was lost; its trail ends in the wastes.'}
                 for a in self.of('artifact', lost=True)]
        alive = {f.id for f in self.living('faction')}
        for event in self.events:
            r = event['roles']
            if r.get('aggressor') in alive and r.get('victim') in alive and not any(
                    e['cause'] == event['id'] for e in self.events):
                hooks.append({'kind': 'unavenged', 'event': event['id'],
                              'text': f'Unavenged (year {event["year"]}): {event["text"]}'})
        return hooks


def write_sqlite(history: History, path: str):
    db = sqlite3.connect(path)
    db.executescript('''
        DROP TABLE IF EXISTS meta; DROP TABLE IF EXISTS entities;
        DROP TABLE IF EXISTS events; DROP TABLE IF EXISTS event_roles; DROP TABLE IF EXISTS hooks;
        CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT);
        CREATE TABLE entities (id INTEGER PRIMARY KEY, kind TEXT, name TEXT, data TEXT);
        CREATE TABLE events (id INTEGER PRIMARY KEY, year INTEGER, kind TEXT, text TEXT,
                             cause INTEGER REFERENCES events(id));
        CREATE TABLE event_roles (event INTEGER REFERENCES events(id), role TEXT,
                                  entity INTEGER REFERENCES entities(id));
        CREATE TABLE hooks (id INTEGER PRIMARY KEY, kind TEXT, data TEXT);
    ''')
    db.executemany('INSERT INTO meta VALUES (?, ?)',
                   [('schema_version', str(SCHEMA_VERSION)), ('seed', str(history.seed))])
    db.executemany('INSERT INTO entities VALUES (?, ?, ?, ?)',
                   [(e.id, e.kind, e.name, json.dumps(e.data, sort_keys=True))
                    for e in history.entities])
    db.executemany('INSERT INTO events VALUES (?, ?, ?, ?, ?)',
                   [(e['id'], e['year'], e['kind'], e['text'], e['cause'])
                    for e in history.events])
    db.executemany('INSERT INTO event_roles VALUES (?, ?, ?)',
                   [(e['id'], role, ref) for e in history.events
                    for role, ref in e['roles'].items() if ref is not None])
    db.executemany('INSERT INTO hooks (kind, data) VALUES (?, ?)',
                   [(h['kind'], json.dumps(h, sort_keys=True)) for h in history.hooks()])
    db.commit()
    db.close()


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument('--seed', type=int, required=True)
    parser.add_argument('--years', type=int, default=YEARS)
    parser.add_argument('--out', help='SQLite path to write')
    parser.add_argument('--print', action='store_true', help='print the chronicle')
    args = parser.parse_args(argv)
    history = History(args.seed).generate(args.years)
    if args.out:
        write_sqlite(history, args.out)
    if args.print or not args.out:
        for event in history.events:
            print(f'{event["year"]:>4}  {event["text"]}')
        print('\nQuest hooks:')
        for hook in history.hooks():
            print(f'  - {hook["text"]}')


if __name__ == '__main__':
    main()
