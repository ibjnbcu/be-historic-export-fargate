#!/bin/bash
OUTPUT_DIR=/Users/a206771231/Desktop/exports

download_all_rss_pages() {
	SITE="$1"
	ODIR="$2"
	LIST_SIZE=50
	TOTAL_PAGES=$(curl -I "${SITE}?rss=y&partner=domo&page=1&listSize=${LIST_SIZE}&after=2023-01-01T00:00:00&es=false&include_total_pages=1" | egrep -o 'totalpages: \d+' | awk '{print $2}')
	#TOTAL_PAGES=2
	echo "Downloading ${TOTAL_PAGES} page(s)."
	PREFIX=$(echo -n "${SITE}" | tr "/" "_")
	curl --retry 10 -Z -# --parallel-max 2 -L "${SITE}?rss=y&partner=domo&page=[1-${TOTAL_PAGES}]&listSize=${LIST_SIZE}&after=2023-01-01T00:00:00&es=false" -o "${ODIR}/${PREFIX}_#1.xml"
}

convert_to_csv() {
	find "${OUTPUT_DIR}" -name '*.xml' -print0 | xargs -0 -n1 /bin/sh -c 'echo "$0"; yq -p xml -o json < "$0" | ./export.py | yq -p json -o csv > "$0".csv'
}

get_all_sites() {
	cat sites.txt
}

combine_all_csv() {
	SITE="$1"
	FIRST_FILE=$(find "${OUTPUT_DIR}" -name "*.csv" | head -1)
	PREFIX=$(echo -n "${SITE}" | tr "/" "_")
	CURDIR=$(pwd)
	cd "${OUTPUT_DIR}"
	head -n1 "${FIRST_FILE}" > "/tmp/${PREFIX}_combined.txt" && find . -name "${PREFIX}*.csv" -print0 | xargs -0 -n1 /bin/bash -c 'tail -n+2 -q "$1" >> "/tmp/${0}_combined.txt"' "${PREFIX}"
	cd "${CURDIR}"
}

for SITE in `get_all_sites`; do
	rm -rf "${OUTPUT_DIR}"
	mkdir -p "${OUTPUT_DIR}"
	echo $SITE
	download_all_rss_pages "$SITE" "${OUTPUT_DIR}"
	convert_to_csv
	combine_all_csv "${SITE}"
	rm -rf "${OUTPUT_DIR}"
done

