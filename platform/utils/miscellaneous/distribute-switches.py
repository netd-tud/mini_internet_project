#!/usr/bin/env python3
import argparse
import os
import re
import random
import subprocess

DEFAULT_TOTAL_CPUS = int(os.getenv("TOTAL_CPUS", "256"))
DEFAULT_CPUS_PER_CONTAINER = int(os.getenv("CPUS_PER_CONTAINER", "6"))
DEFAULT_DRY_RUN = os.getenv("DRY_RUN", "1") != "0"

# More candidates = better overlap minimization, slightly slower.
DEFAULT_CANDIDATES_PER_CONTAINER = int(os.getenv("CANDIDATES_PER_CONTAINER", "3000"))
SWITCH_CONTAINER_PATTERN = r"^[0-9]{1,3}_L2_L2[EN]_S[1-3]$"
IXP_CONTAINER_PATTERN = r"^[0-9]{1,3}_IXP$"

pattern_switches = re.compile(SWITCH_CONTAINER_PATTERN)
pattern_ixps = re.compile(IXP_CONTAINER_PATTERN)

DEFAULT_RANDOM_SEED = os.getenv("RANDOM_SEED")


def parse_args():
    parser = argparse.ArgumentParser(
        description="Distribute Docker L2 switch containers across CPU sets.",
    )
    parser.add_argument(
        "--total-cpus",
        type=int,
        default=DEFAULT_TOTAL_CPUS,
        help=f"Logical CPUs to distribute across (default: {DEFAULT_TOTAL_CPUS}).",
    )
    parser.add_argument(
        "--cpus-per-container",
        type=int,
        default=DEFAULT_CPUS_PER_CONTAINER,
        help=(
            "Number of CPUs assigned to each matching container "
            f"(default: {DEFAULT_CPUS_PER_CONTAINER})."
        ),
    )
    parser.add_argument(
        "--candidates-per-container",
        type=int,
        default=DEFAULT_CANDIDATES_PER_CONTAINER,
        help=(
            "Random candidate CPU sets considered per container "
            f"(default: {DEFAULT_CANDIDATES_PER_CONTAINER})."
        ),
    )

    parser.add_argument(
        "--random-seed",
        type=int,
        default=None if DEFAULT_RANDOM_SEED is None else int(DEFAULT_RANDOM_SEED),
        help="Seed for reproducible assignments.",
    )
    parser.add_argument(
        "--container-count",
        type=int,
        default=None,
        help=(
            "Allocate CPU sets for this many containers instead of reading "
            "existing Docker container names."
        ),
    )
    parser.add_argument(
        "--cpuset-list",
        action="store_true",
        help="Print only ordered cpuset strings, one per container.",
    )
    parser.add_argument(
        "--apply",
        action="store_false",
        dest="dry_run",
        default=DEFAULT_DRY_RUN,
        help="Apply assignments with docker update.",
    )
    return parser.parse_args()


def docker_container_names():
    result = subprocess.run(
        ["docker", "container", "ls", "--format", "{{.Names}}"],
        check=True,
        text=True,
        stdout=subprocess.PIPE,
    )

    names = [
        line.strip()
        for line in result.stdout.splitlines()
        if pattern_switches.match(line.strip()) or pattern_ixps.match(line.strip())
    ]

    return sorted(names)


def score_candidate(candidate, assigned_sets, cpu_remaining):
    candidate_set = set(candidate)

    max_overlap = 0
    overlap_count = 0
    total_overlap = 0
    squared_overlap_penalty = 0

    for existing in assigned_sets:
        overlap = len(candidate_set & existing)
        if overlap:
            overlap_count += 1
            total_overlap += overlap
            squared_overlap_penalty += overlap * overlap
            max_overlap = max(max_overlap, overlap)

    # Prefer CPUs that still have more remaining capacity,
    # which helps preserve global balance feasibility.
    remaining_score = -sum(cpu_remaining[cpu] for cpu in candidate)

    # Tuple ordering: lower is better.
    return (
        max_overlap,              # avoid 2+ CPU overlap with any one container
        squared_overlap_penalty,  # strongly penalize repeated overlap
        total_overlap,            # reduce total shared CPUs
        overlap_count,            # reduce number of containers touched
        remaining_score,          # consume CPUs with higher remaining budget
        random.random(),          # randomized tie-breaker
    )


def feasible_after_pick(candidate, cpu_remaining, containers_left_after, cpus_per_container):
    remaining = cpu_remaining[:]

    for cpu in candidate:
        remaining[cpu] -= 1
        if remaining[cpu] < 0:
            return False

    if containers_left_after == 0:
        return sum(remaining) == 0

    available_cpus = sum(1 for x in remaining if x > 0)

    if available_cpus < cpus_per_container:
        return False

    # A CPU can appear at most once per future container.
    if any(x > containers_left_after for x in remaining):
        return False

    return True


