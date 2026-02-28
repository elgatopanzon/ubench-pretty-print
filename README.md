# ubench-pretty-print

Pretty printer for [ubench](https://github.com/sheredom/ubench.h) benchmark output. Wraps benchmark executables and reformats raw ubench output into readable comparison tables with performance ratios and color-coded results.

Sample output:
```
══ BENCHMARK COMPARISON ══

### hash_suite
| Method       | Mean         | CI         | Ratio    | Status   |
|--------------|--------------|------------|----------|----------|
| fnv1a (~)    | 45.1us       | +-1.2%     | 1.16x    | OK       |
| djb2 (-)     | 52.5us       | +-1.0%     | 1.00x    | OK       |
| murmur3 (+)  | 38.8us       | +-2.3%     | 1.35x    | OK       |

════════════════════════════════════════════════
 SUMMARY: 3 total | 3 OK
════════════════════════════════════════════════
```

## Installation

Copy `ubench-pretty-print.sh` to your project or add to PATH:

```bash
cp ubench-pretty-print.sh /usr/local/bin/
chmod +x /usr/local/bin/ubench-pretty-print.sh
```

## Usage

```bash
./ubench-pretty-print.sh [options] <benchmark_executable> [args...]
```

### Options

| Option | Description |
|--------|-------------|
| `--no-colour`, `--no-color` | Disable ANSI colors, use text indicators instead: `(+)` fastest, `(-)` slowest, `(~)` similar |
| `--show-raw-output` | Show raw benchmark output before comparison tables (hidden by default) |
| `-h`, `--help` | Show usage help |

### Examples

Run benchmark with colors (default):
```bash
./ubench-pretty-print.sh ./my_benchmark
```

Run without colors (for CI/logs):
```bash
./ubench-pretty-print.sh --no-color ./my_benchmark
```

Show raw output alongside formatted tables:
```bash
./ubench-pretty-print.sh --show-raw-output ./my_benchmark
```

Pass arguments to benchmark:
```bash
./ubench-pretty-print.sh ./my_benchmark --filter=*hash*
```

## Sample Input/Output

### Raw ubench output (what the tool parses)

```
[ RUN      ] hash_suite.fnv1a
[       OK ] hash_suite.fnv1a (mean 45.123us, confidence interval +- 1.234%)
[ RUN      ] hash_suite.djb2
[       OK ] hash_suite.djb2 (mean 52.456us, confidence interval +- 0.987%)
[ RUN      ] hash_suite.murmur3
[       OK ] hash_suite.murmur3 (mean 38.789us, confidence interval +- 2.345%)
```

### Formatted output (color mode)

```
══ BENCHMARK COMPARISON ══

### hash_suite
| Method   | Mean         | CI         | Ratio    | Status   |
|----------|--------------|------------|----------|----------|
| fnv1a    | 45.1us       | +-1.2%     | 1.16x    | OK       |  (yellow if similar)
| djb2     | 52.5us       | +-1.0%     | 1.00x    | OK       |  (red = slowest)
| murmur3  | 38.8us       | +-2.3%     | 1.35x    | OK       |  (green = fastest)

════════════════════════════════════════════════
 SUMMARY: 3 total | 3 OK
════════════════════════════════════════════════
```

### Formatted output (no-color mode)

```
══ BENCHMARK COMPARISON ══

### hash_suite
| Method       | Mean         | CI         | Ratio    | Status   |
|--------------|--------------|------------|----------|----------|
| fnv1a (~)    | 45.1us       | +-1.2%     | 1.16x    | OK       |
| djb2 (-)     | 52.5us       | +-1.0%     | 1.00x    | OK       |
| murmur3 (+)  | 38.8us       | +-2.3%     | 1.35x    | OK       |

════════════════════════════════════════════════
 SUMMARY: 3 total | 3 OK
════════════════════════════════════════════════
```

### With --show-raw-output

```
══ BENCHMARK COMPARISON ══

  Raw output:
    [       OK ] hash_suite.fnv1a (mean 45.123us, confidence interval +- 1.234%)
    [       OK ] hash_suite.djb2 (mean 52.456us, confidence interval +- 0.987%)
    [       OK ] hash_suite.murmur3 (mean 38.789us, confidence interval +- 2.345%)

### hash_suite
| Method   | Mean         | CI         | Ratio    | Status   |
|----------|--------------|------------|----------|----------|
...
```

### Table columns

| Column | Description |
|--------|-------------|
| **Method** | Benchmark name within the suite (with indicator in no-color mode) |
| **Mean** | Average execution time, auto-scaled to best unit (ns/us/ms/s) |
| **CI** | Confidence interval percentage, normalized to 1 decimal place |
| **Ratio** | Speed relative to slowest benchmark (slowest=1.00x, faster=higher) |
| **Status** | OK, CI! (confidence interval exceeded), or FAIL |

### Color/indicator meanings

| Color | No-color indicator | Meaning |
|-------|-------------------|---------|
| Green | `(+)` | Fastest in suite |
| Red | `(-)` | Slowest in suite |
| Yellow | `(~)` | Statistically similar |

**Statistical similarity**: Benchmarks are considered statistically similar if the difference is <=2.5% OR <=5ns absolute (noise floor for very fast operations).

## Requirements

- bash 4.0+
- awk
- ubench benchmark executable (built with [ubench.h](https://github.com/sheredom/ubench.h))

## License

MIT License - see [LICENSE](LICENSE) file.
