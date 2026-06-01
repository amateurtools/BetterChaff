#!/usr/bin/env bash
# BetterChaff.sh — privacy chaff file generator
# Writes realistic-looking fake files with proper magic headers,
# mixed readable/binary content, and shuffled block order.
#
# Usage: BetterChaff.sh [OPTIONS] [OUTDIR]
#
#   -c COUNT     files per type (default: 50)
#   -t RATIO     percent of content that is readable text (default: 30)
#   -s SEED      deterministic seed for openssl RNG; omit for /dev/urandom
#   -f           fill mode: keep writing until disk is full (ignores -c)
#   -n           dry-run: print what would be created, write nothing
#   -h           this help
#
# Size overrides: create sizes.conf in CWD:
#   ext minbytes maxbytes
#   mp4 65536 1048576
#
# Requires: bash >=4, xxd, openssl, perl, dd, stat, mktemp

set -euo pipefail

# ── defaults ──────────────────────────────────────────────────────────────────
OUTDIR="chaff_out"
COUNTS=500
TEXT_RATIO_PCT=30
SEED=""
DRY_RUN=0
FILL_MODE=0

usage() {
  grep '^#' "$0" | sed 's/^# \{0,1\}//'
  exit 0
}

while getopts ":c:t:s:fnh" opt; do
  case $opt in
    c) COUNTS="$OPTARG" ;;
    t) TEXT_RATIO_PCT="$OPTARG" ;;
    s) SEED="$OPTARG" ;;
    f) FILL_MODE=1 ;;
    n) DRY_RUN=1 ;;
    h) usage ;;
    :) echo "Option -$OPTARG requires an argument." >&2; exit 1 ;;
    \?) echo "Unknown option -$OPTARG" >&2; exit 1 ;;
  esac
done
shift $(( OPTIND - 1 ))
OUTDIR="${1:-$OUTDIR}"

# ── file type table ────────────────────────────────────────────────────────────
TYPES=(
  "jpg:ffd8ffe0:10240:524288"
  "png:89504e470d0a1a0a:10240:524288"
  "gif:474946383961:4096:2097152"
  "webp:52494646:8192:524288"
  "bmp:424d:8192:4194304"
  "tiff:49492a00:8192:4194304"
  "pdf:255044462d312e34:4096:262144"
  "docx:504b0304:8192:524288"
  "xlsx:504b0304:8192:524288"
  "pptx:504b0304:8192:524288"
  "odt:504b0304:8192:262144"
  "zip:504b0304:8192:134217728"
  "7z:377abcaf271c:8192:134217728"
  "gz:1f8b:2048:67108864"
  "tar:7573746172:8192:134217728"
  "mp4:0000001866747970:65536:134217728"
  "mov:000000146674797071743220:65536:134217728"
  "mkv:1a45dfa3:65536:134217728"
  "webm:1a45dfa3:32768:67108864"
  "avi:52494646:32768:134217728"
  "mp3:494433:16384:8388608"
  "flac:664c6143:16384:524288"
  "wav:52494646:8192:524288"
  "ogg:4f676753:16384:524288"
  "m4a:0000001c66747970:16384:524288"
  "txt::512:65536"
  "csv::256:65536"
  "json:7b:256:131072"
  "xml:3c3f786d6c:512:262144"
  "log::512:131072"
  "md::256:65536"
)

