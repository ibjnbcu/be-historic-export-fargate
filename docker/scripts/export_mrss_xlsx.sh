#!/bin/bash
OUTPUT_DIR="${OUTPUT_DIR:-/tmp/exports}"

download_all_rss_pages() {
  SITE="$1"
  ODIR="$2"
  LIST_SIZE=50
  # Fetch total pages from header which is only available with rss feeds
  TOTAL_PAGES=$(curl --globoff -I --globoff "${SITE}?rss=y&partner=domo&types=video&page=1&listSize=${LIST_SIZE}&after=2023-01-01T00:00:00&es=false&include_total_pages=1" | egrep -o 'totalpages: \d+' | awk '{print $2}')
  #TOTAL_PAGES=2

  # strip trailing slash to avoid //mrss
  SITE_NO_TRAIL="${SITE%/}"

  echo "Downloading ${TOTAL_PAGES} page(s)."
  PREFIX=$(echo -n "${SITE}" | tr "/" "_")

  # download mrss feed data
  curl --globoff --retry 10 -Z -# --parallel-max 2 -L \
    "${SITE_NO_TRAIL}/mrss?partner=domo&page=[1-${TOTAL_PAGES}]&listSize=${LIST_SIZE}&fromDate=2023-01-01T00:00:00&es=false" \
    -o "${ODIR}/${PREFIX}_#1.xml"
}

convert_to_xlsx() {
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  export VENV_PY="python3"


  if ! find "${OUTPUT_DIR}" -name '*.xml' -print -quit | grep -q .; then
    echo "ERROR: No XML files found in ${OUTPUT_DIR}" >&2
    ls -lah "${OUTPUT_DIR}" >&2 || true
    exit 1
  fi

  find "${OUTPUT_DIR}" -name '*.xml' -print0 |
    xargs -0 -n1 /bin/bash -c '
      f="$1"
      echo "Converting: $f"
      yq -p=xml -o=json "." "$f" \
        | ./export_mrss.py \
        | "$VENV_PY" ./json_to_xlsx.py "${f%.xml}.xlsx"
    ' _
}

combine_all_xlsx() {
  SITE="$1"
  PREFIX=$(echo -n "${SITE}" | tr "/" "_")
  OUTPUT_FILE="${OUTPUT_DIR}/${PREFIX}_combined.xlsx"

  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  VENV_PY="python3"

  echo "Combining XLSX files into: $OUTPUT_FILE"
  "$VENV_PY" ./combine_xlsx.py "${OUTPUT_DIR}" "$OUTPUT_FILE"

  # delete everything except combined file
  #find "${OUTPUT_DIR}" -type f ! -name "$(basename "$OUTPUT_FILE")" -delete
}

get_all_sites() { cat sites.txt; }

for SITE in $(get_all_sites); do
  rm -rf "${OUTPUT_DIR}"
  mkdir -p "${OUTPUT_DIR}"

  echo "$SITE"
  download_all_rss_pages "$SITE" "${OUTPUT_DIR}"
  convert_to_xlsx
  combine_all_xlsx "$SITE"
done