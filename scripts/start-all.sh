#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
VENV_DIR="${REPO_ROOT}/.venv"
BACKEND_DIR="${REPO_ROOT}/backend"
FRONTEND_DIR="${REPO_ROOT}/frontend"
LOG_DIR="${REPO_ROOT}/.logs"
BACKEND_LOG="${LOG_DIR}/backend.log"
FRONTEND_LOG="${LOG_DIR}/frontend.log"
TEE_CMD=(tee -a)

if command -v stdbuf >/dev/null 2>&1; then
  TEE_CMD=(stdbuf -oL tee -a)
fi

SKIP_FRONTEND=false
SKIP_BACKEND=false

usage() {
  cat <<'EOF'
Usage: start-all.sh [options]

Options:
  --skip-frontend   Do not start the Next.js frontend.
  --skip-backend    Do not start the FastAPI backend.
  -h, --help        Show this message.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-frontend)
      SKIP_FRONTEND=true
      shift
      ;;
    --skip-backend)
      SKIP_BACKEND=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

mkdir -p "${LOG_DIR}"

BACKEND_PID=""
FRONTEND_PID=""

cleanup() {
  trap - INT TERM EXIT
  if [[ -n "${FRONTEND_PID}" ]] && kill -0 "${FRONTEND_PID}" 2>/dev/null; then
    echo "Stopping frontend (PID ${FRONTEND_PID})"
    kill "${FRONTEND_PID}" 2>/dev/null || true
    wait "${FRONTEND_PID}" 2>/dev/null || true
  fi
  if [[ -n "${BACKEND_PID}" ]] && kill -0 "${BACKEND_PID}" 2>/dev/null; then
    echo "Stopping backend (PID ${BACKEND_PID})"
    kill "${BACKEND_PID}" 2>/dev/null || true
    wait "${BACKEND_PID}" 2>/dev/null || true
  fi
}

trap cleanup INT TERM EXIT

start_backend() {
  if [[ "${SKIP_BACKEND}" == "true" ]]; then
    return
  fi

  local python_bin
  if [[ -f "${VENV_DIR}/bin/python" ]]; then
    python_bin="${VENV_DIR}/bin/python"
  else
    python_bin="$(command -v python3 || true)"
  fi

  if [[ -z "${python_bin}" ]]; then
    echo "Unable to locate python interpreter." >&2
    exit 1
  fi

  echo "Starting backend (logging to ${BACKEND_LOG})"
  (cd "${BACKEND_DIR}" && "${python_bin}" backend_production.py) \
    | "${TEE_CMD[@]}" "${BACKEND_LOG}" &
  BACKEND_PID=$!
}

start_frontend() {
  if [[ "${SKIP_FRONTEND}" == "true" ]]; then
    return
  fi

  if [[ ! -x "$(command -v npm || true)" ]]; then
    echo "npm not available." >&2
    exit 1
  fi

  echo "Starting frontend (logging to ${FRONTEND_LOG})"
  (cd "${FRONTEND_DIR}" && npm run dev) \
    | "${TEE_CMD[@]}" "${FRONTEND_LOG}" &
  FRONTEND_PID=$!
}

if [[ "${SKIP_BACKEND}" == "true" && "${SKIP_FRONTEND}" == "true" ]]; then
  echo "Nothing to start." >&2
  exit 0
fi

start_backend
start_frontend

PIDS=()
if [[ -n "${BACKEND_PID}" ]]; then
  PIDS+=("${BACKEND_PID}")
fi
if [[ -n "${FRONTEND_PID}" ]]; then
  PIDS+=("${FRONTEND_PID}")
fi

if [[ ${#PIDS[@]} -eq 0 ]]; then
  echo "No services running." >&2
  exit 0
fi

echo "Services running. Press Ctrl+C to stop. Logs available under ${LOG_DIR}."
wait -n "${PIDS[@]}"
echo "Process exited. Shutting down remaining services..."
