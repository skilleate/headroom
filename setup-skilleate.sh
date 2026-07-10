#!/usr/bin/env bash
# Install headroom-ai and apply Skilleate patches.
# Usage: bash <(curl -fsSL https://raw.githubusercontent.com/skilleate/headroom/main/setup-skilleate.sh)

set -euo pipefail

HEADROOM_VERSION="0.31.0"
PATCH_COMMIT="c3047d0a"  # skilleate/headroom fix: Claude Code list-format tool_result

# ── 1. Install headroom-ai via uv ─────────────────────────────────────────────
if ! command -v uv &>/dev/null; then
  echo "uv not found — install it first: https://docs.astral.sh/uv/getting-started/installation/"
  exit 1
fi

echo "Installing headroom-ai ${HEADROOM_VERSION}..."
uv tool install "headroom-ai==${HEADROOM_VERSION}"

# ── 2. Locate the installed package ───────────────────────────────────────────
SITE_PACKAGES=$(uv tool run headroom python -c "import headroom, os; print(os.path.dirname(headroom.__file__))" 2>/dev/null \
  || find ~/.local/share/uv/tools/headroom-ai -name "compression_cache.py" -path "*/cache/*" | head -1 | xargs dirname | xargs dirname)

CACHE_FILE="${SITE_PACKAGES}/headroom/cache/compression_cache.py"

if [[ ! -f "$CACHE_FILE" ]]; then
  # Fallback: search directly
  CACHE_FILE=$(find ~/.local/share/uv/tools -name "compression_cache.py" -path "*/headroom/cache/*" 2>/dev/null | head -1)
fi

if [[ ! -f "$CACHE_FILE" ]]; then
  echo "ERROR: could not locate headroom/cache/compression_cache.py"
  exit 1
fi

echo "Patching ${CACHE_FILE}..."

python3 - "$CACHE_FILE" <<'PYEOF'
import sys

path = sys.argv[1]
with open(path) as f:
    src = f.read()

if "Claude Code sends content as a list of text blocks" in src:
    print("  Already patched — skipping.")
    sys.exit(0)

old_extract = '''                if isinstance(inner, str):
                    return inner
    return None'''

new_extract = '''                if isinstance(inner, str):
                    return inner
                # Claude Code sends content as a list of text blocks:
                # [{"type": "text", "text": "..."}]
                if isinstance(inner, list):
                    parts = [
                        b.get("text", "")
                        for b in inner
                        if isinstance(b, dict) and b.get("type") == "text"
                    ]
                    if parts:
                        return "\\n".join(parts)
    return None'''

old_swap = '''            if isinstance(block, dict) and block.get("type") == "tool_result":
                block["content"] = new_content
                break'''

new_swap = '''            if isinstance(block, dict) and block.get("type") == "tool_result":
                inner = block.get("content")
                if isinstance(inner, list):
                    # Preserve list shape: replace with a single text block
                    block["content"] = [{"type": "text", "text": new_content}]
                else:
                    block["content"] = new_content
                break'''

assert old_extract in src, "Pattern 1 not found — headroom version may have changed"
assert old_swap in src, "Pattern 2 not found — headroom version may have changed"

src = src.replace(old_extract, new_extract).replace(old_swap, new_swap)
with open(path, "w") as f:
    f.write(src)

print("  Patch applied OK.")
PYEOF

# ── 3. Configure env vars ──────────────────────────────────────────────────────
PROFILE="${HOME}/.zprofile"
if [[ "$SHELL" == *"bash"* ]]; then
  PROFILE="${HOME}/.bash_profile"
fi

add_env() {
  local var="$1" val="$2"
  if ! grep -q "^export ${var}=" "$PROFILE" 2>/dev/null; then
    printf '\nexport %s=%s\n' "$var" "$val" >> "$PROFILE"
    echo "  Added ${var}=${val} to ${PROFILE}"
  else
    echo "  ${var} already set in ${PROFILE}"
  fi
}

echo "Configuring env vars in ${PROFILE}..."
add_env "HEADROOM_INTERCEPT_ENABLED" "1"
add_env "HEADROOM_NO_CCR"            "1"

# ── 4. Install ast-grep (required for Read outliner) ──────────────────────────
if ! command -v ast-grep &>/dev/null; then
  echo "Installing ast-grep..."
  if command -v brew &>/dev/null; then
    brew install ast-grep
  else
    echo "  brew not found — install ast-grep manually: https://ast-grep.github.io/guide/quick-start.html"
  fi
else
  echo "ast-grep already installed: $(ast-grep --version)"
fi

echo ""
echo "Done! Patch commit: ${PATCH_COMMIT}"
echo "Start a new terminal and run: headroom wrap claude"
