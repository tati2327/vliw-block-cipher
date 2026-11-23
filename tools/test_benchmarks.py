"""Comprueba entradas, límites de medición y detección de trazas incorrectas."""
import copy
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from asm import assemble, parse
from bench_data import (ROOT, PATTERNS, EXTRA_PATTERNS, SIZES, ARRAY_BASE, TABLE_BASE, contents,
                        expected_transactions, generate, line_order, metadata, validate)
from mem_format import read_words
from metricas import verify_trace, verify_store_counts, verify_memory_payloads, write_csv, format_summary, enrich, verify_l2_accounting, verify_case, format_console, format_policy_comparison


class BenchmarkTests(unittest.TestCase):
    def test_invalid_matrix_preserves_existing_results(self):
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary)
            summary = output/'metricas.csv'
            summary.write_text('resultado anterior\n')
            for arguments in (['--patterns','reuso','--sizes','1'], ['--max-cycles','0']):
                with self.subTest(arguments=arguments):
                    result = subprocess.run(
                        [sys.executable,'-B',str(ROOT/'tools/metricas.py'),
                         '--out',str(output),*arguments], capture_output=True,text=True)
                    self.assertNotEqual(result.returncode,0)
                    self.assertEqual(summary.read_text(),'resultado anterior\n')
                    self.assertNotIn('Traceback',result.stderr)

    def test_reuse_workload_has_conflicts_and_checked_results(self):
        for size, reads, checksum in ((8,1536,1175040), (32,7680,17671680)):
            operations = list(expected_transactions('reuso',size,4))
            loads = operations[4:-4]
            self.assertEqual(len(loads),reads)
            self.assertEqual(sum(value for _,_,value in loads),checksum)
            self.assertEqual([a for _,a,_ in loads[:6]],
                             [0x1000,0x1800,0x1000,0x2000,0x1000,0x2800])
            for hot, stream in zip(loads[::2],loads[1::2]):
                self.assertEqual((hot[1]>>5)&63, (stream[1]>>5)&63)
                self.assertNotEqual(hot[1]>>11,stream[1]>>11)
                self.assertTrue(ARRAY_BASE <= stream[1] < ARRAY_BASE+size*1024)
            self.assertEqual(len({a>>5 for _,a,_ in loads}),size*1024//32)
            with tempfile.TemporaryDirectory() as temporary:
                folder = Path(temporary)
                data,expected = contents('reuso',size,4)
                (folder/'input.mem').write_text(data)
                (folder/'expected.mem').write_text(expected)
                inputs = read_words(folder/'input.mem')
                outputs = read_words(folder/'expected.mem')
                self.assertTrue(all(inputs[a//4]==value for _,a,value in loads))
                self.assertEqual([outputs[a] for a in range(8,12)], [checksum,reads,0,4])
        with self.assertRaisesRegex(ValueError,'8 y 32 KiB'):
            contents('reuso',1,4)

    def test_console_tables_fit_eighty_columns(self):
        row = dict(programa='lectura_escritura', tamano_kib=32, cache=2,
                   mem_div=4, vueltas=4, politica_l1='FIFO', ciclos=2276098,
                   pausa_memoria=2013762, ipc=.129655, l1_hit_rate=.437050,
                   l2_hit_rate=.121199, amat_medido=31.723819, amat_formula=31.723819)
        summary = format_console([row])
        self.assertLessEqual(max(map(len, summary.splitlines())), 80)
        self.assertNotIn('No medido', summary)
        self.assertIn('Reemplazo L1 FIFO', summary)
        self.assertIn('2276098', summary)
        self.assertIn('Buffers.', summary)

    def test_policy_comparison_calculates_differences(self):
        base = dict(programa='aleatorio', tamano_kib=32, cache=2, mem_div=4,
                    vueltas=4, l1_misses_lectura=10, l1_misses_escritura=1)
        lru = dict(base, ciclos=100, pausa_memoria=50)
        fifo = dict(base, ciclos=125, pausa_memoria=75, politica_l1='FIFO')
        summary = format_policy_comparison([fifo], [lru])
        self.assertIn('+25.000000%', summary)
        self.assertIn('LRU', summary)
        self.assertIn('FIFO', summary)
        self.assertLessEqual(max(map(len, summary.splitlines())), 80)
        for key, value in [('mem_div',5), ('vueltas',2), ('cache',1), ('tamano_kib',8)]:
            with self.assertRaisesRegex(ValueError, 'Falta una referencia'):
                format_policy_comparison([dict(fifo, **{key:value})], [lru])
        with self.assertRaisesRegex(ValueError, 'dos políticas distintas'):
            format_policy_comparison([lru], [lru])

    def test_summary_keeps_replacement_policies_separate(self):
        base = dict(programa='secuencial', tamano_kib=8, vueltas=4,
                    pausa_memoria=20, ipc=1.0, mem_div=4, cache=2)
        lru = dict(base, ciclos=100, politica_l1='LRU')
        fifo = dict(base, ciclos=125, politica_l1='FIFO')
        summary = format_summary([lru, fifo])
        self.assertIn('Política L1 LRU.', summary)
        self.assertIn('Política L1 FIFO.', summary)
        self.assertIn('100', summary)
        self.assertIn('125', summary)

    def test_rejects_log_with_wrong_replacement_policy(self):
        config = dict(programa='secuencial', tamano_kib=8, cache=2,
                      mem_div=4, vueltas=4, politica_l1='FIFO')
        with tempfile.TemporaryDirectory() as temporary:
            folder = Path(temporary)
            (folder/'simulacion.log').write_text(
                'Politica de reemplazo L1 LRU\nPASS tb_programa\n')
            with self.assertRaisesRegex(ValueError, 'no confirma la política'):
                verify_case(folder, config)

    def test_summary_only_pairs_equal_memory_and_passes(self):
        base = dict(programa='secuencial', tamano_kib=1, vueltas=4,
                    pausa_memoria=20, ipc=1.0)
        direct = dict(base, cache=0, mem_div=4, ciclos=100)
        same = dict(base, cache=1, mem_div=4, ciclos=25)
        other_memory = dict(base, cache=1, mem_div=5, ciclos=10)
        other_passes = dict(base, cache=1, mem_div=4, vueltas=2, ciclos=10)
        full = dict(base, cache=2, mem_div=4, ciclos=20)
        paired = format_summary([direct, same, full])
        self.assertIn('4.00x', paired)
        self.assertNotIn('No medido', paired)
        self.assertIn('53 ciclos nominales', paired)
        for unmatched in (other_memory, other_passes):
            result = format_summary([direct, unmatched])
            self.assertIn('No medido', result)
            self.assertIn('No calculable', result)
            self.assertNotIn('10.00x', result)

    def test_full_hierarchy_rates_and_amat(self):
        config = dict(programa='escritura', tamano_kib=1, vueltas=4, cache=2, mem_div=4)
        row = dict(segmento='total', ciclos=100, instrucciones=50, pausa_memoria=60,
                   lecturas_cpu=0, escrituras_cpu=100, l1_lecturas=0, l1_escrituras=100,
                   l1_hits_lectura=0, l1_hits_escritura=80, l2_lecturas=20,
                   l2_escrituras=10, l2_hits_lectura=10, l2_hits_escritura=5,
                   l2_misses_lectura=10, l2_misses_escritura=5)
        result = enrich(row, config)
        self.assertEqual(result['l1_hit_rate'], .8)
        self.assertEqual(result['l2_hit_rate'], .5)
        self.assertAlmostEqual(result['amat_medido'], 1.6)
        self.assertAlmostEqual(result['amat_formula'], 7.9)
        empty = dict(row, l2_lecturas=0, l2_escrituras=0,
                     l2_hits_lectura=0, l2_hits_escritura=0,
                     l2_misses_lectura=0, l2_misses_escritura=0)
        self.assertEqual(enrich(empty, config)['l2_hit_rate'], '')

    def test_l2_classification_can_cross_interval(self):
        base = dict(l2_lecturas=0, l2_hits_lectura=0, l2_misses_lectura=0,
                    l2_escrituras=0, l2_hits_escritura=0, l2_misses_escritura=0)
        rows = [dict(base, segmento='recorrido', l2_escrituras=1),
                dict(base, segmento='cierre', l2_hits_escritura=1),
                dict(base, segmento='total', l2_escrituras=1, l2_hits_escritura=1)]
        verify_l2_accounting(rows)
        self.assertEqual(rows[0]['l2_escrituras_pendientes_fin'], 1)
        self.assertEqual(rows[1]['l2_escrituras_pendientes_inicio'], 1)
        self.assertEqual(rows[1]['l2_escrituras_pendientes_fin'], 0)
        for index, key, value in [(0, 'l2_escrituras', 2),
                                  (1, 'l2_hits_escritura', 2),
                                  (2, 'l2_hits_escritura', 0)]:
            bad = copy.deepcopy(rows)
            bad[index][key] = value
            with self.assertRaises(ValueError):
                verify_l2_accounting(bad)

    def test_l2_can_keep_intermediate_versions(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            def transfer(turn):
                payload = sum((word+1+turn) << (32*word) for word in range(8))
                return dict(linea=0x1000//32, mascara='ffffffff', datos=f'{payload:064x}')
            path = root/'memoria_escrituras.csv'
            write_csv(path, [transfer(2), transfer(4)])
            verify_memory_payloads(root, 'escritura', 8, 4, 2)
            with self.assertRaises(ValueError):
                verify_memory_payloads(root, 'escritura', 8, 4, 1)
            for turns in ([2, 2], [4, 2], [5]):
                write_csv(path, [transfer(turn) for turn in turns])
                with self.assertRaises(ValueError):
                    verify_memory_payloads(root, 'escritura', 8, 4, 2)

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
            for pattern in PATTERNS + EXTRA_PATTERNS:
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
