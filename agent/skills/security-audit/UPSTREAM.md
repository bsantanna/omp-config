# Upstream provenance

- Source: https://github.com/cloudflare/security-audit-skill
- Path: `skills/security-audit/`
- Commit: `c1c8a8c1471069fb0e188eeaff69b8e8db6564a8` (2026-09-14)
- License: MIT (see `LICENSE`)

All files are vendored verbatim except `SKILL.md`, which carries one appended
`## omp platform mapping` section. `UPSTREAM.md` and `LICENSE` are local
additions.

## Update procedure

```sh
git clone --depth 1 https://github.com/cloudflare/security-audit-skill.git /tmp/sas
cp /tmp/sas/skills/security-audit/* agent/skills/security-audit/
cp /tmp/sas/LICENSE agent/skills/security-audit/LICENSE
# re-append the omp platform mapping section to SKILL.md, then:
./import.sh
```

Update the commit line above to the new `git -C /tmp/sas rev-parse HEAD`.
