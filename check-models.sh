#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETUP_SCRIPT="$SCRIPT_DIR/ubuntu-prep-setup.sh"

if [ ! -f "$SETUP_SCRIPT" ]; then
    echo "❌ Cannot find ubuntu-prep-setup.sh to extract models."
    exit 1
fi

echo "📦 Extracting model lists from ubuntu-prep-setup.sh..."
# Dynamically extract and evaluate the get_model_recommendations function
eval "$(sed -n '/^get_model_recommendations() {/,/^}/p' "$SETUP_SCRIPT")"

VRAM_TIERS=(8 16 24 32 48 72 96)
OLLAMA_MODELS_RAW=("gemma4:e2b")
HF_MODELS_RAW=("unsloth/gemma-4-E2B-it-GGUF")

for vram in "${VRAM_TIERS[@]}"; do
    get_model_recommendations "ollama" "$vram"
    OLLAMA_MODELS_RAW+=("$REC_MODEL_CHAT" "$REC_MODEL_CODE" "$REC_MODEL_MOE" "$REC_MODEL_VISION")
    
    get_model_recommendations "llama" "$vram"
    HF_MODELS_RAW+=("$REC_MODEL_CHAT" "$REC_MODEL_CODE" "$REC_MODEL_MOE" "$REC_MODEL_VISION")
done

# Remove duplicates and empty entries
OLLAMA_MODELS=($(printf "%s\n" "${OLLAMA_MODELS_RAW[@]}" | sort -u | grep -v '^$'))
HF_MODELS=($(printf "%s\n" "${HF_MODELS_RAW[@]}" | sort -u | grep -v '^$'))
echo ""

echo "🔍 Checking Ollama Models..."
for model in "${OLLAMA_MODELS[@]}"; do
    base_model=$(echo "$model" | cut -d':' -f1)
    # The Ollama library returns 200 OK for valid base models
    status=$(curl -s -o /dev/null -w "%{http_code}" "https://ollama.com/library/$base_model")
    if [ "$status" -eq 200 ]; then
        echo -e "✅ [OK] $model"
    else
        echo -e "❌ [ERROR] $model (HTTP $status)"
    fi
done

echo -e "\n🔍 Checking Hugging Face (llama.cpp) Models..."

# Grab HF_TOKEN from .env.secrets if it exists
HF_TOKEN=$(bash -c "source \"$HOME/.env.secrets\" 2>/dev/null && echo \"\$HF_TOKEN\"" | tr -d '\r')

for repo in "${HF_MODELS[@]}"; do
    # Check /tree/main instead of the root to avoid false positives on empty placeholder repos
    curl_cmd=(curl -s -o /dev/null -w "%{http_code}")
    if [[ -n "$HF_TOKEN" ]]; then
        curl_cmd+=(-H "Authorization: Bearer $HF_TOKEN")
    fi
    curl_cmd+=("https://huggingface.co/api/models/$repo/tree/main")
    
    status=$("${curl_cmd[@]}")
    if [ "$status" -eq 200 ]; then
        echo -e "✅ [OK] $repo"
    elif [ "$status" -eq 401 ] || [ "$status" -eq 403 ]; then
        echo -e "🔒 [GATED] $repo (Requires HF_TOKEN and License Agreement)"
    else
        echo -e "❌ [ERROR] $repo (HTTP $status)"
    fi
done
