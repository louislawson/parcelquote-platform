"""Cross-check every decision record's Decided date and Evidence line against git history.

    python docs/adr/check-evidence.py

Run from the repository root, with full history. Prints a line per record and exits
non-zero if a record cites a pull request with no merge commit, cites a file that does
not resolve, is dated after its own evidence, or is dated before it without a sentence
saying why.

This is a check to run by hand rather than a gate, for two reasons. It needs the whole
history, and the Terraform job's checkout does not fetch it. And it reads the merge
commit subjects Azure DevOps and GitHub generate, so a squash merge or a renamed branch
would make it report problems that are not there. It found two real ones on its first
run over seventeen records, which is why it is here rather than in somebody's shell
history.
"""

import glob
import re
import subprocess
import sys

# PR number -> (merge date, branch) from the merge commits on main
merges = {}
log = subprocess.run(
    ["git", "log", "--merges", "--format=%ad%x09%s", "--date=short"],
    capture_output=True, text=True, check=True,
).stdout
for line in log.splitlines():
    date, _, subject = line.partition("\t")
    m = re.match(r"Merge pull request #(\d+) from \S+/(\S+)", subject)
    if m:
        merges[int(m.group(1))] = (date, m.group(2))

rows, problems = [], 0
for path in sorted(glob.glob("docs/adr/[0-9][0-9][0-9][0-9]-*.md")):
    text = open(path, encoding="utf-8").read()
    decided = re.search(r"^\*\*Decided:\*\* (\S+)", text, re.M).group(1)
    evidence = re.search(r"^\*\*Evidence:\*\*(.+?)\n\n", text, re.M | re.S).group(1)
    evidence = " ".join(evidence.split())
    prs = [int(n) for n in re.findall(r"PR #(\d+)", evidence)]

    verdict, detail = "ok", ""
    if not prs:
        # A record may cite a file instead of a pull request; the file has to exist.
        files = re.findall(r"\]\(([^)]+)\)", evidence)
        missing = [f for f in files if not glob.glob("docs/adr/" + f.split("#")[0])]
        verdict = "file-cited"
        detail = "cites " + (", ".join(files) if files else "no pull request")
        if missing:
            verdict, detail, problems = "BROKEN", "cannot resolve " + ", ".join(missing), problems + 1
    else:
        closed = set(int(n) for n in re.findall(r"closed PR #(\d+)", evidence))
        prs = [n for n in prs if n not in closed]
        unknown = [n for n in prs if n not in merges]
        if unknown:
            verdict = "BROKEN"
            detail = "no merge commit for PR #" + ", #".join(str(n) for n in unknown)
            problems += 1
        else:
            dates = sorted(merges[n][0] for n in prs)
            detail = "PR " + ", ".join("#%d (%s)" % (n, merges[n][0]) for n in prs)
            if decided < dates[0]:
                # Legitimate when the record says the decision predates its implementation.
                explained = re.search(r"design|scoped|predates", evidence, re.I)
                verdict = "earlier-than-evidence" if explained else "UNEXPLAINED"
                if not explained:
                    problems += 1
            elif decided > dates[-1]:
                verdict = "LATER-THAN-EVIDENCE"
                problems += 1

    rows.append((path.replace("\\", "/").split("/")[-1][:4], decided, verdict, detail))

width = max(len(r[3]) for r in rows)
for number, decided, verdict, detail in rows:
    print(f"{number}  {decided}  {detail:<{width}}  {verdict}")
print()
print(f"{len(rows)} records, {problems} needing attention")
sys.exit(1 if problems else 0)
