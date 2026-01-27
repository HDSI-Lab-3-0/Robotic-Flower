#!/usr/bin/env bash

set -euo pipefail

readonly PYTHON_VERSION="3.13.11"
readonly PROJECT_NAME="robot-flower"
readonly HIDDEN_ROOT="${HOME}/.hidden"
readonly PROJECT_DIR="${HIDDEN_ROOT}/${PROJECT_NAME}"
readonly PUBLIC_DIR="${HOME}/${PROJECT_NAME}"
readonly FINAL_CMD_PATH="${HOME}/.local/bin/final-version"

export UV_PYTHON_VERSION="${PYTHON_VERSION}"
export UV_PYTHON="cpython@${PYTHON_VERSION}"
export UV_PROJECT_ENVIRONMENT="${PROJECT_DIR}/.venv"

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
    "xarm-python-sdk==1.17.3"
    "hidapi==0.15.0"
    "numpy==2.4.1"
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

persist_local_bin_path() {
    local export_line='export PATH="$HOME/.local/bin:$PATH"'
    local rc_files=(
        "${HOME}/.bashrc"
        "${HOME}/.bash_profile"
        "${HOME}/.profile"
        "${HOME}/.zshrc"
    )
    local updated=0

    for rc in "${rc_files[@]}"; do
        if [[ -f "${rc}" ]]; then
            if ! grep -Fq "${export_line}" "${rc}"; then
                {
                    printf '\n# Added by %s setup to expose final-version command\n' "${PROJECT_NAME}"
                    printf '%s\n' "${export_line}"
                } >> "${rc}"
            fi
            updated=1
        fi
    done

    if [[ "${updated}" -eq 0 ]]; then
        {
            printf '# Added by %s setup to expose final-version command\n' "${PROJECT_NAME}"
            printf '%s\n' "${export_line}"
        } >> "${HOME}/.profile"
    fi
}

log "Updating apt package index..."
sudo apt-get update

log "Installing build prerequisites (may take a moment)..."
sudo apt-get install -y "${APT_PACKAGES[@]}"

ensure_path
persist_local_bin_path

log "Ensuring hidden workspace root exists..."
mkdir -p "${HIDDEN_ROOT}"

if [[ -d "${PROJECT_DIR}" ]]; then
    log "Removing existing project directory at ${PROJECT_DIR}..."
    rm -rf "${PROJECT_DIR}"
fi

install_uv() {
    local current_version
    if command -v uv >/dev/null 2>&1; then
        current_version=$(uv --version | awk '{print $2}')
    else
        current_version=""
    fi

    if [[ -z "${current_version}" ]]; then
        log "Installing latest uv via Astral installer..."
    else
        log "Updating uv to the latest release via Astral installer (current: ${current_version})..."
    fi

    curl -LsSf https://astral.sh/uv/install.sh | sh
    ensure_path
    hash -r 2>/dev/null || true

    command -v uv >/dev/null 2>&1 || fail "uv installation failed."
}

install_uv
UV_BIN="$(command -v uv)"

log "Ensuring CPython ${PYTHON_VERSION} is available via uv..."
"${UV_BIN}" python install "${PYTHON_VERSION}"

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
