#!/usr/bin/env bash

set -o nounset
set -o pipefail

ALL_BUCKET_IDS=(1 2 3 4 5 6 7 8 9 10 11 12 13)
ALL_BUCKET_NAMES=(
  "zama-mpc-mainnet-public-833bcdac"
  "zama-mainnet-dfns-public-11205fc3"
  "zama-mainnet-figment-public-b9789254"
  "zama-mainnet-fireblocks-public-ac8226d8"
  "infstones-zama-mainnet-public-9b5966c2"
  "zama-mpc-mainnet-public-c79dc123"
  "zama-mainnet-layerzerolabs-public-39cb485b"
  "zama-kms-decentralized-threshold-2-public-7abc956e"
  "zama-node-mainnet-omakase-public-2f665598"
  "sc-mpc-vault-public-bec9bb0e"
  "zama-mainnet-openzeppelin-public-dbc88bb4"
  "zama-mpc-mainnet-etherscan-p2p-lab-public-78ab43e8"
  "zama-mainnet-conduit-public-2c3e0051"
)
REGION="eu-central-1"

# ALL_BUCKET_NAMES=(
#   "zama-mpc-testnet-public-efd88e2b"
#   "zama-testnet-dfns-public-7c6dca89"
#   "zama-testnet-figment-public-c7bb33cb"
#   "zama-testnet-fireblocks-public-d3a44422"
#   "infstones-zama-testnet-public-38c3686e"
#   "unit410-zama-testnet-public-e949eb94"
#   "zama-testnet-layerzerolabs-public-8e7ced32"
#   "zama-mpc-testnet-8-public-954ade38"
#   "zama-node-testnet-omakase-public-5a1db418"
#   "sc-mpc-vault-public-c909ba5f"
#   "zama-testnet-openzeppelin-public-50118c6b"
#   "zama-mpc-testnet-etherscan-p2p-lab-public-6e248992"
#   "zama-mpc-testnet-13-public-4550599c"
# )
# REGION="eu-west-1"

