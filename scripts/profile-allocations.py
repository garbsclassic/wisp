#!/usr/bin/env python3
"""Profile disposable release-built AppKit drivers; results stay outside the source tree.

Run through scoped approval when process inspection is sandbox-restricted:
  uv run --no-project scripts/profile-allocations.py --output /tmp/wisp-allocations
Add --baseline-source PATH to compare a separate checkout with the same driver.
"""

import argparse
import csv
import hashlib
import json
import os
from pathlib import Path
import platform
import plistlib
import re
import shutil
import subprocess
import time
import uuid


STAGES = [
    "00-hidden", "01-visible", "02-edits-early", "03-edits-final", "04-undone",
    "05-overlays-early", "06-overlays-final", "07-hidden-settled", "08-released",
]
HISTORY_STAGES = {"01-visible", "03-edits-final", "06-overlays-final", "08-released"}


def run(command, *, output=None, timeout=300, env=None):
    if output is None:
        return subprocess.run(command, check=True, timeout=timeout, env=env)
    with output.open("w") as stream:
        result = subprocess.run(command, stdout=stream, stderr=subprocess.STDOUT,
                                timeout=timeout, env=env)
    if result.returncode:
        raise RuntimeError(f"Command failed ({result.returncode}): {command}; see {output}")
    return result


def select_sdk():
    helper = Path(__file__).resolve().parent / "lib/sdk.sh"
    return Path(subprocess.check_output(["bash", str(helper)], text=True).strip())


def build(source, driver, destination, sdk):
    destination.mkdir(parents=True, exist_ok=True)
    flags = ["xcrun", "swiftc", "-sdk", str(sdk), "-target",
             f"{platform.machine()}-apple-macosx15.0", "-swift-version", "6", "-O", "-g",
             "-parse-as-library"]
    core = sorted((source / "Sources/WispCore").glob("*.swift"))
    run(flags + ["-emit-module", "-emit-library", "-static", "-module-name", "WispCore"]
        + list(map(str, core)) + ["-o", str(destination / "libWispCore.a"),
                                 "-emit-module-path", str(destination / "WispCore.swiftmodule")],
        output=destination / "build-core.log")
    app_sources = sorted(path for path in (source / "Sources/Wisp").glob("*.swift")
                         if path.name != "main.swift")
    binary = destination / "AllocationProfile"
    run(flags + ["-module-name", "Wisp", "-I", str(destination), "-L", str(destination),
                 "-lWispCore"] + list(map(str, app_sources)) + [str(driver), "-o", str(binary)],
        output=destination / "build-app.log")
    return binary


def wait_for(path, process, timeout=3600):
    deadline = time.monotonic() + timeout
    while not path.exists():
        if process.poll() is not None:
            raise RuntimeError(f"Driver exited ({process.returncode}) before {path.name}")
        if time.monotonic() > deadline:
            raise TimeoutError(f"Driver did not reach {path}")
        time.sleep(0.1)


