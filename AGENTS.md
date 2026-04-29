# Agent Instructions

- Treat this directory as a Git-managed deployment project.
- Keep real proxy credentials, `.env`, generated GOST runtime configs, and private keys out of Git.
- Use `scripts/validate.sh` before claiming the project is ready.
- Prefer Docker Compose for deployment; do not add a custom proxy implementation unless the user explicitly requests it.
