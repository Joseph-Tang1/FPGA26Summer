#!/usr/bin/env python3
"""Independently verify every generated station mapping and distance-ROM entry."""

from __future__ import annotations

import csv
import json
from decimal import Decimal
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
DATA = ROOT / "data"
SRC = ROOT / "src"
INFINITY = 10**12


def fail(message: str) -> None:
    raise SystemExit(f"DATA_TEST_FAIL: {message}")


def read_source():
    tokens = (DATA / "metro_lines.txt").read_text(encoding="utf-8").split()
    cursor = 0
    line_total = int(tokens[cursor])
    cursor += 1
    lines = []
    for line_id in range(1, line_total + 1):
        name = tokens[cursor]
        count = int(tokens[cursor + 1])
        cursor += 2
        stations = tokens[cursor : cursor + count]
        cursor += count
        distances = [
            int(Decimal(value) * 1000)
            for value in tokens[cursor : cursor + count - 1]
        ]
        cursor += count - 1
        if len(stations) != count or len(distances) != count - 1:
            fail(f"invalid source record for line {line_id}")
        lines.append((line_id, name, stations, distances))
    if cursor != len(tokens):
        fail("unexpected trailing source tokens")
    return lines


def build_expected_graph(lines):
    station_to_id = {}
    id_to_station = []
    for _, _, stations, _ in lines:
        for station in stations:
            if station not in station_to_id:
                station_to_id[station] = len(id_to_station)
                id_to_station.append(station)

    count = len(id_to_station)
    matrix = [[INFINITY] * count for _ in range(count)]
    for station in range(count):
        matrix[station][station] = 0
    for _, _, stations, distances in lines:
        for index, distance in enumerate(distances):
            left = station_to_id[stations[index]]
            right = station_to_id[stations[index + 1]]
            matrix[left][right] = min(matrix[left][right], distance)
            matrix[right][left] = min(matrix[right][left], distance)

    # Floyd-Warshall is intentionally different from the generator's Dijkstra.
    for middle in range(count):
        via_middle = matrix[middle]
        for start in range(count):
            start_to_middle = matrix[start][middle]
            if start_to_middle == INFINITY:
                continue
            start_row = matrix[start]
            for end in range(count):
                candidate = start_to_middle + via_middle[end]
                if candidate < start_row[end]:
                    start_row[end] = candidate
    if any(value == INFINITY for row in matrix for value in row):
        fail("metro graph is disconnected")
    return station_to_id, id_to_station, matrix


def verify_station_csv(lines, station_to_id):
    with (DATA / "station_codes.csv").open(encoding="utf-8-sig", newline="") as handle:
        actual = list(csv.DictReader(handle))
    expected = []
    for line_id, name, stations, distances in lines:
        for local_index, station in enumerate(stations, start=1):
            expected.append(
                {
                    "line_id": str(line_id),
                    "line_name": name,
                    "local_index": str(local_index),
                    "display_code": str(line_id * 100 + local_index),
                    "global_id": str(station_to_id[station]),
                    "station_name": station,
                    "distance_to_next_m": (
                        str(distances[local_index - 1])
                        if local_index <= len(distances)
                        else ""
                    ),
                }
            )
    if actual != expected:
        fail("station_codes.csv does not match metro_lines.txt")
    return len(expected)


def verify_rom(matrix):
    rom_lines = (DATA / "distance_rom.mem").read_text(encoding="ascii").splitlines()
    station_count = len(matrix)
    expected_count = station_count * (station_count - 1) // 2
    if len(rom_lines) != expected_count:
        fail(f"ROM has {len(rom_lines)} entries, expected {expected_count}")

    address = 0
    maximum = 0
    for high in range(1, station_count):
        for low in range(high):
            try:
                actual = int(rom_lines[address], 16)
            except ValueError:
                fail(f"invalid hexadecimal value at ROM address {address}")
            expected = matrix[high][low]
            if actual != expected:
                fail(
                    f"ROM address {address} for pair ({low}, {high}) is "
                    f"{actual}, expected {expected}"
                )
            if actual >= (1 << 17):
                fail(f"ROM value at address {address} exceeds 17 bits")
            maximum = max(maximum, actual)
            address += 1
    return expected_count, maximum


def verify_generated_verilog(lines, station_to_id, station_count):
    mapper = (SRC / "station_mapper.v").read_text(encoding="ascii")
    base_rom = (SRC / "triangle_base_rom.v").read_text(encoding="ascii")
    for line_id, _, stations, _ in lines:
        count_text = f"station_count = 6'd{len(stations)};"
        if count_text not in mapper:
            fail(f"station_mapper.v lacks line {line_id} count")
        for local_index, station in enumerate(stations, start=1):
            mapping = (
                f"6'd{local_index}: begin global_id = "
                f"7'd{station_to_id[station]}; valid = 1'b1; end"
            )
            if mapping not in mapper:
                fail(f"station_mapper.v lacks line {line_id} station {local_index}")
    for index in range(station_count):
        base = index * (index - 1) // 2
        if f"7'd{index}: base = 13'd{base};" not in base_rom:
            fail(f"triangle_base_rom.v lacks index {index}")


def fare_from_distance(distance: int) -> int:
    limits = [(4000, 2), (9000, 3), (14000, 4), (21000, 5),
              (28000, 6), (37000, 7), (48000, 8), (61000, 9)]
    for limit, fare in limits:
        if distance <= limit:
            return fare
    return 9 + (distance - 61000 + 14999) // 15000


def verify_metadata(lines, station_count, occurrence_count, pair_count, maximum):
    actual = json.loads((DATA / "metadata.json").read_text(encoding="utf-8"))
    expected = {
        "line_count": len(lines),
        "line_station_counts": [len(stations) for _, _, stations, _ in lines],
        "station_occurrences": occurrence_count,
        "unique_station_count": station_count,
        "pair_count": pair_count,
        "distance_width_bits": 17,
        "maximum_distance_m": maximum,
        "maximum_fare_yuan": fare_from_distance(maximum),
    }
    if actual != expected:
        fail(f"metadata.json mismatch: {actual!r} != {expected!r}")


def main() -> None:
    lines = read_source()
    station_to_id, id_to_station, matrix = build_expected_graph(lines)
    occurrence_count = verify_station_csv(lines, station_to_id)
    pair_count, maximum = verify_rom(matrix)
    verify_generated_verilog(lines, station_to_id, len(id_to_station))
    verify_metadata(
        lines, len(id_to_station), occurrence_count, pair_count, maximum
    )
    print(
        "DATA_TEST_PASS: "
        f"{len(lines)} lines, {occurrence_count} station occurrences, "
        f"{len(id_to_station)} unique stations and all {pair_count} "
        "shortest-distance ROM entries match an independent Floyd-Warshall check."
    )


if __name__ == "__main__":
    main()
