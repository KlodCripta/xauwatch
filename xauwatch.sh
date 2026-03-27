#!/bin/bash
# ─────────────────────────────────────────────────────────────────
#  XAUWATCH  |  Real-time Gold Price Monitor  |  by Klod Cripta
#  Live: Swissquote | Storico: freegoldapi.com
# ─────────────────────────────────────────────────────────────────

LIVE_API="https://forex-data-feed.swissquote.com/public-quotes/bboquotes/instrument/XAU/USD"
HIST_API="https://freegoldapi.com/data/latest.csv"

MIN_COLS=62
MIN_ROWS=48

# ── ANSI ──────────────────────────────────────────────────────────
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
ORANGE='\033[38;5;214m'
CYAN='\033[1;36m'
BLUE='\033[1;34m'
FRAME='\033[0;37m'
WHITE='\033[1;37m'
GRAY='\033[0;37m'

# W = larghezza interna box (tra ║ e ║), esclusi i due bordi
W=58

# ── RETE: bytes RX/TX ────────────────────────────────────────────
net_iface() {
    if [[ "$(uname)" == "Darwin" ]]; then
        networksetup -listallhardwareports 2>/dev/null \
            | awk '/Wi-Fi/{found=1} found && /Device:/{print $2; exit}'
    else
        ip link show 2>/dev/null \
            | awk -F: '/wl[a-z0-9]+.*UP/{gsub(/ /,"",$2); print $2; exit}'
    fi
}

net_bytes() {
    local iface="$1"
    if [[ "$(uname)" == "Darwin" ]]; then
        netstat -ib 2>/dev/null \
            | awk -v i="$iface" '$1==i && $7~/^[0-9]+$/ {print $7, $10; exit}'
    else
        awk -v i="$iface:" '$0~i {gsub(/[^0-9 ]/," "); print $2, $10}' \
            /proc/net/dev 2>/dev/null
    fi
}

fmt_speed() {
    python3 -c "
v=$1
if v>=1048576: print(f'{v/1048576:.1f} MB/s')
elif v>=1024:  print(f'{v/1024:.1f} KB/s')
else:          print(f'{v:.0f} B/s')
" 2>/dev/null || echo "—"
}

# ── SPARKLINE ─────────────────────────────────────────────────────
build_sparkline() {
    [ "${#@}" -eq 0 ] && echo "—" && return
    python3 -c "
import sys
vals = [float(x) for x in '$*'.split()]
if len(vals) < 2:
    print('·')
    sys.exit()
mn, mx = min(vals), max(vals)
rng = mx - mn if mx != mn else 1
blocks = ' ▁▂▃▄▅▆▇█'
out = ''
for v in vals:
    idx = int((v - mn) / rng * 8)
    idx = max(0, min(8, idx))
    out += blocks[idx]
w = $W - 2          # 2 spazi margine
if len(out) < w:
    pad = (w - len(out)) // 2
    out = ' ' * pad + out + ' ' * (w - len(out) - pad)
print(out[:w])
" 2>/dev/null
}

# ── CANDELE ASCII — M1 (60s), rosso/verde ────────────────────────
CANDLE_SEC=60
CANDLE_MAX=22    # più candele grazie al box più largo

build_candles() {
    local data="$1"
    [ -z "$data" ] && echo "  nessun dato" && return
    # Python gestisce interamente il padding: niente ${#vis} in Bash
    python3 -c "
import sys, re

GREEN  = '\033[1;32m'
RED    = '\033[1;31m'
RESET  = '\033[0m'
W      = $W          # larghezza interna box

data = '$data'.split()
candles = []
for d in data:
    p = d.split('|')
    if len(p) == 4:
        try: candles.append([float(x) for x in p])
        except: pass
if not candles:
    print('  nessun dato')
    sys.exit()

all_vals = [v for c in candles for v in c]
mn, mx   = min(all_vals), max(all_vals)
rng      = mx - mn if mx != mn else 1
H        = 5

rows_chars  = [[] for _ in range(H)]
rows_colors = [[] for _ in range(H)]

for o, h, l, c in candles:
    def norm(v):
        return int((v - mn) / rng * (H - 1))
    ni_h = norm(h); ni_l = norm(l)
    ni_o = norm(o); ni_c = norm(c)
    body_top    = max(ni_o, ni_c)
    body_bottom = min(ni_o, ni_c)
    bullish = c >= o
    col = GREEN if bullish else RED
    for row in range(H):
        r = H - 1 - row
        if body_bottom <= r <= body_top:
            ch = '█' if bullish else '░'
        elif ni_l <= r <= ni_h:
            ch = '│'
        else:
            ch = ' '
        rows_chars[row].append(ch)
        rows_colors[row].append(col if ch != ' ' else '')

price_top = mn + rng
price_bot = mn
ansi_re   = re.compile(r'\033\[[0-9;]*m')

for i in range(H):
    if i == 0:
        prefix = f'  {price_top:>8.1f} '
    elif i == H - 1:
        prefix = f'  {price_bot:>8.1f} '
    else:
        prefix = '           '
    colored = prefix
    for ch, col in zip(rows_chars[i], rows_colors[i]):
        colored += (col + ch + RESET) if col else ch
    # Lunghezza visibile reale (senza ANSI)
    vis_len = len(ansi_re.sub('', colored))
    pad = W - vis_len
    if pad < 0: pad = 0
    sys.stdout.write(colored + ' ' * pad + '\n')
" 2>/dev/null
}

