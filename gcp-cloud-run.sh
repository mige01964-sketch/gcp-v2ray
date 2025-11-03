#!/bin/bash

set -euo pipefail

# --- Configuration Constants ---
DEFAULT_DEPLOY_DURATION="5h" # ၅ နာရီ (MST)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Region list for selection
declare -A REGIONS=(
    [1]="us-central1|Iowa, USA|🇺🇸"
    [2]="us-west1|Oregon, USA|🇺🇸"
    [3]="us-east1|South Carolina, USA|🇺🇸"
    [4]="europe-west1|Belgium|🇧🇪"
    [5]="asia-southeast1|Singapore|🇸🇬"
    [6]="asia-southeast2|Indonesia|🇮🇩"
    [7]="asia-northeast1|Tokyo, Japan|🇯🇵"
    [8]="asia-east1|Taiwan|🇹🇼"
    [9]="australia-southeast1|Sydney, Australia|🇦🇺"
    [10]="southamerica-east1|São Paulo, Brazil|🇧🇷"
    [11]="northamerica-northeast1|Montreal, Canada|🇨🇦"
    [12]="africa-south1|Johannesburg, South Africa|🇿🇦"
    [13]="asia-south1|Mumbai, India|🇮🇳"
)

log() { echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }
info() { echo -e "${BLUE}[INFO]${NC} $1"; }

# Validation functions
validate_uuid() { ... }
validate_bot_token() { ... }
validate_ids() { ... }
validate_url() { ... }
# (functions body same as original)

select_cpu() { ... }
select_memory() { ... }
validate_memory_config() { ... }
select_region() { ... }

select_telegram_destination() { ... }

get_channel_url() { ... }

get_user_input() { ... }

show_config_summary() { ... }

validate_prerequisites() { ... }

cleanup() { ... }

send_to_telegram() {
    local chat_id="$1"
    local message="$2"
    local keyboard="$3"
    local response
    response=$(curl -s -w "%{http_code}" -X POST \
        -H "Content-Type: application/json" \
        -d "{
            \"chat_id\": \"${chat_id}\",
            \"text\": \"$message\",
            \"parse_mode\": \"MarkdownV2\",
            \"disable_web_page_preview\": true,
            \"reply_markup\": $keyboard
        }" \
        https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage)
    local http_code="${response: -3}"
    local content="${response%???}"
    if [[ "$http_code" == "200" ]]; then
        return 0
    else
        error "Failed to send to Telegram (HTTP $http_code) for chat ID $chat_id: $content"
        return 1
    fi
}

send_deployment_notification() {
    local message="$1"
    local keyboard="$2"
    local success_count=0
    case $TELEGRAM_DESTINATION in
        "channel"|"both")
            log "Sending to Telegram Channel(s)..."
            IFS=',' read -r -a CHANNEL_IDS <<< "$TELEGRAM_CHANNEL_ID"
            for id in "${CHANNEL_IDS[@]}"; do
                if send_to_telegram "$id" "$message" "$keyboard"; then
                    log "✅ Sent to Channel ID: $id"
                    success_count=$((success_count + 1))
                else
                    error "❌ Failed to Channel ID: $id"
                fi
            done
            ;;
    esac
    case $TELEGRAM_DESTINATION in
        "bot"|"both")
            log "Sending to Bot private message(s)..."
            IFS=',' read -r -a CHAT_IDS <<< "$TELEGRAM_CHAT_ID"
            for id in "${CHAT_IDS[@]}"; do
                if send_to_telegram "$id" "$message" "$keyboard"; then
                    log "✅ Sent to Bot ID: $id"
                    success_count=$((success_count + 1))
                else
                    error "❌ Failed to Bot ID: $id"
                fi
            done
            ;;
    esac
    if [[ $success_count -gt 0 ]]; then
        log "Telegram notification completed ($success_count successful)"
        return 0
    else
        warn "All Telegram notifications failed"
        return 1
    fi
}

