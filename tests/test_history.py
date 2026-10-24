import hashlib
import sqlite3
import tempfile
import unittest
from pathlib import Path
from director.history.generator import History, write_sqlite

SEEDS = [0, 1, 7, 42, 2**63 - 1]


def digest(seed):
    with tempfile.TemporaryDirectory() as directory:
        path = Path(directory) / 'world.db'
        write_sqlite(History(seed).generate(), str(path))
        with sqlite3.connect(path) as db:
            rows = [db.execute(f'SELECT * FROM {t} ORDER BY rowid').fetchall()
                    for t in ('meta', 'entities', 'events', 'event_roles', 'hooks')]
        return hashlib.sha256(repr(rows).encode()).hexdigest()


class HistoryTests(unittest.TestCase):
    def test_seed_replay_is_deterministic(self):
        for seed in SEEDS:
            with self.subTest(seed=seed):
                self.assertEqual(digest(seed), digest(seed))
        self.assertNotEqual(digest(1), digest(2))

    def test_invariants(self):
        for seed in SEEDS:
            history = History(seed).generate()
            ids = {e['id']: e for e in history.events}
            with self.subTest(seed=seed):
                self.assertTrue(any(f.data['alive'] for f in history.of('faction')))
                for event in history.events:
                    if event['cause'] is not None:
                        self.assertLess(event['cause'], event['id'])
                        self.assertLessEqual(ids[event['cause']]['year'], event['year'])
                    for ref in event['roles'].values():
                        if ref is not None:
                            history.get(ref)
                for figure in history.of('figure'):
                    died = figure.data.get('died')
                    acts = [e['year'] for e in history.events
                            if e['roles'].get('figure') == figure.id and e['kind'] != 'death']
                    if died is not None:
                        self.assertFalse(figure.data['alive'])
                        self.assertTrue(all(year <= died for year in acts))
                for place in history.of('settlement'):
                    razed = [e['year'] for e in history.events if e['kind'] == 'raze'
                             and e['roles']['settlement'] == place.id]
                    if razed:
                        self.assertFalse(place.data['standing'])

    def test_causal_chains_and_hooks_exist(self):
        history = History(42).generate()
        self.assertTrue(any(e['cause'] for e in history.events))
        self.assertTrue(history.hooks())


if __name__ == '__main__':
    unittest.main()


class PresentTests(unittest.TestCase):
    def test_npcs_are_deterministic_and_grounded(self):
        from director.history.present import Present, write_npcs
        for seed in SEEDS:
            history = History(seed).generate()
            present = Present(history).build()
            again = Present(History(seed).generate()).build()
            ids = {e['id'] for e in history.events}
            with self.subTest(seed=seed):
                self.assertEqual(present.npcs, again.npcs)
                self.assertGreaterEqual(len(present.npcs), 3)
                for npc in present.npcs:
                    self.assertTrue(history.get(npc['faction']).data['alive'])
                    self.assertTrue(history.get(npc['settlement']).data['standing'])
                    self.assertTrue(set(npc['knows']) <= ids and npc['knows'])
                    self.assertTrue(npc['wants'])
                    self.assertIn(npc['name'], present.brief(npc))
                    for artifact in npc['carries']:
                        self.assertFalse(history.get(artifact).data['lost'])
        with tempfile.TemporaryDirectory() as directory:
            path = str(Path(directory) / 'world.db')
            write_sqlite(history, path)
            write_npcs(present, path)
            with sqlite3.connect(path) as db:
                self.assertEqual(db.execute('SELECT COUNT(*) FROM npcs').fetchone()[0],
                                 len(present.npcs))
