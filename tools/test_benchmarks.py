"""Comprueba entradas, límites de medición y detección de trazas incorrectas."""
import copy
import tempfile
import unittest
from pathlib import Path

from asm import assemble, parse
from bench_data import (ROOT, PATTERNS, SIZES, ARRAY_BASE, TABLE_BASE, contents,
                        expected_transactions, generate, line_order, metadata, validate)
from mem_format import read_words
from metricas import verify_trace, verify_store_counts, verify_memory_payloads, write_csv, format_summary


class BenchmarkTests(unittest.TestCase):
    def test_summary_only_pairs_equal_memory_and_passes(self):
        base = dict(programa='secuencial', tamano_kib=1, vueltas=4,
                    pausa_memoria=20, ipc=1.0)
        direct = dict(base, cache=0, mem_div=4, ciclos=100)
        same = dict(base, cache=1, mem_div=4, ciclos=25)
        other_memory = dict(base, cache=1, mem_div=5, ciclos=10)
        other_passes = dict(base, cache=1, mem_div=4, vueltas=2, ciclos=10)
        paired = format_summary([direct, same])
        self.assertIn('4.00x', paired)
        self.assertNotIn('No medido', paired)
        self.assertIn('53 ciclos nominales', paired)
        for unmatched in (other_memory, other_passes):
            result = format_summary([direct, unmatched])
            self.assertIn('No medido', result)
            self.assertIn('No calculable', result)
            self.assertNotIn('10.00x', result)

    def test_memory_regions_and_results(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            generate(root)
            generate(root, check=True)
            for size in SIZES:
                words = size * 256
                for pattern in PATTERNS:
                    data, expected = contents(pattern, size, 4)
                    (root/'input.mem').write_text(data)
                    (root/'expected.mem').write_text(expected)
                    inputs = read_words(root/'input.mem')
                    outputs = read_words(root/'expected.mem')
                    self.assertTrue(all(0 <= address < 16384 for address in inputs))
                    self.assertEqual(inputs[ARRAY_BASE//4], 1)
                    self.assertEqual(inputs[ARRAY_BASE//4+words-1], words)
                    self.assertEqual(outputs[11], 4)
                    expected_sum = sum(range(1, words+1))*4
                    if pattern in ('escritura', 'lectura_escritura'):
                        expected_sum += 10*words
                        self.assertEqual([outputs[ARRAY_BASE//4+i] for i in range(words)],
                                         list(range(5, words+5)))
                    self.assertEqual(outputs[8], expected_sum)
                    if pattern == 'aleatorio':
                        offsets = [inputs[TABLE_BASE//4+i] for i in range(words//8)]
                        self.assertEqual(sorted(offsets), list(range(0, words*4, 32)))
                        coverage = [offset//4+phase for phase in range(8) for offset in offsets]
                        self.assertEqual(sorted(coverage), list(range(words)))
            path = root/'programs/bench_secuencial.mem'
            path.write_text('00000000\n')
            with self.assertRaises(ValueError):
                generate(root, check=True)

    def test_random_order_is_stable(self):
        # Vector fijo independiente de las bibliotecas de aleatoriedad del sistema.
        self.assertEqual(line_order(256)[:8], [30, 2, 27, 24, 23, 9, 17, 31])
        self.assertEqual(line_order(8192), line_order(8192))

    def test_invalid_inputs(self):
        for size, turns in ((0, 4), (4, 4), (32, 0), (1, 101)):
            with self.assertRaises(ValueError):
                validate(size, turns)
        with self.assertRaises(ValueError):
            line_order(255)

    def test_labels_do_not_add_instructions(self):
        with tempfile.TemporaryDirectory() as folder:
            for pattern in PATTERNS:
                source = ROOT/'programs'/f'bench_{pattern}.asm'
                bundles, labels = parse(source)
                self.assertLess(labels['.VUELTA'], labels['.FIN_RECORRIDO'])
                self.assertIn(f"-DBENCH_END_PC={labels['.FIN_RECORRIDO']}", metadata(source))
                other = Path(folder)/source.name
                other.write_text(source.read_text().replace('.FIN_RECORRIDO:', ''))
                self.assertEqual(assemble(source), assemble(other))
                self.assertGreater(len(bundles), 0)

    def test_drained_line_keeps_its_accepted_version(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            payload = sum((word+2) << (32*word) for word in range(8))
            transfer = dict(linea=0x1000//32, mascara='ffffffff', datos=f'{payload:064x}')
            path = root/'memoria_escrituras.csv'
            write_csv(path, [transfer])
            verify_memory_payloads(root, 'escritura', 8, 4, 1)
            for change in (dict(datos=f'{payload+1:064x}'), dict(mascara='0000000f'),
                           dict(linea=0), dict(datos=f'{payload+(1 << 32):064x}')):
                write_csv(path, [dict(transfer, **change)])
                with self.assertRaises(ValueError):
                    verify_memory_payloads(root, 'escritura', 8, 4, 1)
            write_csv(path, [transfer, transfer])
            with self.assertRaises(ValueError):
                verify_memory_payloads(root, 'escritura', 8, 4, 1)

    def test_store_classification_matches_original_counts(self):
        rows = [dict(segmento='recorrido', recorrido=1,
                     l1_hits_escritura=7, l1_misses_escritura=1)]
        costs = [dict(nivel='store_cpu', recorrido=1, caso='l1_hit', cantidad=7),
                 dict(nivel='store_cpu', recorrido=1, caso='l1_miss_memoria', cantidad=1)]
        verify_store_counts(rows, costs)
        bad = copy.deepcopy(costs)
        bad[1]['caso'] = 'l1_hit'
        with self.assertRaises(ValueError):
            verify_store_counts(rows, bad)
        with self.assertRaises(ValueError):
            verify_store_counts(rows, costs[:1])

    def test_trace_rejects_wrong_value_order_and_length(self):
        operations = list(expected_transactions('lectura_escritura', 1, 2))
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder)/'trace.txt'
            def save(ops):
                path.write_text('ciclo tipo direccion dato espera\n' + ''.join(
                    f'{index} {kind} {addr:08x} {value:08x} 0\n'
                    for index, (kind, addr, value) in enumerate(ops)))
            save(operations)
            self.assertEqual(len(verify_trace(path, 'lectura_escritura', 1, 2)), 516)
            changes = [operations[:-1], operations+[operations[-1]],
                       operations[:4]+[operations[5], operations[4]]+operations[6:]]
            kind, addr, value = operations[4]
            changes.append(operations[:4]+[(kind, addr, value+1)]+operations[5:])
            for corrupted in changes:
                save(corrupted)
                with self.assertRaises(ValueError):
                    verify_trace(path, 'lectura_escritura', 1, 2)


if __name__ == '__main__':
    unittest.main()
