#!/usr/bin/env bash
# Check that every external install URL in ubuntu-prep-setup.sh is still reachable.
#
# Strategy:
#   1. Extract literal URLs from the script (skipping anything parameterized).
#   2. Filter out localhost/private IPs and obvious placeholders.
#   3. HEAD-check each URL. Fall back to GET if HEAD is rejected (some CDNs do this).
#   4. Separately check a curated list of parameterized URLs with known
#      substitutions (cuDNN version, Ubuntu version, etc.) — these are the
#      URLs most likely to break silently because NVIDIA/NodeSource move
#      binaries between versions.
#
# Exits 0 if every URL returned a success status, non-zero otherwise.

set -u
# NOTE: no `set -e` here — we want to collect all failures, not bail on first.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_SCRIPT="${SCRIPT_DIR}/../ubuntu-prep-setup.sh"

if [[ ! -f "$TARGET_SCRIPT" ]]; then
    echo "❌ Cannot find ubuntu-prep-setup.sh at $TARGET_SCRIPT"
    exit 2
fi

# Curated parameterized URLs — substitute known values so we can check them.
# Keep these in sync with the script's pinned versions.
CUDNN_VERSION="9.21.0"
CUDA_UBUNTU_VERSION="2404"  # also commonly 2204; script handles both
NVIDIA_DRIVER_VERSION="595.58.03"

CURATED_URLS=(
    "https://developer.download.nvidia.com/compute/cuda/repos/ubuntu${CUDA_UBUNTU_VERSION}/x86_64/cuda-keyring_1.1-1_all.deb"
    "https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-keyring_1.1-1_all.deb"
    "https://developer.download.nvidia.com/compute/cudnn/${CUDNN_VERSION}/local_installers/cudnn-local-repo-ubuntu${CUDA_UBUNTU_VERSION}-${CUDNN_VERSION}_1.0-1_amd64.deb"
    "https://developer.download.nvidia.com/compute/cudnn/${CUDNN_VERSION}/local_installers/cudnn-local-repo-ubuntu2204-${CUDNN_VERSION}_1.0-1_amd64.deb"
    "https://us.download.nvidia.com/XFree86/Linux-x86_64/${NVIDIA_DRIVER_VERSION}/NVIDIA-Linux-x86_64-${NVIDIA_DRIVER_VERSION}.run"
)

# Extract literal URLs from the script, then strip artifacts.
RAW_URLS=()
while IFS= read -r line; do
    RAW_URLS+=("$line")
done < <(
    grep -oE 'https?://[^"'"'"' )<>]+' "$TARGET_SCRIPT" \
        | sed -E 's/\\e\[[0-9;]*m.*$//' \
        | sed -E 's/[\\.,]+$//' \
        | sed -E 's/}+$//' \
        | sort -u
)

# Filter rules:
#   - drop anything with shell-variable expansion or stray braces
#   - drop localhost/loopback/docker-internal/private ranges
#   - drop obvious placeholders
#   - drop URLs that are just fragments or punctuation left over
SKIP_PATTERNS=(
    '\$'                             # any shell variable
    '\{'                             # opening brace (parameterized)
    '\}$'                            # stray closing brace
    '^https?://(localhost|127\.|10\.|192\.168\.|host\.docker\.internal)'
    'yourdomain\.com'
    '^https?://#'                    # fragment-only artifacts
    '^https?://,$'                   # literal trailing comma
    '^https?://$'                    # empty host
)

is_skipped() {
    local url="$1" pat
    for pat in "${SKIP_PATTERNS[@]}"; do
        if [[ "$url" =~ $pat ]]; then
            return 0
        fi
    done
    return 1
}

declare -a TO_CHECK=()
for url in "${RAW_URLS[@]}"; do
    [[ -z "$url" ]] && continue
    if is_skipped "$url"; then
        continue
    fi
    TO_CHECK+=("$url")
done

# Merge in curated parameterized URLs
for url in "${CURATED_URLS[@]}"; do
    TO_CHECK+=("$url")
done

# De-duplicate again after merging
DEDUP=()
while IFS= read -r line; do
    DEDUP+=("$line")
done < <(printf '%s\n' "${TO_CHECK[@]}" | sort -u)
TO_CHECK=("${DEDUP[@]}")

check_url() {
    local url="$1"
    local code
    # Try HEAD first (fast, no body); some CDNs reject HEAD so retry with GET
    code=$(curl -fsSL -o /dev/null -I --max-time 15 --retry 2 --retry-delay 2 \
        -w '%{http_code}' "$url" 2>/dev/null || true)
    if [[ "$code" =~ ^(2|3)[0-9]{2}$ ]]; then
        echo "$code"
        return 0
    fi
    # Retry with GET (use Range to avoid downloading full body)
    code=$(curl -fsSL -o /dev/null --max-time 15 --retry 2 --retry-delay 2 \
        -H 'Range: bytes=0-0' \
        -w '%{http_code}' "$url" 2>/dev/null || true)
    echo "${code:-000}"
    [[ "$code" =~ ^(2|3)[0-9]{2}$ ]]
}

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " Ubuntu-Prep install-URL reachability check"
echo " Script:   $TARGET_SCRIPT"
echo " URLs to check: ${#TO_CHECK[@]}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

FAILURES=()
for url in "${TO_CHECK[@]}"; do
    status=$(check_url "$url")
    if [[ "$status" =~ ^(2|3)[0-9]{2}$ ]]; then
        printf '  [OK  %s] %s\n' "$status" "$url"
    else
        printf '  [FAIL %s] %s\n' "$status" "$url"
        FAILURES+=("$status $url")
    fi
done

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [[ ${#FAILURES[@]} -eq 0 ]]; then
    echo " ✅ All ${#TO_CHECK[@]} URLs reachable."
    exit 0
else
    echo " ❌ ${#FAILURES[@]} of ${#TO_CHECK[@]} URL(s) failed:"
    for f in "${FAILURES[@]}"; do
        echo "     $f"
    done
    exit 1
fi