PARTNERS=(p1 p2 p3 p4 p5 p6 p7 p8 p9 p10 p11 p12 p13)
NUM_PARTNERS=${#PARTNERS[@]}

CERT_OBJECT="CACert/60b7070add74be3827160aa635fb255eeeeb88586c4debf7ab1134ddceb4beee"

COMPARE_IDS=()

print_usage() {
  echo "Usage: $0 <baseline-bucket-id> [bucket-id ...]"
  echo "       baseline-bucket-id is required and must be between 1 and 13."
  echo "       additional bucket ids (optional) limit which buckets are compared."
}

bucket_name_by_id() {
  local search_id="$1"
  local idx
  for idx in "${!ALL_BUCKET_IDS[@]}"; do
    if [[ "${ALL_BUCKET_IDS[idx]}" == "${search_id}" ]]; then
      echo "${ALL_BUCKET_NAMES[idx]}"
      return 0
    fi
  done
  echo ""
  return 1
}

print_bucket_table() {
  echo ""
  echo "ID  | S3 Bucket Name"
  echo "----|---------------------------------------------"
  local idx
  for idx in "${!ALL_BUCKET_IDS[@]}"; do
    printf "%-4s| %s\n" "${ALL_BUCKET_IDS[idx]}" "${ALL_BUCKET_NAMES[idx]}"
  done
  echo ""
}

extract_certificate_data() {
  local cert_path="$1"
  local partner_dir="$2"
  local partner="$3"
  local bucket_name="$4"

  if ! openssl x509 -in "${cert_path}" -pubkey -noout > "${partner_dir}/${partner}-public-key.pem" 2>/dev/null; then
    echo "Failed to extract public key for ${partner} from ${bucket_name}" >&2
    return 1
  fi

  if ! openssl x509 -in "${cert_path}" -pubkey -noout \
    | openssl ec -pubin -text -noout 2>/dev/null \
    | awk '
        /pub:/ {capture=1; next}
        capture {
          if ($0 ~ /^[[:space:]]*[0-9a-fA-F:]+$/) {
            gsub(/^[[:space:]]+/, "");
            print;
          } else {
            capture=0;
          }
        }
      ' > "${partner_dir}/${partner}-public-key-raw.txt"; then
    echo "Failed to extract raw public key for ${partner} from ${bucket_name}" >&2
  fi

  if ! openssl x509 -in "${cert_path}" -noout -text \
    | awk '
        /Signature Value:/ {
          while (getline) {
            if ($0 ~ /^[[:space:]]+[0-9a-fA-F:]+$/) {
              gsub(/^ +/, "");
              print;
            } else {
              exit;
            }
          }
        }
      ' > "${partner_dir}/${partner}-signature-value.txt"; then
    echo "Failed to extract signature for ${partner} from ${bucket_name}" >&2
  fi

  if ! openssl x509 -in "${cert_path}" -noout -startdate | cut -d= -f2 > "${partner_dir}/${partner}-startdate.txt"; then
    echo "Failed to extract start date for ${partner} from ${bucket_name}" >&2
  fi

  if ! openssl x509 -in "${cert_path}" -noout -enddate | cut -d= -f2 > "${partner_dir}/${partner}-enddate.txt"; then
    echo "Failed to extract end date for ${partner} from ${bucket_name}" >&2
  fi

  if ! openssl x509 -in "${cert_path}" -noout -subject -nameopt RFC2253 \
    | sed -n 's/^subject=//; s/.*CN=\([^,]*\).*/\1/p' > "${partner_dir}/${partner}-common-name.txt"; then
    echo "Failed to extract common name for ${partner} from ${bucket_name}" >&2
  fi

  if ! openssl x509 -in "${cert_path}" -noout -ext subjectAltName 2>/dev/null \
    | awk '
        /DNS:/ {
          gsub(/,/, " ");
          for (i = 1; i <= NF; i++) {
            if ($i ~ /^DNS:/) {
              sub(/^DNS:/, "", $i);
              print $i;
            }
          }
        }
      ' > "${partner_dir}/${partner}-san.txt"; then
    echo "Failed to extract SAN for ${partner} from ${bucket_name}" >&2
  fi
}

download_bucket_certificates() {
  local bucket_id="$1"
  local bucket_name="$2"
  shift 2
  local partners_to_fetch=("$@")
  if [[ ${#partners_to_fetch[@]} -eq 0 ]]; then
    partners_to_fetch=("${PARTNERS[@]}")
  fi

  echo "Fetching certificates in bucket ${bucket_id} (${bucket_name})..."

  rm -rf "${bucket_name}"
  local partner
  for partner in "${partners_to_fetch[@]}"; do
    local partner_dir="${bucket_name}/${partner}"
    local cert_path="${partner_dir}/${partner}.cert"
    mkdir -p "${partner_dir}"

    local url="https://${bucket_name}.s3.${REGION}.amazonaws.com/PUB-${partner}/${CERT_OBJECT}"
    if ! wget -q -O "${cert_path}" "${url}"; then
      echo "Failed to download certificate for ${partner} from ${bucket_name}" >&2
      rm -f "${cert_path}"
      continue
    fi

    extract_certificate_data "${cert_path}" "${partner_dir}" "${partner}" "${bucket_name}"
  done
}

read_signature_value() {
  local bucket_name="$1"
  local partner="$2"
  local file_path="${bucket_name}/${partner}/${partner}-signature-value.txt"
  if [[ -f "${file_path}" ]]; then
    tr -d '[:space:]' < "${file_path}"
  else
    echo ""
  fi
}

read_public_key_raw() {
  local bucket_name="$1"
  local partner="$2"
  local file_path="${bucket_name}/${partner}/${partner}-public-key-raw.txt"
  if [[ -f "${file_path}" ]]; then
    tr -d '[:space:]' < "${file_path}"
  else
    echo ""
  fi
}

read_start_date() {
  local bucket_name="$1"
  local partner="$2"
  local file_path="${bucket_name}/${partner}/${partner}-startdate.txt"
  if [[ -f "${file_path}" ]]; then
    cat "${file_path}"
  else
    echo ""
  fi
}

read_end_date() {
  local bucket_name="$1"
  local partner="$2"
  local file_path="${bucket_name}/${partner}/${partner}-enddate.txt"
  if [[ -f "${file_path}" ]]; then
    cat "${file_path}"
  else
    echo ""
  fi
}

read_common_name() {
  local bucket_name="$1"
  local partner="$2"
  local file_path="${bucket_name}/${partner}/${partner}-common-name.txt"
  if [[ -f "${file_path}" ]]; then
    tr -d '[:space:]' < "${file_path}"
  else
    echo ""
  fi
}

read_san_entries() {
  local bucket_name="$1"
  local partner="$2"
  local file_path="${bucket_name}/${partner}/${partner}-san.txt"
  if [[ -f "${file_path}" ]]; then
    paste -sd' ' "${file_path}"
  else
    echo ""
  fi
}

partner_for_bucket_id() {
  local bucket_id="$1"
  if (( bucket_id >= 1 && bucket_id <= NUM_PARTNERS )); then
    local idx=$((bucket_id - 1))
    echo "${PARTNERS[idx]}"
  else
    echo ""
  fi
}

compare_values() {
  local baseline_value="$1"
  local compare_value="$2"
  local missing_label="$3"

  if [[ -z "${baseline_value}" || -z "${compare_value}" ]]; then
    echo "${missing_label}"
  elif [[ "${compare_value}" == "${baseline_value}" ]]; then
    echo "OK"
  else
    echo "MISMATCH"
  fi
}

compare_name_and_san() {
  local expected_name="$1"
  local common_name="$2"
  local san_entries="$3"

  if [[ -z "${common_name}" ]]; then
    echo "NO CN"
  elif [[ -z "${san_entries}" ]]; then
    echo "NO SAN"
  elif [[ "${common_name}" == "${expected_name}" && " ${san_entries} " == *" ${expected_name} "* ]]; then
    echo "OK"
  else
    echo "MISMATCH"
  fi
}

build_comparison_list() {
  local baseline_id="$1"
  shift

  COMPARE_IDS=()
  local ids_to_check=("$@")

  if [[ ${#ids_to_check[@]} -eq 0 ]]; then
    ids_to_check=("${ALL_BUCKET_IDS[@]}")
  fi

  local id
  for id in "${ids_to_check[@]}"; do
    [[ "${id}" == "${baseline_id}" ]] && continue

    if [[ -n "$(bucket_name_by_id "${id}")" ]]; then
      COMPARE_IDS+=("${id}")
    else
      echo "Skipping unknown bucket id '${id}'." >&2
    fi
  done
}

compare_buckets() {
  local baseline_id="$1"
  shift
  local compare_ids=("$@")

  local baseline_name
  baseline_name="$(bucket_name_by_id "${baseline_id}")"
  if [[ -z "${baseline_name}" ]]; then
    echo "Unknown baseline bucket id '${baseline_id}'." >&2
    exit 1
  fi

  download_bucket_certificates "${baseline_id}" "${baseline_name}"

  local baseline_signature=()
  local baseline_pubkey=()
  local baseline_start_date=()
  local baseline_end_date=()
  local idx partner

  for idx in "${!PARTNERS[@]}"; do
    partner="${PARTNERS[idx]}"
    baseline_signature[idx]="$(read_signature_value "${baseline_name}" "${partner}")"
    baseline_pubkey[idx]="$(read_public_key_raw "${baseline_name}" "${partner}")"
    baseline_start_date[idx]="$(read_start_date "${baseline_name}" "${partner}")"
    baseline_end_date[idx]="$(read_end_date "${baseline_name}" "${partner}")"
    if [[ -z "${baseline_signature[idx]}" || -z "${baseline_pubkey[idx]}" ]]; then
      echo "Warning: baseline data missing for ${partner} in bucket ${baseline_name}" >&2
    fi
  done

  printf "\nComparing bucket %s (%s) against selected buckets\n" "${baseline_id}" "${baseline_name}"
  printf "%-8s | %-52s | %-6s | %-12s | %-12s | %-14s | %-25s | %-25s\n" "ID" "Bucket" "Party" "Signature" "PublicKey" "CN/SAN" "Start Date" "End Date"
  printf "%-8s-+-%-52s-+-%-6s-+-%-12s-+-%-12s-+-%-14s-+-%-25s-+-%-25s\n" "--------" "--------------------------------------------------------" "------" "------------" "------------" "--------------" "-------------------------" "-------------------------"

  local compare_id compare_name partner partner_idx
  local sig_value pub_value sig_status pub_status name_san_status
  local common_name san_entries expected_name
  local start_date end_date

  for compare_id in "${compare_ids[@]}"; do
    compare_name="$(bucket_name_by_id "${compare_id}")"
    if [[ -z "${compare_name}" ]]; then
      echo "Skipping unknown bucket id '${compare_id}'." >&2
      continue
    fi

    partner="$(partner_for_bucket_id "${compare_id}")"
    if [[ -z "${partner}" ]]; then
      echo "Skipping bucket ${compare_id}: no associated partner." >&2
      continue
    fi

    partner_idx=$((compare_id - 1))
    download_bucket_certificates "${compare_id}" "${compare_name}" "${partner}"

    sig_value="$(read_signature_value "${compare_name}" "${partner}")"
    pub_value="$(read_public_key_raw "${compare_name}" "${partner}")"
    common_name="$(read_common_name "${compare_name}" "${partner}")"
    san_entries="$(read_san_entries "${compare_name}" "${partner}")"
    start_date="$(read_start_date "${compare_name}" "${partner}")"
    end_date="$(read_end_date "${compare_name}" "${partner}")"

    sig_status="$(compare_values "${baseline_signature[partner_idx]}" "${sig_value}" "NO SIGNATURE")"
    pub_status="$(compare_values "${baseline_pubkey[partner_idx]}" "${pub_value}" "NO PUBLIC KEY")"
    expected_name="mpc-node-${compare_id}"
    name_san_status="$(compare_name_and_san "${expected_name}" "${common_name}" "${san_entries}")"

    printf "%-8s | %-52s | %-6s | %-12s | %-12s | %-14s | %-25s | %-25s\n" "${compare_id}" "${compare_name}" "${partner}" "${sig_status}" "${pub_status}" "${name_san_status}" "${start_date}" "${end_date}"
  done
}

main() {
  if [[ $# -lt 1 ]]; then
    print_bucket_table
    for i in $(seq 1 13); do
      local baseline_id="$i"
      build_comparison_list "${baseline_id}" "$@"
      if [[ ${#COMPARE_IDS[@]} -eq 0 ]]; then
        echo "No comparison buckets selected." >&2
        exit 1
      fi
      compare_buckets "${baseline_id}" "${COMPARE_IDS[@]}"
    done
  else
    local baseline_id="$1"
    shift

    local baseline_name
    baseline_name="$(bucket_name_by_id "${baseline_id}")"
    if [[ -z "${baseline_name}" ]]; then
      echo "Invalid baseline bucket id '${baseline_id}'." >&2
      print_usage
      exit 1
    fi

    build_comparison_list "${baseline_id}" "$@"

    if [[ ${#COMPARE_IDS[@]} -eq 0 ]]; then
      echo "No comparison buckets selected." >&2
      exit 1
    fi

    compare_buckets "${baseline_id}" "${COMPARE_IDS[@]}"
  fi
}

main "$@"