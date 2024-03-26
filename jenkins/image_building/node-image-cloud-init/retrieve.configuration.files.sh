#!/bin/bash
set -e
url="${1}"
dst="${2}"
filename="$(basename "${url}")"
tmpfile="/tmp/${filename}"
curl -sSL -w "%{http_code}" "${url}" | sed "s:/usr/bin:/usr/local/bin:g" > /tmp/"${filename}"
http_status=$(tail -1 "${tmpfile}")
if [ "${http_status}" != "200" ]; then
  echo "Error: unable to retrieve ${filename} file";
  exit 1;
else
  sed '$d' "${tmpfile}" > "${dst}";
fi
