#!/bin/bash
# ─────────────────────────────────────────────────────────────────
#  XAUWATCH  |  Real-time Gold Price Monitor  |  by Klod Cripta
#  Live: Swissquote | Storico: freegoldapi.com
# ─────────────────────────────────────────────────────────────────

LIVE_API="https://forex-data-feed.swissquote.com/public-quotes/bboquotes/instrument/XAU/USD"
HIST_API="https://freegoldapi.com/data/latest.csv"

MIN_COLS=60
MIN_ROWS=48

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

BOX_W=58
CONTENT_W=$((BOX_W - 2))
HR_LINE=$(python3 -c "print('─' * $BOX_W)")

CANDLE_SEC=60
CANDLE_MAX=22

# ── RETE ─────────────────────────────────────────────────────────
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
if v >= 1048576:
    print(f'{v/1048576:.1f} MB/s')
elif v >= 1024:
    print(f'{v/1024:.1f} KB/s')
else:
    print(f'{v:.0f} B/s')
" 2>/dev/null || echo "—"
}

# ── HELPERS BOX ──────────────────────────────────────────────────
hr_top() { printf "${FRAME}+%s+${RESET}\n" "$HR_LINE"; }
hr_bot() { printf "${FRAME}+%s+${RESET}\n" "$HR_LINE"; }
hr_sep() { printf "${FRAME}|%s|${RESET}\n" "$HR_LINE"; }

static_line() {
    local content="$1"
    printf "${FRAME}|${RESET} %-*s ${FRAME}|${RESET}\n" "$CONTENT_W" "$content"
}

blank_line() {
    printf "${FRAME}|${RESET} %-*s ${FRAME}|${RESET}\n" "$CONTENT_W" ""
}

