#!/bin/bash
OUTPUT_DIR="${OUTPUT_DIR:-/tmp/exports}"

download_all_rss_pages() {
	SITE="$1"
	ODIR="$2"
	LIST_SIZE=50
	TOTAL_PAGES=$(curl --globoff -I "${SITE}?rss=y&partner=domo&page=1&listSize=${LIST_SIZE}&after=2023-01-01T00:00:00&es=false&include_total_pages=1" | egrep -o 'totalpages: \d+' | awk '{print $2}')
	#TOTAL_PAGES=1
	echo "Downloading ${TOTAL_PAGES} page(s)."
	PREFIX=$(echo -n "${SITE}" | tr "/" "_")
	curl --globoff --retry 10 -Z -# --parallel-max 2 -L "${SITE}?rss&partner=domo&page=[1-${TOTAL_PAGES}]&listSize=${LIST_SIZE}&after=2023-01-01T00:00:00&es=false" -o "${ODIR}/${PREFIX}_#1.xml"
}

convert_to_csv() {
  # Fail loudly if no XML files exist
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
        | ./export_rss.py \
        | yq -p=json -o=csv "." - \
        > "${f}.csv"
    ' _
}

get_all_sites() {
	cat sites.txt
}

combine_all_csv() {
  SITE="$1"
  PREFIX=$(echo -n "${SITE}" | tr "/" "_")
  COMBINED_FILE="${OUTPUT_DIR}/${PREFIX}_combined.csv"

  shopt -s nullglob
  FILES=("${OUTPUT_DIR}/${PREFIX}"*.csv)

  if [ ${#FILES[@]} -eq 0 ]; then
    echo "No CSV files found for ${SITE}" >&2
    return 1
  fi

  echo "Combining into: ${COMBINED_FILE}"

  # Header from first file
  head -n1 "${FILES[0]}" > "$COMBINED_FILE"

  # Append rows from all files
  for f in "${FILES[@]}"; do
    tail -n +2 "$f" >> "$COMBINED_FILE"
  done
}

for SITE in `get_all_sites`; do
	rm -rf "${OUTPUT_DIR}"
	mkdir -p "${OUTPUT_DIR}"
	echo $SITE
	download_all_rss_pages "$SITE" "${OUTPUT_DIR}"
	convert_to_csv
	combine_all_csv "${SITE}"
	#rm -rf "${OUTPUT_DIR}"
done

