#!/usr/bin/env bash
set -euo pipefail

SERVER="${QSYNC_SERVER:-user@server}"
REMOTE_BASE="${QSYNC_REMOTE_BASE:-/srv/qsync}"
ID="${QSYNC_ID:-}"
SSH_OPTS=(-o BatchMode=yes)
RSYNC_OPTS=(
  -a
  --no-perms
  --omit-dir-times
  --protect-args
  --partial
  --info=name,progress2
  --no-owner
  --no-group
)

die() { echo "qsync: $*" >&2; exit 1; }

need_id() {
  [[ -n "${ID}" ]] || die "Set QSYNC_ID=a or QSYNC_ID=b."
  [[ "${ID}" == "a" || "${ID}" == "b" ]] || die "QSYNC_ID must be 'a' or 'b'."
}

other_id() {
  case "${ID}" in
    a) echo "b" ;;
    b) echo "a" ;;
  esac
}

remote_dir_for() {
  local dest="$1"
  echo "${REMOTE_BASE}/to-${dest}"
}

ssh_run() {
  local cmdline cmd_arg

  # TODO: ssh splits args twice (local + remote shell); refactor to
  # argv-safe ssh without breaking filenames with spaces
  sq() {
    local s=$1
    s=${s//\'/\'\"\'\"\'}
    printf "'%s'" "$s"
  }

  cmdline=""
  for a in "$@"; do
    cmdline+="$(sq "$a") "
  done
  cmdline="${cmdline% }"

  cmd_arg="$(sq "$cmdline")"
  ssh "${SSH_OPTS[@]}" "${SERVER}" "bash -lc ${cmd_arg}"
}

mk_remote_dirs() {
  ssh_run mkdir -p "$(remote_dir_for a)" "$(remote_dir_for b)"
}

enqueue() {
  need_id
  [[ "$#" -ge 1 ]] || die "enqueue needs at least one file"
  mk_remote_dirs

  local dest rdir tmpdir prefix
  dest="$(other_id)"
  rdir="$(remote_dir_for "${dest}")"
  tmpdir="${rdir}/.tmp"
  prefix="$(date -u +%Y-%m-%dT%H%M%SZ)"

  echo "Enqueue: ${ID} -> ${dest} via ${SERVER}"
  ssh_run mkdir -p "${tmpdir}"

  for f in "$@"; do
    [[ -f "$f" ]] || die "not a file: $f"
    local base final tmp
    base="$(basename "$f")"
    final="${prefix}--${base}"
    tmp="${tmpdir}/.${final}.part"

    rsync "${RSYNC_OPTS[@]}" -e "ssh ${SSH_OPTS[*]}" --chmod=F600 \
      "$f" "${SERVER}:${tmp}"

    ssh_run mv -f "${tmp}" "${rdir}/${final}"
  done

  echo "Done."
}


dequeue() {
  need_id
  local destdir="${1:-.}"
  [[ -d "${destdir}" ]] || mkdir -p "${destdir}"

  mk_remote_dirs
  local rdir
  rdir="$(remote_dir_for "${ID}")"
  src="$(other_id)"

  echo "Dequeue: ${ID} -> ${src} via ${SERVER}"

  rsync --exclude='.tmp/' "${RSYNC_OPTS[@]}" -e "ssh ${SSH_OPTS[*]}" --remove-source-files \
    "${SERVER}:${rdir}/" "${destdir}/"


  ssh_run find "${rdir}" -mindepth 1 -type f -name '*.part' -delete
  ssh_run find "${rdir}" -mindepth 1 -type d -empty -delete

  echo "Done."
}

status() {
  mk_remote_dirs
  echo "Server queues on ${SERVER}:${REMOTE_BASE}"

  for r in a b; do
    local rdir
    rdir="$(remote_dir_for "$r")"
    echo
    echo "Incoming queue for '${r}':"

    ssh_run bash -c '
      shopt -s nullglob
      files=("$1"/*)
      if (( ${#files[@]} == 0 )); then
        echo "<empty>"
      else
        ls -lh -- "$1"
      fi
    ' _ "$rdir"
  done
}

usage() {
  cat <<EOF
Usage:
  QSYNC_ID=a qsync enqueue FILES...
  QSYNC_ID=b qsync enqueue FILES...

  QSYNC_ID=a qsync dequeue [DESTDIR]
  QSYNC_ID=b qsync dequeue [DESTDIR]

  qsync status

Environment variables:
  QSYNC_ID=a|b
  QSYNC_SERVER=user@host
  QSYNC_REMOTE_BASE=/srv/qsync
  QSYNC_SSH_OPTS="..."
EOF
}

main() {
  local cmd="${1:-}"; shift || true
  case "${cmd}" in
    enqueue)
      [[ $# -ge 1 ]] || die "enqueue needs files..."
      enqueue "$@"
      ;;
    dequeue)
      dequeue "$@"
      ;;
    status)
      status
      ;;
    ""|-h|--help|help)
      usage
      ;;
    *)
      die "unknown command: ${cmd} (try --help)"
      ;;
  esac
}

main "$@"