def profile(binary, case, lines, newline, edit_count=100, overlay_count=50):
    case.mkdir(parents=True, exist_ok=False)
    (case / "xdg/wisp").mkdir(parents=True)
    identifier = f"dev.garbs.wisp.allocation-profile.{uuid.uuid4().hex}"
    app = case / "AllocationProfile.app"
    executable = app / "Contents/MacOS/AllocationProfile"
    executable.parent.mkdir(parents=True)
    # Keep matching symbols alongside each executable for external stack symbolication.
    shutil.copy2(binary, executable)
    dsym = binary.with_name(binary.name + ".dSYM")
    if dsym.exists():
        shutil.copytree(dsym, executable.with_name(executable.name + ".dSYM"))
    (app / "Contents/Info.plist").write_bytes(plistlib.dumps({
        "CFBundleIdentifier": identifier, "CFBundleExecutable": "AllocationProfile",
        "CFBundleName": "Wisp Allocation Profile", "CFBundlePackageType": "APPL",
        "LSUIElement": True, "NSPrincipalClass": "WispAllocationApplication",
    }))
    run(["codesign", "--force", "--sign", "-", str(app)], output=case / "sign.log")
    stack_logs = case / "stack-logs"
    stack_logs.mkdir()
    environment = dict(os.environ, MallocStackLogging="full", MallocStackLoggingNoCompact="1",
                       MallocStackLoggingDirectory=str(stack_logs),
                       WISP_ALLOCATION_ROOT=str(case), WISP_ALLOCATION_LINES=str(lines),
                       WISP_ALLOCATION_NEWLINE=newline, XDG_CONFIG_HOME=str(case / "xdg"))
    environment.update(WISP_ALLOCATION_EDITS=str(edit_count),
                       WISP_ALLOCATION_OVERLAYS=str(overlay_count))
    samples = []
    with (case / "driver.log").open("w") as log:
        process = subprocess.Popen([str(executable)], stdout=log, stderr=subprocess.STDOUT,
                                   env=environment)
        try:
            for stage in STAGES:
                ready = case / f"{stage}.ready"
                wait_for(ready, process)
                sample = json.loads(ready.read_text())
                if (sample.get("planned_edits"), sample.get("planned_overlays")) != (
                        edit_count, overlay_count):
                    raise RuntimeError("Driver workload does not match the requested counts")
                pid = str(process.pid)
                run(["heap", "-s", "--noContent", "-q", pid],
                    output=case / f"{stage}.heap.txt")
                if stage in HISTORY_STAGES:
                    run(["malloc_history", pid, "-noContent", "-callTree",
                         "-consolidateAllBySymbol"],
                        output=case / f"{stage}.history.txt")
                    run(["malloc_history", pid, "-noContent", "-highWaterMark", "-callTree",
                         "-consolidateAllBySymbol"],
                        output=case / f"{stage}.peak.txt")
                if stage == "08-released":
                    # leaks uses exit 1 when leaks are found; retain that result for interpretation.
                    with (case / "leaks.txt").open("w") as stream:
                        leaks = subprocess.run(["leaks", "--noContent", "--groupByType", pid],
                                               stdout=stream, stderr=subprocess.STDOUT, timeout=300)
                    sample["leaks_exit_code"] = leaks.returncode
                    leak_report = case / "leaks.txt"
                    if leaks.returncode not in (0, 1):
                        raise RuntimeError(f"leaks could not inspect the driver; see {leak_report}")
                    if not re.search(r"\d+ leaks? for [\d,]+ total leaked bytes",
                                     leak_report.read_text()):
                        raise RuntimeError(f"leaks returned no valid summary; see {leak_report}")
                samples.append(sample)
                (case / f"{stage}.resume").touch()
                print(f"{case.name}: {stage} malloc={sample['malloc_bytes']} "
                      f"footprint={sample['phys_footprint']}", flush=True)
            process.wait(timeout=30)
            if process.returncode:
                raise RuntimeError(f"Driver exited with {process.returncode}")
        finally:
            if process.poll() is None:
                process.terminate()
                process.wait(timeout=10)
            subprocess.run(["defaults", "delete", identifier], stdout=subprocess.DEVNULL,
                           stderr=subprocess.DEVNULL)
    return samples