put_in_box() {
    local row="$1"
    local content="$2"

    local plain vis pad
    plain=$(printf '%b' "$content" | sed 's/\x1b\[[0-9;]*m//g')
    vis=${#plain}
    pad=$(( CONTENT_W - vis ))
    (( pad < 0 )) && pad=0

    tput cup "$row" 2
    printf '%b%*s' "$content" "$pad" ""
}

# ── SPARKLINE ────────────────────────────────────────────────────
build_sparkline() {
    [ "$#" -eq 0 ] && printf '·' && return

    python3 - "$CONTENT_W" "$*" <<'PY'
import sys

width = int(sys.argv[1])
vals = [float(x) for x in sys.argv[2].split()] if len(sys.argv) > 2 else []

if not vals:
    print('·'.center(width))
    raise SystemExit

if len(vals) == 1:
    print('·'.center(width))
    raise SystemExit

mn = min(vals)
mx = max(vals)
rng = mx - mn if mx != mn else 1.0
blocks = ' ▁▂▃▄▅▆▇█'

out = []
for v in vals:
    idx = int((v - mn) / rng * 8)
    idx = max(0, min(8, idx))
    out.append(blocks[idx])

s = ''.join(out)
if len(s) < width:
    left = (width - len(s)) // 2
    right = width - len(s) - left
    s = ' ' * left + s + ' ' * right
else:
    s = s[:width]

print(s)
PY
}

# ── CANDELE ASCII ────────────────────────────────────────────────
build_candles() {
    local data="$1"
    [ -z "$data" ] && return

    python3 - "$CONTENT_W" "$data" <<'PY'
import sys
import re

GREEN = '\033[1;32m'
RED = '\033[1;31m'
RESET = '\033[0m'

width = int(sys.argv[1])
raw = sys.argv[2].split()

candles = []
for d in raw:
    p = d.split('|')
    if len(p) == 4:
        try:
            candles.append([float(x) for x in p])
        except:
            pass

if not candles:
    for _ in range(5):
        print(' ' * width)
    raise SystemExit

all_vals = [v for c in candles for v in c]
mn = min(all_vals)
mx = max(all_vals)
rng = mx - mn if mx != mn else 1.0
H = 5

rows_chars = [[] for _ in range(H)]
rows_colors = [[] for _ in range(H)]

for o, h, l, c in candles:
    def norm(v):
        return int((v - mn) / rng * (H - 1))
    ni_h = norm(h)
    ni_l = norm(l)
    ni_o = norm(o)
    ni_c = norm(c)
    body_top = max(ni_o, ni_c)
    body_bottom = min(ni_o, ni_c)
    bullish = c >= o
    col = GREEN if bullish else RED

    for row in range(H):
        r = H - 1 - row
        if body_bottom <= r <= body_top:
            ch = '█' if bullish else '░'
        elif ni_l <= r <= ni_h:
            ch = '|'
        else:
            ch = ' '
        rows_chars[row].append(ch)
        rows_colors[row].append(col if ch != ' ' else '')

ansi_re = re.compile(r'\033\[[0-9;]*m')

price_top = mn + rng
price_bot = mn

label_top = f'{price_top:>8.1f} '
label_bot = f'{price_bot:>8.1f} '
label_mid = ' ' * 9

body_width = len(candles)
label_width = len(label_top)
core_width = label_width + body_width

left_pad = max(0, (width - core_width) // 2)

for i in range(H):
    if i == 0:
        prefix = label_top
    elif i == H - 1:
        prefix = label_bot
    else:
        prefix = label_mid

    line = ' ' * left_pad + prefix
    for ch, col in zip(rows_chars[i], rows_colors[i]):
        line += (col + ch + RESET) if col else ch

    visible = len(ansi_re.sub('', line))
    if visible < width:
        line += ' ' * (width - visible)
    else:
        plain = ansi_re.sub('', line)
        line = plain[:width]

    print(line)
PY
}

# ── CONTROLLO FINESTRA ───────────────────────────────────────────
check_size() {
    local cols rows
    cols=$(tput cols)
    rows=$(tput lines)

    if [ "$cols" -lt "$MIN_COLS" ] || [ "$rows" -lt "$MIN_ROWS" ]; then
        clear
        tput cnorm
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

# ── HEADER ───────────────────────────────────────────────────────
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

# ── FETCH DATI ───────────────────────────────────────────────────
fetch_historical() {
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
    if not l:
        continue
    parts = l.split(',')
    if len(parts) < 2:
        continue
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

fetch_live() {
    local response parsed
    response=$(curl -s --max-time 5 "$LIVE_API")
    [ -z "$response" ] && bid="" && ask="" && return 1

    parsed=$(echo "$response" | python3 -c "
import json, sys
try:
    d = json.loads(sys.stdin.read())
    for p in d[0]['spreadProfilePrices']:
        if p['spreadProfile'] == 'prime':
            print('{:.2f}|{:.2f}'.format(p['bid'], p['ask']))
            break
except:
    print('|')
" 2>/dev/null)

    bid="${parsed%%|*}"
    ask="${parsed##*|}"
}

calc_pct() {
    local val="$1" ref="$2"
    [ -z "$val" ] || [ -z "$ref" ] && echo "n/d" && return
    python3 -c "
b, r = $val, $ref
p = (b-r)/r*100
print(('+' if p>=0 else '') + f'{p:.2f}%')
" 2>/dev/null || echo "n/d"
}

# ── LAYOUT STATICO ───────────────────────────────────────────────
LAYOUT_DRAWN=0

draw_static_layout() {
    local base=$HEADER_ROWS
    local r=$base

    R_TITLE_GRAFICO=$((r + 1))
    R_SPARK=$((r + 2))

    R_TITLE_PREZZI=$((r + 4))
    R_BID=$((r + 5))
    R_ASK=$((r + 6))
    R_MID=$((r + 7))

    R_TITLE_CONV=$((r + 9))
    R_OZT=$((r + 10))
    R_GRAM=$((r + 11))

    R_TITLE_VAR=$((r + 13))
    R_VDAY=$((r + 14))

    R_TITLE_NET=$((r + 16))
    R_DL=$((r + 17))
    R_UL=$((r + 18))

    R_TITLE_CAND=$((r + 20))
    R_C0=$((r + 21))
    R_C1=$((r + 22))
    R_C2=$((r + 23))
    R_C3=$((r + 24))
    R_C4=$((r + 25))

    R_TITLE_SYS=$((r + 27))
    R_ORA=$((r + 28))
    R_SRC=$((r + 30))
    R_INFO=$((r + 32))

    tput cup "$base" 0
    tput ed

    {
        hr_top
        blank_line
        blank_line
        hr_sep

        blank_line
        blank_line
        blank_line
        blank_line
        hr_sep

        blank_line
        blank_line
        blank_line
        hr_sep

        blank_line
        blank_line
        hr_sep

        blank_line
        blank_line
        blank_line
        hr_sep

        blank_line
        blank_line
        blank_line
        blank_line
        blank_line
        blank_line
        hr_sep

        blank_line
        blank_line
        hr_sep

        blank_line
        hr_sep
        blank_line
        hr_bot
    } | cat

    static_titles
    LAYOUT_DRAWN=1
}

static_titles() {
    put_in_box "$R_TITLE_GRAFICO" "${BOLD}[ GRAFICO — sparkline ]${RESET}"
    put_in_box "$R_TITLE_PREZZI"  "${BOLD}[ PREZZI LIVE — XAU/USD ]${RESET}"
    put_in_box "$R_TITLE_CONV"    "${BOLD}[ CONVERSIONI ]${RESET}"
    put_in_box "$R_TITLE_VAR"     "${BOLD}[ VARIAZIONI ]${RESET}"
    put_in_box "$R_TITLE_NET"     "${BOLD}[ RETE — ${NET_IFACE:-n/d} ]${RESET}"
    put_in_box "$R_TITLE_CAND"    "${BOLD}[ CANDELE — M1 ]${RESET}"
    put_in_box "$R_TITLE_SYS"     "${BOLD}[ SISTEMA ]${RESET}"
}

# ── UPDATE DINAMICO ──────────────────────────────────────────────
update_values() {
    local now today_str gram mid
    local pct_day color_day label_day
    local arrow_sym arrow_col
    local rx_speed tx_speed
    local sparkline
    local candle_str=""

    now=$(date +"%H:%M:%S")
    today_str=$(date +"%a %d %b %Y")

    if [ -n "$bid" ]; then
        gram=$(python3 -c "print(f'{$bid/31.1035:.4f}')" 2>/dev/null)
        mid=$(python3 -c "print(f'{($bid+$ask)/2:.2f}')" 2>/dev/null)
    else
        gram="—"
        mid="—"
    fi

    arrow_sym="—"
    arrow_col="$GRAY"
    if [ -n "$prev_bid" ] && [ -n "$bid" ]; then
        if awk "BEGIN{exit !($bid > $prev_bid)}" 2>/dev/null; then
            arrow_sym="▲"
            arrow_col="$GREEN"
        elif awk "BEGIN{exit !($bid < $prev_bid)}" 2>/dev/null; then
            arrow_sym="▼"
            arrow_col="$RED"
        fi
    fi

    pct_day=$(calc_pct "$bid" "$REF_TODAY")
    color_day=$GREEN
    [[ "$pct_day" == -* ]] && color_day=$RED

    if [ "$REF_TODAY" = "$FIRST_BID" ] && [ -z "$REF_TODAY_ORIG" ]; then
        label_day="fallback locale"
    else
        label_day="rif. esterno"
    fi

    if [ -n "$NET_IFACE" ]; then
        local bytes_now rx_now tx_now drx dtx
        bytes_now=$(net_bytes "$NET_IFACE")
        rx_now=$(echo "$bytes_now" | awk '{print $1}')
        tx_now=$(echo "$bytes_now" | awk '{print $2}')

        if [ -n "$rx_prev" ] && [ -n "$rx_now" ] && [ "$rx_now" -gt 0 ] 2>/dev/null; then
            drx=$(( rx_now - rx_prev ))
            dtx=$(( tx_now - tx_prev ))
            [ "$drx" -lt 0 ] && drx=0
            [ "$dtx" -lt 0 ] && dtx=0
            rx_speed=$(fmt_speed "$drx")
            tx_speed=$(fmt_speed "$dtx")
        else
            rx_speed="—"
            tx_speed="—"
        fi

        rx_prev=$rx_now
        tx_prev=$tx_now
    else
        rx_speed="n/d"
        tx_speed="n/d"
    fi

    if [ -n "$bid" ]; then
        PRICE_HISTORY+=("$bid")
        [ ${#PRICE_HISTORY[@]} -gt 44 ] && PRICE_HISTORY=("${PRICE_HISTORY[@]:1}")
    fi
    sparkline=$(build_sparkline "${PRICE_HISTORY[@]}")

    if [ -n "$bid" ]; then
        if [ -z "$CANDLE_OPEN" ]; then
            CANDLE_OPEN=$bid
            CANDLE_HIGH=$bid
            CANDLE_LOW=$bid
            CANDLE_CLOSE=$bid
            CANDLE_START=$SECONDS
        else
            CANDLE_CLOSE=$bid
            awk "BEGIN{exit !($bid > $CANDLE_HIGH)}" 2>/dev/null && CANDLE_HIGH=$bid
            awk "BEGIN{exit !($bid < $CANDLE_LOW)}" 2>/dev/null && CANDLE_LOW=$bid

            if [ $(( SECONDS - CANDLE_START )) -ge $CANDLE_SEC ]; then
                CANDLE_HISTORY+=("${CANDLE_OPEN}|${CANDLE_HIGH}|${CANDLE_LOW}|${CANDLE_CLOSE}")
                [ ${#CANDLE_HISTORY[@]} -gt $CANDLE_MAX ] && CANDLE_HISTORY=("${CANDLE_HISTORY[@]:1}")
                CANDLE_OPEN=$bid
                CANDLE_HIGH=$bid
                CANDLE_LOW=$bid
                CANDLE_CLOSE=$bid
                CANDLE_START=$SECONDS
            fi
        fi

        local all_candles=("${CANDLE_HISTORY[@]}" "${CANDLE_OPEN}|${CANDLE_HIGH}|${CANDLE_LOW}|${CANDLE_CLOSE}")
        candle_str="${all_candles[*]}"
    fi

    {
    put_in_box "$R_SPARK" "${YELLOW}${sparkline}${RESET}"

if [ -z "$bid" ]; then
    put_in_box "$R_BID" "${RED}${BOLD}Errore fetch — riprovo...${RESET}"
else
    put_in_box "$R_BID" "BID  ${RED}${BOLD}\$ ${bid}${RESET}  ${arrow_col}${BOLD}${arrow_sym}${RESET}"
fi

put_in_box "$R_ASK" "ASK  ${GREEN}${BOLD}\$ ${ask}${RESET}"
put_in_box "$R_MID" "MID  ${YELLOW}${BOLD}\$ ${mid}${RESET}"

put_in_box "$R_OZT" "Oncia troy   ${ORANGE}${BOLD}\$ ${bid}${RESET}  ${DIM}31.1035 g${RESET}"
put_in_box "$R_GRAM" "Al grammo    ${ORANGE}${BOLD}\$ ${gram}${RESET}"

put_in_box "$R_VDAY" "Var. giorno  ${color_day}${BOLD}${pct_day}${RESET}  ${DIM}(${label_day})${RESET}"

put_in_box "$R_DL" "Download  ${CYAN}${BOLD}${rx_speed}${RESET}"
put_in_box "$R_UL" "Upload    ${BLUE}${BOLD}${tx_speed}${RESET}"
        if [ -n "$candle_str" ]; then
            local ci=0 crow
            while IFS= read -r cline && [ $ci -lt 5 ]; do
                crow=$(( R_C0 + ci ))
                put_in_box "$crow" "$cline"
                ci=$(( ci + 1 ))
            done < <(build_candles "$candle_str")

            while [ $ci -lt 5 ]; do
                crow=$(( R_C0 + ci ))
                put_in_box "$crow" ""
                ci=$(( ci + 1 ))
            done
        else
            put_in_box "$R_C0" "${DIM}In attesa dati candele (60s per candela)${RESET}"
            put_in_box "$R_C1" ""
            put_in_box "$R_C2" ""
            put_in_box "$R_C3" ""
            put_in_box "$R_C4" ""
        fi

        put_in_box "$R_ORA" "${BOLD}Ora    ${WHITE}${BOLD}${now}${RESET}  ${DIM}${today_str}${RESET}"
        put_in_box "$R_SRC"  "Live: Swissquote  ·  Storico: freegoldapi.com"
        put_in_box "$R_INFO" "Aggiornamento ogni 3s  ·  Ctrl+C per uscire"
    } | cat
}

draw_dashboard() {
    tput civis
    if [ "$LAYOUT_DRAWN" -eq 0 ]; then
        draw_static_layout
    fi
    update_values
}

# ── BOOTSTRAP ────────────────────────────────────────────────────
while ! check_size; do
    sleep 1
done

print_header
HEADER_ROWS=11

fetch_historical
REF_TODAY_ORIG="$REF_TODAY"
REF_MONTH_ORIG="$REF_MONTH"

bid=""
ask=""
prev_bid=""
FIRST_BID=""

NET_IFACE=$(net_iface)
rx_prev=""
tx_prev=""

declare -a PRICE_HISTORY=()
declare -a CANDLE_HISTORY=()

CANDLE_OPEN=""
CANDLE_HIGH=""
CANDLE_LOW=""
CANDLE_CLOSE=""
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

# ── LOOP ─────────────────────────────────────────────────────────
while true; do
    if ! check_size; then
        tput cnorm
        needs_redraw_header=1
        LAYOUT_DRAWN=0
        sleep 1
        tput civis
        continue
    fi

    if [ "$needs_redraw_header" -eq 1 ]; then
        print_header
        needs_redraw_header=0
        LAYOUT_DRAWN=0
    fi

    fetch_live

    [ -z "$FIRST_BID" ] && [ -n "$bid" ] && FIRST_BID="$bid"
    [ -z "$REF_TODAY" ] && [ -n "$FIRST_BID" ] && REF_TODAY="$FIRST_BID"
    [ -z "$REF_MONTH" ] && [ -n "$FIRST_BID" ] && REF_MONTH="$FIRST_BID"

    draw_dashboard
    prev_bid="$bid"

    sleep 3
done
