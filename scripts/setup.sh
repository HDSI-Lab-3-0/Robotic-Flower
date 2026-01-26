#!/usr/bin/env bash

set -euo pipefail

declare -r PYTHON_VERSION="3.12.12"
declare -r UV_VERSION="0.9.26"
declare -r PROJECT_NAME="robot-flower"
declare -r HIDDEN_ROOT="${HOME}/hidden"
declare -r PROJECT_DIR="${HIDDEN_ROOT}/${PROJECT_NAME}"
declare -r PUBLIC_DIR="${HOME}/${PROJECT_NAME}"
declare -r FINAL_CMD_PATH="${HOME}/.local/bin/final-version"

APT_PACKAGES=(
    build-essential
    curl
    pkg-config
    libssl-dev
    zlib1g-dev
    libbz2-dev
    libreadline-dev
    libsqlite3-dev
    libffi-dev
    liblzma-dev
    tk-dev
    uuid-dev
)

DEPENDENCIES=(
    "tensorflow==2.20.0"
    "opencv-python==4.13.0.90"
    "xarm==0.0.4"
    "hidapi==0.15.0"
    "numpy==1.26.4"
    "scikit-learn==1.8.0"
)

log() {
    printf '[INFO] %s\n' "$1"
}

fail() {
    printf '[ERROR] %s\n' "$1" >&2
    exit 1
}

trap 'fail "Command failed on line ${LINENO}."' ERR

ensure_path() {
    case ":$PATH:" in
        *":${HOME}/.local/bin:"*) ;;
        *) export PATH="${HOME}/.local/bin:$PATH" ;;
    esac
}

log "Updating apt package index..."
sudo apt-get update

log "Installing build prerequisites (may take a moment)..."
sudo apt-get install -y "${APT_PACKAGES[@]}"

ensure_path

log "Ensuring hidden workspace root exists..."
mkdir -p "${HIDDEN_ROOT}"

install_uv() {
    local current_version
    if command -v uv >/dev/null 2>&1; then
        current_version=$(uv --version | awk '{print $2}')
    else
        current_version=""
    fi

    if [[ "${current_version}" != "${UV_VERSION}" ]]; then
        log "Installing uv ${UV_VERSION} via the official installer..."
        curl -LsSf https://astral.sh/uv/install.sh | sh -s -- --version "v${UV_VERSION}"
    else
        log "uv ${UV_VERSION} already installed."
    fi

    command -v uv >/dev/null 2>&1 || fail "uv installation failed."
}

install_uv
UV_BIN="$(command -v uv)"

log "Ensuring CPython ${PYTHON_VERSION} is available via uv..."
"${UV_BIN}" python install "${PYTHON_VERSION}"

if [[ -d "${PROJECT_DIR}" ]]; then
    fail "${PROJECT_DIR} already exists. Move or remove it, then rerun the script."
fi

log "Initializing uv project at ${PROJECT_DIR}..."
"${UV_BIN}" init "${PROJECT_DIR}"

cd "${PROJECT_DIR}"

log "Pinning the project to CPython ${PYTHON_VERSION}..."
"${UV_BIN}" python pin "${PYTHON_VERSION}"

log "Creating the base environment..."
"${UV_BIN}" sync

log "Adding all required dependencies with pinned versions..."
for dep in "${DEPENDENCIES[@]}"; do
    log "Adding ${dep}"
    "${UV_BIN}" add "${dep}"

done

log "Environment ready at ${PROJECT_DIR}."
log "Installing final-version helper command..."
mkdir -p "$(dirname "${FINAL_CMD_PATH}")"
cat > "${FINAL_CMD_PATH}" <<EOF
#!/usr/bin/env bash
set -euo pipefail
SOURCE_DIR="${PROJECT_DIR}"
TARGET_DIR="${PUBLIC_DIR}"

if [[ ! -d "${PROJECT_DIR}" ]]; then
    printf '[ERROR] Hidden project not found at %s\n' "${PROJECT_DIR}" >&2
    exit 1
fi

if [[ -d "${PUBLIC_DIR}" ]]; then
    rm -rf "${PUBLIC_DIR}"
fi

cp -R "${PROJECT_DIR}" "${PUBLIC_DIR}"
printf '[INFO] Copied robotic flower env to %s\n' "${PUBLIC_DIR}"
printf '[INFO] Use uv commands inside the copied directory, e.g.: cd %s && uv run python smile_detection_robot.py\n' "${PUBLIC_DIR}"
EOF
chmod +x "${FINAL_CMD_PATH}"

log "Hidden environment ready at ${PROJECT_DIR}."
log "When you're ready to expose it, run: final-version"
log "This copies the env into ${PUBLIC_DIR} where you can run uv commands directly."
