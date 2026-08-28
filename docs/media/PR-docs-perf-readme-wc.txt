PR-docs README byte size vs trunk, 2026-08-28.

Head working copy / pr-docs README.md:
6182 bytes (wc -c)

Trunk origin/main `8bd3b24` has no README.md.
git show origin/main:README.md fails.

The 4000-byte growth rule cannot apply against an absent trunk file. Checking the box would treat 6182 vs 0 as a pass. Do not check the perf boxes.
