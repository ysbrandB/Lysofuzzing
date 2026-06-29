import argparse
import json
import pathlib
import sys

import angr
import networkx as nx

def resolve_line_to_addr(project, target_str):
    """
    Parses a 'filename:lineno' string and returns the matching hex memory address.
    """
    try:
        filename, lineno = target_str.split(":")
        lineno = int(lineno)
        print(f"[+] Searching for source target -> {filename}:{lineno}")
    except ValueError:
        # If it's already a hex address string, return it directly
        return int(target_str, 16)

    binary = project.loader.main_object

    # In angr, the mapping goes from Address -> Line info.
    # To find a Line -> Address, we iterate through binary.addr_to_line
    matching_addrs = []
    if hasattr(binary, 'addr_to_line') and binary.addr_to_line:
        for addr, line_info in binary.addr_to_line.items():
            if isinstance(line_info, tuple) and len(line_info) == 2:
                src_file, src_line = line_info
                if src_file.endswith(filename) and src_line == lineno:
                    matching_addrs.append(addr)

    if matching_addrs:
        # Sort so we get the earliest instruction corresponding to that source line
        matching_addrs.sort()
        return matching_addrs[0]

    raise RuntimeError(f"Could not find line info for {target_str}. Did you compile with -g?")


def create_cfg(binary, target_str, debug):
    print(f"[*] Analyzing binary: {binary}")

    # FIX 1: You MUST explicitly tell angr to parse DWARF debug line info
    project = angr.Project(binary, auto_load_libs=False, load_debug_info=True)
    binary_obj = project.loader.main_object

    # Check if debug info exists safely using angr attributes
    if not hasattr(binary_obj, 'addr_to_line') or not binary_obj.addr_to_line:
        print("[-] No line debug symbols found in binary!")
    else:
        print("[+] Debug symbols successfully parsed by angr.")

    # FIX 2: Fixed variable reference from 'p' to 'project'
    try:
        target_addr = resolve_line_to_addr(project, target_str)
        print(f"[+] Successfully resolved {target_str} to memory address: {hex(target_addr)}")
    except Exception as e:
        raise RuntimeError(f"Address resolution failed: {e}")

    cfg = project.analyses.CFGFast(normalize=True)
    graph = cfg.graph

    entry_node = cfg.model.get_any_node(project.entry)
    target_node = cfg.model.get_any_node(target_addr, anyaddr=True)

    if entry_node is None:
        raise RuntimeError(f"no entry node at {hex(project.entry)}")

    if target_node is None:
        raise RuntimeError(f"no target node containing {hex(target_addr)}")

    reachable = nx.descendants(graph, entry_node)
    reachable.add(entry_node)
    subgraph = graph.subgraph(reachable).copy()

    if target_node not in subgraph:
        raise RuntimeError(
            f"target_node {hex(target_addr)} is not reachable from entry {hex(project.entry)}"
        )

    idom = nx.immediate_dominators(subgraph, entry_node)
    dom_chain = []
    cur = target_node

    while True:
        dom_chain.append(cur)
        if cur == entry_node:
            break
        cur = idom[cur]

    dom_chain.reverse()
    ranges = set()

    for node in dom_chain:
        start = node.addr
        size = node.size if node.size and node.size > 0 else 1
        end = start + size
        ranges.add((start, end))

    sorted_ranges = sorted(ranges)

    range_strings = [
        f"0x{start:x}-0x{end:x}"
        for start, end in sorted_ranges
    ]

    if debug:
        return {
            "binary": str(pathlib.Path(binary).resolve()),
            "entry": hex(project.entry),
            "target": hex(target_addr),
            "target_node": hex(target_node.addr),
            "dominator_chain": [hex(node.addr) for node in dom_chain],
            "ranges": range_strings,
            "afl_qemu_inst_ranges": ",".join(range_strings),
        }

    return ",".join(range_strings)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("binary")
    parser.add_argument(
        "--debug",
        action="store_true",
        help="debug json"
    )
    parser.add_argument(
        "--target",
        required=True,
        help="Target address (e.g. 0x401189) OR target line format (e.g. iff.c:1782)"
    )
    args = parser.parse_args()

    try:
        result = create_cfg(args.binary, args.target, args.debug)
        if isinstance(result, dict):
            print(json.dumps(result, indent=2))
        else:
            print(result)
    except Exception as e:
        print(f"[-] Error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()