# ── CONTROLLO DIMENSIONI ──────────────────────────────────────────
check_size() {
    local cols rows
    cols=$(tput cols); rows=$(tput lines)
    if [ "$cols" -lt "$MIN_COLS" ] || [ "$rows" -lt "$MIN_ROWS" ]; then
        clear; tput cnorm
        echo ""
        echo -e "  ${RED}${BOLD}⚠  FINESTRA TROPPO PICCOLA${RESET}"
        echo ""
        echo -e "  ${GRAY}Dimensione attuale :${RESET}  ${WHITE}${cols} × ${rows}${RESET}"
        echo -e "  ${GRAY}Dimensione minima  :${RESET}  ${WHITE}${MIN_COLS} × ${MIN_ROWS}${RESET}"
        echo ""
        echo -e "  ${DIM}Allarga la finestra del terminale per continuare.${RESET}"
        echo ""
        return 1
    fi
    return 0
}

# ── RIQUADRI (grigi, W=58) ────────────────────────────────────────
hr_top() { printf "${FRAME}╔"; printf '═%.0s' $(seq 1 $W); printf "╗${RESET}\n"; }
hr_mid() { printf "${FRAME}╠"; printf '═%.0s' $(seq 1 $W); printf "╣${RESET}\n"; }
hr_bot() { printf "${FRAME}╚"; printf '═%.0s' $(seq 1 $W); printf "╝${RESET}\n"; }
hr_sep() { printf "${FRAME}║"; printf '─%.0s' $(seq 1 $W); printf "${FRAME}║${RESET}\n"; }

# ── HEADER ────────────────────────────────────────────────────────
print_header() {
    clear
    echo ""
    echo -e "${YELLOW}${BOLD}  ██╗  ██╗ █████╗ ██╗   ██╗${WHITE}    ██╗    ██╗ █████╗ ████████╗ ██████╗██╗  ██╗${RESET}"
    echo -e "${YELLOW}${BOLD}   ╚██╗██╔╝██╔══██╗██║   ██║${WHITE}    ██║    ██║██╔══██╗╚══██╔══╝██╔════╝██║  ██║${RESET}"
    echo -e "${YELLOW}${BOLD}    ╚███╔╝ ███████║██║   ██║${WHITE}    ██║ █╗ ██║███████║   ██║   ██║     ███████║${RESET}"
    echo -e "${YELLOW}${BOLD}    ██╔██╗ ██╔══██║██║   ██║${WHITE}    ██║███╗██║██╔══██║   ██║   ██║     ██╔══██║${RESET}"
    echo -e "${YELLOW}${BOLD}   ██╔╝ ██╗██║  ██║╚██████╔╝${WHITE}    ╚███╔███╔╝██║  ██║   ██║   ╚██████╗██║  ██║${RESET}"
    echo -e "${YELLOW}${BOLD}   ╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝${WHITE}     ╚══╝╚══╝ ╚═╝  ╚═╝   ╚═╝    ╚═════╝╚═╝  ╚═╝${RESET}"
    echo ""
    printf "  ${ORANGE}${BOLD}Live XAU/USD monitor for terminal${RESET}  ${GREEN}${BOLD}v1.0${RESET}  ${WHITE}|  Klod Cripta${RESET}\n"
    printf "  ${GRAY}$(printf '─%.0s' $(seq 1 56))${RESET}\n"
    echo ""
}