def allocate(containers, total_cpus, cpus_per_container, candidates_per_container):
    n = len(containers)
    total_slots = n * cpus_per_container

    base = total_slots // total_cpus
    extra = total_slots % total_cpus

    cpu_remaining = [base] * total_cpus

    # Randomize which CPUs get the one extra assignment.
    extra_cpus = list(range(total_cpus))
    random.shuffle(extra_cpus)

    for cpu in extra_cpus[:extra]:
        cpu_remaining[cpu] += 1

    assigned_sets = []
    assignments = {}

    for idx, container in enumerate(containers):
        containers_left_after = n - idx - 1
        available = [cpu for cpu, rem in enumerate(cpu_remaining) if rem > 0]

        best_candidate = None
        best_score = None

        for _ in range(candidates_per_container):
            if len(available) < cpus_per_container:
                raise RuntimeError("Not enough available CPUs to continue allocation")

            candidate = tuple(sorted(random.sample(available, cpus_per_container)))

            if not feasible_after_pick(
                candidate,
                cpu_remaining,
                containers_left_after,
                cpus_per_container,
            ):
                continue

            score = score_candidate(candidate, assigned_sets, cpu_remaining)

            if best_score is None or score < best_score:
                best_score = score
                best_candidate = candidate

        if best_candidate is None:
            raise RuntimeError(
                f"Could not find feasible CPU assignment for {container}. "
                f"Try increasing --candidates-per-container."
            )

        for cpu in best_candidate:
            cpu_remaining[cpu] -= 1

        assigned_sets.append(set(best_candidate))
        assignments[container] = best_candidate

    if any(x != 0 for x in cpu_remaining):
        raise RuntimeError("Internal allocator error: CPU capacity not fully consumed")

    return assignments


def cpuset_string(cpus):
    return ",".join(str(cpu) for cpu in cpus)


def main():
    args = parse_args()

    if args.total_cpus <= 0:
        raise ValueError("--total-cpus must be greater than 0")
    if args.cpus_per_container <= 0:
        raise ValueError("--cpus-per-container must be greater than 0")
    if args.candidates_per_container <= 0:
        raise ValueError("--candidates-per-container must be greater than 0")
    if args.container_count is not None and args.container_count < 0:
        raise ValueError("--container-count must be greater than or equal to 0")
    if args.cpus_per_container > args.total_cpus:
        raise ValueError("--cpus-per-container cannot exceed --total-cpus")
    if args.container_count is not None and not args.dry_run:
        raise ValueError("--apply cannot be used with --container-count")

    if args.random_seed is not None:
        random.seed(args.random_seed)

    if args.container_count is None:
        containers = docker_container_names()
    else:
        containers = list(range(args.container_count))

    if not containers:
        if args.cpuset_list:
            return 0
        print("No matching containers found.")
        return 1

    assignments = allocate(
        containers,
        args.total_cpus,
        args.cpus_per_container,
        args.candidates_per_container,
    )

    if args.cpuset_list:
        for container in containers:
            print(cpuset_string(assignments[container]))
        return 0

    if args.container_count is None:
        print(f"Found {len(containers)} matching containers.")
    else:
        print(f"Allocating CPU sets for {len(containers)} containers.")
    print(
        f"Assigning {args.cpus_per_container} CPUs per container "
        f"across {args.total_cpus} logical CPUs."
    )

    total_slots = len(containers) * args.cpus_per_container
    base = total_slots // args.total_cpus
    extra = total_slots % args.total_cpus

    print(f"Total CPU assignments: {total_slots}")
    print(f"Expected per-core use: {base} or {base + 1} containers per CPU")
    print(f"Dry run: {args.dry_run}")
    print()

    cpu_use = [0] * args.total_cpus

    for container, cpus in assignments.items():
        for cpu in cpus:
            cpu_use[cpu] += 1

        cpuset = cpuset_string(cpus)

        print(f"{container:<45} -> CPUs {cpuset}")

        if not args.dry_run:
            subprocess.run(
                ["docker", "update", "--cpuset-cpus", cpuset, container],
                check=True,
                stdout=subprocess.DEVNULL,
            )
            subprocess.run(
                ["docker", "exec", container, "supervisorctl restart ovs"],
                check=True,
                stdout=subprocess.DEVNULL,
            )

    print()
    print("Per-core assignment distribution:")

    counts = {}
    for use in cpu_use:
        counts[use] = counts.get(use, 0) + 1

    for use in sorted(counts):
        print(f"  {counts[use]:3d} CPUs have {use} containers assigned")

    print()

    if args.dry_run:
        print("Dry run only. Apply with:")
        print("  ./distribute-switches.py --apply")
    else:
        print("CPU sets applied.")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