main() {
    info "=== GCP Cloud Run V2Ray Deployment ==="

    select_region
    select_cpu
    select_memory
    select_telegram_destination
    get_user_input
    show_config_summary

    PROJECT_ID=$(gcloud config get-value project)

    log "Starting Cloud Run deployment..."

    validate_prerequisites

    trap cleanup EXIT

    log "Enabling required APIs..."
    gcloud services enable \
        cloudbuild.googleapis.com \
        run.googleapis.com \
        iam.googleapis.com \
        --quiet

    cleanup

    log "Cloning repository..."
    if ! git clone https://github.com/KaungSattKyaw/gcp-v2ray.git; then
        error "Failed to clone repository"
        exit 1
    fi
    cd gcp-v2ray

    log "Building container image..."
    if ! gcloud builds submit --tag gcr.io/${PROJECT_ID}/gcp-v2ray-image --quiet; then
        error "Build failed"
        exit 1
    fi

    log "Deploying to Cloud Run..."
    if ! gcloud run deploy ${SERVICE_NAME} \
        --image gcr.io/${PROJECT_ID}/gcp-v2ray-image \
        --platform managed \
        --region ${REGION} \
        --allow-unauthenticated \
        --cpu ${CPU} \
        --memory ${MEMORY} \
        --quiet; then
        error "Deployment failed"
        exit 1
    fi

    SERVICE_URL=$(gcloud run services describe ${SERVICE_NAME} \
        --region ${REGION} \
        --format 'value(status.url)' \
        --quiet)

    DOMAIN=$(echo $SERVICE_URL | sed 's|https://||')

    # --- TIMING (မြန်မာစံတော်ချိန်) ---
    export TZ='Asia/Yangon'
    now_epoch=$(date +%s)
    start_time=$(date -d @$now_epoch +"%b %d, %I:%M %p (MST)")
    expiry_epoch=$((now_epoch + 5*3600))
    expiry_time=$(date -d @$expiry_epoch +"%b %d, %I:%M %p (MST)")
    unset TZ

    VLESS_LINK="vless://${UUID}@${HOST_DOMAIN}:443?path=%2Ftgkmks26381Mr&security=tls&alpn=none&encryption=none&host=${DOMAIN}&type=ws&sni=${DOMAIN}#${SERVICE_NAME}"
    QR_LINK="https://api.qrserver.com/v1/create-qr-code/?data=${VLESS_LINK}"

    # ----------- MODERN TELEGRAM MESSAGE -----------
    MESSAGE="
━━━━━━━━━━━━━━━━━━━━━━
🚀 *Deploy Completed!* 🚀

━━━━━━━━━━━━━━━━━━━━━━
📆 *စတင်ချိန်:* \`${start_time}\`
⏰ *ပြီးဆုံးချိန်:* \`${expiry_time}\`
━━━━━━━━━━━━━━━━━━━━━━

✨ *Service Details*
• *Project:* \`${PROJECT_ID}\`
• *Service:* \`${SERVICE_NAME}\`
• *Region:* ${FLAG_EMOJI} \`${REGION}\` (_${REGION_NAME}_)
• *CPU:* \`${CPU}\` • *RAM:* \`${MEMORY}\`
• *Domain:* [${DOMAIN}](https://${DOMAIN})

━━━━━━━━━━━━━━━━━━━━━━
🔗 *Vless Link:*
\`\`\`
${VLESS_LINK}
\`\`\`
━━━━━━━━━━━━━━━━━━━━━━

📝 *အသုံးပြုနည်း လမ်းညွှန်*
1️⃣ 🔗 link ကို copy အသုံးပြုပါ။
2️⃣ 📱 သုံး app ကိုဖွင့် clipboard import လုပ်ပါ။
3️⃣ ✅ ချိတ်ပြီး အသုံးပြုပါ။
━━━━━━━━━━━━━━━━━━━━━━

🔰 *Quick Actions:*
[🔗 Channel](${CHANNEL_URL})
[📖 Guide](https://docs.yourapp.com/deploy)
[🛠 Support](https://t.me/support_channel)
━━━━━━━━━━━━━━━━━━━━━━

*Scan QR to import:*  
${QR_LINK}
"

    KEYBOARD=$(cat << EOF
{
  "inline_keyboard": [
    [
      {"text": "🔗 Copy Link", "url": "${VLESS_LINK}"},
      {"text": "📺 Channel", "url": "${CHANNEL_URL}"}
    ],
    [
      {"text": "📖 Guide", "url": "https://docs.yourapp.com/deploy"},
      {"text": "🛠 Support", "url": "https://t.me/support_channel"}
    ],
    [
      {"text": "🖼 QR Import", "url": "${QR_LINK}"}
    ]
  ]
}
EOF
)

    echo "$MESSAGE" > deployment-info.txt
    log "Deployment info saved to deployment-info.txt"

    echo
    info "=== Deployment Information ==="
    echo "$MESSAGE"
    echo

    if [[ "$TELEGRAM_DESTINATION" != "none" ]]; then
        log "Sending deployment info to Telegram..."
        send_deployment_notification "$MESSAGE" "$KEYBOARD"
    else
        log "Skipping Telegram notification as per user selection"
    fi

    log "Deployment completed successfully!"
    log "Service URL: $SERVICE_URL"
    log "Configuration saved to: deployment-info.txt"
    log "QR Link: $QR_LINK"
}

main "$@"
