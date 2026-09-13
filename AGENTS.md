# SuperCollider skills collection

Keep the three public skills portable and independently understandable. Put mode-specific detail in linked references and executable examples in each skill; keep SKILL.md concise.

Validate changed helpers with actual runtime evidence. Use offline NRT renders for audio checks without opening hardware output. Check all TCP/UDP ports before starting services; use owned process groups and bounded timeouts, never global process-name kills.

Run `python3 scripts/validate.py` and `python3 -m unittest discover -s tests -v` before committing. Run the affected skill's documented runtime checks after behavioral changes. Keep generated media, private project sources, personal paths, credentials, and dependencies out of Git.

This repository is the public distribution source. Other catalogs may import reviewed versions; use targeted deployment with backups and record the revision instead of overwriting unrelated skills. Existing skill names remain stable.