def summarize(output):
    """Keep retained heap, allocator/VM high-water marks, and footprint distinct."""
    summary = json.loads((output / "summary.json").read_text())
    rows = []
    units = {"bytes": 1, "KB": 1000, "MB": 1000**2, "GB": 1000**3}
    for name, samples in summary.items():
        for sample in samples:
            row = {"case": name, **sample}
            case = output / name
            stage = sample["stage"]
            heap = (case / f"{stage}.heap.txt").read_text()
            match = re.search(r"All zones: ([\d,]+) nodes \(([\d,]+) bytes\)", heap)
            if not match:
                raise RuntimeError(f"Missing heap summary: {case / stage}")
            row["heap_nodes"], row["heap_bytes"] = (
                int(value.replace(",", "")) for value in match.groups())
            for name_of_class in [
                "EditorModel", "NotesTextView", "DocumentAnalysis", "HelpBodyView",
                "HelpDocumentTextView", "NSUndoReplaceCharacters",
            ]:
                match = re.search(r"^\s*(\d+)\s+\d+\s+[\d.]+\s+"
                                  + name_of_class + r"\s{2,}", heap, re.MULTILINE)
                row[f"count_{name_of_class}"] = int(match[1]) if match else 0
            peak = case / f"{stage}.peak.txt"
            if peak.exists():
                text = peak.read_text()
                for label, key in [
                    ("High water mark of allocated heap + VM memory", "peak_heap_vm_bytes"),
                    ("Cumulative total allocated heap + VM memory", "cumulative_heap_vm_bytes"),
                ]:
                    match = re.search(re.escape(label) + r":\s*([\d.,]+)\s*(bytes|KB|MB|GB)", text)
                    if not match:
                        raise RuntimeError(f"Missing {label} in {peak}")
                    row[key] = round(float(match[1].replace(",", "")) * units[match[2]])
                match = re.search(r"allocations:\s*([\d,]+)\s+deallocations:\s*([\d,]+)", text)
                if not match:
                    raise RuntimeError(f"Missing allocation counts in {peak}")
                row["allocations"], row["deallocations"] = (
                    int(value.replace(",", "")) for value in match.groups())
            if stage == "08-released":
                match = re.search(r"(\d+) leaks? for ([\d,]+) total leaked bytes",
                                  (case / "leaks.txt").read_text())
                if not match:
                    raise RuntimeError(f"Missing leak count in {case}")
                row["leak_count"], row["leak_bytes"] = (
                    int(value.replace(",", "")) for value in match.groups())
            rows.append(row)
    (output / "report-summary.json").write_text(json.dumps(rows, indent=2) + "\n")
    with (output / "report-summary.csv").open("w", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=sorted({key for row in rows for key in row}))
        writer.writeheader()
        writer.writerows(rows)
    return rows


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--baseline-source", type=Path)
    parser.add_argument("--omit-heading-bar", action="store_true",
                        help="Diagnostic control: omit heading buttons in the source snapshot only")
    parser.add_argument("--lines", nargs="+", type=int, default=[100, 3000, 30000])
    parser.add_argument("--edits", type=int, default=100)
    parser.add_argument("--overlay-cycles", type=int, default=50)
    parser.add_argument("--newlines", nargs="+", choices=["lf", "crlf"], default=["lf", "crlf"])
    arguments = parser.parse_args()
    if any(count <= 0 for count in arguments.lines + [arguments.edits, arguments.overlay_cycles]):
        parser.error("line, edit, and overlay counts must be positive")
    output = arguments.output.resolve()
    repo = Path(__file__).resolve().parent.parent
    sources = {"current": repo}
    if arguments.baseline_source:
        sources = {"baseline": arguments.baseline_source.resolve(), **sources}
    for source in sources.values():
        if output == source or source in output.parents:
            parser.error("--output must be outside the source checkouts")
    output.mkdir(parents=True, exist_ok=True)
    summary = {}
    sdk = select_sdk()
    driver = output / "AllocationProfile.swift"
    shutil.copy2(repo / "Tests/AppKit/AllocationProfile.swift", driver)
    manifest = {"sdk": str(sdk), "optimization": "-O", "debug_symbols": "-g",
                "heading_bar_omitted": arguments.omit_heading_bar,
                "edits": arguments.edits, "overlay_cycles": arguments.overlay_cycles,
                "stack_logging": "full", "stack_logging_no_compact": True,
                "driver_sha256": hashlib.sha256(driver.read_bytes()).hexdigest(),
                "sources": {}}
    for label, source in sources.items():
        print(f"Building {label} release driver", flush=True)
        snapshot = output / f"source-{label}"
        shutil.copytree(source / "Sources", snapshot / "Sources")
        if arguments.omit_heading_bar:
            editor = snapshot / "Sources/Wisp/EditorView.swift"
            text = editor.read_text()
            original = "HeaderBar(items: model.navigationHeadings, title: \\.title)"
            replacement = ("HeaderBar(items: Array(model.navigationHeadings.prefix(0)), "
                           "title: \\.title)")
            if text.count(original) != 1:
                raise RuntimeError("Cannot isolate the heading bar in this source revision")
            editor.write_text(text.replace(original, replacement))
        manifest["sources"][label] = {
            str(path.relative_to(snapshot)): hashlib.sha256(path.read_bytes()).hexdigest()
            for path in sorted((snapshot / "Sources").rglob("*.swift"))
        }
        (output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
        binary = build(snapshot, driver, output / f"build-{label}", sdk)
        for count in arguments.lines:
            for newline in arguments.newlines:
                name = f"{label}-{count}-{newline}"
                summary[name] = profile(binary, output / name, count, newline,
                                        arguments.edits, arguments.overlay_cycles)
                (output / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    summarize(output)
    print(f"Results: {output}", flush=True)


if __name__ == "__main__":
    main()