# ── size overrides ─────────────────────────────────────────────────────────────
declare -A OVERRIDE_MIN OVERRIDE_MAX
if [ -f sizes.conf ]; then
  while read -r e mn mx; do
    [[ -z "$e" || "$e" =~ ^# ]] && continue
    OVERRIDE_MIN["$e"]="$mn"
    OVERRIDE_MAX["$e"]="$mx"
  done < sizes.conf
  echo "Loaded size overrides from sizes.conf"
fi

# ── helpers ────────────────────────────────────────────────────────────────────

avail_bytes() {
  df --output=avail -B1 "$OUTDIR" | tail -1
}

rand_bytes() {
  local n="$1" out="$2"
  if [ -n "$SEED" ]; then
    openssl enc -aes-256-ctr -pass "pass:$SEED" -nosalt </dev/zero 2>/dev/null \
      | dd bs=65536 count=$(( (n + 65535) / 65536 )) 2>/dev/null \
      | head -c "$n" >"$out"
  else
    dd if=/dev/urandom bs=65536 count=$(( (n + 65535) / 65536 )) 2>/dev/null \
      | head -c "$n" >"$out"
  fi
}

# Write n bytes of human-readable text to a file.
# Word list is embedded directly — no bash→Perl handoff needed.
readable_block() {
  local n="$1" out="$2"
  perl - "$n" <<'PERL' >"$out"
    use strict; use warnings;
    srand(time ^ $$);

    my $n = shift;

    my @w = qw(
      access account active address admin agent alert alpha archive asset assign audit
      backup batch beta binary block bounce buffer build cache cancel channel check
      circuit cleanup client close cluster code column commit config connect content
      context copy count create credential cron cycle data debug default delete delta
      deploy detect device disabled dispatch document domain drop dump edge enable
      endpoint entry environment error eval event exclude execute expire export extract
      fail fetch field file filter flag flush format forward function gateway global
      group handle hash header host import index info inject input install interface
      interval invoke issue iterate key label layer limit link load local lock log loop
      map match message method metric migrate mode model module monitor mount network
      node notify null object observer offset open operation output owner package parse
      path pause pending pipeline policy port primary probe process project queue read
      reboot record refresh region reject remote remove render request reset resolve
      resource restart retry role rotate route rule run schedule scope search select
      send sequence service session set skip socket source spawn split stack state stop
      store stream sync system tag task timeout token trace trigger type update user
      value version warning watch webhook worker write zone foxtrot golf hotel india
      juliet kilo lima mike november oscar papa quebec romeo sierra tango uniform victor
    );
    my $wc = scalar @w;

    my @log_levels = qw(INFO DEBUG WARN ERROR NOTICE);
    my @months     = qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec);

    sub rw { $w[int(rand($wc))] }
    sub rv { int(rand(99999))   }

    my $buf = "";
    while (length($buf) < $n) {
      my $r = int(rand(5));
      if ($r == 0) {
        my $ts = sprintf "%s %02d %02d:%02d:%02d",
          $months[int(rand(12))], 1+int(rand(28)),
          int(rand(24)), int(rand(60)), int(rand(60));
        $buf .= sprintf "[%s] %s: %s %s id=%d latency=%dms\n",
          $log_levels[int(rand(5))], $ts, rw(), rw(), rv(), int(rand(999));
      } elsif ($r == 1) {
        $buf .= sprintf "%s=%s %s=%d %s=%s\n", rw(), rw(), rw(), rv(), rw(), rw();
      } elsif ($r == 2) {
        $buf .= sprintf "%d,%s,%s,%s,%.2f\n", rv(), rw(), rw(), rw(), rand(1000);
      } elsif ($r == 3) {
        $buf .= sprintf "  %s:\n    value: %s\n    id: %d\n", rw(), rw(), rv();
      } else {
        my @frag;
        push @frag, rw() for 1..(4+int(rand(8)));
        $buf .= join(" ", @frag) . ".\n";
      }
    }
    print substr($buf, 0, $n);
PERL
}

write_mixed() {
  local path="$1" header="$2" size="$3"
  : >"$path"

  if [ -n "$header" ]; then
    printf '%s' "$header" | xxd -r -p >>"$path"
  fi

  local current; current=$(stat -c%s "$path")
  local remaining=$(( size - current ))
  [ "$remaining" -le 0 ] && return

  local num_chunks=$(( 2 + RANDOM % 4 ))
  local chunk_size=$(( remaining / num_chunks ))
  local leftover=$(( remaining - chunk_size * num_chunks ))
  local TMP; TMP=$(mktemp)

  for (( c=0; c<num_chunks; c++ )); do
    local this_chunk=$(( c == num_chunks-1 ? chunk_size + leftover : chunk_size ))
    local text_sz=$(( this_chunk * TEXT_RATIO_PCT / 100 ))
    local bin_sz=$(( this_chunk - text_sz ))

    if (( c % 2 == 0 )); then
      readable_block "$text_sz" "$TMP"; cat "$TMP" >>"$path"
      rand_bytes "$bin_sz" "$TMP";      cat "$TMP" >>"$path"
    else
      rand_bytes "$bin_sz" "$TMP";      cat "$TMP" >>"$path"
      readable_block "$text_sz" "$TMP"; cat "$TMP" >>"$path"
    fi
  done

  rm -f "$TMP"
  chmod 0644 "$path"
}

# ── main loop ──────────────────────────────────────────────────────────────────
[ "$DRY_RUN" -eq 0 ] && mkdir -p "$OUTDIR"

echo "chaffer: → ${OUTDIR}/ (text ratio ${TEXT_RATIO_PCT}%)"
[ -n "$SEED" ]       && echo "         seeded RNG (SEED=${SEED})"
[ "$FILL_MODE" -eq 1 ] && echo "         fill mode: running until disk full"
[ "$DRY_RUN" -eq 1 ] && echo "         DRY RUN — nothing will be written"

written=0
type_idx=0
file_idx=1
num_types="${#TYPES[@]}"

# In fill mode we cycle through types indefinitely until the disk is full.
# In normal mode we write COUNTS files per type.
while true; do
  entry="${TYPES[$type_idx]}"
  IFS=":" read -r ext header minsz maxsz <<<"$entry"

  minsz="${OVERRIDE_MIN[$ext]:-$minsz}"
  maxsz="${OVERRIDE_MAX[$ext]:-$maxsz}"
  minsz="${minsz:-512}"
  maxsz="${maxsz:-65536}"
  range=$(( maxsz - minsz + 1 ))

  size=$(( ( (RANDOM<<15 | RANDOM) % range ) + minsz ))
  fname="$(printf '%s_%06d.%s' "$ext" "$file_idx" "$ext")"
  out="$OUTDIR/$fname"

  if [ "$DRY_RUN" -eq 1 ]; then
    printf 'would write %-38s  %d bytes\n' "$fname" "$size"
  else
    # In fill mode, check available space; stop gracefully if not enough
    if [ "$FILL_MODE" -eq 1 ]; then
      avail=$(avail_bytes)
      if [ "$avail" -lt "$size" ]; then
        # try a smaller file using remaining space (minus 1MB buffer)
        size=$(( avail - 1048576 ))
        if [ "$size" -le 0 ]; then
          printf '\nDisk full after %d files.\n' "$written"
          break
        fi
      fi
    fi

    # write_mixed; if it fails (e.g. truly out of space), stop cleanly
    if ! write_mixed "$out" "$header" "$size" 2>/dev/null; then
      printf '\nDisk full after %d files.\n' "$written"
      # remove the incomplete file
      rm -f "$out"
      break
    fi
  fi

  written=$(( written + 1 ))
  file_idx=$(( file_idx + 1 ))
  type_idx=$(( (type_idx + 1) % num_types ))

  # progress every 100 files
  if (( written % 100 == 0 )); then
    if [ "$FILL_MODE" -eq 1 ] && [ "$DRY_RUN" -eq 0 ]; then
      avail=$(avail_bytes)
      printf '  %d files written, %d MB remaining...\n' "$written" $(( avail / 1048576 ))
    else
      printf '  %d files written...\n' "$written"
    fi
  fi

  # normal mode exit condition
  if [ "$FILL_MODE" -eq 0 ]; then
    # count files per type: exit after COUNTS full cycles through all types
    if (( file_idx > COUNTS * num_types )); then
      break
    fi
  fi
done

[ "$DRY_RUN" -eq 0 ] && printf 'Done. Wrote %d files to %s/\n' "$written" "$OUTDIR"
[ "$DRY_RUN" -eq 1 ] && printf 'Dry run complete. Would have written %d files.\n' "$written"
