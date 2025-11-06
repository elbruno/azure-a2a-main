#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
VENV_DIR="${REPO_ROOT}/.venv"
BACKEND_DIR="${REPO_ROOT}/backend"
FRONTEND_DIR="${REPO_ROOT}/frontend"
LOG_DIR="${REPO_ROOT}/.logs"
ENV_FILE="${REPO_ROOT}/.env"
ENV_TEMPLATE="${REPO_ROOT}/.env.example"
START_SCRIPT="${SCRIPT_DIR}/start-all.sh"

INSTALL=true
START=true
SKIP_FRONTEND=false
SKIP_BACKEND=false

usage() {
  cat <<'EOF'
Usage: bootstrap.sh [options]

Options:
  --install-only       Install dependencies but do not start services.
  --start-only         Start services assuming dependencies are installed.
  --skip-frontend      Skip frontend dependency install/start.
  --skip-backend       Skip backend dependency install/start.
  -h, --help           Show this message.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --install-only)
      START=false
      shift
      ;;
    --start-only)
      INSTALL=false
      shift
      ;;
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

ensure_env_file() {
  if [[ ! -f "${ENV_FILE}" && -f "${ENV_TEMPLATE}" ]]; then
    cp "${ENV_TEMPLATE}" "${ENV_FILE}"
    echo "Created ${ENV_FILE} from template. Please review and update secrets." >&2
  fi
}

create_virtualenv() {
  if [[ "${SKIP_BACKEND}" == "true" ]]; then
    return
  fi

  if [[ ! -x "$(command -v python3 || true)" ]]; then
    echo "python3 is not available. Please install Python 3.12+ inside the container." >&2
    exit 1
  fi

  if [[ ! -d "${VENV_DIR}" ]]; then
    python3 -m venv "${VENV_DIR}"
  fi

  # shellcheck source=/dev/null
  source "${VENV_DIR}/bin/activate"
  python -m pip install --upgrade pip wheel
  pip install -r "${BACKEND_DIR}/requirements.txt"
  deactivate
}

install_frontend() {
  if [[ "${SKIP_FRONTEND}" == "true" ]]; then
    return
  fi

  if [[ ! -x "$(command -v npm || true)" ]]; then
    echo "npm is not available. Please install Node.js 20+ inside the container." >&2
    exit 1
  fi

  pushd "${FRONTEND_DIR}" >/dev/null
  npm install
  popd >/dev/null
}

install_dependencies() {
  ensure_env_file
  mkdir -p "${LOG_DIR}"

  if [[ "${SKIP_BACKEND}" != "true" ]]; then
    create_virtualenv
  fi

  if [[ "${SKIP_FRONTEND}" != "true" ]]; then
    install_frontend
  fi
}

start_services() {
  if [[ ! -x "${START_SCRIPT}" ]]; then
    echo "Start script ${START_SCRIPT} missing or not executable." >&2
    exit 1
  fi

  if [[ "${SKIP_BACKEND}" == "true" ]]; then
    START_ARGS+=("--skip-backend")
  fi
  if [[ "${SKIP_FRONTEND}" == "true" ]]; then
    START_ARGS+=("--skip-frontend")
  fi

  bash "${START_SCRIPT}" "${START_ARGS[@]}"
}

if [[ "${INSTALL}" == true ]]; then
  install_dependencies
fi

if [[ "${START}" == true ]]; then
  START_ARGS=()
  start_services
fi