# ── FETCH STORICO ─────────────────────────────────────────────────
fetch_historical() {
    hr_top
    printf "${FRAME}║${RESET}  ${GRAY}Carico riferimenti storici...%-27s${FRAME}║${RESET}\n" ""
    hr_bot

    local hist_data today_str month_str result
    hist_data=$(curl -s --max-time 8 "$HIST_API")
    today_str=$(date +"%Y-%m-%d")
    month_str=$(date +"%Y-%m")

    result=$(echo "$hist_data" | python3 -c "
import sys
today, month = '$today_str', '$month_str'
ref_today = ref_month = ''
for line in sys.stdin:
    l = line.strip()
    if not l: continue
    parts = l.split(',')
    if len(parts) < 2: continue
    if not ref_today and parts[0].startswith(today):
        ref_today = parts[1].strip()
    if not ref_month and parts[0].startswith(month):
        ref_month = parts[1].strip()
    if ref_today and ref_month:
        break
print(ref_today + '|' + ref_month)
" 2>/dev/null)

    REF_TODAY="${result%%|*}"
    REF_MONTH="${result##*|}"
}

# ── FETCH LIVE ────────────────────────────────────────────────────
fetch_live() {
    local response parsed
    response=$(curl -s --max-time 5 "$LIVE_API")
    [ -z "$response" ] && bid="" && ask="" && return 1

    parsed=$(echo "$response" | python3 -c "
import json,sys
try:
    d=json.loads(sys.stdin.read())
    for p in d[0]['spreadProfilePrices']:
        if p['spreadProfile']=='prime':
            print('{:.2f}|{:.2f}'.format(p['bid'],p['ask']))
            break
except:
    print('|')
" 2>/dev/null)

    bid="${parsed%%|*}"
    ask="${parsed##*|}"
}

# ── CALCOLO PERCENTUALE ───────────────────────────────────────────
calc_pct() {
    local val="$1" ref="$2"
    [ -z "$val" ] || [ -z "$ref" ] && echo "n/d" && return
    python3 -c "
b,r = $val, $ref
p = (b-r)/r*100
print(('+' if p>=0 else '') + f'{p:.2f}%')
" 2>/dev/null || echo "n/d"
}

# ── DRAW DASHBOARD ────────────────────────────────────────────────
draw_dashboard() {
    local now today_str gram mid
    local pct_day color_day label_day
    local arrow_sym arrow_col
    local rx_speed tx_speed

    now=$(date +"%H:%M:%S")
    today_str=$(date +"%a %d %b %Y")   # formato breve — es. "ven 27 mar 2026"

    if [ -n "$bid" ]; then
        gram=$(python3 -c "print(f'{$bid/31.1035:.4f}')" 2>/dev/null)
        mid=$(python3 -c "print(f'{($bid+$ask)/2:.2f}')" 2>/dev/null)
    else
        gram="—"; mid="—"
    fi

    # Freccia direzionale
    arrow_sym="—"; arrow_col="${GRAY}"
    if [ -n "$prev_bid" ] && [ -n "$bid" ]; then
        if awk "BEGIN{exit !($bid > $prev_bid)}" 2>/dev/null; then
            arrow_sym="▲"; arrow_col="$GREEN"
        elif awk "BEGIN{exit !($bid < $prev_bid)}" 2>/dev/null; then
            arrow_sym="▼"; arrow_col="$RED"
        fi
    fi

    # Variazione giorno
    pct_day=$(calc_pct "$bid" "$REF_TODAY")
    color_day=$GREEN; [[ "$pct_day" == -* ]] && color_day=$RED
    [ "$REF_TODAY" = "$FIRST_BID" ] && [ -z "$REF_TODAY_ORIG" ] \
        && label_day="fallback locale" || label_day="rif. esterno"

    # Velocità rete
    if [ -n "$NET_IFACE" ]; then
        local bytes_now rx_now tx_now
        bytes_now=$(net_bytes "$NET_IFACE")
        rx_now=$(echo "$bytes_now" | awk '{print $1}')
        tx_now=$(echo "$bytes_now" | awk '{print $2}')
        if [ -n "$rx_prev" ] && [ -n "$rx_now" ] && [ "$rx_now" -gt 0 ] 2>/dev/null; then
            local drx dtx
            drx=$(( rx_now - rx_prev )); dtx=$(( tx_now - tx_prev ))
            [ $drx -lt 0 ] && drx=0; [ $dtx -lt 0 ] && dtx=0
            rx_speed=$(fmt_speed $drx)
            tx_speed=$(fmt_speed $dtx)
        else
            rx_speed="—"; tx_speed="—"
        fi
        rx_prev=$rx_now; tx_prev=$tx_now
    else
        rx_speed="n/d"; tx_speed="n/d"
    fi

    # Storico prezzi per sparkline
    if [ -n "$bid" ]; then
        PRICE_HISTORY+=("$bid")
        [ ${#PRICE_HISTORY[@]} -gt 44 ] && PRICE_HISTORY=("${PRICE_HISTORY[@]:1}")
    fi
    local sparkline
    sparkline=$(build_sparkline "${PRICE_HISTORY[@]}")

    # Candele M1
    local candle_str=""
    if [ -n "$bid" ]; then
        if [ -z "$CANDLE_OPEN" ]; then
            CANDLE_OPEN=$bid; CANDLE_HIGH=$bid; CANDLE_LOW=$bid
            CANDLE_CLOSE=$bid; CANDLE_START=$SECONDS
        else
            CANDLE_CLOSE=$bid
            awk "BEGIN{exit !($bid > $CANDLE_HIGH)}" 2>/dev/null && CANDLE_HIGH=$bid
            awk "BEGIN{exit !($bid < $CANDLE_LOW)}"  2>/dev/null && CANDLE_LOW=$bid
            if [ $(( SECONDS - CANDLE_START )) -ge $CANDLE_SEC ]; then
                CANDLE_HISTORY+=("${CANDLE_OPEN}|${CANDLE_HIGH}|${CANDLE_LOW}|${CANDLE_CLOSE}")
                [ ${#CANDLE_HISTORY[@]} -gt $CANDLE_MAX ] && CANDLE_HISTORY=("${CANDLE_HISTORY[@]:1}")
                CANDLE_OPEN=$bid; CANDLE_HIGH=$bid; CANDLE_LOW=$bid
                CANDLE_CLOSE=$bid; CANDLE_START=$SECONDS
            fi
        fi
        local all_candles=("${CANDLE_HISTORY[@]}" "${CANDLE_OPEN}|${CANDLE_HIGH}|${CANDLE_LOW}|${CANDLE_CLOSE}")
        candle_str="${all_candles[*]}"
    fi

    # ── Ridisegna (cursore nascosto) ──────────────────────────────
    tput civis
    tput cup $HEADER_ROWS 0
    tput ed

    # ── 0: SPARKLINE ─────────────────────────────────────────────
    hr_top
    printf "${FRAME}║${RESET}  ${WHITE}${BOLD}[ GRAFICO — sparkline ]${RESET}%-35s${FRAME}║${RESET}\n" ""
    hr_mid
    printf "${FRAME}║${RESET}  ${YELLOW}%-56s${FRAME}║${RESET}\n" "$sparkline"
    hr_mid

    # ── 1: PREZZI LIVE ───────────────────────────────────────────
    printf "${FRAME}║${RESET}  ${WHITE}${BOLD}[ PREZZI LIVE — XAU/USD ]${RESET}%-33s${FRAME}║${RESET}\n" ""
    hr_mid
    if [ -z "$bid" ]; then
        printf "${FRAME}║${RESET}  ${RED}${BOLD}⚠  Errore fetch — riprovo...${RESET}%-30s${FRAME}║${RESET}\n" ""
        printf "${FRAME}║${RESET}  %-56s${FRAME}║${RESET}\n" ""
        printf "${FRAME}║${RESET}  %-56s${FRAME}║${RESET}\n" ""
    else
        printf "${FRAME}║${RESET}  ${BOLD}BID  ${RED}${BOLD}\$ %-12s${RESET}  ${arrow_col}${BOLD}%s${RESET}%-31s${FRAME}║${RESET}\n" \
            "$bid" "$arrow_sym" ""
        printf "${FRAME}║${RESET}  ${BOLD}ASK  ${GREEN}${BOLD}\$ %-12s${RESET}%-37s${FRAME}║${RESET}\n" "$ask" ""
        printf "${FRAME}║${RESET}  ${BOLD}MID  ${YELLOW}${BOLD}\$ %-12s${RESET}%-37s${FRAME}║${RESET}\n" "$mid" ""
    fi

    # ── 2: CONVERSIONI ───────────────────────────────────────────
    hr_mid
    printf "${FRAME}║${RESET}  ${WHITE}${BOLD}[ CONVERSIONI ]${RESET}%-43s${FRAME}║${RESET}\n" ""
    hr_mid
    printf "${FRAME}║${RESET}  ${BOLD}Oncia troy   ${ORANGE}${BOLD}\$ %-10s${RESET}  ${DIM}31.1035 g${RESET}%-18s${FRAME}║${RESET}\n" "$bid" ""
    printf "${FRAME}║${RESET}  ${BOLD}Al grammo    ${ORANGE}${BOLD}\$ %-10s${RESET}%-31s${FRAME}║${RESET}\n" "$gram" ""

    # ── 3: VARIAZIONI ────────────────────────────────────────────
    hr_mid
    printf "${FRAME}║${RESET}  ${WHITE}${BOLD}[ VARIAZIONI ]${RESET}%-43s${FRAME}║${RESET}\n" ""
    hr_mid
    printf "${FRAME}║${RESET}  ${BOLD}Var. giorno  ${color_day}${BOLD}%-8s${RESET}  ${DIM}(%-14s)${RESET}%-13s${FRAME}║${RESET}\n" \
        "$pct_day" "$label_day" ""

    # ── 4: RETE ──────────────────────────────────────────────────
    hr_mid
    printf "${FRAME}║${RESET}  ${WHITE}${BOLD}[ RETE — ${NET_IFACE:-n/d} ]${RESET}%-41s${FRAME}║${RESET}\n" ""
    hr_mid
    printf "${FRAME}║${RESET}  ${BOLD}Download  ${CYAN}${BOLD}%-12s${RESET}%-34s${FRAME}║${RESET}\n" "$rx_speed" ""
    printf "${FRAME}║${RESET}  ${BOLD}Upload    ${BLUE}${BOLD}%-12s${RESET}%-34s${FRAME}║${RESET}\n"   "$tx_speed" ""

    # ── 5: CANDELE M1 ────────────────────────────────────────────
    hr_mid
    printf "${FRAME}║${RESET}  ${WHITE}${BOLD}[ CANDELE — M1 ]${RESET}%-41s${FRAME}║${RESET}\n" ""
    hr_mid
    if [ -n "$candle_str" ]; then
        # Il padding è già calcolato in Python — solo bordi Bash
        while IFS= read -r cline; do
            printf "${FRAME}║${RESET}%s${FRAME}║${RESET}\n" "$cline"
        done < <(build_candles "$candle_str")
    else
        printf "${FRAME}║${RESET}  ${DIM}In attesa dati candele (60s per candela)${RESET}%-17s${FRAME}║${RESET}\n" ""
        for i in 1 2 3 4; do printf "${FRAME}║${RESET}  %-56s${FRAME}║${RESET}\n" ""; done
    fi

    # ── 6: SISTEMA ───────────────────────────────────────────────
    hr_mid
    printf "${FRAME}║${RESET}  ${WHITE}${BOLD}[ SISTEMA ]${RESET}%-47s${FRAME}║${RESET}\n" ""
    hr_mid
    printf "${FRAME}║${RESET}  ${BOLD}Ora    ${WHITE}${BOLD}%-10s${RESET}  ${DIM}%-35s${RESET}${FRAME}║${RESET}\n" "$now" "$today_str"
    hr_sep
    printf "${FRAME}║${RESET}  ${DIM}Live: Swissquote  ·  Storico: freegoldapi.com${RESET}%-12s${FRAME}║${RESET}\n" ""
    hr_mid
    printf "${FRAME}║${RESET}  ${DIM}Aggiornamento ogni 3s  ·  Ctrl+C per uscire${RESET}%-14s${FRAME}║${RESET}\n" ""
    hr_bot
}

# ── BOOTSTRAP ─────────────────────────────────────────────────────
while ! check_size; do sleep 1; done

print_header
HEADER_ROWS=11

fetch_historical
REF_TODAY_ORIG="$REF_TODAY"
REF_MONTH_ORIG="$REF_MONTH"

bid=""; ask=""; prev_bid=""; FIRST_BID=""
NET_IFACE=$(net_iface)
rx_prev=""; tx_prev=""

declare -a PRICE_HISTORY=()
declare -a CANDLE_HISTORY=()
CANDLE_OPEN=""; CANDLE_HIGH=""; CANDLE_LOW=""; CANDLE_CLOSE=""
CANDLE_START=0

cleanup() {
    tput cnorm
    tput cup 999 0
    echo -e "\n${ORANGE}  XAUWATCH terminato. Ciao, Klod.${RESET}\n"
}
trap 'cleanup; exit 0' INT TERM
trap 'tput cnorm' EXIT

needs_redraw_header=0
tput civis

# ── LOOP ──────────────────────────────────────────────────────────
while true; do
    if ! check_size; then
        tput cnorm
        needs_redraw_header=1
        sleep 1
        tput civis
        continue
    fi

    if [ "$needs_redraw_header" -eq 1 ]; then
        print_header
        needs_redraw_header=0
    fi

    fetch_live

    [ -z "$FIRST_BID" ] && [ -n "$bid" ] && FIRST_BID="$bid"
    [ -z "$REF_TODAY" ] && [ -n "$FIRST_BID" ] && REF_TODAY="$FIRST_BID"
    [ -z "$REF_MONTH" ] && [ -n "$FIRST_BID" ] && REF_MONTH="$FIRST_BID"

    draw_dashboard
    prev_bid="$bid"

    sleep 3
done
